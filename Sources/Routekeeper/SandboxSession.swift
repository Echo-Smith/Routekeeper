import AppKit
import Darwin
import Foundation
import GuardCore
import Observation

enum ClaudeLoginCallbackStatus: Equatable {
    case idle
    case invalid
    case waiting
    case delivered
    case failed
}

enum SandboxPauseReason: Equatable {
    case none
    case manual
    case networkChange(String)
    case sleeping

    var allowsAutomaticResume: Bool {
        switch self {
        case .networkChange, .sleeping: return true
        case .none, .manual: return false
        }
    }
}

@MainActor
@Observable
final class SandboxSession {
    var phase: IsolationPhase = .ready
    var configuration: IsolationConfiguration {
        didSet {
            persistConfiguration()
            configurationDidChange?(configuration)
        }
    }
    @ObservationIgnored var configurationDidChange: ((IsolationConfiguration) -> Void)?
    var checks: [IsolationCheck] = []
    var message = "选择项目和交换文件夹后，可以创建隔离会话。"
    var sessionRoot: URL?
    var exchangePath: String?
    var changedFiles: [String] = []
    var claudeRunning = false
    var networkEnabled = false
    var busy = false
    var relayPort: Int?
    var detectedProxy: SystemProxyDescriptor?
    var expectedExits = IsolationExpectedExits()
    var proxyDetectionMessage = "创建会话时会重新读取当前系统代理。"
    var claudeCodeInstallation: ClaudeCodeInstallation? = nil
    var desktopInstallation: ClaudeDesktopInstallation? = nil
    var desktopAppRunningOutsideSandbox = false
    var claudeLoginCallbackStatus: ClaudeLoginCallbackStatus = .idle
    var claudeLoginCallbackMessage = "不会读取邮箱；请手动粘贴邮件中的 Claude 登录链接。"
    var persistedClaudeProfileAvailable = false
    var networkValidationInProgress = false
    let externalActions = ExternalActionController()
    private(set) var pauseReason: SandboxPauseReason = .none

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let sessionsRoot: URL
    @ObservationIgnored private let profilesRoot: URL
    @ObservationIgnored private let relay = LocalRelay()
    @ObservationIgnored private var activeExecutable: URL?
    @ObservationIgnored private var desktopProcess: Process?
    @ObservationIgnored private var processCheckTask: Task<Void, Never>?
    @ObservationIgnored private var scienceWindow: ScienceShellWindowController?
    @ObservationIgnored private var scienceProcessLog: ScienceProcessLog?
    @ObservationIgnored private var scienceWindowTask: Task<Void, Never>?
    @ObservationIgnored private var networkValidationTask: Task<Void, Never>?
    @ObservationIgnored private var networkValidationGeneration = 0
    @ObservationIgnored private var lastAcceptedNetworkFingerprint: NetworkFingerprint?
    @ObservationIgnored private let persistsConfiguration: Bool

    private static let configurationKey = "routekeeper-isolation-configuration-v1"

    init(
        preferences: UserDefaults = .standard,
        sessionsRoot: URL? = nil,
        profilesRoot: URL? = nil,
        initialConfiguration: IsolationConfiguration? = nil,
        persistsConfiguration: Bool = true
    ) {
        self.preferences = preferences
        self.persistsConfiguration = persistsConfiguration
        let applicationSupport = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Routekeeper", isDirectory: true)
        self.sessionsRoot = sessionsRoot
            ?? applicationSupport.appendingPathComponent("Isolation", isDirectory: true)
        self.profilesRoot = profilesRoot
            ?? applicationSupport.appendingPathComponent("Profiles", isDirectory: true)
        var loaded = initialConfiguration
        if loaded == nil,
           let data = preferences.data(forKey: Self.configurationKey) {
            loaded = try? JSONDecoder().decode(IsolationConfiguration.self, from: data)
        }
        var sanitized = loaded ?? IsolationConfiguration()
        sanitized.upstream.password = ""
        configuration = sanitized
        if persistsConfiguration,
           let sanitizedData = try? JSONEncoder().encode(sanitized) {
            preferences.set(sanitizedData, forKey: Self.configurationKey)
        }
        persistedClaudeProfileAvailable = Self.hasOwnedClaudeProfile(
            at: self.profilesRoot.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        )
        refreshInstalledApplications()
        recoverOrphanedSessions()
    }

    var canPrepare: Bool {
        configuration.hasRequiredPaths && configuration.hasValidTimezone && configuration.hasValidLanguage
            && configuration.upstream.isValid && !busy && !phase.isActive
            && (detectedProxy?.isLoopback != false)
            && targetInstallationReady
    }

    var canLaunchClaude: Bool {
        !busy && (phase == .running || phase == .networkPaused)
    }

    var desktopInstalled: Bool {
        configuration.target != .claudeDesktop || desktopInstallation != nil
    }

    var codeInstalled: Bool {
        configuration.target != .claudeCode || claudeCodeInstallation != nil
    }

    var desktopIsolationSupported: Bool {
        configuration.target != .claudeDesktop
            || desktopInstallation?.supportsIsolatedLaunch == true
    }

    var targetInstallationReady: Bool {
        switch configuration.target {
        case .claudeCode: return claudeCodeInstallation != nil
        case .claudeDesktop: return desktopIsolationSupported
        }
    }

    var canPauseNetwork: Bool { !busy && phase == .running }
    var canResumeNetwork: Bool { !busy && phase == .networkPaused }
    var canEnd: Bool { phase.isActive || phase == .failed }
    var cleanupSessionsRoot: URL { sessionsRoot }
    var cleanupProfilesRoot: URL { profilesRoot }

    var statusTitle: String {
        switch phase {
        case .disabled: return "未开启"
        case .ready:
            if configuration.target == .claudeCode, claudeCodeInstallation == nil {
                return "未检测到 Claude Code"
            }
            if configuration.target == .claudeDesktop, !desktopIsolationSupported {
                return desktopInstallation == nil
                    ? "未检测到 Claude Desktop"
                    : "Claude Desktop 无法隔离启动"
            }
            return configuration.hasRequiredPaths ? "可以创建会话" : "等待选择会话范围"
        case .preparing: return "正在准备隔离环境"
        case .checking: return "正在验证隔离边界"
        case .running:
            return configuration.target == .claudeDesktop
                ? "官方 Claude Desktop 已隔离"
                : "沙箱已隔离"
        case .networkPaused: return "网络已关闭"
        case .failed: return "启动失败"
        case .ended: return "会话已结束"
        }
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

    var sessionLocaleIdentifier: String {
        IsolationSessionEnvironment.posixLocale(for: configuration.languageIdentifier)
    }

    var configurationMatchesDetectedProxy: Bool {
        configuration.upstream.matches(detectedProxy)
    }

    var proxyConsistencyTitle: String {
        guard let detectedProxy else { return "未检测到系统代理" }
        guard detectedProxy.isLoopback else { return "系统代理不是本机端口" }
        return configurationMatchesDetectedProxy
            ? "沙箱与系统代理一致"
            : "沙箱与系统代理不一致"
    }

    var proxyConsistencyDetail: String {
        guard let detectedProxy else {
            return "当前可能使用 TUN，或系统代理没有开启。请确认本页本地端口与代理客户端的混合端口或 HTTP/SOCKS 端口一致。"
        }
        guard detectedProxy.isLoopback else {
            return "系统代理地址为 \(detectedProxy.host)。实验性沙箱只接受本机回环代理，请在本机开启 HTTP 或 SOCKS 入口。"
        }
        let detected = "\(detectedProxy.protocolType.title) · \(detectedProxy.host):\(detectedProxy.port)"
        if configurationMatchesDetectedProxy {
            return "将使用当前系统代理 \(detected)。"
        }
        return "当前系统代理是 \(detected)；本页配置不同。创建会话时会自动改为当前系统代理。"
    }

    func refreshDetectedProxy(alignIfNeeded: Bool = false) {
        detectedProxy = SystemProxyDescriptor.current()
        guard let detectedProxy else {
            proxyDetectionMessage = "未检测到明确的系统代理，继续使用本页设置的本地端口。"
            return
        }
        guard detectedProxy.isLoopback else {
            proxyDetectionMessage = "检测到非本机系统代理；实验性沙箱不能直接使用它。"
            return
        }
        if alignIfNeeded && !configuration.upstream.matches(detectedProxy) {
            configuration.upstream.host = detectedProxy.host
            configuration.upstream.port = detectedProxy.port
            configuration.upstream.protocolType = detectedProxy.protocolType
            proxyDetectionMessage = "已自动匹配当前系统代理 \(detectedProxy.host):\(detectedProxy.port)。"
        } else if configuration.upstream.matches(detectedProxy) {
            proxyDetectionMessage = "当前配置与系统代理一致。"
        } else {
            proxyDetectionMessage = "检测到新的系统代理配置，可手动重新检测或在创建会话时自动匹配。"
        }
    }

    func refreshDesktopDiscovery() {
        desktopInstallation = ClaudeDesktopDiscovery.locate()
        desktopAppRunningOutsideSandbox = !ClaudeDesktopDiscovery.runningBundleIdentifiers().isEmpty
    }

    func refreshClaudeCodeDiscovery() {
        claudeCodeInstallation = ClaudeCodeDiscovery.locate(
            manualPath: preferences.string(forKey: ClaudeCodeDiscovery.manualPathPreferenceKey)
        )
    }

    func refreshInstalledApplications() {
        refreshClaudeCodeDiscovery()
        refreshDesktopDiscovery()
    }

    @discardableResult
    func selectClaudeCodeCommand(at url: URL) -> Bool {
        guard let installation = ClaudeCodeDiscovery.inspect(
            executableURL: url,
            source: .manuallySelected
        ) else {
            message = "所选文件不是可执行的 claude 命令。请选择文件名称为 claude 的可执行文件。"
            return false
        }
        preferences.set(
            installation.executableURL.path,
            forKey: ClaudeCodeDiscovery.manualPathPreferenceKey
        )
        claudeCodeInstallation = installation
        message = "已选择现有 Claude Code 命令；Routekeeper 会直接使用它，不会复制或覆盖安装。"
        return true
    }

    func prepare(expectedExits: IsolationExpectedExits) async {
        self.expectedExits = expectedExits
        refreshDetectedProxy(alignIfNeeded: true)
        refreshInstalledApplications()
        if configuration.target == .claudeCode, claudeCodeInstallation == nil {
            message = "未检测到可执行的 claude 命令。请先安装 Claude Code，或在本卡片中选择命令后重试。"
            return
        }
        if configuration.target == .claudeDesktop, desktopInstallation == nil {
            message = "没有找到已验证签名的官方 Claude Desktop。请先从 Anthropic 官方渠道安装，再返回本页重新检测。"
            return
        }
        if configuration.target == .claudeDesktop, !desktopIsolationSupported {
            message = "已找到 Claude Desktop，但当前版本没有可用于隔离启动的官方入口。请更新官方客户端后重新检测。"
            return
        }
        guard canPrepare else {
            message = detectedProxy?.isLoopback == false
                ? "当前系统代理不是本机端口。请先在代理客户端开启本机 HTTP 或 SOCKS 入口。"
                : "请先填写项目和交换文件夹，并确认时区、语言与本地代理端口。"
            return
        }
        guard expectedExits.hasAny else {
            message = "还没有保存可核对的固定出口。请先在网络体检中确认并保存 IPv4 或 IPv6 出口。"
            return
        }
        busy = true
        phase = .preparing
        checks = []
        changedFiles = []
        claudeRunning = false
        networkEnabled = false
        claudeLoginCallbackStatus = .idle
        claudeLoginCallbackMessage = "不会读取邮箱；请手动粘贴邮件中的 Claude 登录链接。"
        message = "正在复制项目并建立本次会话目录。"
        defer { busy = false }

        do {
            let proxyAtStart = detectedProxy
            let paths = try createSession()
            externalActions.start(exchange: paths.exchange)
            let copyResult: WorkspaceCopyKind?
            if let originalProject = paths.originalProject {
                message = "正在创建项目工作副本。"
                copyResult = try await Task.detached(priority: .userInitiated) {
                    try Self.copyProject(from: originalProject, to: paths.layout.workspace)
                }.value
            } else {
                copyResult = nil
            }

            phase = .checking
            message = copyResult == .clone
                ? "已建立 APFS 写时复制工作副本，正在验证文件与网络边界。"
                : copyResult == .copy
                    ? "已建立普通项目副本，正在验证文件与网络边界。"
                    : "已建立空工作区，正在验证文件与网络边界。"
            let port = try relay.start(upstream: configuration.upstream)
            relayPort = port
            let expectedExits = expectedExits
            let desktopApplicationURL = desktopInstallation?.appURL
            let inputMethodApplications = InputMethodCompatibility.enabledApplications()
            let result = await Task.detached(priority: .userInitiated) {
                [configuration, relay, paths, expectedExits, desktopApplicationURL, inputMethodApplications] in
                Self.runPreflight(
                    configuration: configuration,
                    paths: paths,
                    applicationURL: desktopApplicationURL,
                    relayPort: port,
                    environment: relay.proxyEnvironment(),
                    expectedExits: expectedExits,
                    inputMethodApplications: inputMethodApplications
                )
            }.value
            detectedProxy = SystemProxyDescriptor.current()
            checks = withTargetChecks(
                withDetectedProxyCheck(result.checks, expected: proxyAtStart)
            )
            activeExecutable = result.executable

            guard !checks.contains(where: \.blocksLaunch) else {
                relay.pause()
                phase = .failed
                networkEnabled = false
                message = result.failure.isEmpty
                    ? "隔离自检没有通过，受限程序未启动。请按下方检查项处理。"
                    : result.failure
                return
            }
            phase = .running
            networkEnabled = true
            pauseReason = .none
            lastAcceptedNetworkFingerprint = result.networkFingerprint(
                proxy: proxyAtStart,
                upstream: configuration.upstream
            )
            let warningSuffix = checks.contains(where: { $0.isWarning && !$0.passed })
                ? "出口核对有警告，但安全边界已通过；会话按你的选择继续。"
                : ""
            message = configuration.target == .claudeDesktop
                ? "文件、系统代理、官方客户端签名和断网边界已验证。\(warningSuffix)下一步可启动官方 Claude Desktop。"
                : "文件、系统代理、中继路径和断网边界已验证。\(warningSuffix)下一步可在终端启动 Claude Code。"
        } catch {
            relay.stop()
            networkEnabled = false
            phase = .failed
            message = "无法创建沙箱会话：\(error.localizedDescription)"
        }
    }

    func launchClaudeCode(token: String) {
        guard configuration.target == .claudeCode else {
            message = "当前会话选择了 Claude Desktop，请使用桌面客户端启动。"
            return
        }
        guard canLaunchClaude else {
            message = "请先通过沙箱自检，再启动 Claude Code。"
            return
        }
        guard let root = sessionRoot else {
            message = "找不到本次沙箱会话目录，请重新创建。"
            return
        }
        refreshClaudeCodeDiscovery()
        guard let executable = claudeCodeInstallation?.executableURL else {
            message = "没有找到可用的 Claude Code 命令。请先安装 Claude Code，或在本卡片中选择命令。"
            return
        }
        let layout = IsolationSessionLayout(root: root)
        guard let exchangePath, let originalProject = configurationPath(configuration.projectPath) else {
            message = "Claude Code 的项目或交换文件夹路径已变化，请重新创建会话。"
            return
        }
        do {
            let paths = resolvedPaths(
                originalProject: originalProject,
                exchange: URL(fileURLWithPath: exchangePath, isDirectory: true),
                layout: layout
            )
            let profile = IsolationSandboxProfile.make(
                paths: paths,
                executableURL: executable,
                relayPort: try XCTUnwrapPort(relayPort)
            )
            try writePrivate(Data(profile.utf8), to: layout.profile)
            activeExecutable = executable
            let script = try makeLaunchScript(
                token: token,
                executable: executable,
                profile: layout.profile,
                layout: layout,
                home: paths.runtimeHome,
                exchange: paths.exchange
            )
            guard openTerminal(script: script) else {
                try? FileManager.default.removeItem(at: script)
                throw LocalRelayError.socket("无法打开 Terminal。")
            }
            claudeRunning = true
            message = phase == .networkPaused
                ? "Claude Code 已在沙箱中启动；网络当前关闭，恢复网络后才能访问代理。"
                : "Claude Code 已在沙箱中启动，终端中的新命令会继承相同限制。"
            beginProcessChecks(profile: layout.profile)
        } catch {
            message = "Claude Code 未启动：\(error.localizedDescription)"
        }
    }

    func launchClaudeDesktop() {
        guard configuration.target == .claudeDesktop else {
            message = "当前会话选择了 Claude Code，请使用终端启动。"
            return
        }
        guard canLaunchClaude else {
            message = "请先通过沙箱自检，再启动 Claude Desktop。"
            return
        }
        guard !claudeRunning else {
            message = "当前沙箱会话中的 Claude Desktop 已在运行。请先结束会话，再重新启动。"
            return
        }
        guard let installation = desktopInstallation ?? ClaudeDesktopDiscovery.locate() else {
            message = "没有找到已验证签名的官方 Claude Desktop。请先从 Anthropic 官方渠道安装。"
            return
        }
        if installation.runtimeFamily == .electron,
           !ClaudeDesktopDiscovery.runningBundleIdentifiers().isEmpty {
            desktopAppRunningOutsideSandbox = true
            message = "检测到 Claude Desktop 已在沙箱外运行。请先完全退出它及其菜单栏进程，再回到本页重新检测并启动，避免普通实例被重新激活。"
            return
        }
        guard installation.supportsIsolatedLaunch else {
            message = "没有找到可安全托管的官方 Claude 客户端。Routekeeper 不会让 Science 回退到沙箱外浏览器。"
            return
        }
        guard let root = sessionRoot else {
            message = "找不到本次沙箱会话目录，请重新创建。"
            return
        }
        let layout = IsolationSessionLayout(root: root)
        guard let exchangePath else {
            message = "交换文件夹路径已变化，请重新创建会话。"
            return
        }
        let originalProject = configurationPath(configuration.projectPath)
        do {
            let paths = resolvedPaths(
                originalProject: originalProject,
                exchange: URL(fileURLWithPath: exchangePath, isDirectory: true),
                layout: layout
            )
            let profile = IsolationSandboxProfile.makeDesktop(
                paths: paths,
                applicationURL: installation.appURL,
                relayPort: try XCTUnwrapPort(relayPort),
                inputMethodApplications: InputMethodCompatibility.enabledApplications()
            )
            try writePrivate(Data(profile.utf8), to: layout.profile)
            try prepareDesktopRuntime(installation: installation, paths: paths)
            let relayEnvironment = relay.proxyEnvironment()
            switch installation.runtimeFamily {
            case .electron:
                try launchElectronDesktop(
                    installation: installation,
                    paths: paths,
                    layout: layout,
                    root: root,
                    relayEnvironment: relayEnvironment
                )
            case .operonHostedWeb:
                try launchHostedScience(
                    installation: installation,
                    paths: paths,
                    layout: layout,
                    root: root,
                    relayEnvironment: relayEnvironment
                )
            }
        } catch {
            if desktopProcess != nil {
                terminateClaudeProcesses()
            }
            claudeRunning = false
            message = "Claude Desktop 未启动：\(error.localizedDescription)"
        }
    }

    /// Validate a copied mail link in memory and deliver it only to the Claude
    /// process already recorded by this sandbox session.
    @discardableResult
    func submitClaudeLoginLink(_ rawLink: String) -> Bool {
        guard configuration.target == .claudeDesktop else {
            failClaudeLogin("当前会话不是 Claude Desktop。")
            return false
        }
        guard phase == .running, networkEnabled else {
            failClaudeLogin("请先恢复沙箱网络，再提交登录回调。")
            return false
        }
        guard claudeRunning, let root = sessionRoot, let identity = recordedProcess(root: root) else {
            failClaudeLogin("沙箱中的 Claude Desktop 尚未运行，或进程身份已失效。")
            return false
        }
        guard let installation = desktopInstallation,
              installation.runtimeFamily == .electron else {
            failClaudeLogin("当前官方客户端不支持这个登录回调通道。")
            return false
        }

        let callback: ClaudeLoginCallback
        do {
            callback = try ClaudeLoginCallback.parse(rawLink)
        } catch {
            claudeLoginCallbackStatus = .invalid
            claudeLoginCallbackMessage = "链接格式无效。只接受 Claude 官方一次性登录链接、SSO 或 Google 登录回调。"
            return false
        }

        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: installation.bundleIdentifier
        )
        guard running.count == 1,
              let application = running.first,
              application.processIdentifier == identity.pid,
              application.bundleURL?.standardizedFileURL.resolvingSymlinksInPath()
                == installation.appURL.standardizedFileURL.resolvingSymlinksInPath() else {
            failClaudeLogin("需要且只能有本次沙箱记录的 Claude Desktop 实例在运行。请结束会话后重新启动。")
            return false
        }

        claudeLoginCallbackStatus = .waiting
        claudeLoginCallbackMessage = "正在把经过校验的回调交给沙箱中的 Claude…"
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        openConfiguration.addsToRecentItems = false
        openConfiguration.createsNewApplicationInstance = false
        NSWorkspace.shared.open(
            [callback.callbackURL],
            withApplicationAt: installation.appURL,
            configuration: openConfiguration
        ) { [weak self] openedApplication, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil || openedApplication == nil {
                    self.failClaudeLogin("登录回调未能交给沙箱中的 Claude。链路内容没有写入日志。")
                    return
                }
                guard let openedApplication,
                      openedApplication.processIdentifier == identity.pid else {
                    if let openedApplication,
                       openedApplication.bundleIdentifier == installation.bundleIdentifier {
                        openedApplication.terminate()
                    }
                    self.failClaudeLogin("系统尝试启动新的 Claude 实例，已中止该回调。请结束会话后重新创建。")
                    return
                }
                self.claudeLoginCallbackStatus = .delivered
                self.claudeLoginCallbackMessage = switch callback.kind {
                case .magicLink:
                    "一次性登录链接已交给沙箱中的 Claude。请等待客户端完成登录，不要再次在浏览器中打开邮件链接。"
                case .ssoCallback:
                    "SSO 回调已交给沙箱中的 Claude。请等待客户端完成登录。"
                case .googleAuth:
                    "Google 登录回调已交给沙箱中的 Claude。请等待客户端完成登录。"
                }
            }
        }
        return true
    }

    private func failClaudeLogin(_ message: String) {
        claudeLoginCallbackStatus = .failed
        claudeLoginCallbackMessage = message
    }

    private func launchElectronDesktop(
        installation: ClaudeDesktopInstallation,
        paths: IsolationResolvedPaths,
        layout: IsolationSessionLayout,
        root: URL,
        relayEnvironment: [String: String]
    ) throws {
        activeExecutable = installation.executableURL
        let logURL = layout.logs.appendingPathComponent("claude-desktop.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-f", layout.profile.path, installation.executableURL.path]
        process.arguments?.append(
            contentsOf: Self.desktopLocaleLaunchArguments(
                for: configuration.timezoneIdentifier,
                languageIdentifier: configuration.languageIdentifier
            )
        )
        guard let proxyURL = relay.socks5URL() else { throw LocalRelayError.stopped }
        process.arguments?.append("--no-sandbox")
        process.arguments?.append("--proxy-server=\(proxyURL)")
        process.arguments?.append("--disable-quic")
        process.arguments?.append("--use-mock-keychain")
        process.currentDirectoryURL = layout.workspace
        process.environment = desktopEnvironment(
            paths: paths,
            relayEnvironment: relayEnvironment,
            runtimeFamily: .electron
        )
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        logHandle.closeFile()
        desktopProcess = process
        Thread.sleep(forTimeInterval: 2)
        guard process.isRunning else {
            let logTail = (try? String(contentsOf: logURL, encoding: .utf8))
                .map { String($0.suffix(4_000)) }
                ?? ""
            throw NSError(
                domain: "Routekeeper.Desktop",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: logTail.isEmpty
                        ? "Claude Desktop 启动后立即退出，请查看会话日志。"
                        : "Claude Desktop 启动后立即退出。日志末尾：\n\(logTail)"
                ]
            )
        }

        try writeDesktopProcessRecord(
            pid: process.processIdentifier,
            executableURL: installation.executableURL,
            root: root
        )
        claudeRunning = true
        desktopAppRunningOutsideSandbox = true
        message = phase == .networkPaused
            ? "Claude Desktop 已在沙箱中启动；网络当前关闭，恢复网络后才能访问代理。"
            : "Claude Desktop 已在沙箱中启动；Chat 的内置网页工作区和由本次实例派生的辅助进程会沿用相同的文件与网络限制。启动后仍会持续审计监听地址。"
        beginProcessChecks(profile: layout.profile)
    }

    private func launchHostedScience(
        installation: ClaudeDesktopInstallation,
        paths: IsolationResolvedPaths,
        layout: IsolationSessionLayout,
        root: URL,
        relayEnvironment: [String: String]
    ) throws {
        guard let executable = installation.scienceWebExecutableURL else {
            throw NSError(
                domain: "Routekeeper.Science",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "官方 Science 包内没有通过签名校验的本地服务。"]
            )
        }
        let log = try ScienceProcessLog(
            logURL: layout.logs.appendingPathComponent("claude-science.log")
        )
        scienceProcessLog = log

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = [
            "-f", layout.profile.path,
            executable.path,
            "serve",
            "--no-browser",
            "--no-auto-update",
            "--host", "127.0.0.1",
            "--port", "0",
            "--sandbox-port", "0"
        ]
        process.currentDirectoryURL = layout.workspace
        process.environment = desktopEnvironment(
            paths: paths,
            relayEnvironment: relayEnvironment,
            runtimeFamily: .operonHostedWeb
        )
        process.standardOutput = log.pipe
        process.standardError = log.pipe
        try process.run()
        desktopProcess = process
        activeExecutable = executable
        Thread.sleep(forTimeInterval: 0.25)
        guard process.isRunning else {
            throw NSError(
                domain: "Routekeeper.Science",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Claude Science 服务启动后立即退出，请查看会话日志。"]
            )
        }

        try writeDesktopProcessRecord(
            pid: process.processIdentifier,
            executableURL: executable,
            root: root
        )
        claudeRunning = true
        desktopAppRunningOutsideSandbox = true
        message = phase == .networkPaused
            ? "Claude Science 已在沙箱中启动；网络当前关闭，恢复网络后才能完成本机窗口登录。"
            : "Claude Science 沙箱服务已启动，正在准备 Routekeeper 受控窗口。"
        beginProcessChecks(profile: layout.profile)
        beginHostedScienceWindow(
            log: log,
            process: process,
            root: root,
            exchange: paths.exchange
        )
    }

    private func beginHostedScienceWindow(
        log: ScienceProcessLog,
        process: Process,
        root: URL,
        exchange: URL
    ) {
        scienceWindowTask?.cancel()
        scienceWindowTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loginURL = try await log.waitForLoginURL()
                guard !Task.isCancelled,
                      self.desktopProcess === process,
                      self.phase.isActive else {
                    return
                }
                guard let appPort = loginURL.port else {
                    throw ScienceShellError.contentRulesUnavailable
                }

                var ports = Set<Int>()
                var sawAuditError: String?
                for _ in 0..<80 {
                    guard let identity = self.recordedProcess(root: root) else { break }
                    let pids = [identity.pid] + self.descendants(of: identity.pid)
                    let audit = await Task.detached(priority: .userInitiated) {
                        Self.auditLoopbackListeners(pids: pids)
                    }.value
                    if let error = audit.error {
                        sawAuditError = error
                        break
                    }
                    if !audit.nonLoopback.isEmpty {
                        self.failListenerAudit(
                            "检测到受限 Claude Science 在非回环地址监听 TCP：\(audit.nonLoopback.joined(separator: "；"))。会话已终止。"
                        )
                        return
                    }
                    ports.formUnion(audit.ports)
                    if ports.contains(appPort), ports.count >= 2 { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard sawAuditError == nil,
                      ports.contains(appPort),
                      ports.count >= 2 else {
                    throw NSError(
                        domain: "Routekeeper.Science",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: sawAuditError
                                ?? "Science 服务没有同时暴露应用和预览两个回环端口。"
                        ]
                    )
                }

                let window = try await ScienceShellWindowController.present(
                    loginURL: loginURL,
                    ports: ports,
                    exchangeURL: exchange
                )
                guard !Task.isCancelled, self.desktopProcess === process else {
                    window.closeFromRoutekeeper()
                    return
                }
                self.scienceWindow = window
                window.onClose = { [weak self, weak window] controller in
                    guard let self, let window, self.scienceWindow === window else { return }
                    self.scienceWindow = nil
                    self.terminateClaudeProcesses()
                    self.claudeRunning = false
                    self.message = "Science 窗口已关闭，本地服务已停止。可重新启动或结束本次会话。"
                }
                self.message = self.phase == .networkPaused
                    ? "Claude Science 窗口已打开；网络当前关闭，恢复网络后才能继续使用。"
                    : "Claude Science 已在 Routekeeper 窗口中运行；网页视图只能访问本地服务的两个回环端口。"
            } catch {
                guard !Task.isCancelled, self.desktopProcess === process else { return }
                self.terminateClaudeProcesses()
                self.claudeRunning = false
                self.message = "Claude Science 窗口未打开：\(error.localizedDescription)"
            }
        }
    }

    func pauseNetwork() {
        guard canPauseNetwork else { return }
        networkValidationTask?.cancel()
        networkValidationGeneration += 1
        networkValidationInProgress = false
        relay.pause()
        networkEnabled = false
        phase = .networkPaused
        pauseReason = .manual
        message = "网络已关闭。Claude 进程仍在运行，已有连接已断开，新的直连和中继连接都会失败。"
    }

    func invalidateNetwork(reason: String) {
        guard phase == .running else { return }
        pauseNetworkAutomatically(reason: .networkChange(reason), message: reason)
    }

    func networkEnvironmentChanged(
        _ reason: String,
        sleeping: Bool,
        waking: Bool
    ) {
        guard phase == .running || phase == .networkPaused else { return }
        if sleeping {
            networkValidationTask?.cancel()
            networkValidationGeneration += 1
            networkValidationInProgress = false
            if phase == .networkPaused, pauseReason == .manual {
                message = "系统即将休眠；你手动关闭的网络会保持关闭，唤醒后不会自动恢复。"
                return
            }
            pauseNetworkAutomatically(
                reason: .sleeping,
                message: "系统即将休眠，沙箱网络已关闭；唤醒后会等待网络稳定并自动复检。"
            )
            return
        }
        guard phase == .running || pauseReason.allowsAutomaticResume else { return }
        scheduleNetworkRevalidation(reason: reason, waking: waking)
    }

    private func pauseNetworkAutomatically(reason: SandboxPauseReason, message: String) {
        relay.pause()
        networkEnabled = false
        phase = .networkPaused
        pauseReason = reason
        self.message = message
    }

    func resumeNetwork() async {
        await resumeNetwork(automatically: false)
    }

    private func resumeNetwork(automatically: Bool) async {
        guard canResumeNetwork else { return }
        if !automatically {
            networkValidationTask?.cancel()
            networkValidationGeneration += 1
            networkValidationInProgress = false
        }
        if automatically {
            guard pauseReason.allowsAutomaticResume else { return }
            let proxy = SystemProxyDescriptor.current()
            detectedProxy = proxy
            if let proxy, !proxy.isLoopback || !configuration.upstream.matches(proxy) {
                pauseNetworkAutomatically(
                    reason: .networkChange("唤醒时检测到代理地址、端口或协议已变化"),
                    message: "唤醒后发现代理入口已变化。为保持身份链路一致，网络保持关闭；请确认代理后手动恢复。"
                )
                return
            }
        } else {
            refreshDetectedProxy(alignIfNeeded: true)
        }
        guard detectedProxy?.isLoopback != false else {
            phase = .networkPaused
            networkEnabled = false
            message = "系统代理已变为非本机地址。请恢复本机 HTTP 或 SOCKS 入口后再试。"
            return
        }
        busy = true
        phase = .checking
        message = "正在恢复本地中继，并重新核对代理配置、Claude 路径和保存出口。"
        defer { busy = false }
        do {
            let proxyAtStart = detectedProxy
            let port = try relay.start(upstream: configuration.upstream)
            guard let root = sessionRoot else { throw LocalRelayError.stopped }
            let layout = IsolationSessionLayout(root: root)
            let project = configurationPath(configuration.projectPath)
            let exchange = URL(fileURLWithPath: exchangePath ?? configuration.exchangePath, isDirectory: true)
            let paths = resolvedPaths(
                originalProject: project,
                exchange: exchange,
                layout: layout
            )
            let expectedExits = expectedExits
            let desktopApplicationURL = desktopInstallation?.appURL
            let inputMethodApplications = InputMethodCompatibility.enabledApplications()
            let result = await Task.detached {
                [configuration, relay, expectedExits, desktopApplicationURL, inputMethodApplications] in
                Self.runPreflight(
                    configuration: configuration,
                    paths: paths,
                    applicationURL: desktopApplicationURL,
                    relayPort: port,
                    environment: relay.proxyEnvironment(),
                    expectedExits: expectedExits,
                    inputMethodApplications: inputMethodApplications
                )
            }.value
            detectedProxy = SystemProxyDescriptor.current()
            checks = withTargetChecks(
                withDetectedProxyCheck(result.checks, expected: proxyAtStart)
            )
            guard !checks.contains(where: \.blocksLaunch) else {
                relay.pause()
                phase = .networkPaused
                networkEnabled = false
                pauseReason = automatically
                    ? .networkChange("自动复检未通过")
                    : .manual
                message = result.failure.isEmpty
                    ? "网络没有恢复：请查看未通过项。"
                    : result.failure
                return
            }
            lastAcceptedNetworkFingerprint = result.networkFingerprint(
                proxy: detectedProxy,
                upstream: configuration.upstream
            )
            networkEnabled = true
            phase = .running
            pauseReason = .none
            let warningSuffix = checks.contains(where: { $0.isWarning && !$0.passed })
                ? "出口核对仍有警告，但网络未中断。"
                : ""
            message = automatically
                ? "网络已自动恢复；代理配置未发生实质变化，Claude 路径和断网保护复检通过。\(warningSuffix)"
                : "网络已恢复；Claude 路径和断网保护重新验证通过。\(warningSuffix)"
        } catch {
            relay.pause()
            networkEnabled = false
            phase = .networkPaused
            pauseReason = automatically
                ? .networkChange("自动复检失败")
                : .manual
            message = "网络没有恢复：\(error.localizedDescription)"
        }
    }

    private func scheduleNetworkRevalidation(reason: String, waking: Bool) {
        networkValidationTask?.cancel()
        networkValidationGeneration += 1
        let generation = networkValidationGeneration
        networkValidationInProgress = true
        if phase == .running {
            message = "检测到网络状态变化，正在等待稳定后复检；代理配置未变时不会中断 Claude。"
        }
        networkValidationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, let self, self.networkValidationGeneration == generation else {
                return
            }
            guard self.phase == .running
                    || (self.phase == .networkPaused && self.pauseReason.allowsAutomaticResume) else {
                self.networkValidationInProgress = false
                return
            }

            var sampledProxy = SystemProxyDescriptor.current()
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, self.networkValidationGeneration == generation else {
                    return
                }
                let next = SystemProxyDescriptor.current()
                if next != sampledProxy {
                    sampledProxy = next
                }
            }
            self.detectedProxy = sampledProxy
            if let sampledProxy, !sampledProxy.isLoopback {
                self.networkValidationInProgress = false
                self.pauseNetworkAutomatically(
                    reason: .networkChange(reason),
                    message: "网络复检发现系统代理不再指向本机入口，沙箱已保持断网。"
                )
                return
            }
            if let sampledProxy, !self.configuration.upstream.matches(sampledProxy) {
                self.networkValidationInProgress = false
                self.pauseNetworkAutomatically(
                    reason: .networkChange(reason),
                    message: "检测到代理地址、端口或协议发生实质变化，沙箱已断网。请确认新代理后手动恢复。"
                )
                return
            }

            if self.phase == .networkPaused {
                self.networkValidationInProgress = false
                await self.resumeNetwork(automatically: true)
            } else {
                await self.revalidateRunningRelay(
                    reason: reason,
                    waking: waking,
                    generation: generation
                )
            }
        }
    }

    private func revalidateRunningRelay(
        reason: String,
        waking: Bool,
        generation: Int
    ) async {
        guard phase == .running, let root = sessionRoot, !busy else {
            networkValidationInProgress = false
            return
        }
        let layout = IsolationSessionLayout(root: root)
        let project = configurationPath(configuration.projectPath)
        let exchange = URL(fileURLWithPath: exchangePath ?? configuration.exchangePath, isDirectory: true)
        let paths = resolvedPaths(
            originalProject: project,
            exchange: exchange,
            layout: layout
        )
        let expectedExits = expectedExits
        let desktopApplicationURL = desktopInstallation?.appURL
        let proxyAtStart = detectedProxy
        let inputMethodApplications = InputMethodCompatibility.enabledApplications()
        guard let relayPort else {
            networkValidationInProgress = false
            pauseNetworkAutomatically(
                reason: .networkChange(reason),
                message: "本地中继端口已丢失，沙箱已断网。"
            )
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            [configuration, relay, expectedExits, desktopApplicationURL, inputMethodApplications] in
            Self.runPreflight(
                configuration: configuration,
                paths: paths,
                applicationURL: desktopApplicationURL,
                relayPort: relayPort,
                environment: relay.proxyEnvironment(),
                expectedExits: expectedExits,
                inputMethodApplications: inputMethodApplications
            )
        }.value
        guard !Task.isCancelled, networkValidationGeneration == generation else { return }
        networkValidationInProgress = false
        detectedProxy = SystemProxyDescriptor.current()
        checks = withTargetChecks(
            withDetectedProxyCheck(result.checks, expected: proxyAtStart)
        )
        guard !checks.contains(where: \.blocksLaunch), result.relayReachable else {
            pauseNetworkAutomatically(
                reason: .networkChange(reason),
                message: "网络稳定性复检未通过，沙箱已断网；Claude 进程仍保留，可修正代理后手动恢复。"
            )
            return
        }
        let next = result.networkFingerprint(
            proxy: proxyAtStart,
            upstream: configuration.upstream
        )
        let exitChanged = lastAcceptedNetworkFingerprint?.exitAnchor != next.exitAnchor
        lastAcceptedNetworkFingerprint = next
        networkEnabled = true
        phase = .running
        pauseReason = .none
        let warningSuffix = checks.contains(where: { $0.isWarning && !$0.passed })
            ? "；出口核对仍有警告，但网络未中断。"
            : "。"
        message = waking
            ? "系统唤醒后复检通过，中继保持可用；Claude 连接未被 Routekeeper 主动重启\(warningSuffix)"
            : exitChanged
                ? "网络事件复检通过；出口锚点已更新，Claude 连接未被中断\(warningSuffix)"
                : "网络事件复检通过；代理配置和出口锚点未变，Claude 连接未被中断\(warningSuffix)"
    }

    func endSession() async {
        networkValidationTask?.cancel()
        networkValidationGeneration += 1
        networkValidationInProgress = false
        busy = true
        defer { busy = false }
        relay.stop()
        terminateClaudeProcesses()
        externalActions.stopScanning()
        networkEnabled = false
        claudeRunning = false
        pauseReason = .none
        lastAcceptedNetworkFingerprint = nil
        claudeLoginCallbackStatus = .idle
        claudeLoginCallbackMessage = "不会读取邮箱；请手动粘贴邮件中的 Claude 登录链接。"
        phase = .ended
        if let root = sessionRoot {
            let layout = IsolationSessionLayout(root: root)
            if let project = configurationPath(configuration.projectPath) {
                await refreshChanges(original: project, workspace: layout.workspace)
            }
        }
        message = changedFiles.isEmpty
            ? "会话已结束。沙箱网络已关闭，未发现项目文件变化。"
            : "会话已结束。项目变化仍保留在沙箱工作副本中，请审阅后再决定是否采用。"
    }

    func reset() {
        guard !phase.isActive else { return }
        networkValidationTask?.cancel()
        networkValidationGeneration += 1
        networkValidationInProgress = false
        if let root = sessionRoot { removeOwnedSession(at: root) }
        externalActions.clear()
        sessionRoot = nil
        exchangePath = nil
        activeExecutable = nil
        claudeCodeInstallation = nil
        desktopProcess = nil
        desktopAppRunningOutsideSandbox = false
        relayPort = nil
        checks = []
        changedFiles = []
        networkEnabled = false
        claudeRunning = false
        pauseReason = .none
        lastAcceptedNetworkFingerprint = nil
        claudeLoginCallbackStatus = .idle
        claudeLoginCallbackMessage = "不会读取邮箱；请手动粘贴邮件中的 Claude 登录链接。"
        phase = .ready
        message = "可以开始一个新的隔离会话。"
    }

    func clearForLocalDataReset() async -> Bool {
        guard !busy else { return false }
        if phase.isActive {
            await endSession()
        }
        reset()
        purgeOwnedSessions()
        purgeOwnedProfiles()
        configuration = IsolationConfiguration()
        preferences.removeObject(forKey: Self.configurationKey)
        preferences.removeObject(forKey: ClaudeCodeDiscovery.manualPathPreferenceKey)
        persistedClaudeProfileAvailable = false
        refreshInstalledApplications()
        phase = .ready
        message = "本地沙箱配置和会话副本已清空。"
        return true
    }

    @discardableResult
    func clearClaudeLoginState() -> Bool {
        guard !busy, !phase.isActive, !claudeRunning else {
            message = "请先结束会话并完全退出沙箱中的 Claude，再清除持久登录状态。"
            return false
        }
        let home = profilesRoot.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        guard Self.hasOwnedClaudeProfile(at: home) else {
            persistedClaudeProfileAvailable = false
            message = "没有找到 Routekeeper 创建的 Claude 持久登录数据。"
            return true
        }
        do {
            try FileManager.default.removeItem(at: home)
            let parent = home.deletingLastPathComponent()
            if let remaining = try? FileManager.default.contentsOfDirectory(atPath: parent.path),
               remaining.isEmpty {
                try? FileManager.default.removeItem(at: parent)
            }
            persistedClaudeProfileAvailable = false
            message = "已清除 Claude Desktop 的持久登录数据。下一次启用持久登录时需要重新登录。"
            return true
        } catch {
            message = "无法清除 Claude 持久登录数据：\(error.localizedDescription)"
            return false
        }
    }

    func openWorkspace() {
        guard let root = sessionRoot else { return }
        NSWorkspace.shared.open(IsolationSessionLayout(root: root).workspace)
    }

    private func withDetectedProxyCheck(
        _ checks: [IsolationCheck],
        expected: SystemProxyDescriptor?
    ) -> [IsolationCheck] {
        guard let expected else { return checks }
        let stable = detectedProxy == expected
        let matches = configuration.upstream.matches(expected)
        let detail: String
        if !stable {
            detail = "检查期间系统代理发生变化，请重新创建会话。"
        } else if matches {
            detail = "沙箱与当前系统代理一致：\(expected.protocolType.title) · \(expected.host):\(expected.port)"
        } else {
            detail = "沙箱配置与当前系统代理不同；请重新检测后再启动。"
        }
        return [
            .init(id: "system-proxy-config", title: "系统代理配置", detail: detail, passed: stable && matches)
        ] + checks
    }

    private func withTargetChecks(_ checks: [IsolationCheck]) -> [IsolationCheck] {
        guard configuration.target == .claudeDesktop else { return checks }
        guard let installation = desktopInstallation else {
            return [
                .init(
                    id: "desktop-signature",
                    title: "官方客户端签名",
                    detail: "未找到通过 Anthropic Team ID 校验的 Claude 桌面应用",
                    passed: false
                )
            ] + checks
        }
        return [
            .init(
                id: "desktop-signature",
                title: "官方客户端签名",
                detail: "\(installation.displayName) \(installation.shortVersion ?? "") 通过 Anthropic 签名校验",
                passed: true
            )
        ] + checks
    }

    private func resolvedPaths(
        originalProject: URL?,
        exchange: URL,
        layout: IsolationSessionLayout
    ) -> IsolationResolvedPaths {
        let identityHome: URL?
        if configuration.target == .claudeDesktop, configuration.persistClaudeLogin {
            let home = profilesRoot.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
            identityHome = Self.hasOwnedClaudeProfile(at: home) ? home.standardizedFileURL : nil
        } else {
            identityHome = nil
        }
        return .init(
            originalProject: originalProject,
            exchange: exchange,
            layout: layout,
            identityHome: identityHome
        )
    }

    private func createSession() throws -> IsolationResolvedPaths {
        relay.stop()
        sessionRoot = nil
        let fileManager = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        try fileManager.createDirectory(
            at: sessionsRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let root = sessionsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let marker = root.appendingPathComponent(".routekeeper-session")
        try Data("Routekeeper experimental isolation\n".utf8).write(to: marker, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)

        var paths = try IsolationPathValidator.validate(configuration, sessionRoot: root, home: home)
        paths.identityHome = try prepareDesktopIdentityHome()
        if let identityHome = paths.identityHome {
            for candidate in [paths.originalProject, Optional(paths.exchange)].compactMap({ $0 })
                where IsolationPathValidator.contains(identityHome, candidate)
                    || IsolationPathValidator.contains(candidate, identityHome) {
                throw IsolationValidationError.unsafePath(candidate.path)
            }
        }
        for directory in [paths.runtimeHome, paths.layout.temporary, paths.layout.control, paths.layout.logs] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        if paths.originalProject == nil {
            try fileManager.createDirectory(
                at: paths.layout.workspace,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.createDirectory(
            at: paths.runtimeHome.appendingPathComponent(".config"),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try writeSessionLocalePreferences(home: paths.runtimeHome)
        sessionRoot = root
        exchangePath = paths.exchange.path
        return paths
    }

    private func prepareDesktopIdentityHome() throws -> URL? {
        guard configuration.target == .claudeDesktop, configuration.persistClaudeLogin else {
            return nil
        }
        let home = profilesRoot.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        let marker = home.appendingPathComponent(".routekeeper-profile")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: home.path) {
            guard fileManager.fileExists(atPath: marker.path) else {
                throw NSError(
                    domain: "Routekeeper.Profile",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Claude 持久登录目录已存在，但不是由 Routekeeper 创建。为避免覆盖现有数据，已拒绝使用。"
                    ]
                )
            }
        } else {
            try fileManager.createDirectory(
                at: home,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data("Routekeeper persistent Claude Desktop profile\n".utf8)
                .write(to: marker, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        }
        persistedClaudeProfileAvailable = true
        return home.standardizedFileURL
    }

    private func writeSessionLocalePreferences(home: URL) throws {
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        try FileManager.default.createDirectory(
            at: preferences,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let locale = IsolationSessionEnvironment.posixLocale(for: configuration.languageIdentifier)
        let appleLanguage = IsolationSessionEnvironment.appleLanguage(for: configuration.languageIdentifier)
        let values: [String: Any] = [
            "AppleLocale": locale.replacingOccurrences(of: ".UTF-8", with: ""),
            "AppleLanguages": [appleLanguage]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try writePrivate(data, to: preferences.appendingPathComponent(".GlobalPreferences.plist"))
    }

    private func makeLaunchScript(
        token: String,
        executable: URL,
        profile: URL,
        layout: IsolationSessionLayout,
        home: URL,
        exchange: URL
    ) throws -> URL {
        let environment = relay.proxyEnvironment()
        let scriptURL = layout.control.appendingPathComponent("launch-\(UUID().uuidString).command")
        let processIDPath = layout.control.appendingPathComponent("sandbox.pid").path
        let processStartPath = layout.control.appendingPathComponent("sandbox.started").path
        let path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        let locale = IsolationSessionEnvironment.posixLocale(for: configuration.languageIdentifier)
        let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
        let appleLanguage = IsolationSessionEnvironment.appleLanguage(for: configuration.languageIdentifier)
        let appleLocale = locale.replacingOccurrences(of: ".UTF-8", with: "")
        var exports = [
            "HOME=\(home.path)",
            "TMPDIR=\(layout.temporary.path)",
            "TMP=\(layout.temporary.path)",
            "TEMP=\(layout.temporary.path)",
            "XDG_CONFIG_HOME=\(home.appendingPathComponent(".config").path)",
            "XDG_CACHE_HOME=\(home.appendingPathComponent(".cache").path)",
            "XDG_DATA_HOME=\(home.appendingPathComponent(".local/share").path)",
            "TZ=\(configuration.timezoneIdentifier)",
            "LANG=\(locale)",
            "LC_ALL=\(locale)",
            "LANGUAGE=\(language)",
            "AppleLanguages=\(appleLanguage)",
            "AppleLocale=\(appleLocale)",
            "PATH=\(path)",
            "TERM=xterm-256color",
            "CLAUDE_CODE_OAUTH_TOKEN=\(token)",
            "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1",
            "NODE_USE_ENV_PROXY=1",
            "ISOLATION_EXCHANGE=\(exchange.path)"
        ]
        exports += environment.keys.sorted().map { "\($0)=\(environment[$0] ?? "")" }
        let lines = [
            "#!/bin/zsh",
            "set -eu",
            "launch_script=\"$0\"",
            "unset SSH_AUTH_SOCK NODE_OPTIONS NODE_EXTRA_CA_CERTS",
            exports.map { "export \($0)" }.joined(separator: "\n"),
            "cd \(Self.shellQuote(layout.workspace.path))",
            "( /bin/sleep 2; /bin/rm -f -- \"$launch_script\" ) </dev/null >/dev/null 2>&1 &",
            "/usr/bin/sandbox-exec -f \(Self.shellQuote(profile.path)) \(Self.shellQuote(executable.path)) &",
            "sandbox_pid=$!",
            "printf '%s\\n' \"$sandbox_pid\" > \(Self.shellQuote(processIDPath))",
            "/bin/ps -p \"$sandbox_pid\" -o lstart= > \(Self.shellQuote(processStartPath))",
            "wait \"$sandbox_pid\""
        ]
        let wrapper = lines.joined(separator: "\n") + "\n"
        try Data(wrapper.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func openTerminal(script: URL) -> Bool {
        let source = """
        tell application "Terminal"
        activate
        do script \(Self.appleScriptString(Self.shellQuote(script.path)))
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func beginProcessChecks(profile: URL) {
        processCheckTask?.cancel()
        processCheckTask = Task { [weak self] in
            var firstAudit = true
            while !Task.isCancelled {
                try? await Task.sleep(for: firstAudit ? .milliseconds(250) : .seconds(1))
                firstAudit = false
                guard let self else { return }
                let root = IsolationSessionLayout(
                    root: profile.deletingLastPathComponent().deletingLastPathComponent()
                ).root
                guard let identity = self.recordedProcess(root: root) else {
                    self.desktopProcess = nil
                    self.desktopAppRunningOutsideSandbox = false
                    if self.claudeRunning { self.claudeRunning = false }
                    return
                }
                if self.configuration.target == .claudeDesktop {
                    let pids = [identity.pid] + self.descendants(of: identity.pid)
                    let audit = await Task.detached(priority: .userInitiated) {
                        Self.auditLoopbackListeners(pids: pids)
                    }.value
                    if let error = audit.error {
                        self.failListenerAudit(
                            "无法核验 Claude Desktop 的 TCP 监听地址，已按失败关闭策略终止会话：\(error)"
                        )
                        return
                    }
                    if !audit.nonLoopback.isEmpty {
                        self.failListenerAudit(
                            "检测到受限 Claude Desktop 在非回环地址监听 TCP：\(audit.nonLoopback.joined(separator: "；"))。会话已终止。"
                        )
                        return
                    }
                    if self.configuration.target == .claudeDesktop {
                        self.scienceWindow?.updateAllowedPorts(audit.ports)
                    }
                    self.setListenerAuditCheck(
                        detail: "当前 Claude 进程树的 TCP 监听均限于 127.0.0.1 或 ::1"
                    )
                }
                if !self.claudeRunning { self.claudeRunning = true }
                guard self.phase.isActive else { return }
            }
        }
    }

    private func setListenerAuditCheck(detail: String, passed: Bool = true) {
        checks.removeAll { $0.id == "listener-audit" }
        checks.insert(
            .init(id: "listener-audit", title: "监听地址审计", detail: detail, passed: passed),
            at: 0
        )
    }

    private func failListenerAudit(_ message: String) {
        setListenerAuditCheck(detail: message, passed: false)
        terminateClaudeProcesses()
        relay.pause()
        networkEnabled = false
        claudeRunning = false
        phase = .failed
        self.message = message
    }

    private func terminateClaudeProcesses() {
        processCheckTask?.cancel()
        processCheckTask = nil
        scienceWindowTask?.cancel()
        scienceWindowTask = nil
        scienceWindow?.closeFromRoutekeeper()
        scienceWindow = nil
        if let log = scienceProcessLog {
            Task { await log.stop() }
            scienceProcessLog = nil
        }
        defer {
            desktopProcess = nil
            desktopAppRunningOutsideSandbox = false
        }
        guard let root = sessionRoot else { return }
        let profile = IsolationSessionLayout(root: root).profile.path
        var trackedPIDs = Set<Int32>()
        if let identity = recordedProcess(root: root) {
            trackedPIDs.insert(identity.pid)
            trackedPIDs.formUnion(descendants(of: identity.pid))
        }
        if let desktopProcess { trackedPIDs.insert(desktopProcess.processIdentifier) }
        for pid in trackedPIDs { _ = Darwin.kill(pid, SIGTERM) }
        _ = Command.run("/usr/bin/pkill", ["-TERM", "-f", profile], timeout: 4)
        Thread.sleep(forTimeInterval: 0.45)
        if let identity = recordedProcess(root: root) {
            trackedPIDs.formUnion(descendants(of: identity.pid))
        }
        for pid in trackedPIDs where Darwin.kill(pid, 0) == 0 {
            _ = Darwin.kill(pid, SIGKILL)
        }
        _ = Command.run("/usr/bin/pkill", ["-KILL", "-f", profile], timeout: 4)
        try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.pid"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.started"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.executable"))
    }

    private func desktopEnvironment(
        paths: IsolationResolvedPaths,
        relayEnvironment: [String: String],
        runtimeFamily: ClaudeDesktopRuntimeFamily
    ) -> [String: String] {
        Self.desktopEnvironment(
            configuration: configuration,
            paths: paths,
            relayEnvironment: relayEnvironment,
            runtimeFamily: runtimeFamily,
            inherited: ProcessInfo.processInfo.environment
        )
    }

    nonisolated static func desktopLocaleLaunchArguments(
        for timezoneIdentifier: String,
        languageIdentifier: String? = nil
    ) -> [String] {
        let language = languageIdentifier
            ?? IsolationSessionEnvironment.defaultLanguageIdentifier(for: timezoneIdentifier)
        let locale = IsolationSessionEnvironment.posixLocale(for: language)
        let appleLanguage = IsolationSessionEnvironment.appleLanguage(for: language)
        let appleLocale = locale.replacingOccurrences(of: ".UTF-8", with: "")
        return ["-AppleLanguages", "(\(appleLanguage))", "-AppleLocale", appleLocale]
    }

    nonisolated static func desktopEnvironment(
        configuration: IsolationConfiguration,
        paths: IsolationResolvedPaths,
        relayEnvironment: [String: String],
        runtimeFamily: ClaudeDesktopRuntimeFamily = .electron,
        inherited: [String: String] = [:]
    ) -> [String: String] {
        let layout = paths.layout
        let runtimeHome = paths.runtimeHome
        let locale = IsolationSessionEnvironment.posixLocale(for: configuration.languageIdentifier)
        let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
        let appleLanguage = IsolationSessionEnvironment.appleLanguage(for: configuration.languageIdentifier)
        let appleLocale = locale.replacingOccurrences(of: ".UTF-8", with: "")
        var values = [
            "HOME": runtimeHome.path,
            "CFFIXED_USER_HOME": runtimeHome.path,
            "TMPDIR": layout.temporary.path,
            "TMP": layout.temporary.path,
            "TEMP": layout.temporary.path,
            "XDG_CONFIG_HOME": runtimeHome.appendingPathComponent(".config").path,
            "XDG_CACHE_HOME": runtimeHome.appendingPathComponent(".cache").path,
            "XDG_DATA_HOME": runtimeHome.appendingPathComponent(".local/share").path,
            "TZ": configuration.timezoneIdentifier,
            "LANG": locale,
            "LC_ALL": locale,
            "LANGUAGE": language,
            "AppleLanguages": appleLanguage,
            "AppleLocale": appleLocale,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "SHELL": "/bin/zsh",
            "NODE_USE_ENV_PROXY": "1",
            "NSUnbufferedIO": "YES",
            "ELECTRON_DISABLE_SANDBOX": "1",
            "ELECTRON_ENABLE_LOGGING": "1",
            "ELECTRON_LOG_FILE": layout.logs.appendingPathComponent("electron.log").path,
            "ISOLATION_WORKSPACE": layout.workspace.path,
            "ISOLATION_EXCHANGE": paths.exchange.path,
            "ISOLATION_ORIGINAL": paths.originalProject?.path ?? "",
            "ISOLATION_CONTROL": layout.control.path
        ]
        if runtimeFamily == .operonHostedWeb {
            values["OPERON_SKIP_INSTALL"] = "1"
        }
        for key in ["USER", "LOGNAME"] {
            if let value = inherited[key], !value.isEmpty {
                values[key] = value
            }
        }
        values.merge(relayEnvironment) { _, new in new }
        for (key, value) in relayEnvironment {
            values[key.lowercased()] = value
        }
        return values
    }

    private func prepareDesktopRuntime(
        installation: ClaudeDesktopInstallation,
        paths: IsolationResolvedPaths
    ) throws {
        guard installation.runtimeFamily == .operonHostedWeb else { return }
        let directory = paths.runtimeHome.appendingPathComponent(".claude-science", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let configuration = """
        [sandbox]
        hard_fail = false
        """
        try writePrivate(
            Data((configuration + "\n").utf8),
            to: directory.appendingPathComponent("config.toml")
        )
    }

    private func writeDesktopProcessRecord(
        pid: Int32,
        executableURL: URL,
        root: URL
    ) throws {
        let control = IsolationSessionLayout(root: root).control
        let process = Command.run("/bin/ps", ["-p", String(pid), "-o", "lstart="], timeout: 2)
        let start = process.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.status == 0, !start.isEmpty else {
            throw NSError(
                domain: "Routekeeper.Desktop",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法记录 Claude Desktop 的进程身份。"]
            )
        }
        try writePrivate(Data("\(pid)\n".utf8), to: control.appendingPathComponent("sandbox.pid"))
        try writePrivate(Data("\(start)\n".utf8), to: control.appendingPathComponent("sandbox.started"))
        try writePrivate(
            Data((executableURL.path + "\n").utf8),
            to: control.appendingPathComponent("sandbox.executable")
        )
    }

    private func refreshChanges(original: URL, workspace: URL) async {
        let result = await Task.detached {
            Command.run(
                "/usr/bin/diff",
                ["-qr", "--exclude=.git", original.path, workspace.path],
                timeout: 60
            )
        }.value
        guard result.status == 0 || result.status == 1 else {
            changedFiles = ["无法生成文件差异：\(result.output)"]
            return
        }
        changedFiles = result.status == 0
            ? []
            : result.output.split(separator: "\n").prefix(100).map(String.init)
    }

    private func persistConfiguration() {
        guard persistsConfiguration, phase.canChangeConfiguration else { return }
        var persisted = configuration
        persisted.upstream.password = ""
        if let data = try? JSONEncoder().encode(persisted) {
            preferences.set(data, forKey: Self.configurationKey)
        }
    }

    private func configurationPath(_ path: String) -> URL? {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
    }

    private func removeOwnedSession(at root: URL) {
        guard root.deletingLastPathComponent().standardizedFileURL == sessionsRoot.standardizedFileURL,
              FileManager.default.fileExists(atPath: root.appendingPathComponent(".routekeeper-session").path) else {
            return
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func recoverOrphanedSessions() {
        guard let roots = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for root in roots {
            let control = IsolationSessionLayout(root: root).control
            let executableText = try? String(
                contentsOf: control.appendingPathComponent("sandbox.executable"),
                encoding: .utf8
            )
            let expectedExecutable = executableText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".routekeeper-session").path),
                  let identity = recordedProcess(root: root),
                  identity.command.contains(IsolationSessionLayout(root: root).profile.path)
                    || expectedExecutable.map({ !$0.isEmpty && identity.command.contains($0) }) == true else {
                continue
            }
            for pid in descendants(of: identity.pid).reversed() {
                _ = Darwin.kill(pid, SIGTERM)
            }
            _ = Darwin.kill(identity.pid, SIGTERM)
            Thread.sleep(forTimeInterval: 0.2)
            for pid in [identity.pid] + descendants(of: identity.pid) where Darwin.kill(pid, 0) == 0 {
                _ = Darwin.kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.pid"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.started"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.executable"))
        }
    }

    private func purgeOwnedSessions() {
        if let roots = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for root in roots
                where root.deletingLastPathComponent().standardizedFileURL == sessionsRoot.standardizedFileURL
                && FileManager.default.fileExists(atPath: root.appendingPathComponent(".routekeeper-session").path) {
                try? FileManager.default.removeItem(at: root)
            }
        }
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: sessionsRoot.path),
           remaining.isEmpty {
            try? FileManager.default.removeItem(at: sessionsRoot)
        }
    }

    private func purgeOwnedProfiles() {
        let home = profilesRoot.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        guard Self.hasOwnedClaudeProfile(at: home) else { return }
        try? FileManager.default.removeItem(at: home)
        let desktopRoot = home.deletingLastPathComponent()
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: desktopRoot.path),
           remaining.isEmpty {
            try? FileManager.default.removeItem(at: desktopRoot)
        }
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: profilesRoot.path),
           remaining.isEmpty {
            try? FileManager.default.removeItem(at: profilesRoot)
        }
    }

    private nonisolated static func hasOwnedClaudeProfile(at home: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: home.appendingPathComponent(".routekeeper-profile").path
        )
    }

    nonisolated static func nonLoopbackListeners(
        in lsofOutput: String,
        ownedPIDs: Set<Int32>
    ) -> [String] {
        var currentPID: Int32?
        var violations: [String] = []
        var seen = Set<String>()
        for line in lsofOutput.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                currentPID = Int32(value)
            case "n":
                guard let currentPID, ownedPIDs.contains(currentPID) else { continue }
                let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = name.lowercased()
                let isLoopback = normalized.hasPrefix("127.0.0.1:")
                    || normalized.hasPrefix("[::1]:")
                    || normalized.hasPrefix("localhost:")
                if !isLoopback {
                    let entry = "PID \(currentPID) \(name)"
                    if seen.insert(entry).inserted { violations.append(entry) }
                }
            default:
                continue
            }
        }
        return violations
    }

    nonisolated static func auditLoopbackListeners(pids: [Int32]) -> ListenerAuditResult {
        guard !pids.isEmpty else { return .init(nonLoopback: [], ports: [], error: nil) }
        let lsof = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: lsof) else {
            return .init(nonLoopback: [], ports: [], error: "系统缺少 lsof")
        }
        let pidList = Array(Set(pids)).map(String.init).joined(separator: ",")
        let arguments = ["-nP", "-b", "-w", "-a", "-p", pidList, "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        var result = Command.run(lsof, arguments, timeout: 6)
        if result.status == 15 {
            // Electron startup can make lsof miss a short probe window on macOS.
            result = Command.run(lsof, arguments, timeout: 6)
        }
        // lsof exits 1 when the selected processes have no matching listeners.
        if result.status < 0 || result.status > 1 {
            return .init(nonLoopback: [], ports: [], error: "lsof 返回状态 \(result.status)")
        }
        let ownedPIDs = Set(pids)
        return .init(
            nonLoopback: nonLoopbackListeners(
                in: result.output,
                ownedPIDs: ownedPIDs
            ),
            ports: ScienceWebBoundary.loopbackListenerPorts(
                in: result.output,
                ownedPIDs: ownedPIDs
            ),
            error: nil
        )
    }

    private func recordedProcess(root: URL) -> RecordedProcess? {
        let control = IsolationSessionLayout(root: root).control
        let pidText = try? String(contentsOf: control.appendingPathComponent("sandbox.pid"), encoding: .utf8)
        let startText = try? String(contentsOf: control.appendingPathComponent("sandbox.started"), encoding: .utf8)
        guard let pid = pidText.flatMap({ Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
              pid > 1,
              let expectedStart = startText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedStart.isEmpty else {
            return nil
        }
        let process = Command.run(
            "/bin/ps",
            ["-p", String(pid), "-o", "lstart=,command="],
            timeout: 2
        )
        guard process.status == 0 else {
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.pid"))
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.started"))
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.executable"))
            return nil
        }
        let line = process.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix(expectedStart) else {
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.pid"))
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.started"))
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.executable"))
            return nil
        }
        return RecordedProcess(pid: pid, command: line)
    }

    private func descendants(of rootPID: Int32) -> [Int32] {
        let result = Command.run("/bin/ps", ["-axo", "pid=,ppid="], timeout: 2)
        guard result.status == 0 else { return [] }
        let parentByChild = result.output.split(separator: "\n").reduce(into: [Int32: Int32]()) { values, line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let parent = Int32(parts[1]) else { return }
            values[pid] = parent
        }
        var found: [Int32] = []
        var pending = [rootPID]
        while let parent = pending.popLast() {
            let children = parentByChild.compactMap { $0.value == parent ? $0.key : nil }
            found.append(contentsOf: children)
            pending.append(contentsOf: children)
        }
        return found
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func XCTUnwrapPort(_ port: Int?) throws -> Int {
        guard let port else { throw LocalRelayError.stopped }
        return port
    }

    nonisolated private static func copyProject(from source: URL, to destination: URL) throws -> WorkspaceCopyKind {
        if copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE)) == 0 {
            return .clone
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return .copy
    }

    nonisolated private static func runPreflight(
        configuration: IsolationConfiguration,
        paths: IsolationResolvedPaths,
        applicationURL: URL?,
        relayPort: Int,
        environment: [String: String],
        expectedExits: IsolationExpectedExits,
        inputMethodApplications: [URL] = []
    ) -> PreflightResult {
        let executable = URL(fileURLWithPath: "/bin/sh")
        let profile: String
        if configuration.target == .claudeDesktop {
            guard let applicationURL else {
                return PreflightResult(
                    checks: [
                        .init(
                            id: "desktop-signature",
                            title: "官方客户端签名",
                            detail: "预检时没有可用的官方 Claude Desktop",
                            passed: false
                        )
                    ],
                    executable: executable,
                    failure: "官方 Claude Desktop 在预检前不可用。",
                    relayReachable: false,
                    exitAnchor: nil
                )
            }
            profile = IsolationSandboxProfile.makeDesktop(
                paths: paths,
                applicationURL: applicationURL,
                relayPort: relayPort,
                inputMethodApplications: inputMethodApplications
            )
        } else {
            profile = IsolationSandboxProfile.make(
                paths: paths,
                executableURL: executable,
                relayPort: relayPort
            )
        }
        let listenerExpectation = configuration.target == .claudeDesktop ? "allow" : "block"
        do {
            try Data(profile.utf8).write(to: paths.layout.profile, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.layout.profile.path
            )
            let canary = paths.layout.control.appendingPathComponent("outside-canary")
            try Data("not-readable".utf8).write(to: canary, options: .atomic)
            let script = paths.layout.temporary.appendingPathComponent("preflight.sh")
            let resultFile = paths.layout.temporary.appendingPathComponent("preflight-result")
            let claudeTraceFile = paths.layout.temporary.appendingPathComponent("claude-trace")
            let zoned = TimeZone(identifier: configuration.timezoneIdentifier)?.identifier ?? ""
            let locale = IsolationSessionEnvironment.posixLocale(for: configuration.languageIdentifier)
            let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
            let expectedIPv4 = expectedExits.ipv4 ?? ""
            let expectedIPv6 = expectedExits.ipv6 ?? ""
            let scriptText = """
            result=\(shellQuote(resultFile.path))
            : > "$result"
            if [ "$TZ" = \(shellQuote(zoned)) ]; then echo "timezone=1" >> "$result"; else echo "timezone=0" >> "$result"; fi
            if [ "$LANG" = \(shellQuote(locale)) ] && [ "$LC_ALL" = \(shellQuote(locale)) ] && [ "$LANGUAGE" = \(shellQuote(language)) ]; then echo "session-locale=1" >> "$result"; else echo "session-locale=0" >> "$result"; fi
            if printf 'ok' > "$HOME/preflight-write" 2>/dev/null; then echo "home-write=1" >> "$result"; else echo "home-write=0" >> "$result"; fi
            if printf 'ok' > "$ISOLATION_WORKSPACE/preflight-write" 2>/dev/null; then echo "workspace-write=1" >> "$result"; else echo "workspace-write=0" >> "$result"; fi
            if printf 'ok' > "$ISOLATION_EXCHANGE/preflight-write" 2>/dev/null; then echo "exchange-write=1" >> "$result"; else echo "exchange-write=0" >> "$result"; fi
            if [ -n "$ISOLATION_ORIGINAL" ]; then
              echo "original-project=1" >> "$result"
              if printf 'blocked' > "$ISOLATION_ORIGINAL/.routekeeper-forbidden" 2>/dev/null; then echo "original-write=0" >> "$result"; else echo "original-write=1" >> "$result"; fi
            else
              echo "original-project=0" >> "$result"
              echo "original-write=1" >> "$result"
            fi
            if /bin/cat "$ISOLATION_CONTROL/outside-canary" >/dev/null 2>&1; then echo "control-read=0" >> "$result"; else echo "control-read=1" >> "$result"; fi
            if [ -n "$ISOLATION_ORIGINAL" ]; then
              if /bin/sh -c 'printf blocked > "$ISOLATION_ORIGINAL/.routekeeper-child-forbidden"' 2>/dev/null; then echo "child-inherit=0" >> "$result"; else echo "child-inherit=1" >> "$result"; fi
            else
              if /bin/sh -c 'printf blocked > "$ISOLATION_CONTROL/.routekeeper-child-forbidden"' 2>/dev/null; then echo "child-inherit=0" >> "$result"; else echo "child-inherit=1" >> "$result"; fi
            fi
            if /usr/bin/curl --noproxy '*' --silent --connect-timeout 2 --max-time 3 http://1.1.1.1 >/dev/null 2>&1; then echo "direct-network=0" >> "$result"; else echo "direct-network=1" >> "$result"; fi
            if /usr/bin/host -W 1 example.com >/dev/null 2>&1; then echo "direct-dns=0" >> "$result"; else echo "direct-dns=1" >> "$result"; fi
            if /usr/bin/nc -u -z -w 1 1.1.1.1 53 >/dev/null 2>&1; then echo "direct-udp=0" >> "$result"; else echo "direct-udp=1" >> "$result"; fi
            if /usr/bin/curl --proxy "$HTTPS_PROXY" --silent --fail --connect-timeout 5 --max-time 12 https://api.ipify.org >/dev/null 2>&1; then echo "relay-network=1" >> "$result"; else echo "relay-network=0" >> "$result"; fi
            if /usr/bin/curl --noproxy '*' --silent --fail --connect-timeout 3 --max-time 6 https://claude.ai/cdn-cgi/trace >/dev/null 2>&1; then echo "direct-claude=0" >> "$result"; else echo "direct-claude=1" >> "$result"; fi
            if /usr/bin/curl --proxy "$HTTPS_PROXY" --silent --fail --connect-timeout 5 --max-time 12 https://claude.ai/cdn-cgi/trace > \(shellQuote(claudeTraceFile.path)) 2>/dev/null; then echo "claude-relay=1" >> "$result"; else echo "claude-relay=0" >> "$result"; fi
            relay_ipv4=$(/usr/bin/curl --proxy "$HTTPS_PROXY" --silent --show-error --fail --connect-timeout 5 --max-time 12 https://api.ipify.org 2>/dev/null | /usr/bin/tr -d '[:space:]')
            echo "relay-exit-ip=$relay_ipv4" >> "$result"
            trace_ip=$(/usr/bin/awk -F= '$1 == "ip" { print $2; exit }' \(shellQuote(claudeTraceFile.path)) 2>/dev/null)
            echo "claude-exit-ip=$trace_ip" >> "$result"
            if [ -n "$trace_ip" ] && { [ "$trace_ip" = \(shellQuote(expectedIPv4)) ] || [ "$trace_ip" = \(shellQuote(expectedIPv6)) ]; }; then
              echo "claude-exit-match=1" >> "$result"
              echo "claude-exit-basis=exact" >> "$result"
            elif [ -n "$trace_ip" ] && [ "${trace_ip#*:}" != "$trace_ip" ] && [ -n "$relay_ipv4" ] && [ "$relay_ipv4" = \(shellQuote(expectedIPv4)) ]; then
              echo "claude-exit-match=1" >> "$result"
              echo "claude-exit-basis=relay-ipv4-anchor" >> "$result"
            else
              echo "claude-exit-match=0" >> "$result"
              echo "claude-exit-basis=mismatch" >> "$result"
            fi
            /usr/bin/nc -l 127.0.0.1 0 >/dev/null 2>&1 &
            listener_pid=$!
            /bin/sleep 0.2
            if /bin/kill -0 "$listener_pid" >/dev/null 2>&1; then listener_alive=1; /bin/kill "$listener_pid" >/dev/null 2>&1 || true; else listener_alive=0; fi
            if [ \(shellQuote(listenerExpectation)) = "allow" ]; then listener_ok=$listener_alive; else listener_ok=$((1 - listener_alive)); fi
            echo "loopback-listener=$listener_ok" >> "$result"
            wait "$listener_pid" 2>/dev/null || true
            if /usr/bin/osascript -e 'path to application id "com.apple.Safari"' >/dev/null 2>&1; then echo "external-app=0" >> "$result"; else echo "external-app=1" >> "$result"; fi
            /bin/rm -f "$HOME/preflight-write" "$ISOLATION_WORKSPACE/preflight-write" "$ISOLATION_EXCHANGE/preflight-write"
            printf 'complete' >> "$result"
            """
            try Data(scriptText.utf8).write(to: script, options: .atomic)
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-f", paths.layout.profile.path, "/bin/sh", script.path]
            process.currentDirectoryURL = paths.layout.workspace
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            process.environment = baseEnvironment(
                configuration: configuration,
                paths: paths,
                relayEnvironment: environment
            )
            try process.run()
            process.waitUntilExit()
            let values = (try? String(contentsOf: resultFile, encoding: .utf8)) ?? ""
            let checks = preflightChecks(values, target: configuration.target)
            let stderrText = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile().prefix(4_000),
                as: UTF8.self
            )
            let failure = process.terminationStatus == 0 && !checks.contains(where: \.blocksLaunch)
                ? ""
                : "隔离自检未通过。\(stderrText.isEmpty ? "请检查下方各项。" : "系统拒绝了启动，技术信息见运行记录。")"
            let relayIPv4 = values
                .split(separator: "\n")
                .first(where: { $0.hasPrefix("relay-exit-ip=") })?
                .split(separator: "=", maxSplits: 1)
                .last
                .flatMap { IPAddress.normalized(String($0)) }
            let observedExit = values
                .split(separator: "\n")
                .first(where: { $0.hasPrefix("claude-exit-ip=") })?
                .split(separator: "=", maxSplits: 1)
                .last
                .flatMap { IPAddress.normalized(String($0)) }
            return PreflightResult(
                checks: checks,
                executable: executable,
                failure: failure,
                relayReachable: values.contains("relay-network=1\n")
                    && values.contains("claude-relay=1\n"),
                exitAnchor: relayIPv4 ?? observedExit
            )
        } catch {
            return PreflightResult(
                checks: [
                    .init(id: "sandbox-launch", title: "启动受限进程", detail: error.localizedDescription, passed: false)
                ],
                executable: executable,
                failure: "无法执行隔离自检：\(error.localizedDescription)",
                relayReachable: false,
                exitAnchor: nil
            )
        }
    }

    nonisolated static func baseEnvironment(
        configuration: IsolationConfiguration,
        paths: IsolationResolvedPaths,
        relayEnvironment: [String: String]
    ) -> [String: String] {
        let locale = IsolationSessionEnvironment.posixLocale(for: configuration.languageIdentifier)
        let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
        let appleLanguage = IsolationSessionEnvironment.appleLanguage(for: configuration.languageIdentifier)
        var values = [
            "HOME": paths.runtimeHome.path,
            "TMPDIR": paths.layout.temporary.path,
            "TZ": configuration.timezoneIdentifier,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": locale,
            "LC_ALL": locale,
            "LANGUAGE": language,
            "AppleLanguages": appleLanguage,
            "AppleLocale": locale.replacingOccurrences(of: ".UTF-8", with: ""),
            "ISOLATION_WORKSPACE": paths.layout.workspace.path,
            "ISOLATION_EXCHANGE": paths.exchange.path,
            "ISOLATION_ORIGINAL": paths.originalProject?.path ?? "",
            "ISOLATION_CONTROL": paths.layout.control.path
        ]
        values.merge(relayEnvironment) { _, new in new }
        return values
    }

    nonisolated static func preflightChecks(
        _ output: String,
        target: IsolationApplicationTarget = .claudeCode
    ) -> [IsolationCheck] {
        let values = output.split(separator: "\n").reduce(into: [String: String]()) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            result[String(parts[0])] = String(parts[1])
        }
        let observedExit = values["claude-exit-ip"].flatMap(IPAddress.normalized)
        let relayIPv4Exit = values["relay-exit-ip"].flatMap(IPAddress.normalized).flatMap {
            IPFamily.of($0) == .ipv4 ? $0 : nil
        }
        let exitBasis = values["claude-exit-basis"] ?? "exact"
        let exitMatched = values["claude-exit-match"] == "1"
        let hasOriginalProject = values["original-project"] != "0"
        let exitCheckDetail: String
        if exitMatched, exitBasis == "relay-ipv4-anchor", let observedExit, let relayIPv4Exit {
            exitCheckDetail = "Claude 路径观察到节点轮换 IPv6 \(observedExit)；同一中继的稳定 IPv4 出口 \(relayIPv4Exit) 与已保存值一致"
        } else if exitMatched, let observedExit {
            exitCheckDetail = "Claude 路径返回 \(observedExit)，与已保存出口完全一致"
        } else if let observedExit, let relayIPv4Exit {
            exitCheckDetail = "Claude 路径返回 \(observedExit)；同一中继的 IPv4 出口为 \(relayIPv4Exit)，无法与已保存出口核对"
        } else if let observedExit {
            exitCheckDetail = "Claude 路径返回 \(observedExit)，无法与已保存出口核对"
        } else {
            exitCheckDetail = "Claude 路径没有返回有效出口，无法与已保存值核对"
        }
        var definitions: [(String, String, String)] = [
            ("timezone", "会话时区", "本次会话使用独立 TZ，不修改 Mac 的系统时区"),
            ("session-locale", "会话语言", "语言和 locale 与本会话地区设置一致"),
            ("home-write", "独立用户目录", "临时 HOME 可写"),
            ("workspace-write", "项目工作副本", "只能在本次副本中修改项目"),
            ("exchange-write", "交换文件夹", "只能使用你选择的交换目录"),
            (
                "original-write",
                "原项目只读",
                hasOriginalProject ? "原项目拒绝写入" : "未选择原项目，Chat 使用独立空工作区"
            ),
            ("control-read", "会话控制目录", "受限进程不能读取控制文件"),
            (
                "child-inherit",
                "子进程继承",
                hasOriginalProject ? "二级 shell 也继承相同文件边界" : "二级 shell 也不能写入会话控制目录"
            ),
            ("direct-network", "拦截公网直连", "公网直连失败"),
            ("direct-dns", "拦截系统 DNS", "域名解析不能绕过中继"),
            ("direct-udp", "拦截 UDP", "公网 UDP 直连失败"),
            ("relay-network", "代理中继", "唯一允许的本地中继可用"),
            ("direct-claude", "Claude 断网保护", "无代理访问 Claude 失败"),
            ("claude-relay", "Claude 代理路径", "Claude 可以通过 Routekeeper 中继访问"),
            (
                "claude-exit-match",
                "Claude 出口核对",
                exitCheckDetail
            ),
            (
                "loopback-listener",
                "本地端口监听",
                target == .claudeDesktop
                    ? "官方客户端可以建立本机监听；启动后会持续审计并拒绝非回环地址"
                    : "受限进程不能启动 localhost 项目服务器"
            )
        ]
        if target == .claudeCode {
            definitions.append(("external-app", "外部应用启动", "受限进程不能代开默认浏览器"))
        }
        return definitions.map { id, title, detail in
            let passed = values[id] == "1"
            let resolvedDetail: String
            if id == "claude-exit-match" {
                resolvedDetail = exitCheckDetail
            } else {
                resolvedDetail = detail
            }
            // Exit matching is advisory; sandbox and fail-closed network boundaries remain mandatory.
            let warning = id == "claude-exit-match" && !passed
            return IsolationCheck(
                id: id,
                title: title,
                detail: passed ? resolvedDetail : warning ? "警告：\(resolvedDetail)" : "未通过：\(resolvedDetail)",
                passed: passed,
                isWarning: warning
            )
        }
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

private enum WorkspaceCopyKind {
    case clone
    case copy
}

private struct PreflightResult {
    var checks: [IsolationCheck]
    var executable: URL
    var failure: String
    var relayReachable: Bool
    var exitAnchor: String?

    func networkFingerprint(
        proxy: SystemProxyDescriptor?,
        upstream: IsolationUpstream
    ) -> NetworkFingerprint {
        .init(
            proxy: proxy,
            upstream: upstream,
            upstreamReachable: relayReachable,
            exitAnchor: exitAnchor
        )
    }
}

private struct RecordedProcess {
    var pid: Int32
    var command: String
}

struct ListenerAuditResult: Sendable {
    var nonLoopback: [String]
    var ports: Set<Int>
    var error: String?
}
