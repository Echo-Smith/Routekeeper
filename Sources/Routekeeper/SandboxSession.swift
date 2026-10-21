import AppKit
import Darwin
import Foundation
import GuardCore
import Observation

@MainActor
@Observable
final class SandboxSession {
    var phase: IsolationPhase = .ready
    var configuration: IsolationConfiguration {
        didSet { persistConfiguration() }
    }
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

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let sessionsRoot: URL
    @ObservationIgnored private let relay = LocalRelay()
    @ObservationIgnored private var activeExecutable: URL?
    @ObservationIgnored private var processCheckTask: Task<Void, Never>?

    private static let configurationKey = "routekeeper-isolation-configuration-v1"

    init(preferences: UserDefaults = .standard, sessionsRoot: URL? = nil) {
        self.preferences = preferences
        self.sessionsRoot = sessionsRoot ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Routekeeper/Isolation", isDirectory: true)
        if let data = preferences.data(forKey: Self.configurationKey),
           let saved = try? JSONDecoder().decode(IsolationConfiguration.self, from: data) {
            var sanitized = saved
            sanitized.upstream.password = ""
            configuration = sanitized
            if let sanitizedData = try? JSONEncoder().encode(sanitized) {
                preferences.set(sanitizedData, forKey: Self.configurationKey)
            }
        } else {
            configuration = IsolationConfiguration()
        }
        recoverOrphanedSessions()
    }

    var canPrepare: Bool {
        configuration.hasRequiredPaths && configuration.hasValidTimezone
            && configuration.upstream.isValid && !busy && !phase.isActive
            && (detectedProxy?.isLoopback != false)
    }

    var canLaunchClaude: Bool {
        !busy && (phase == .running || phase == .networkPaused)
    }

    var canPauseNetwork: Bool { !busy && phase == .running }
    var canResumeNetwork: Bool { !busy && phase == .networkPaused }
    var canEnd: Bool { phase.isActive || phase == .failed }

    var statusTitle: String {
        switch phase {
        case .disabled: return "未开启"
        case .ready:
            return configuration.hasRequiredPaths ? "可以创建会话" : "等待选择会话范围"
        case .preparing: return "正在准备隔离环境"
        case .checking: return "正在验证隔离边界"
        case .running: return "沙箱已隔离"
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
        IsolationSessionEnvironment.localeIdentifier(for: configuration.timezoneIdentifier)
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

    func prepare(expectedExits: IsolationExpectedExits) async {
        self.expectedExits = expectedExits
        refreshDetectedProxy(alignIfNeeded: true)
        guard canPrepare else {
            message = detectedProxy?.isLoopback == false
                ? "当前系统代理不是本机端口。请先在代理客户端开启本机 HTTP 或 SOCKS 入口。"
                : "请先填写项目和交换文件夹，并确认时区与本地代理端口。"
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
        message = "正在复制项目并建立本次会话目录。"
        defer { busy = false }

        do {
            let proxyAtStart = detectedProxy
            let paths = try createSession()
            message = "正在创建项目工作副本。"
            let copyResult = try await Task.detached(priority: .userInitiated) {
                try Self.copyProject(from: paths.originalProject, to: paths.layout.workspace)
            }.value

            phase = .checking
            message = copyResult == .clone
                ? "已建立 APFS 写时复制工作副本，正在验证文件与网络边界。"
                : "已建立普通项目副本，正在验证文件与网络边界。"
            let port = try relay.start(upstream: configuration.upstream)
            relayPort = port
            let expectedExits = expectedExits
            let result = await Task.detached(priority: .userInitiated) { [configuration, relay, paths, expectedExits] in
                Self.runPreflight(
                    configuration: configuration,
                    paths: paths,
                    relayPort: port,
                    environment: relay.proxyEnvironment(),
                    expectedExits: expectedExits
                )
            }.value
            detectedProxy = SystemProxyDescriptor.current()
            checks = withDetectedProxyCheck(result.checks, expected: proxyAtStart)
            activeExecutable = result.executable

            guard checks.allSatisfy(\.passed) else {
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
            message = "文件、系统代理、Claude 路径和保存出口均已验证。下一步可在终端启动 Claude Code。"
        } catch {
            relay.stop()
            networkEnabled = false
            phase = .failed
            message = "无法创建沙箱会话：\(error.localizedDescription)"
        }
    }

    func launchClaudeCode(token: String) {
        guard canLaunchClaude else {
            message = "请先通过沙箱自检，再启动 Claude Code。"
            return
        }
        guard let root = sessionRoot else {
            message = "找不到本次沙箱会话目录，请重新创建。"
            return
        }
        guard let executable = ApplicationDiscovery.codePaths()
            .map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath() })
            .first(where: { $0.lastPathComponent == "claude" }) else {
            message = "没有找到可用的 Claude Code 命令，请先完成安装。"
            return
        }
        let layout = IsolationSessionLayout(root: root)
        guard let exchangePath, let originalProject = configurationPath(configuration.projectPath) else {
            message = "项目或交换文件夹路径已变化，请重新创建会话。"
            return
        }
        do {
            let paths = IsolationResolvedPaths(
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

    func pauseNetwork() {
        guard canPauseNetwork else { return }
        relay.pause()
        networkEnabled = false
        phase = .networkPaused
        message = "网络已关闭。Claude 进程仍在运行，已有连接已断开，新的直连和中继连接都会失败。"
    }

    func invalidateNetwork(reason: String) {
        guard phase == .running else { return }
        relay.pause()
        networkEnabled = false
        phase = .networkPaused
        message = "网络状态发生变化，沙箱已自动关闭网络。确认本机代理可用后，再点“恢复网络”。"
    }

    func resumeNetwork() async {
        guard canResumeNetwork else { return }
        refreshDetectedProxy(alignIfNeeded: true)
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
            let project = configurationPath(configuration.projectPath) ?? layout.workspace
            let exchange = URL(fileURLWithPath: exchangePath ?? configuration.exchangePath, isDirectory: true)
            let paths = IsolationResolvedPaths(originalProject: project, exchange: exchange, layout: layout)
            let expectedExits = expectedExits
            let result = await Task.detached { [configuration, relay, expectedExits] in
                Self.runPreflight(
                    configuration: configuration,
                    paths: paths,
                    relayPort: port,
                    environment: relay.proxyEnvironment(),
                    expectedExits: expectedExits
                )
            }.value
            detectedProxy = SystemProxyDescriptor.current()
            checks = withDetectedProxyCheck(result.checks, expected: proxyAtStart)
            guard checks.allSatisfy(\.passed) else {
                relay.pause()
                phase = .networkPaused
                networkEnabled = false
                message = result.failure.isEmpty
                    ? "网络没有恢复：请查看未通过的检查项。"
                    : result.failure
                return
            }
            networkEnabled = true
            phase = .running
            message = "网络已恢复；Claude 路径、断网保护和保存出口重新验证通过。"
        } catch {
            relay.pause()
            networkEnabled = false
            phase = .networkPaused
            message = "网络没有恢复：\(error.localizedDescription)"
        }
    }

    func endSession() async {
        busy = true
        defer { busy = false }
        relay.stop()
        terminateClaudeProcesses()
        networkEnabled = false
        claudeRunning = false
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
        if let root = sessionRoot { removeOwnedSession(at: root) }
        sessionRoot = nil
        exchangePath = nil
        activeExecutable = nil
        relayPort = nil
        checks = []
        changedFiles = []
        networkEnabled = false
        claudeRunning = false
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
        configuration = IsolationConfiguration()
        preferences.removeObject(forKey: Self.configurationKey)
        phase = .ready
        message = "本地沙箱配置和会话副本已清空。"
        return true
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

        let paths = try IsolationPathValidator.validate(configuration, sessionRoot: root, home: home)
        for directory in [paths.layout.home, paths.layout.temporary, paths.layout.control, paths.layout.logs] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.createDirectory(
            at: paths.layout.home.appendingPathComponent(".config"),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try writeSessionLocalePreferences(home: paths.layout.home)
        sessionRoot = root
        exchangePath = paths.exchange.path
        return paths
    }

    private func writeSessionLocalePreferences(home: URL) throws {
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        try FileManager.default.createDirectory(
            at: preferences,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let locale = IsolationSessionEnvironment.localeIdentifier(for: configuration.timezoneIdentifier)
        let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
        let values: [String: Any] = [
            "AppleLocale": locale.replacingOccurrences(of: ".UTF-8", with: ""),
            "AppleLanguages": [language]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try writePrivate(data, to: preferences.appendingPathComponent(".GlobalPreferences.plist"))
    }

    private func makeLaunchScript(
        token: String,
        executable: URL,
        profile: URL,
        layout: IsolationSessionLayout,
        exchange: URL
    ) throws -> URL {
        let environment = relay.proxyEnvironment()
        let scriptURL = layout.control.appendingPathComponent("launch-\(UUID().uuidString).command")
        let processIDPath = layout.control.appendingPathComponent("sandbox.pid").path
        let processStartPath = layout.control.appendingPathComponent("sandbox.started").path
        let path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        let locale = IsolationSessionEnvironment.localeIdentifier(for: configuration.timezoneIdentifier)
        let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
        let appleLocale = locale.replacingOccurrences(of: ".UTF-8", with: "")
        var exports = [
            "HOME=\(layout.home.path)",
            "TMPDIR=\(layout.temporary.path)",
            "TMP=\(layout.temporary.path)",
            "TEMP=\(layout.temporary.path)",
            "XDG_CONFIG_HOME=\(layout.home.appendingPathComponent(".config").path)",
            "XDG_CACHE_HOME=\(layout.home.appendingPathComponent(".cache").path)",
            "XDG_DATA_HOME=\(layout.home.appendingPathComponent(".local/share").path)",
            "TZ=\(configuration.timezoneIdentifier)",
            "LANG=\(locale)",
            "LC_ALL=\(locale)",
            "LANGUAGE=\(language)",
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
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let running = self.matchesRecordedProcess(root: IsolationSessionLayout(root: profile.deletingLastPathComponent().deletingLastPathComponent()).root)
                if self.claudeRunning != running { self.claudeRunning = running }
                if !self.phase.isActive { return }
            }
        }
    }

    private func terminateClaudeProcesses() {
        processCheckTask?.cancel()
        processCheckTask = nil
        guard let root = sessionRoot else { return }
        let profile = IsolationSessionLayout(root: root).profile.path
        if let identity = recordedProcess(root: root, requireProfile: profile) {
            for pid in descendants(of: identity.pid).reversed() {
                _ = Darwin.kill(pid, SIGTERM)
            }
            _ = Darwin.kill(identity.pid, SIGTERM)
        }
        _ = Command.run("/usr/bin/pkill", ["-TERM", "-f", profile], timeout: 4)
        _ = Command.run("/bin/sleep", ["0.2"], timeout: 1)
        if let identity = recordedProcess(root: root, requireProfile: profile) {
            for pid in descendants(of: identity.pid).reversed() {
                _ = Darwin.kill(pid, SIGKILL)
            }
            _ = Darwin.kill(identity.pid, SIGKILL)
        }
        _ = Command.run("/usr/bin/pkill", ["-KILL", "-f", profile], timeout: 4)
        try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.pid"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.started"))
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
        guard phase.canChangeConfiguration else { return }
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
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".routekeeper-session").path),
                  let identity = recordedProcess(root: root),
                  identity.command.contains(IsolationSessionLayout(root: root).profile.path) else {
                continue
            }
            for pid in descendants(of: identity.pid).reversed() {
                _ = Darwin.kill(pid, SIGTERM)
            }
            _ = Darwin.kill(identity.pid, SIGTERM)
            try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.pid"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("control/sandbox.started"))
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

    private func matchesRecordedProcess(root: URL) -> Bool {
        recordedProcess(root: root) != nil
    }

    private func recordedProcess(root: URL, requireProfile: String? = nil) -> RecordedProcess? {
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
            return nil
        }
        let line = process.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix(expectedStart) else {
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.pid"))
            try? FileManager.default.removeItem(at: control.appendingPathComponent("sandbox.started"))
            return nil
        }
        if let requireProfile, !line.contains(requireProfile) { return nil }
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
        relayPort: Int,
        environment: [String: String],
        expectedExits: IsolationExpectedExits
    ) -> PreflightResult {
        let executable = URL(fileURLWithPath: "/bin/sh")
        let profile = IsolationSandboxProfile.make(
            paths: paths,
            executableURL: executable,
            relayPort: relayPort
        )
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
            let locale = IsolationSessionEnvironment.localeIdentifier(for: configuration.timezoneIdentifier)
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
            if printf 'blocked' > "$ISOLATION_ORIGINAL/.routekeeper-forbidden" 2>/dev/null; then echo "original-write=0" >> "$result"; else echo "original-write=1" >> "$result"; fi
            if /bin/cat "$ISOLATION_CONTROL/outside-canary" >/dev/null 2>&1; then echo "control-read=0" >> "$result"; else echo "control-read=1" >> "$result"; fi
            if /bin/sh -c 'printf blocked > "$ISOLATION_ORIGINAL/.routekeeper-child-forbidden"' 2>/dev/null; then echo "child-inherit=0" >> "$result"; else echo "child-inherit=1" >> "$result"; fi
            if /usr/bin/curl --noproxy '*' --silent --connect-timeout 2 --max-time 3 http://1.1.1.1 >/dev/null 2>&1; then echo "direct-network=0" >> "$result"; else echo "direct-network=1" >> "$result"; fi
            if /usr/bin/host -W 1 example.com >/dev/null 2>&1; then echo "direct-dns=0" >> "$result"; else echo "direct-dns=1" >> "$result"; fi
            if /usr/bin/nc -u -z -w 1 1.1.1.1 53 >/dev/null 2>&1; then echo "direct-udp=0" >> "$result"; else echo "direct-udp=1" >> "$result"; fi
            if /usr/bin/curl --proxy "$HTTPS_PROXY" --silent --fail --connect-timeout 5 --max-time 12 https://api.ipify.org >/dev/null 2>&1; then echo "relay-network=1" >> "$result"; else echo "relay-network=0" >> "$result"; fi
            if /usr/bin/curl --noproxy '*' --silent --fail --connect-timeout 3 --max-time 6 https://claude.ai/cdn-cgi/trace >/dev/null 2>&1; then echo "direct-claude=0" >> "$result"; else echo "direct-claude=1" >> "$result"; fi
            if /usr/bin/curl --proxy "$HTTPS_PROXY" --silent --fail --connect-timeout 5 --max-time 12 https://claude.ai/cdn-cgi/trace > \(shellQuote(claudeTraceFile.path)) 2>/dev/null; then echo "claude-relay=1" >> "$result"; else echo "claude-relay=0" >> "$result"; fi
            trace_ip=$(/usr/bin/awk -F= '$1 == "ip" { print $2; exit }' \(shellQuote(claudeTraceFile.path)) 2>/dev/null)
            echo "claude-exit-ip=$trace_ip" >> "$result"
            if [ -n "$trace_ip" ] && { [ "$trace_ip" = \(shellQuote(expectedIPv4)) ] || [ "$trace_ip" = \(shellQuote(expectedIPv6)) ]; }; then echo "claude-exit-match=1" >> "$result"; else echo "claude-exit-match=0" >> "$result"; fi
            /usr/bin/nc -l 127.0.0.1 0 >/dev/null 2>&1 &
            listener_pid=$!
            /bin/sleep 0.2
            if /bin/kill -0 "$listener_pid" >/dev/null 2>&1; then echo "loopback-listener=0" >> "$result"; /bin/kill "$listener_pid" >/dev/null 2>&1 || true; else echo "loopback-listener=1" >> "$result"; fi
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
            let checks = preflightChecks(values)
            let stderrText = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile().prefix(4_000),
                as: UTF8.self
            )
            let failure = process.terminationStatus == 0 && checks.allSatisfy(\.passed)
                ? ""
                : "隔离自检未通过。\(stderrText.isEmpty ? "请检查下方各项。" : "系统拒绝了启动，技术信息见运行记录。")"
            return PreflightResult(checks: checks, executable: executable, failure: failure)
        } catch {
            return PreflightResult(
                checks: [
                    .init(id: "sandbox-launch", title: "启动受限进程", detail: error.localizedDescription, passed: false)
                ],
                executable: executable,
                failure: "无法执行隔离自检：\(error.localizedDescription)"
            )
        }
    }

    nonisolated static func baseEnvironment(
        configuration: IsolationConfiguration,
        paths: IsolationResolvedPaths,
        relayEnvironment: [String: String]
    ) -> [String: String] {
        let locale = IsolationSessionEnvironment.localeIdentifier(for: configuration.timezoneIdentifier)
        let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
        var values = [
            "HOME": paths.layout.home.path,
            "TMPDIR": paths.layout.temporary.path,
            "TZ": configuration.timezoneIdentifier,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": locale,
            "LC_ALL": locale,
            "LANGUAGE": language,
            "AppleLocale": locale.replacingOccurrences(of: ".UTF-8", with: ""),
            "ISOLATION_WORKSPACE": paths.layout.workspace.path,
            "ISOLATION_EXCHANGE": paths.exchange.path,
            "ISOLATION_ORIGINAL": paths.originalProject.path,
            "ISOLATION_CONTROL": paths.layout.control.path
        ]
        values.merge(relayEnvironment) { _, new in new }
        return values
    }

    nonisolated static func preflightChecks(_ output: String) -> [IsolationCheck] {
        let values = output.split(separator: "\n").reduce(into: [String: String]()) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            result[String(parts[0])] = String(parts[1])
        }
        let observedExit = values["claude-exit-ip"].flatMap(IPAddress.normalized)
        let definitions: [(String, String, String)] = [
            ("timezone", "会话时区", "本次会话使用独立 TZ，不修改 Mac 的系统时区"),
            ("session-locale", "会话语言", "语言和 locale 与本会话地区设置一致"),
            ("home-write", "独立用户目录", "临时 HOME 可写"),
            ("workspace-write", "项目工作副本", "只能在本次副本中修改项目"),
            ("exchange-write", "交换文件夹", "只能使用你选择的交换目录"),
            ("original-write", "原项目只读", "原项目拒绝写入"),
            ("control-read", "会话控制目录", "受限进程不能读取控制文件"),
            ("child-inherit", "子进程继承", "二级 shell 也继承相同文件边界"),
            ("direct-network", "拦截公网直连", "公网直连失败"),
            ("direct-dns", "拦截系统 DNS", "域名解析不能绕过中继"),
            ("direct-udp", "拦截 UDP", "公网 UDP 直连失败"),
            ("relay-network", "代理中继", "唯一允许的本地中继可用"),
            ("direct-claude", "Claude 断网保护", "无代理访问 Claude 失败"),
            ("claude-relay", "Claude 代理路径", "Claude 可以通过 Routekeeper 中继访问"),
            (
                "claude-exit-match",
                "Claude 实际出口",
                observedExit.map { "Claude 路径返回 \($0)，与已保存出口一致" }
                    ?? "Claude 路径没有返回有效出口，无法与已保存值比对"
            ),
            ("loopback-listener", "本地端口监听", "受限进程不能启动 localhost 项目服务器"),
            ("external-app", "外部应用启动", "受限进程不能代开默认浏览器")
        ]
        return definitions.map { id, title, detail in
            IsolationCheck(
                id: id,
                title: title,
                detail: values[id] == "1" ? detail : "未通过：\(detail)",
                passed: values[id] == "1"
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
}

private struct RecordedProcess {
    var pid: Int32
    var command: String
}
