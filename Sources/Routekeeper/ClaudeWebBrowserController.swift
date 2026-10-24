import AppKit
import Darwin
import Foundation
import GuardCore
import Observation

enum ClaudeWebBrowserPhase: Equatable {
    case stopped
    case launching
    case running
    case networkPaused
    case failed

    var isRunning: Bool {
        self == .running || self == .networkPaused
    }
}

@MainActor
@Observable
final class ClaudeWebBrowserController {
    var installation: ClaudeWebBrowserInstallation?
    var phase: ClaudeWebBrowserPhase = .stopped
    var busy = false
    var discovering = false
    var message: String
    var egressReport: RelayEgressReport?
    var egressChecking = false
    var pendingLaunchWarning: String?
    private(set) var profileAvailable = false

    @ObservationIgnored private let relay = LocalRelay()
    @ObservationIgnored private let profileRoot: URL
    @ObservationIgnored private let profileURL: URL
    @ObservationIgnored private let homeURL: URL
    @ObservationIgnored private let tempURL: URL
    @ObservationIgnored private let downloadsURL: URL
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let logsURL: URL
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var logHandle: FileHandle?
    @ObservationIgnored private var lastUpstream: IsolationUpstream?
    @ObservationIgnored private var launchGeneration = UUID()
    @ObservationIgnored private var launchedAt: Date?
    @ObservationIgnored private var hasDiscovered: Bool
    @ObservationIgnored private var pausedByEnvironment = false
    @ObservationIgnored private var lastExpectedExits = IsolationExpectedExits()
    @ObservationIgnored private var pendingLaunchConfiguration: SandboxSharedConfiguration?
    @ObservationIgnored private var pendingExpectedExits = IsolationExpectedExits()
    @ObservationIgnored private var egressValidationTask: Task<Void, Never>?
    @ObservationIgnored private var egressValidationGeneration = UUID()

    private static let profileMarkerName = ".routekeeper-profile"

    init(profilesRoot: URL? = nil, discover: Bool = true) {
        let applicationSupport = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Routekeeper", isDirectory: true)
        let resolvedProfilesRoot = profilesRoot
            ?? applicationSupport.appendingPathComponent("Profiles", isDirectory: true)
        let root = resolvedProfilesRoot.appendingPathComponent("ClaudeWeb", isDirectory: true)
        profileRoot = root
        profileURL = root.appendingPathComponent("ChromeProfile", isDirectory: true)
        homeURL = root.appendingPathComponent("Home", isDirectory: true)
        tempURL = root.appendingPathComponent("Temp", isDirectory: true)
        downloadsURL = root.appendingPathComponent("Downloads", isDirectory: true)
        cacheURL = root.appendingPathComponent("Cache", isDirectory: true)
        logsURL = root.appendingPathComponent("Logs", isDirectory: true)
        profileAvailable = Self.isOwnedProfile(at: root)
        let detectedInstallation = discover ? ClaudeWebBrowserDiscovery.locate() : nil
        discovering = !discover
        hasDiscovered = discover
        installation = detectedInstallation
        message = !discover
            ? Self.text(
                "正在验证 Google Chrome 的官方签名与版本。",
                "Verifying the official Google Chrome signature and version."
            )
            : detectedInstallation == nil
            ? Self.text(
                "未检测到 Google Chrome。安装官方版本后即可在独立配置中打开 Claude 网页版。",
                "Google Chrome was not found. Install the official browser to open Claude on the web in a dedicated profile."
            )
            : Self.text(
                "使用独立 Chrome 配置打开 Claude 网页版；不会导入宿主浏览器的 Cookie、密码、历史或扩展。",
                "Open Claude on the web in a dedicated Chrome profile without importing host cookies, passwords, history or extensions."
            )
    }

    var statusTitle: String {
        switch phase {
        case .stopped:
            if discovering {
                return Self.text("正在检测 Google Chrome", "Detecting Google Chrome")
            }
            return installation == nil
                ? Self.text("未检测到 Google Chrome", "Google Chrome not found")
                : Self.text("尚未打开", "Not open")
        case .launching:
            return Self.text("正在打开 Chrome", "Opening Chrome")
        case .running:
            return Self.text("Claude 网页版正在运行", "Claude on the web is running")
        case .networkPaused:
            return Self.text("网页版网络已暂停", "Web browser network paused")
        case .failed:
            return Self.text("网页版未能启动", "The web browser could not start")
        }
    }

    var statusSymbol: String {
        switch phase {
        case .running: return "globe"
        case .networkPaused: return "wifi.slash"
        case .launching: return "hourglass"
        case .failed: return "exclamationmark.triangle.fill"
        case .stopped:
            if discovering { return "hourglass" }
            return installation == nil ? "exclamationmark.triangle.fill" : "globe"
        }
    }

    var canLaunch: Bool {
        installation != nil && !busy && !discovering && !phase.isRunning
    }

    var canStop: Bool {
        phase.isRunning && !busy
    }

    var canPauseNetwork: Bool {
        phase == .running && !busy
    }

    var canResumeNetwork: Bool {
        phase == .networkPaused && lastUpstream != nil && !busy
    }

    var downloadPath: String { downloadsURL.path }
    var profilePath: String { profileRoot.path }
    var egressWarning: String? {
        guard let report = egressReport, !report.isVerified else { return nil }
        return report.detail
    }

    func refreshInstallation() async {
        discovering = true
        let detected = await Task.detached(priority: .userInitiated) {
            ClaudeWebBrowserDiscovery.locate()
        }.value
        installation = detected
        discovering = false
        hasDiscovered = true
        profileAvailable = Self.isOwnedProfile(at: profileRoot)
        if detected == nil, !phase.isRunning {
            phase = .stopped
            message = Self.text(
                "未检测到 Google Chrome 官方应用。Routekeeper 不内置浏览器，也不会使用来源不明的 Chromium。",
                "The official Google Chrome app was not found. Routekeeper does not bundle a browser or use an unverified Chromium build."
            )
        } else if detected != nil, phase == .failed {
            phase = .stopped
            message = Self.text(
                "Google Chrome 已就绪。网页版会使用独立配置和当前会话的语言、时区与代理。",
                "Google Chrome is ready. The web browser will use a dedicated profile with the current session language, timezone and proxy."
            )
        }
    }

    func discoverIfNeeded() async {
        guard !hasDiscovered else { return }
        await refreshInstallation()
    }

    func sharedConfigurationDidChange(_ configuration: SandboxSharedConfiguration) {
        guard !busy, !phase.isRunning, phase == .failed else { return }
        phase = .stopped
        if installation == nil {
            message = Self.text(
                "未检测到 Google Chrome。请先安装 Google 官方版本。",
                "Google Chrome was not found. Install the official Google build first."
            )
        } else if !configuration.hasValidTimezone || !configuration.hasValidLanguage {
            message = Self.text(
                "会话时区或语言仍无效，请编辑共享设置后再打开网页版。",
                "The session timezone or language is still invalid. Edit the shared settings before opening Claude on the web."
            )
        } else if !configuration.upstream.isValid {
            message = Self.text(
                "上游代理仍需有效的本机回环地址和端口，请编辑共享设置后重试。",
                "The upstream proxy still needs a valid loopback host and port. Edit the shared settings and try again."
            )
        } else {
            message = Self.text(
                "共享设置已更新，可以重新打开 Claude 网页版。",
                "Shared settings were updated. Claude on the web can be opened again."
            )
        }
    }

    @discardableResult
    func launch(
        configuration: SandboxSharedConfiguration,
        expectedExits: IsolationExpectedExits
    ) async -> Bool {
        await performLaunch(
            configuration: configuration,
            expectedExits: expectedExits,
            verifyEgress: true,
            acknowledgedWarning: false
        )
    }

    @discardableResult
    func confirmPendingLaunch() async -> Bool {
        guard pendingLaunchWarning != nil,
              let configuration = pendingLaunchConfiguration else {
            return false
        }
        let expectedExits = pendingExpectedExits
        clearPendingLaunch()
        return await performLaunch(
            configuration: configuration,
            expectedExits: expectedExits,
            verifyEgress: false,
            acknowledgedWarning: true
        )
    }

    func cancelPendingLaunch() {
        guard pendingLaunchWarning != nil else { return }
        clearPendingLaunch()
        message = egressReport?.detail ?? Self.text(
            "已取消打开 Claude 网页版。",
            "Opening Claude on the web was cancelled."
        )
    }

    private func performLaunch(
        configuration: SandboxSharedConfiguration,
        expectedExits: IsolationExpectedExits,
        verifyEgress: Bool,
        acknowledgedWarning: Bool
    ) async -> Bool {
        guard !busy, !phase.isRunning else { return false }
        guard let installation else {
            message = Self.text(
                "未检测到 Google Chrome。请先安装 Google 官方版本。",
                "Google Chrome was not found. Install the official Google build first."
            )
            phase = .failed
            return false
        }
        guard TimeZone(identifier: configuration.timezoneIdentifier) != nil,
              let language = IsolationSessionEnvironment.normalizedLanguageIdentifier(
                configuration.languageIdentifier
              ) else {
            message = Self.text(
                "请先设置有效的会话时区和语言。",
                "Set a valid session timezone and language first."
            )
            phase = .failed
            return false
        }
        guard configuration.upstream.isValid else {
            message = Self.text(
                "上游代理必须是本机回环地址，并填写有效端口。",
                "The upstream proxy must be a valid loopback endpoint."
            )
            phase = .failed
            return false
        }
        guard let existingPIDs = profileProcessIdentifiers() else {
            message = Self.text(
                "无法核验独立 Chrome Profile 是否已被占用，已拒绝启动。",
                "Could not verify whether the dedicated Chrome profile is in use, so the launch was refused."
            )
            phase = .failed
            return false
        }
        guard existingPIDs.isEmpty else {
            message = Self.text(
                "独立 Chrome Profile 已被另一个 Routekeeper 浏览器进程占用。请先关闭该窗口。",
                "The dedicated Chrome profile is already used by another Routekeeper browser process. Close that window first."
            )
            phase = .failed
            return false
        }

        busy = true
        phase = .launching
        pendingLaunchWarning = nil
        if verifyEgress {
            egressReport = nil
        }
        message = verifyEgress
            ? Self.text(
                "正在通过 Routekeeper 中继核对 Claude 出口。",
                "Checking the Claude exit through the Routekeeper relay."
            )
            : Self.text(
                "正在以独立 Chrome 配置打开 Claude 网页版。",
                "Opening Claude on the web in a dedicated Chrome profile."
            )

        do {
            try prepareOwnedProfile(languageIdentifier: language, timezoneIdentifier: configuration.timezoneIdentifier)
            _ = try relay.start(upstream: configuration.upstream)
            guard let proxyURL = relay.socks5URL() else { throw LocalRelayError.stopped }
            if verifyEgress {
                egressChecking = true
                let report = await RelayEgressVerification.check(
                    proxyURL: proxyURL,
                    expectedExits: expectedExits
                )
                egressChecking = false
                egressReport = report
                guard report.isVerified || acknowledgedWarning else {
                    relay.stop()
                    pendingLaunchConfiguration = configuration
                    pendingExpectedExits = expectedExits
                    pendingLaunchWarning = report.detail
                    lastUpstream = configuration.upstream
                    lastExpectedExits = expectedExits
                    phase = .stopped
                    busy = false
                    message = report.detail
                    return false
                }
            }
            let arguments = Self.launchArguments(
                languageIdentifier: language,
                proxyURL: proxyURL,
                profileURL: profileURL,
                cacheURL: cacheURL,
                downloadsURL: downloadsURL
            )
            let environment = Self.launchEnvironment(
                languageIdentifier: language,
                timezoneIdentifier: configuration.timezoneIdentifier,
                profileRoot: profileRoot,
                inherited: ProcessInfo.processInfo.environment
            )
            let logURL = logsURL.appendingPathComponent("chrome.log", isDirectory: false)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: logURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)

            let launch = Process()
            launch.executableURL = installation.executableURL
            launch.arguments = arguments
            launch.currentDirectoryURL = profileURL
            launch.environment = environment
            launch.standardOutput = handle
            launch.standardError = handle

            let generation = UUID()
            launchGeneration = generation
            launch.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    await self?.browserTerminated(process, generation: generation)
                }
            }
            try launch.run()
            process = launch
            logHandle = handle
            lastUpstream = configuration.upstream
            lastExpectedExits = expectedExits
            launchedAt = Date()
            pausedByEnvironment = false
            busy = false
            phase = .running
            if let report = egressReport, !report.isVerified {
                message = Self.text(
                    "已按你的选择打开 Claude 网页版，但出口检查仍需确认：\(report.detail)",
                    "Claude on the web opened as requested, but the exit check still needs attention: \(report.detail)"
                )
            } else {
                message = Self.text(
                    "已通过 Routekeeper 中继打开 Claude 网页版；Claude 出口与固定目标一致，Chrome 原生沙箱保持启用。",
                    "Claude on the web is open through the Routekeeper relay; its exit matches the fixed target and Chrome's native sandbox remains enabled."
                )
            }
            return true
        } catch {
            egressChecking = false
            relay.stop()
            closeLog()
            process = nil
            pausedByEnvironment = false
            busy = false
            phase = .failed
            message = Self.text(
                "无法打开 Claude 网页版：\(error.localizedDescription)",
                "Could not open Claude on the web: \(error.localizedDescription)"
            )
            return false
        }
    }

    func pauseNetwork() {
        guard phase == .running else { return }
        egressValidationTask?.cancel()
        egressValidationTask = nil
        relay.pause()
        phase = .networkPaused
        pausedByEnvironment = false
        message = Self.text(
            "Routekeeper 中继已暂停；Chrome 仍保持打开，但 Claude 网页版无法继续联网。",
            "The Routekeeper relay is paused. Chrome remains open, but Claude on the web cannot continue networking."
        )
    }

    func networkEnvironmentChanged(_ reason: String, sleeping: Bool, waking: Bool) {
        guard phase.isRunning else { return }
        if sleeping {
            egressValidationTask?.cancel()
            egressValidationTask = nil
            guard phase == .running else { return }
            relay.pause()
            phase = .networkPaused
            pausedByEnvironment = true
            message = Self.text(
                "系统休眠前已暂停网页版网络。唤醒后请确认代理仍可用，再手动恢复网络。",
                "The web browser network was paused before sleep. After waking, confirm the proxy is available and restore it manually."
            )
        } else if waking, phase == .networkPaused, pausedByEnvironment {
            message = Self.text(
                "系统已唤醒，网页版网络仍保持暂停。确认代理可用后手动恢复，避免沿用旧网络状态。",
                "The Mac woke, but the web browser network remains paused. Confirm the proxy is available before restoring it."
            )
        } else if phase == .running {
            scheduleEgressValidation(reason: reason)
        }
    }

    @discardableResult
    func resumeNetwork() async -> Bool {
        guard phase == .networkPaused, let lastUpstream else { return false }
        busy = true
        do {
            _ = try relay.start(upstream: lastUpstream)
            guard let proxyURL = relay.socks5URL() else { throw LocalRelayError.stopped }
            egressChecking = true
            let report = await RelayEgressVerification.check(
                proxyURL: proxyURL,
                expectedExits: lastExpectedExits
            )
            egressChecking = false
            egressReport = report
            phase = .running
            pausedByEnvironment = false
            busy = false
            if report.isVerified {
                message = Self.text(
                    "Routekeeper 中继已恢复，Claude 出口与固定目标一致。",
                    "The Routekeeper relay is running again and the Claude exit matches the fixed target."
                )
            } else {
                message = Self.text(
                    "Routekeeper 中继已恢复，但出口检查仍需确认：\(report.detail)",
                    "The Routekeeper relay is running again, but the exit check still needs attention: \(report.detail)"
                )
            }
            return true
        } catch {
            egressChecking = false
            busy = false
            phase = .failed
            message = Self.text(
                "无法恢复网页版网络：\(error.localizedDescription)",
                "Could not restore the browser network: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func scheduleEgressValidation(reason: String) {
        egressValidationTask?.cancel()
        let generation = UUID()
        egressValidationGeneration = generation
        egressValidationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, let self,
                  self.phase == .running,
                  self.egressValidationGeneration == generation,
                  let proxyURL = self.relay.socks5URL() else {
                return
            }
            self.egressChecking = true
            let report = await RelayEgressVerification.check(
                proxyURL: proxyURL,
                expectedExits: self.lastExpectedExits
            )
            guard !Task.isCancelled,
                  self.phase == .running,
                  self.egressValidationGeneration == generation else {
                if self.egressValidationGeneration == generation {
                    self.egressChecking = false
                }
                return
            }
            self.egressChecking = false
            self.egressReport = report
            self.message = report.isVerified
                ? Self.text(
                    "网络状态变化后已复测：Claude 出口仍与固定目标一致。",
                    "Checked after the network change: the Claude exit still matches the fixed target."
                )
                : Self.text(
                    "网络状态变化后，出口检查仍需确认：\(report.detail)",
                    "After the network change, the exit check still needs attention: \(report.detail)"
                )
            if !report.isVerified {
                self.message += Self.text("（触发原因：\(reason)）", " (Reason: \(reason))")
            }
        }
    }

    func stop() async {
        guard !busy else { return }
        busy = true
        egressValidationTask?.cancel()
        egressValidationTask = nil
        launchGeneration = UUID()
        relay.stop()
        var pids = profileProcessIdentifiers() ?? []
        if let process, process.isRunning {
            pids.insert(process.processIdentifier)
            process.terminate()
        }
        for pid in pids {
            _ = Darwin.kill(pid, SIGTERM)
        }
        for _ in 0..<20 {
            if pids.allSatisfy({ Darwin.kill($0, 0) != 0 }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        pids.formUnion(profileProcessIdentifiers() ?? [])
        for pid in pids where Darwin.kill(pid, 0) == 0 {
            _ = Darwin.kill(pid, SIGKILL)
        }
        process = nil
        closeLog()
        lastUpstream = nil
        lastExpectedExits = IsolationExpectedExits()
        launchedAt = nil
        pausedByEnvironment = false
        egressChecking = false
        egressReport = nil
        clearPendingLaunch()
        phase = .stopped
        busy = false
        message = Self.text(
            "浏览器已关闭；独立 Profile 和网页版登录状态仍保留。",
            "The browser is closed. Its dedicated profile and web sign-in remain saved."
        )
    }

    @discardableResult
    func clearProfileData() async -> Bool {
        if phase.isRunning || phase == .launching {
            await stop()
        }
        if let pids = profileProcessIdentifiers(), !pids.isEmpty {
            phase = .failed
            message = Self.text(
                "独立 Chrome Profile 仍被 Routekeeper 浏览器进程占用，未删除任何数据。",
                "The dedicated Chrome profile is still in use by a Routekeeper browser process; no data was removed."
            )
            return false
        }
        guard Self.isOwnedProfile(at: profileRoot) else {
            profileAvailable = false
            phase = .stopped
            message = Self.text(
                "没有找到由 Routekeeper 创建的 Claude 网页版 Profile。",
                "No Routekeeper-owned Claude web profile was found."
            )
            return false
        }
        do {
            try FileManager.default.removeItem(at: profileRoot)
            profileAvailable = false
            phase = .stopped
            message = Self.text(
                "已清除 Claude 网页版的独立 Profile、Cookie 和下载目录。",
                "The Claude web profile, cookies and download directory were removed."
            )
            return true
        } catch {
            phase = .failed
            message = Self.text(
                "无法清除网页版 Profile：\(error.localizedDescription)",
                "Could not remove the web profile: \(error.localizedDescription)"
            )
            return false
        }
    }

    nonisolated static func launchArguments(
        languageIdentifier: String,
        proxyURL: String,
        profileURL: URL,
        cacheURL: URL,
        downloadsURL: URL
    ) -> [String] {
        let language = IsolationSessionEnvironment.appleLanguage(for: languageIdentifier)
        let acceptLanguage = IsolationSessionEnvironment.acceptLanguage(for: languageIdentifier)
        return [
            "--user-data-dir=\(profileURL.path)",
            "--profile-directory=Claude",
            "--disk-cache-dir=\(cacheURL.path)",
            "--download-default-directory=\(downloadsURL.path)",
            "--proxy-server=\(proxyURL)",
            "--proxy-bypass-list=<-loopback>",
            "--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
            "--disable-quic",
            "--lang=\(language)",
            "--accept-lang=\(acceptLanguage)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-sync",
            "--disable-extensions",
            "--use-mock-keychain",
            "--new-window",
            ClaudeWebBrowserDiscovery.claudeURL.absoluteString
        ]
    }

    nonisolated static func launchEnvironment(
        languageIdentifier: String,
        timezoneIdentifier: String,
        profileRoot: URL,
        inherited: [String: String] = [:]
    ) -> [String: String] {
        let home = profileRoot.appendingPathComponent("Home", isDirectory: true)
        let temporary = profileRoot.appendingPathComponent("Temp", isDirectory: true)
        let locale = IsolationSessionEnvironment.posixLocale(for: languageIdentifier)
        let language = IsolationSessionEnvironment.languageIdentifier(forLocale: locale)
        let appleLanguage = IsolationSessionEnvironment.appleLanguage(for: languageIdentifier)
        var values = [
            "HOME": home.path,
            "CFFIXED_USER_HOME": home.path,
            "TMPDIR": temporary.path,
            "TMP": temporary.path,
            "TEMP": temporary.path,
            "XDG_CONFIG_HOME": home.appendingPathComponent(".config").path,
            "XDG_CACHE_HOME": home.appendingPathComponent(".cache").path,
            "XDG_DATA_HOME": home.appendingPathComponent(".local/share").path,
            "TZ": timezoneIdentifier,
            "LANG": locale,
            "LC_ALL": locale,
            "LANGUAGE": language,
            "AppleLanguages": appleLanguage,
            "AppleLocale": locale.replacingOccurrences(of: ".UTF-8", with: ""),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        for key in ["USER", "LOGNAME", "SHELL"] {
            if let value = inherited[key], !value.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private func prepareOwnedProfile(
        languageIdentifier: String,
        timezoneIdentifier: String
    ) throws {
        let fileManager = FileManager.default
        let marker = profileRoot.appendingPathComponent(Self.profileMarkerName)
        if fileManager.fileExists(atPath: profileRoot.path) {
            guard fileManager.fileExists(atPath: marker.path) else {
                throw NSError(
                    domain: "Routekeeper.ClaudeWeb",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: Self.text(
                        "网页版 Profile 已存在，但不是由 Routekeeper 创建。为避免覆盖现有数据，已拒绝使用。",
                        "A web profile already exists but was not created by Routekeeper. It was left untouched to avoid overwriting existing data."
                    )]
                )
            }
        } else {
            try fileManager.createDirectory(
                at: profileRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data("Routekeeper Claude web browser profile\n".utf8)
                .write(to: marker, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        }
        for directory in [
            profileURL,
            homeURL,
            homeURL.appendingPathComponent("Downloads", isDirectory: true),
            tempURL,
            downloadsURL,
            cacheURL,
            logsURL,
            homeURL.appendingPathComponent("Library/Preferences", isDirectory: true)
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let locale = IsolationSessionEnvironment.posixLocale(for: languageIdentifier)
        let appleLanguage = IsolationSessionEnvironment.appleLanguage(for: languageIdentifier)
        let preferences: [String: Any] = [
            "AppleLocale": locale.replacingOccurrences(of: ".UTF-8", with: ""),
            "AppleLanguages": [appleLanguage],
            "TZ": timezoneIdentifier
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: preferences,
            format: .binary,
            options: 0
        )
        try data.write(
            to: homeURL.appendingPathComponent("Library/Preferences/.GlobalPreferences.plist"),
            options: .atomic
        )
        profileAvailable = true
    }

    private func browserTerminated(_ terminated: Process, generation: UUID) async {
        guard launchGeneration == generation else { return }
        egressValidationTask?.cancel()
        egressValidationTask = nil
        let shortLived = launchedAt.map { Date().timeIntervalSince($0) < 1.5 } ?? false
        relay.stop()
        closeLog()
        process = nil
        launchedAt = nil
        lastUpstream = nil
        lastExpectedExits = IsolationExpectedExits()
        pausedByEnvironment = false
        egressChecking = false
        clearPendingLaunch()
        if terminated.terminationReason == .uncaughtSignal || terminated.terminationStatus != 0 || shortLived {
            phase = .failed
            message = Self.text(
                "Chrome 启动后立即退出。请确认没有其他窗口占用同一 Routekeeper Profile，然后重试。",
                "Chrome exited immediately. Make sure no other window is using the same Routekeeper profile, then try again."
            )
        } else {
            phase = .stopped
            message = Self.text(
                "浏览器已关闭；独立 Profile 和网页版登录状态仍保留。",
                "The browser is closed. Its dedicated profile and web sign-in remain saved."
            )
        }
    }

    private func closeLog() {
        try? logHandle?.close()
        logHandle = nil
    }

    private func clearPendingLaunch() {
        pendingLaunchWarning = nil
        pendingLaunchConfiguration = nil
        pendingExpectedExits = IsolationExpectedExits()
    }

    private func profileProcessIdentifiers() -> Set<pid_t>? {
        let result = Command.run(
            "/bin/ps",
            ["-ww", "-axo", "pid=,command="],
            timeout: 2
        )
        guard result.status == 0 else { return nil }
        let marker = "--user-data-dir=\(profileURL.path)"
        var identifiers = Set<pid_t>()
        for line in result.output.split(separator: "\n") {
            let fields = line.split(
                maxSplits: 1,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard fields.count == 2,
                  let pid = pid_t(fields[0]),
                  fields[1].contains(marker) else {
                continue
            }
            identifiers.insert(pid)
        }
        return identifiers
    }

    private static func isOwnedProfile(at root: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: root.appendingPathComponent(profileMarkerName).path
        )
    }

    private static func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }
}
