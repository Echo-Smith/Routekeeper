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
            gatewayVerification.invalidate(
                reason: L10n.resolvedEnglish
                    ? "Protection settings changed after gateway verification."
                    : "保护设置已更改，之前的代理网关检查需要重做。"
            )
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
    var gatewayVerification: GatewayVerificationController
    var egressAudit: EgressAuditController
    var events: [GuardEvent] = []
    var notice = ""
    var clearingLocalData = false
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
    @ObservationIgnored private let credentialClearer: (() -> Bool)?
    @ObservationIgnored private let networkFilterDisabler: (() async -> Error?)?

    private static let egressAutomationKey = "routekeeper-egress-auto-v1"
    private static let egressIntervalKey = "routekeeper-egress-auto-interval-v1"

    init(defaults: UserDefaults = .standard, watchNetwork: Bool = true, notificationsEnabled: Bool = true,
         gatewayVerification: GatewayVerificationController? = nil,
         egressAuditController: EgressAuditController? = nil,
         sandbox: SandboxSession? = nil,
         credentialClearer: (() -> Bool)? = nil,
         networkFilterDisabler: (() async -> Error?)? = nil,
         runDiagnostic: @escaping @Sendable (GuardSettings) async -> DiagnosticSnapshot = { await Diagnostics.run(settings: $0) }) {
        preferences = defaults
        self.gatewayVerification = gatewayVerification ?? GatewayVerificationController(defaults: defaults)
        self.egressAudit = egressAuditController ?? EgressAuditController(defaults: defaults)
        self.sandbox = sandbox ?? SandboxSession(preferences: defaults)
        self.credentialClearer = credentialClearer
        self.networkFilterDisabler = networkFilterDisabler
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
        if policy.phase == .idle, settings.gatewayProtectionMode != .off {
            switch gatewayVerification.status(for: settings.gatewayProtectionMode) {
            case .verified:
                break
            case .needsNodeFailureTest:
                return L10n.resolvedEnglish ? "Gateway node test pending" : "代理网关待测节点断开"
            case .needsClientExitTest:
                return L10n.resolvedEnglish ? "Gateway client test pending" : "代理网关待测客户端退出"
            case .needsRecovery:
                return L10n.resolvedEnglish ? "Restore proxy and finish" : "代理网关待恢复复测"
            case .failed:
                return L10n.resolvedEnglish ? "Gateway check failed" : "代理网关检查未通过"
            case .expired:
                return L10n.resolvedEnglish ? "Gateway evidence expired" : "代理网关证据已过期"
            case .unverified:
                return L10n.resolvedEnglish ? "Gateway check pending" : "代理网关待检查"
            }
        }
        return L10n.t("status.\(policy.phase == .idle ? (checking ? "checking" : "idle") : policy.phase == .armed ? "armed" : "incident")")
    }
    var symbol: String {
        if settings.experimentalSandboxEnabled { return sandbox.statusSymbol }
        if policy.phase == .idle,
           settings.gatewayProtectionMode != .off,
           gatewayVerification.status(for: settings.gatewayProtectionMode) != .verified {
            return "shield.lefthalf.filled"
        }
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
        guard settings.gatewayProtectionMode == .off
                || gatewayVerification.isFreshlyVerified(for: settings.gatewayProtectionMode) else {
            notice = L10n.resolvedEnglish
                ? "Complete the current gateway checks before starting monitoring while gateway protection is selected."
                : "已选择代理网关保护，请先在“网络体检 → 代理网关”完成当前网络下的检查。"
            log(notice, attention: true)
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
        gatewayVerification.invalidate(
            reason: L10n.resolvedEnglish
                ? "Network state changed; previous gateway evidence was invalidated."
                : "网络状态已变化，之前的代理网关证据已作废。"
        )
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
              settings.protectDesktop, let path = latest.desktopPath,
              settings.gatewayProtectionMode == .off
                || gatewayVerification.isFreshlyVerified(for: settings.gatewayProtectionMode) else {
            notice = L10n.resolvedEnglish
                ? "Pass the current gateway and self-check evidence before launching."
                : "请先完成当前网络下的代理网关和自检，再启动桌面版。"
            return
        }
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
        let expectedExits = IsolationExpectedExits(
            ipv4: settings.target(for: .ipv4),
            ipv6: settings.target(for: .ipv6)
        )
        guard expectedExits.hasAny else {
            notice = L10n.resolvedEnglish
                ? "Save an IPv4 or IPv6 exit in the ordinary network check before creating a sandbox session."
                : "请先完成普通网络体检并保存 IPv4 或 IPv6 出口，再创建沙箱会话。保存值用于核对沙箱内 Claude 的实际出口。"
            return
        }
        if settings.gatewayProtectionMode != .off
            && !gatewayVerification.isFreshlyVerified(for: settings.gatewayProtectionMode) {
            notice = L10n.resolvedEnglish
                ? "Finish the current gateway checks before creating a sandbox session."
                : "已选择代理网关保护，请先在“网络体检 → 代理网关”完成当前网络下的检查。"
            return
        }
        if monitoring { stop() }
        await sandbox.prepare(expectedExits: expectedExits)
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

    @discardableResult
    func clearLocalInformation() async -> Bool {
        guard !clearingLocalData else { return false }
        guard !checking, !capture.busy, !sandbox.busy, !networkFilter.busy,
              !gatewayVerification.busy, !egressAudit.busy else {
            notice = L10n.resolvedEnglish
                ? "A check, sandbox, capture or network-filter operation is still running. Wait for it to finish, then try again."
                : "当前仍有检查、沙箱、抓包或网络过滤操作在运行。请等待完成后再清空。"
            return false
        }

        clearingLocalData = true
        defer { clearingLocalData = false }

        stop()
        egressAutomationTask?.cancel()
        egressEventTask?.cancel()
        egressAutomationTask = nil
        egressEventTask = nil

        let filterError: Error?
        if let networkFilterDisabler {
            filterError = await networkFilterDisabler()
        } else {
            filterError = await networkFilter.disableAndWait()
        }
        if let error = filterError {
            notice = L10n.resolvedEnglish
                ? "The system network filter could not be turned off, so local information was kept: \(error.localizedDescription)"
                : "系统网络过滤未能关闭，为避免留下仍在生效的旧配置，本次没有清空本地信息：\(error.localizedDescription)"
            return false
        }

        let sandboxCleared = await sandbox.clearForLocalDataReset()
        guard sandboxCleared else {
            notice = L10n.resolvedEnglish
                ? "The sandbox is still busy. Wait for it to finish, then try again."
                : "沙箱仍在处理其他操作。请等待完成后再清空。"
            return false
        }

        let credentialCleared = credentialClearer?() ?? authentication.delete()
        gatewayVerification.clear()
        egressAudit.clearHistory()
        egressAudit.clearStoredResults()
        capture.reset()

        settings = GuardSettings()
        automaticEgressAuditEnabled = true
        automaticEgressAuditIntervalMinutes = 30
        policy = GuardPolicy()
        snapshot = nil
        activeFamilies = nil
        monitoring = false
        checking = false
        lastSignal = [:]
        events = []
        cleanupPlan = nil
        cleanupBusy = false
        cleanupSelection = []
        cleanupResult = ""
        egressAutomationTask?.cancel()
        egressEventTask?.cancel()
        egressAutomationTask = nil
        egressEventTask = nil

        let fixedKeys: Set<String> = [
            "guard-settings-v1",
            "routekeeper-egress-auto-v1",
            "routekeeper-egress-auto-interval-v1",
            L10n.languageKey,
            L10n.appearanceKey,
            "AppleLanguages"
        ]
        let preservedKeys: Set<String> = [
            "routekeeper.disclaimer-accepted-version"
        ]
        let dynamicKeys = Set(preferences.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("routekeeper") && !preservedKeys.contains($0)
        })
        for key in fixedKeys.union(dynamicKeys) {
            preferences.removeObject(forKey: key)
        }

        languageRevision += 1
        if credentialCleared {
            notice = L10n.resolvedEnglish
                ? "Local settings, reports, saved credentials, sandbox copies and run history were cleared."
                : "已清空本地设置、报告、登录凭证、沙箱副本和运行记录。"
            return true
        }
        notice = L10n.resolvedEnglish
            ? "Local settings and files were cleared, but the Keychain credential could not be removed. Check Keychain Access."
            : "本地设置与文件已清空，但 Keychain 登录凭证未能删除。请检查“钥匙串访问”。"
        return false
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
