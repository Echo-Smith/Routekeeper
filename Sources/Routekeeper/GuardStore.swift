import SwiftUI
import Observation
import GuardCore
import UserNotifications
import AppKit

struct GuardEvent: Identifiable {
    let id = UUID()
    let time = Date()
    let message: String
    var isAttention = false
}

@MainActor @Observable
final class GuardStore {
    var settings: GuardSettings {
        didSet {
            guard settings != oldValue else { return }
            if monitoring { stop() }
            epoch += 1
            snapshot = nil
            notice = L("notice.settingsChanged")
            if let data = try? JSONEncoder().encode(settings) { preferences.set(data, forKey: "guard-settings-v1") }
        }
    }
    var snapshot: DiagnosticSnapshot?
    var activeFamilies: Set<IPFamily>?
    var checking = false
    var monitoring = false
    var automaticEgressAuditEnabled: Bool {
        didSet {
            guard automaticEgressAuditEnabled != oldValue else { return }
            preferences.set(automaticEgressAuditEnabled, forKey: Self.egressAutomationKey)
            restartEgressAutomation(runImmediately: automaticEgressAuditEnabled)
        }
    }
    var automaticEgressAuditIntervalMinutes: Int {
        didSet {
            let normalized = Self.normalizedEgressInterval(automaticEgressAuditIntervalMinutes)
            if normalized != automaticEgressAuditIntervalMinutes {
                automaticEgressAuditIntervalMinutes = normalized
                return
            }
            guard automaticEgressAuditIntervalMinutes != oldValue else { return }
            preferences.set(automaticEgressAuditIntervalMinutes, forKey: Self.egressIntervalKey)
            restartEgressAutomation(runImmediately: false)
        }
    }
    var policy = GuardPolicy()
    var networkFilter = FilterController()
    var capture = CaptureController()
    var authentication = CredentialController()
    var sandbox: SandboxSession
    var egressAudit = EgressAuditController()
    var events: [GuardEvent] = []
    var notice = ""
    var cleanupPlan: CleanupPlan?
    var cleanupBusy = false
    var cleanupSelection: Set<String> = []
    var cleanupResult = ""
    var cleanupCandidates: [CleanupTarget] { cleanupPlan?.targets.filter { $0.exists && $0.fileCount > 0 } ?? [] }
    var selectedCleanupTargets: [CleanupTarget] { cleanupCandidates.filter { cleanupSelection.contains($0.id) } }
    @ObservationIgnored private var revisionHandlers: [() -> Void] = []
    var languageRevision = 0 {
        didSet { revisionHandlers.forEach { $0() } }
    }
    var desktopInstalled: Bool { snapshot?.desktopPath != nil }
    var codeInstalled: Bool { ApplicationDiscovery.codePathsInstalled() }
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var egressAutomationTask: Task<Void, Never>?
    @ObservationIgnored private var egressEventTask: Task<Void, Never>?
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var lastSignal: [ProcessIdentity: Date] = [:]
    @ObservationIgnored private var networkChanges: NetworkChanges?
    @ObservationIgnored private var revalidation: Task<Void, Never>?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let diagnostics: DiagnosticRunner
    @ObservationIgnored private let notificationsEnabled: Bool
    @ObservationIgnored private var systemSleeping = false

    private static let egressAutomationKey = "routekeeper-egress-auto-v1"
    private static let egressIntervalKey = "routekeeper-egress-auto-interval-v1"

    init(defaults: UserDefaults = .standard, watchNetwork: Bool = true, notificationsEnabled: Bool = true,
         runDiagnostic: @escaping @Sendable (GuardSettings) async -> DiagnosticSnapshot = { await Diagnostics.run(settings: $0) }) {
        preferences = defaults
        sandbox = SandboxSession(preferences: defaults)
        self.notificationsEnabled = notificationsEnabled
        automaticEgressAuditEnabled = defaults.object(forKey: Self.egressAutomationKey) as? Bool ?? true
        automaticEgressAuditIntervalMinutes = Self.normalizedEgressInterval(
            defaults.object(forKey: Self.egressIntervalKey) as? Int ?? 30
        )
        diagnostics = DiagnosticRunner(operation: runDiagnostic)
        settings = defaults.data(forKey: "guard-settings-v1").flatMap { try? JSONDecoder().decode(GuardSettings.self, from: $0) } ?? GuardSettings()
        if watchNetwork {
            networkChanges = NetworkChanges()
            networkChanges?.onChange = { [weak self] reason, sleeping, waking in self?.environmentChanged(reason, sleeping: sleeping, waking: waking) }
        }
        networkFilter.refresh()
    }
    var title: String {
        if settings.experimentalSandboxEnabled {
            return sandbox.statusTitle
        }
        return L10n.t("status.\(policy.phase == .idle ? (checking ? "checking" : "idle") : policy.phase == .armed ? "armed" : "incident")")
    }
    var symbol: String {
        if settings.experimentalSandboxEnabled { return sandbox.statusSymbol }
        return policy.phase == .incident ? "exclamationmark.shield.fill" : policy.phase == .armed ? "shield.lefthalf.filled" : "shield"
    }

    var sandboxModeActive: Bool {
        settings.experimentalSandboxEnabled && sandbox.phase.isActive
    }

    var sandboxModeEnabled: Bool { settings.experimentalSandboxEnabled }
    func log(_ text: String, attention: Bool = false) {
        events.insert(GuardEvent(message: text, isAttention: attention), at: 0)
        if events.count > 60 { events.removeLast(events.count - 60) }
    }
    func check() async {
        guard !settings.experimentalSandboxEnabled, !checking, !monitoring, !systemSleeping else { return }
        checking = true
        let requestEpoch = epoch; let selected = settings
        let result = await diagnostics.run(selected)
        checking = false
        guard epoch == requestEpoch, selected == settings else { return }
        snapshot = result
        activeFamilies = result.enabledFamilies
        notice = result.ready ? L("notice.checkPassed") : L("notice.checkFailed")
        log(result.ready ? L("notice.passedLog") : L("notice.failedLog"), attention: !result.ready)
    }

    func snapshotForEgressAudit(maxAge: TimeInterval = 45) async -> DiagnosticSnapshot? {
        guard !settings.experimentalSandboxEnabled else { return nil }
        if !monitoring {
            if let snapshot,
               Date().timeIntervalSince(snapshot.checkedAt) <= maxAge {
                return snapshot
            }
            return await freshExitSnapshot()
        }
        for _ in 0..<20 {
            guard !Task.isCancelled else { return nil }
            if let snapshot { return snapshot }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return snapshot
    }

    func startEgressAuditAutomation() {
        restartEgressAutomation(runImmediately: false)
    }

    private func restartEgressAutomation(runImmediately: Bool) {
        egressAutomationTask?.cancel()
        egressAutomationTask = nil
        guard automaticEgressAuditEnabled else { return }
        let interval = TimeInterval(automaticEgressAuditIntervalMinutes * 60)
        let age = egressAudit.report.map { Date().timeIntervalSince($0.auditedAt) } ?? interval
        let initialDelay = runImmediately ? 1 : max(1, interval - age)
        egressAutomationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(initialDelay))
            while !Task.isCancelled {
                guard let self else { return }
                await self.runAutomaticEgressAudit(trigger: .scheduled)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func scheduleEgressAuditAfterNetworkChange() {
        egressEventTask?.cancel()
        egressEventTask = nil
        guard automaticEgressAuditEnabled else { return }
        egressEventTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await self.runAutomaticEgressAudit(trigger: .networkChange)
        }
    }

    private func runAutomaticEgressAudit(trigger: EgressAuditTrigger) async {
        guard !settings.experimentalSandboxEnabled, automaticEgressAuditEnabled, !systemSleeping,
              !egressAudit.busy, !checking else { return }
        guard let snapshot = await snapshotForEgressAudit(maxAge: 45) else { return }
        let previousLevel = egressAudit.report?.assessment.level
        guard let result = await egressAudit.run(
            snapshot: snapshot, includeIntelligence: false, trigger: trigger
        ) else { return }
        let comparison = egressAudit.comparison
        if result.assessment.level == .attention,
           previousLevel != .attention || comparison?.addedFindings.isEmpty == false {
            log(
                L10n.resolvedEnglish
                    ? "Automatic egress check found an item that needs attention."
                    : "自动出口体检发现需要处理的项目。",
                attention: true
            )
        }
    }

    func notifyLanguageChanged() {
        notice = L("notice.langChanged")
    }

    func autoAdoptExit() async {
        guard !settings.experimentalSandboxEnabled else {
            notice = L10n.resolvedEnglish
                ? "Turn off experimental sandbox mode before changing ordinary network monitoring."
                : "请先关闭实验性进程沙箱模式，再调整普通网络监控。"
            return
        }
        guard !monitoring else {
            notice = L10n.resolvedEnglish ? "Stop monitoring before detecting an exit." : "请先停止监控，再获取出口。"
            return
        }
        guard let result = await freshExitSnapshot() else { return }
        var updated = settings
        var saved = 0
        for family in IPFamily.allCases {
            if let ip = matchingExit(in: result, family: family) {
                updated.setFixedExit(ip, for: family)
                saved += 1
            }
        }
        guard saved > 0 else {
            notice = L10n.resolvedEnglish ? "No matching exit is available for an enabled address family." : "当前已启用地址族没有可保存的一致出口。"
            return
        }
        settings = updated
        if let confirmed = await freshExitSnapshot() {
            notice = confirmed.ready
                ? (L10n.resolvedEnglish ? "Detected, saved and verified matching exits." : "已自动获取、保存并验证一致出口。")
                : (L10n.resolvedEnglish ? "Saved matching exits; remaining check items still need attention." : "已保存一致出口；复检仍有待处理项。")
        }
    }
    func adoptObservedExit(family: IPFamily) async {
        guard !settings.experimentalSandboxEnabled else {
            notice = L10n.resolvedEnglish
                ? "Turn off experimental sandbox mode before changing ordinary network monitoring."
                : "请先关闭实验性进程沙箱模式，再调整普通网络监控。"
            return
        }
        guard !monitoring else {
            notice = L10n.resolvedEnglish ? "Stop monitoring before detecting an exit." : "请先停止监控，再获取出口。"
            return
        }
        guard let result = await freshExitSnapshot(),
              let ip = matchingExit(in: result, family: family) else {
            notice = L10n.resolvedEnglish ? "Run self-check until both exits match, then retry." : "先运行自检查，等两路出口一致后再试。"
            return
        }
        var updated = settings
        updated.setFixedExit(ip, for: family)
        settings = updated
        if let confirmed = await freshExitSnapshot() {
            notice = confirmed.ready
                ? (L10n.resolvedEnglish ? "Detected, saved and verified the matching \(family.displayName) exit." : "已自动获取、保存并验证一致的 \(family.displayName) 出口。")
                : (L10n.resolvedEnglish ? "Saved the matching \(family.displayName) exit; remaining check items still need attention." : "已保存一致的 \(family.displayName) 出口；复检仍有待处理项。")
        }
    }
    func start() async {
        guard !settings.experimentalSandboxEnabled, !checking, !monitoring, !systemSleeping else {
            if settings.experimentalSandboxEnabled {
                notice = L10n.resolvedEnglish
                    ? "Turn off experimental sandbox mode before starting ordinary monitoring."
                    : "请先关闭“实验性进程沙箱”模式，再开启普通监控。"
            }
            return
        }
        checking = true; epoch += 1
        let requestEpoch = epoch; let selected = settings
        let result = await diagnostics.run(selected)
        checking = false
        guard epoch == requestEpoch, selected == settings else { return }
        snapshot = result
        activeFamilies = result.enabledFamilies
        guard policy.arm(result, settings: settings) else { notice = L("notice.armBlocked"); log(notice, attention: true); return }
        monitoring = true; notice = ""; lastSignal = [:]
        log("\(L("notice.startLog")) \(settings.action == .notify ? L("action.notify") : L("action.terminate"))")
        if notificationsEnabled { Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            if !granted { log(L10n.resolvedEnglish ? "System notifications denied; window and menu bar still show incidents." : "系统通知未获授权；异常仍会显示在窗口与菜单栏。") }
        } }
        beginLoop(requestEpoch: requestEpoch, selected: selected)
    }
    private func beginLoop(requestEpoch: Int, selected: GuardSettings, immediate: Bool = false) {
        loop = Task { [weak self] in
            var first = immediate
            while !Task.isCancelled {
                if !first { try? await Task.sleep(for: .seconds(selected.pollInterval)) }
                first = false
                guard !Task.isCancelled, let self, self.monitoring, self.epoch == requestEpoch else { break }
                let next = await self.diagnostics.run(selected)
                guard !Task.isCancelled, self.monitoring, self.epoch == requestEpoch else { break }
                self.snapshot = next
                self.activeFamilies = next.enabledFamilies
                let before = self.policy.phase
                self.policy.observe(next)
                if before == .armed && self.policy.phase == .incident {
                    self.log("\(L10n.resolvedEnglish ? "Incident: " : "异常：")\(self.policy.reason)", attention: true)
                    self.notify(self.policy.reason)
                }
                if self.policy.phase == .incident && selected.action == .terminate {
                    self.requestSelectedExits(next, selected: selected)
                }
            }
        }
    }
    func environmentChanged(_ reason: String, sleeping: Bool, waking: Bool = false) {
        if sandboxModeActive {
            if sleeping { systemSleeping = true }
            if waking { systemSleeping = false }
            sandbox.invalidateNetwork(reason: reason)
            log(
                L10n.resolvedEnglish
                    ? "Network changed while sandbox mode was active. Sandbox network access was paused."
                    : "沙箱模式运行期间网络状态发生变化，已暂停沙箱网络访问。",
                attention: true
            )
            return
        }
        if sleeping { systemSleeping = true }
        if waking { systemSleeping = false }
        epoch += 1
        let revision = epoch
        loop?.cancel(); revalidation?.cancel(); snapshot = nil
        let wasArmed = policy.phase == .armed
        policy.trip(reason); notice = reason; log(reason, attention: true)
        if monitoring && wasArmed {
            notify(reason)
            if settings.action == .terminate {
                let desktop = ApplicationDiscovery.path(bundleID: ApplicationDiscovery.desktopID, name: "Claude")
                let scan = LocalProcesses.scan(desktopRoots: desktop.map { [$0] } ?? [])
                for record in scan.records where settings.includes(record.kind) {
                    log(LocalProcesses.requestExit(record, settings: settings, desktopRoots: desktop.map { [$0] } ?? []), attention: true)
                }
            }
        }
        guard !systemSleeping else { return }
        revalidation = Task { [weak self] in
            // Debounce related SCDynamicStore events, retaining the incident lock immediately.
            try? await Task.sleep(for: .milliseconds(600))
            guard let self else { return }
            while self.checking && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled, self.epoch == revision else { return }
            if self.monitoring { self.beginLoop(requestEpoch: revision, selected: self.settings, immediate: true) }
            else { await self.check() }
            self.scheduleEgressAuditAfterNetworkChange()
        }
    }
    private func requestSelectedExits(_ result: DiagnosticSnapshot, selected: GuardSettings) {
        let roots = result.desktopPath.map { [$0] } ?? []
        for record in result.processes where selected.includes(record.kind) {
            if let last = lastSignal[record], Date().timeIntervalSince(last) < 15 { continue }
            lastSignal[record] = Date()
            log(LocalProcesses.requestExit(record, settings: selected, desktopRoots: roots), attention: true)
        }
        let active = Set(result.processes)
        lastSignal = lastSignal.filter { active.contains($0.key) }
    }
    func stop() {
        epoch += 1; loop?.cancel(); revalidation?.cancel(); loop = nil; monitoring = false; policy.stop(); lastSignal = [:]
        notice = L("notice.stopped"); log(L("notice.stopLog"))
    }
    private func matchingExit(in result: DiagnosticSnapshot, family: IPFamily) -> String? {
        guard let row = result.familyExits.first(where: { $0.family == family }),
              let direct = row.direct, let proxied = row.proxied,
              direct == proxied, IPAddress.normalized(direct) != nil else { return nil }
        return direct
    }
    private func freshExitSnapshot() async -> DiagnosticSnapshot? {
        guard !monitoring, !systemSleeping, !checking else {
            notice = L10n.resolvedEnglish ? "Another network check is already running." : "已有网络检查正在运行，请稍后重试。"
            return nil
        }
        checking = true
        let requestEpoch = epoch
        let selected = settings
        let result = await diagnostics.run(selected)
        checking = false
        guard epoch == requestEpoch, selected == settings else { return nil }
        snapshot = result
        activeFamilies = result.enabledFamilies
        return result
    }
    func notify(_ message: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Routekeeper 检测到网络异常"
        content.body = settings.action == .terminate ? "正在请求退出所选 Claude 进程，请查看应用中的处理结果。" : "仅提醒模式：Claude 可能仍在联网，请查看检查结果。"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        NSSound.beep()
    }
    func launchDesktop() {
        guard monitoring, policy.phase == .armed, let latest = snapshot,
              Date().timeIntervalSince(latest.checkedAt) < 15, latest.ready,
              settings.protectDesktop, let path = latest.desktopPath else { notice = L10n.resolvedEnglish ? "Pass self-check and enable desktop monitoring first." : "请先通过检查并开启桌面版监控。"; return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in
            if let error { Task { @MainActor in self.notice = "\(L10n.resolvedEnglish ? "Launch failed: " : "启动失败：")\(error.localizedDescription)" } }
        }
    }

    func prepareSandbox() async {
        guard settings.experimentalSandboxEnabled else {
            notice = L10n.resolvedEnglish
                ? "Turn on experimental sandbox mode first."
                : "请先开启“实验性进程沙箱”模式。"
            return
        }
        if monitoring { stop() }
        await sandbox.prepare()
        log(sandbox.statusTitle, attention: sandbox.phase == .failed)
    }

    func launchClaudeInSandbox() {
        guard let token = authentication.launchToken() else {
            sandbox.message = L10n.resolvedEnglish
                ? "Save a Claude Code sign-in token in Keychain before launching the isolated session."
                : "请先在“Claude Code 登录凭证”中保存登录凭证，再启动隔离会话。"
            return
        }
        sandbox.launchClaudeCode(token: token)
        log(
            L10n.resolvedEnglish
                ? "Requested an isolated Claude Code launch in Terminal."
                : "已在终端中请求启动隔离的 Claude Code。"
        )
    }

    func launchFromAuthentication() {
        if settings.experimentalSandboxEnabled {
            guard sandbox.phase == .running || sandbox.phase == .networkPaused else {
                notice = L10n.resolvedEnglish
                    ? "Create and verify an isolated session before launching Claude Code."
                    : "请先创建并验证隔离会话，再启动 Claude Code。"
                return
            }
            launchClaudeInSandbox()
        } else {
            authentication.launchClaudeCode()
        }
    }

    func pauseSandboxNetwork() {
        sandbox.pauseNetwork()
        log(sandbox.statusTitle, attention: true)
    }

    func resumeSandboxNetwork() async {
        await sandbox.resumeNetwork()
        log(sandbox.statusTitle, attention: sandbox.phase == .networkPaused)
    }

    func endSandboxSession() async {
        await sandbox.endSession()
        log(sandbox.statusTitle)
    }

    func prepareForTermination() async {
        stop()
        if sandbox.phase.isActive {
            await sandbox.endSession()
        }
    }
    func exportReport(redacted: Bool = false) {
        guard let snapshot else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = redacted
            ? "Routekeeper-self-check-redacted.json"
            : "Routekeeper-自检查.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if redacted {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? "unknown"
                let data = try DiagnosticReportExport.redactedData(
                    snapshot: snapshot, appVersion: version
                )
                try data.write(to: url, options: .atomic)
                notice = L10n.resolvedEnglish
                    ? "Redacted report exported. Exit IPs and local paths were replaced or removed."
                    : "脱敏报告已导出：出口 IP 与本地路径已替换或移除。"
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(snapshot).write(to: url, options: .atomic)
                notice = L10n.resolvedEnglish
                    ? "Raw report exported; it contains exit IP and local paths. Share carefully."
                    : "原始报告已导出，含出口 IP 和本地安装路径，请按需分享。"
            }
        } catch { notice = "\(L10n.resolvedEnglish ? "Export failed: " : "报告导出失败：")\(error.localizedDescription)" }
    }

    func refreshCleanup() {
        guard !cleanupBusy else { return }
        cleanupBusy = true
        cleanupResult = ""
        cleanupSelection.removeAll()
        Task {
            let home = NSHomeDirectory()
            let plan = await Task.detached { CacheCleaner.scan(home: home) }.value
            cleanupPlan = plan
            cleanupBusy = false
        }
    }

    func runCleanup() {
        guard !cleanupBusy, !selectedCleanupTargets.isEmpty else { return }
        cleanupBusy = true
        let selected = selectedCleanupTargets
        var moved = 0; var failed = 0
        for target in selected {
            if CacheCleaner.trash(target.path) { moved += 1; log("\(L10n.resolvedEnglish ? "Moved to Trash: " : "已移到废纸篓：")\(target.label)") }
            else { failed += 1; log("\(L10n.resolvedEnglish ? "Cleanup failed: " : "清理失败：")\(target.label)", attention: true) }
        }
        cleanupBusy = false
        cleanupSelection.removeAll()
        cleanupPlan = CacheCleaner.scan(home: NSHomeDirectory())
        cleanupResult = selected.isEmpty
            ? (L10n.resolvedEnglish ? "No caches or logs to clean." : "没有可清理的缓存或日志。")
            : moved > 0 && failed == 0
                ? (L10n.resolvedEnglish ? "Moved \(moved) directories to Trash." : "已把 \(moved) 个目录移到废纸篓。")
                : (L10n.resolvedEnglish ? "Moved \(moved), failed \(failed)." : "已移到废纸篓 \(moved) 个，失败 \(failed) 个。")

    }

    private static func normalizedEgressInterval(_ value: Int) -> Int {
        [15, 30, 60].contains(value) ? value : 30
    }
}
