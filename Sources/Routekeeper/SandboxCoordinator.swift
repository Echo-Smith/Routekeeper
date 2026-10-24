import Foundation
import GuardCore
import Observation

@MainActor
@Observable
final class SandboxCoordinator {
    var sharedConfiguration: SandboxSharedConfiguration {
        didSet {
            guard sharedConfiguration != oldValue else { return }
            persistConfiguration()
            webBrowser.sharedConfigurationDidChange(sharedConfiguration)
            synchronizeSessions()
        }
    }

    let codeSession: SandboxSession
    let desktopSession: SandboxSession
    let webBrowser: ClaudeWebBrowserController

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let installedTargetsOverride: Set<IsolationApplicationTarget>?
    @ObservationIgnored private var isSynchronizing = false

    private static let configurationKey = "routekeeper-sandbox-shared-v1"
    private static let legacyConfigurationKey = "routekeeper-isolation-configuration-v1"

    init(
        preferences: UserDefaults = .standard,
        sessionsRoot: URL? = nil,
        workspacesRoot: URL? = nil,
        profilesRoot: URL? = nil,
        installedTargets: Set<IsolationApplicationTarget>? = nil
    ) {
        self.preferences = preferences
        installedTargetsOverride = installedTargets
        let loaded = Self.loadConfiguration(from: preferences)
        sharedConfiguration = loaded.configuration
        codeSession = SandboxSession(
            preferences: preferences,
            sessionsRoot: sessionsRoot,
            workspacesRoot: workspacesRoot,
            profilesRoot: profilesRoot,
            initialConfiguration: loaded.configuration.configuration(for: .claudeCode),
            persistsConfiguration: false
        )
        desktopSession = SandboxSession(
            preferences: preferences,
            sessionsRoot: sessionsRoot,
            workspacesRoot: workspacesRoot,
            profilesRoot: profilesRoot,
            initialConfiguration: loaded.configuration.configuration(for: .claudeDesktop),
            persistsConfiguration: false
        )
        let browser = ClaudeWebBrowserController(profilesRoot: profilesRoot, discover: false)
        webBrowser = browser
        if !loaded.hasSavedConfiguration {
            sharedConfiguration.enabledTargets = installedTargets
                ?? Self.detectedTargets(from: [codeSession, desktopSession])
        }
        applyConfigurationToSessions()
        installConfigurationCallbacks()
    }

    var sessions: [SandboxSession] {
        [codeSession, desktopSession]
    }

    var enabledSessions: [SandboxSession] {
        sessions.filter { sharedConfiguration.isEnabled($0.configuration.target) }
    }

    var activeSessions: [SandboxSession] {
        enabledSessions.filter(\.phase.isActive)
    }

    var anyActive: Bool {
        activeSessions.isEmpty == false || webBrowser.phase.isRunning
    }

    var busy: Bool {
        sessions.contains(where: \.busy) || webBrowser.busy
    }

    var networkEnabled: Bool {
        activeSessions.contains(where: \.networkEnabled) || webBrowser.phase == .running
    }

    var claudeRunning: Bool {
        activeSessions.contains(where: \.claudeRunning) || webBrowser.phase.isRunning
    }

    var externalActionsPendingCount: Int {
        sessions.reduce(0) { $0 + $1.externalActions.pendingCount }
    }

    var hasDetectedInstallation: Bool {
        if let installedTargetsOverride {
            return !installedTargetsOverride.isEmpty || webBrowser.installation != nil
        }
        return codeSession.claudeCodeInstallation != nil
            || desktopSession.desktopInstallation != nil
            || webBrowser.installation != nil
    }

    var checks: [IsolationCheck] {
        enabledSessions.flatMap(\.checks)
    }

    var relayPort: Int? {
        activeSessions.compactMap(\.relayPort).first
    }

    var cleanupSessionsRoot: URL {
        codeSession.cleanupSessionsRoot
    }

    var cleanupProfilesRoot: URL {
        desktopSession.cleanupProfilesRoot
    }

    var cleanupWorkspacesRoot: URL {
        codeSession.cleanupWorkspacesRoot
    }

    var currentSessionRoots: Set<URL> {
        Set(sessions.compactMap(\.sessionRoot))
    }

    var phase: IsolationPhase {
        let phases = enabledSessions.map(\.phase)
        if phases.contains(.failed) { return .failed }
        if phases.contains(.preparing) { return .preparing }
        if phases.contains(.checking) { return .checking }
        if phases.contains(.networkPaused) { return .networkPaused }
        if phases.contains(.running) { return .running }
        if webBrowser.phase == .failed { return .failed }
        if webBrowser.phase == .launching { return .preparing }
        if webBrowser.phase == .networkPaused { return .networkPaused }
        if webBrowser.phase == .running { return .running }
        if phases.isEmpty || phases.allSatisfy({ $0 == .disabled }) { return .disabled }
        if phases.allSatisfy({ $0 == .ended }) { return .ended }
        return .ready
    }

    var statusTitle: String {
        let active = activeSessions
        if phase == .failed {
            let failed = enabledSessions.filter { $0.phase == .failed }
            if failed.isEmpty, webBrowser.phase == .failed {
                return webBrowser.statusTitle
            }
            return failed.count > 1
                ? text("隔离会话启动失败", "Isolated sessions failed")
                : failed.first.map { text("\($0.configuration.target.title) 启动失败", "\($0.configuration.target.title) failed") }
                    ?? text("隔离会话启动失败", "Isolated session failed")
        }
        if phase == .networkPaused {
            let paused = activeSessions.filter { $0.phase == .networkPaused }
            if paused.count == 1, let session = paused.first {
                return session.statusTitle
            }
            if paused.isEmpty, webBrowser.phase == .networkPaused {
                return webBrowser.statusTitle
            }
            return text("沙箱网络已关闭", "Sandbox network off")
        }
        if phase == .preparing || phase == .checking {
            return active.count > 1
                ? text("正在准备隔离会话", "Preparing isolated sessions")
                : active.first.map { text("正在准备 \($0.configuration.target.title)", "Preparing \($0.configuration.target.title)") }
                    ?? text("正在准备隔离会话", "Preparing isolated session")
        }
        if active.count > 1 {
            return text("\(active.count) 个隔离会话运行中", "\(active.count) isolated sessions running")
        }
        if let session = active.first {
            return session.statusTitle
        }
        if webBrowser.phase.isRunning {
            return webBrowser.statusTitle
        }
        if phase == .ended {
            return text("隔离会话已结束", "Isolated sessions ended")
        }
        if phase == .disabled {
            if enabledSessions.isEmpty {
                if webBrowser.installation != nil {
                    return text("Chrome 可独立使用", "Chrome is available")
                }
                return hasDetectedInstallation
                    ? text("选择要保护的应用", "Choose a protected app")
                    : text("未检测到 Claude 应用", "No Claude app detected")
            }
            return text("实验性沙箱尚未启用", "Experimental sandbox is off")
        }
        return text("等待创建隔离会话", "Ready to create isolated sessions")
    }

    var statusSymbol: String {
        switch phase {
        case .running: return "lock.shield.fill"
        case .networkPaused: return "wifi.slash"
        case .failed: return "exclamationmark.shield.fill"
        case .preparing, .checking: return "hourglass"
        default: return "lock.shield"
        }
    }

    var message: String {
        if let active = activeSessions.first(where: \.busy)
            ?? activeSessions.first(where: { $0.phase == .running })
            ?? activeSessions.first {
            return active.message
        }
        if webBrowser.phase.isRunning || webBrowser.phase == .failed {
            return webBrowser.message
        }
        if phase == .disabled {
            if enabledSessions.isEmpty {
                if webBrowser.installation != nil {
                    return text(
                        "未检测到 Claude 客户端；仍可在独立的官方 Chrome 配置中访问 Claude。",
                        "No Claude client was detected. Chrome can still open in a dedicated official Chrome profile."
                    )
                }
                return hasDetectedInstallation
                    ? text(
                        "已检测到现有 Claude 应用。启用至少一个保护对象后即可继续。",
                        "An existing Claude app was detected. Enable at least one protected target to continue."
                    )
                    : text(
                        "未检测到 Claude Code、Claude 或 Google Chrome。普通网络保护仍可使用；安装后可回到本页重新检测。",
                        "Claude Code, Claude and Google Chrome were not detected. Regular network protection still works; return here to detect them after installation."
                    )
            }
            return text(
                "启用至少一个保护对象后，可以创建独立隔离会话。",
                "Enable at least one protected target to create isolated sessions."
            )
        }
        return text(
            "共享设置只需配置一次；每个保护对象独立检测、启动和结束。",
            "Shared settings are configured once; each protected target is checked, launched and ended independently."
        )
    }

    var expectedExits: IsolationExpectedExits {
        sessions.map(\.expectedExits).first(where: \.hasAny) ?? IsolationExpectedExits()
    }

    var detectedProxy: SystemProxyDescriptor? {
        sessions.compactMap(\.detectedProxy).first
    }

    func session(for target: IsolationApplicationTarget) -> SandboxSession {
        target == .claudeCode ? codeSession : desktopSession
    }

    @discardableResult
    func setTarget(_ target: IsolationApplicationTarget, enabled: Bool) -> Bool {
        let session = session(for: target)
        guard !session.phase.isActive, !session.busy else { return false }
        let wasDisabled = session.phase == .disabled
        if enabled,
           session.claudeCodeInstallation == nil,
           session.desktopInstallation == nil {
            Task { await session.loadInstalledApplicationsIfNeeded() }
        }
        var updated = sharedConfiguration
        if enabled {
            updated.enabledTargets.insert(target)
        } else {
            updated.enabledTargets.remove(target)
        }
        if updated == sharedConfiguration { return true }
        if !enabled {
            session.reset()
        }
        sharedConfiguration = updated
        if enabled {
            if wasDisabled || session.phase == .disabled {
                session.phase = .ready
                session.message = text("可以开始新的隔离会话。", "Ready to create an isolated session.")
            }
        } else if !enabled {
            session.phase = .disabled
            session.message = text(
                "这个保护对象当前未启用。",
                "This protected target is currently disabled."
            )
        }
        return true
    }

    func refreshDetectedProxy(alignIfNeeded: Bool = false) {
        for session in sessions {
            session.refreshDetectedProxy(alignIfNeeded: alignIfNeeded)
        }
    }

    func refreshInstalledApplications() {
        for session in sessions {
            session.refreshInstalledApplications()
        }
    }

    func prepare(
        target: IsolationApplicationTarget,
        expectedExits: IsolationExpectedExits
    ) async {
        let session = session(for: target)
        guard sharedConfiguration.isEnabled(target), session.phase != .disabled else { return }
        // Take a fresh shared snapshot at the launch boundary, not only on UI edits.
        applyConfigurationToSessions()
        do {
            let destination = try targetExchangeURL(for: target)
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            session.phase = .failed
            session.message = text(
                "无法创建交换目录：\(error.localizedDescription)",
                "Could not create the exchange directory: \(error.localizedDescription)"
            )
            return
        }
        await session.prepare(expectedExits: expectedExits)
    }

    func pauseNetwork(target: IsolationApplicationTarget) {
        session(for: target).pauseNetwork()
    }

    func resumeNetwork(target: IsolationApplicationTarget) async {
        await session(for: target).resumeNetwork()
    }

    func endSession(target: IsolationApplicationTarget) async {
        await session(for: target).endSession()
    }

    func pauseAllNetworks() {
        enabledSessions.filter(\.canPauseNetwork).forEach { $0.pauseNetwork() }
        webBrowser.pauseNetwork()
    }

    func resumeAllNetworks() async {
        for session in enabledSessions where session.canResumeNetwork {
            await session.resumeNetwork()
        }
        _ = await webBrowser.resumeNetwork()
    }

    func endAllSessions() async {
        for session in enabledSessions where session.phase.isActive {
            await session.endSession()
        }
        if webBrowser.phase.isRunning || webBrowser.busy {
            await webBrowser.stop()
        }
    }

    func resetInactiveSessions() {
        for session in sessions where !session.phase.isActive {
            session.reset()
            if !sharedConfiguration.isEnabled(session.configuration.target) {
                session.phase = .disabled
            }
        }
    }

    func environmentChanged(_ reason: String, sleeping: Bool, waking: Bool = false) {
        for session in enabledSessions {
            session.networkEnvironmentChanged(reason, sleeping: sleeping, waking: waking)
        }
        webBrowser.networkEnvironmentChanged(reason, sleeping: sleeping, waking: waking)
    }

    func clearForLocalDataReset() async -> Bool {
        guard !busy else { return false }
        var succeeded = true
        for session in sessions {
            if !(await session.clearForLocalDataReset()) {
                succeeded = false
            }
        }
        if webBrowser.phase.isRunning || webBrowser.busy {
            await webBrowser.stop()
        }
        if webBrowser.profileAvailable,
           !(await webBrowser.clearProfileData()) {
            succeeded = false
        }
        preferences.removeObject(forKey: Self.configurationKey)
        var fresh = SandboxSharedConfiguration()
        fresh.enabledTargets = installedTargetsOverride
            ?? Self.detectedTargets(from: sessions)
        sharedConfiguration = fresh
        return succeeded
    }

    func synchronizeSharedUpstream(_ upstream: IsolationUpstream) {
        guard sharedConfiguration.upstream != upstream else { return }
        isSynchronizing = true
        sharedConfiguration.upstream = upstream
        isSynchronizing = false
    }

    func commitSharedConfiguration() {
        persistConfiguration()
        webBrowser.sharedConfigurationDidChange(sharedConfiguration)
        synchronizeSessions()
    }

    func updateTimezoneIdentifier(_ value: String) {
        sharedConfiguration.usesEgressRegionalDefaults = false
        sharedConfiguration.timezoneIdentifier = value
    }

    func updateLanguageIdentifier(_ value: String) {
        sharedConfiguration.usesEgressRegionalDefaults = false
        sharedConfiguration.languageIdentifier = value
    }

    func applyEgressRegionalDefaults(from report: EgressAuditReport?) {
        guard sharedConfiguration.usesEgressRegionalDefaults, !anyActive, !busy,
              let report else { return }
        let intelligence = report.primaryIP.flatMap { primaryIP in
            report.intelligence.first { $0.ip == primaryIP }
        } ?? report.intelligence.first
        guard let timezone = intelligence?.timezone,
              TimeZone(identifier: timezone) != nil else { return }
        var updated = sharedConfiguration
        updated.timezoneIdentifier = timezone
        if let countryCode = intelligence?.countryCode,
           let language = IsolationSessionEnvironment.defaultLanguageIdentifier(
            forCountryCode: countryCode
           ) {
            updated.languageIdentifier = language
        }
        sharedConfiguration = updated
    }

    @discardableResult
    func repairRegionalSettings(from report: EgressAuditReport?) -> Bool {
        guard !anyActive, !busy else { return false }
        let intelligence = report?.primaryIP.flatMap { primaryIP in
            report?.intelligence.first { $0.ip == primaryIP }
        } ?? report?.intelligence.first
        let egressTimezone = intelligence?.timezone.flatMap { value in
            TimeZone(identifier: value) == nil ? nil : value
        }
        var updated = sharedConfiguration
        var didRepair = false
        if TimeZone(identifier: updated.timezoneIdentifier) == nil {
            updated.timezoneIdentifier = egressTimezone ?? TimeZone.current.identifier
            didRepair = true
        }
        if IsolationSessionEnvironment.normalizedLanguageIdentifier(
            updated.languageIdentifier
        ) == nil {
            let countryLanguage = intelligence?.countryCode.flatMap {
                IsolationSessionEnvironment.defaultLanguageIdentifier(forCountryCode: $0)
            }
            updated.languageIdentifier = countryLanguage
                ?? IsolationSessionEnvironment.defaultLanguageIdentifier(
                    for: updated.timezoneIdentifier
                )
            didRepair = true
        }
        if egressTimezone != nil {
            updated.usesEgressRegionalDefaults = true
        }
        guard didRepair else { return false }
        sharedConfiguration = updated
        return true
    }

    private func installConfigurationCallbacks() {
        codeSession.configurationDidChange = { [weak self] configuration in
            self?.receive(configuration, from: .claudeCode)
        }
        desktopSession.configurationDidChange = { [weak self] configuration in
            self?.receive(configuration, from: .claudeDesktop)
        }
    }

    private func receive(
        _ configuration: IsolationConfiguration,
        from target: IsolationApplicationTarget
    ) {
        guard !isSynchronizing, configuration.target == target else { return }
        var updated = sharedConfiguration
        if updated.upstream != configuration.upstream {
            updated.upstream = configuration.upstream
        }
        if target == .claudeDesktop,
           updated.persistClaudeLogin != configuration.persistClaudeLogin {
            updated.persistClaudeLogin = configuration.persistClaudeLogin
        }
        guard updated != sharedConfiguration else { return }
        isSynchronizing = true
        sharedConfiguration = updated
        isSynchronizing = false
        persistConfiguration()
        synchronizeSessions()
    }

    private func synchronizeSessions() {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        applyConfigurationToSessions()
        isSynchronizing = false
    }

    private func applyConfigurationToSessions() {
        for session in sessions {
            let target = session.configuration.target
            let enabled = sharedConfiguration.isEnabled(target)
            if session.phase.canChangeConfiguration {
                let next = sharedConfiguration.configuration(for: target)
                if session.configuration != next {
                    session.configuration = next
                }
                session.phase = enabled ? (session.phase == .disabled ? .ready : session.phase) : .disabled
            }
        }
    }

    private func targetExchangeURL(for target: IsolationApplicationTarget) throws -> URL {
        let path = sharedConfiguration.targetExchangePath(for: target)
        guard !path.isEmpty else {
            throw NSError(
                domain: "Routekeeper.Sandbox",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: text(
                    "请先选择交换根目录。",
                    "Choose an exchange root first."
                )]
            )
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func persistConfiguration() {
        guard !isSynchronizing else { return }
        var persisted = sharedConfiguration
        persisted.upstream.password = ""
        if let data = try? JSONEncoder().encode(persisted) {
            preferences.set(data, forKey: Self.configurationKey)
        }
    }

    private struct LoadedConfiguration {
        var configuration: SandboxSharedConfiguration
        var hasSavedConfiguration: Bool
    }

    private static func detectedTargets(
        from sessions: [SandboxSession]
    ) -> Set<IsolationApplicationTarget> {
        var targets = Set<IsolationApplicationTarget>()
        if sessions.contains(where: { $0.claudeCodeInstallation != nil }) {
            targets.insert(.claudeCode)
        }
        if sessions.contains(where: { $0.desktopInstallation != nil }) {
            targets.insert(.claudeDesktop)
        }
        return targets
    }

    private static func loadConfiguration(from preferences: UserDefaults) -> LoadedConfiguration {
        if let data = preferences.data(forKey: configurationKey),
           var saved = try? JSONDecoder().decode(SandboxSharedConfiguration.self, from: data) {
            saved.upstream.password = ""
            return LoadedConfiguration(configuration: saved, hasSavedConfiguration: true)
        }
        if let data = preferences.data(forKey: legacyConfigurationKey),
           var legacy = try? JSONDecoder().decode(IsolationConfiguration.self, from: data) {
            legacy.upstream.password = ""
            return LoadedConfiguration(
                configuration: SandboxSharedConfiguration(legacy: legacy),
                hasSavedConfiguration: true
            )
        }
        return LoadedConfiguration(
            configuration: SandboxSharedConfiguration(),
            hasSavedConfiguration: false
        )
    }

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }
}
