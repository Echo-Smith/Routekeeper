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
    @ObservationIgnored private var configurationValidationMessage: String?

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
                "未检测到 Google Chrome。安装官方版本后即可在独立配置中打开 Chrome。",
                "Google Chrome was not found. Install the official browser to open Chrome in a dedicated profile."
            )
            : Self.text(
                "使用独立 Chrome 配置访问 Claude；不会导入宿主浏览器的 Cookie、密码、历史或扩展。",
                "Use a dedicated Chrome profile for Claude without importing host cookies, passwords, history or extensions."
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
            return Self.text("Chrome 正在运行", "Chrome is running")
        case .networkPaused:
            return Self.text("Chrome 网络已暂停", "Chrome network paused")
        case .failed:
            return Self.text("Chrome 未能启动", "Chrome could not start")
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

    var showsReadySummary: Bool {
        phase == .stopped
            && installation != nil
            && !discovering
            && configurationValidationMessage == nil
    }

    var downloadPath: String { downloadsURL.path }
    var profilePath: String { profileRoot.path }
    func refreshProfileAvailability() {
        profileAvailable = Self.isOwnedProfile(at: profileRoot)
    }

    /// Stops only the dedicated Routekeeper Chrome instance before its profile
    /// is trashed. Host Chrome sessions are never matched or terminated.
    func stopForCleanup() async -> Bool {
        if phase.isRunning || phase == .launching || busy {
            await stop()
        }
        guard let pids = profileProcessIdentifiers(), pids.isEmpty else {
            message = Self.text(
                "无法确认 Routekeeper Chrome 已关闭，未清理配置。",
                "Could not confirm that Routekeeper Chrome is closed; the profile was not cleaned."
            )
            return false
        }
        return true
    }

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
        } else if detected != nil,
                  !phase.isRunning,
                  let existingPIDs = profileProcessIdentifiers(),
                  !existingPIDs.isEmpty,
                  Self.isOwnedProfile(at: profileRoot) {
            phase = .failed
            message = Self.text(
                "检测到上次由 Routekeeper 打开的专用 Chrome 仍在运行。点击“重试”会先关闭该专用实例，再用当前共享设置重新打开；宿主 Chrome 不受影响。",
                "A dedicated Chrome instance opened by Routekeeper is still running. Retry closes that dedicated instance and reopens it with the current shared settings; your host Chrome is not affected."
            )
        } else if detected != nil, !phase.isRunning {
            phase = .stopped
            message = configurationValidationMessage ?? Self.text(
                "Google Chrome 已就绪。Chrome 会使用独立配置和当前会话的语言、时区与代理。",
                "Google Chrome is ready. Chrome will use a dedicated profile with the current session language, timezone and proxy."
            )
        }
    }

    func discoverIfNeeded() async {
        guard !hasDiscovered else { return }
        await refreshInstallation()
    }

    func sharedConfigurationDidChange(_ configuration: SandboxSharedConfiguration) {
        // Valid edits must also replace a previous invalid-settings message.
        guard !busy, !phase.isRunning else { return }
        phase = .stopped
        configurationValidationMessage = nil
        if installation == nil {
            message = Self.text(
                "未检测到 Google Chrome。请先安装 Google 官方版本。",
                "Google Chrome was not found. Install the official Google build first."
            )
        } else if !configuration.hasValidTimezone {
            message = Self.text(
                "会话时区“\(configuration.timezoneIdentifier)”无效，请修正红色配置后再打开 Chrome。",
                "The session timezone \"\(configuration.timezoneIdentifier)\" is invalid. Fix the red setting before opening Chrome."
            )
            configurationValidationMessage = message
        } else if !configuration.hasValidLanguage {
            message = Self.text(
                "会话语言“\(configuration.languageIdentifier)”无效，请修正红色配置后再打开 Chrome。",
                "The session language \"\(configuration.languageIdentifier)\" is invalid. Fix the red setting before opening Chrome."
            )
            configurationValidationMessage = message
        } else if !configuration.upstream.isValid {
            message = Self.text(
                "上游代理仍需有效的本机回环地址和端口，请编辑共享设置后重试。",
                "The upstream proxy still needs a valid loopback host and port. Edit the shared settings and try again."
            )
            configurationValidationMessage = message
        } else {
            message = Self.text(
                "共享设置已更新，可以重新打开 Chrome。",
                "Shared settings were updated. Chrome can be opened again."
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
            "已取消打开 Chrome。",
            "Opening Chrome was cancelled."
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
        guard TimeZone(identifier: configuration.timezoneIdentifier) != nil else {
            message = Self.text(
                "会话时区“\(configuration.timezoneIdentifier)”无效，请修正红色配置后再试。",
                "The session timezone \"\(configuration.timezoneIdentifier)\" is invalid. Fix the red setting and try again."
            )
            phase = .failed
            return false
        }
        guard let language = IsolationSessionEnvironment.normalizedLanguageIdentifier(
            configuration.languageIdentifier
        ) else {
            message = Self.text(
                "会话语言“\(configuration.languageIdentifier)”无效，请修正红色配置后再试。",
                "The session language \"\(configuration.languageIdentifier)\" is invalid. Fix the red setting and try again."
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
                "无法核验独立 Chrome 配置是否已被占用，已拒绝启动。",
                "Could not verify whether the dedicated Chrome profile is in use, so the launch was refused."
            )
            phase = .failed
            return false
        }
        if !existingPIDs.isEmpty {
            guard Self.isOwnedProfile(at: profileRoot) else {
                message = Self.text(
                    "独立 Chrome 配置已被另一个 Chrome 进程占用，且无法确认它由 Routekeeper 创建。请先关闭该窗口。",
                    "The dedicated Chrome profile is in use by a Chrome process that Routekeeper cannot verify. Close that window first."
                )
                phase = .failed
                return false
            }
            message = Self.text(
                "检测到上次启动的专用 Chrome 仍在运行，正在先关闭该专用实例再重新打开。宿主 Chrome 不受影响。",
                "A previously launched dedicated Chrome instance is still running. Routekeeper is closing that dedicated instance before reopening it; your host Chrome is not affected."
            )
            phase = .launching
            await terminateProfileProcesses(existingPIDs)
            guard let remainingPIDs = profileProcessIdentifiers() else {
                message = Self.text(
                    "无法确认专用 Chrome 是否已退出，已停止本次启动。",
                    "Routekeeper could not confirm that the dedicated Chrome exited, so this launch was stopped."
                )
                phase = .failed
                return false
            }
            guard remainingPIDs.isEmpty else {
                message = Self.text(
                    "专用 Chrome 仍在运行，无法安全复用同一配置。请稍后重试。",
                    "The dedicated Chrome is still running, so the profile cannot be reused safely. Try again shortly."
                )
                phase = .failed
                return false
            }
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
                "正在以独立 Chrome 配置打开 Chrome。",
                "Opening Chrome in a dedicated Chrome profile."
            )

        do {
            try prepareOwnedProfile(languageIdentifier: language, timezoneIdentifier: configuration.timezoneIdentifier)
            try Self.markProfileCleanlyExited(profileURL: profileURL)
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
                    "已按你的选择打开 Chrome，但出口检查仍需确认：\(report.detail)",
                    "Chrome opened as requested, but the exit check still needs attention: \(report.detail)"
                )
            } else {
                message = Self.text(
                    "已通过 Routekeeper 中继打开 Chrome；Claude 出口与固定目标一致，Chrome 原生沙箱保持启用。",
                    "Chrome is open through the Routekeeper relay; its exit matches the fixed target and Chrome's native sandbox remains enabled."
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
                "无法打开 Chrome：\(error.localizedDescription)",
                "Could not open Chrome: \(error.localizedDescription)"
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
            "Routekeeper 中继已暂停；Chrome 仍保持打开，但当前无法继续联网。",
            "The Routekeeper relay is paused. Chrome remains open, but Chrome cannot continue networking."
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
                "系统休眠前已暂停 Chrome 网络。唤醒后请确认代理仍可用，再手动恢复网络。",
                "Chrome networking was paused before sleep. After waking, confirm the proxy is available and restore it manually."
            )
        } else if waking, phase == .networkPaused, pausedByEnvironment {
            message = Self.text(
                "系统已唤醒，Chrome 网络仍保持暂停。确认代理可用后手动恢复，避免沿用旧网络状态。",
                "The Mac woke, but Chrome networking remains paused. Confirm the proxy is available before restoring it."
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
                "无法恢复 Chrome 网络：\(error.localizedDescription)",
                "Could not restore Chrome networking: \(error.localizedDescription)"
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
        try? Self.markProfileCleanlyExited(profileURL: profileURL)
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
            "Chrome 已关闭；独立配置和登录状态仍保留。",
            "Chrome is closed. Its dedicated profile and sign-in state remain saved."
        )
    }

    @discardableResult
    func clearProfileData() async -> Bool {
        if phase.isRunning || phase == .launching {
            await stop()
        }
        guard let pids = profileProcessIdentifiers() else {
            phase = .failed
            message = Self.text(
                "无法核验独立 Chrome 配置是否仍被占用，未删除任何数据。",
                "Could not verify whether the dedicated Chrome profile is still in use; no data was removed."
            )
            return false
        }
        if !pids.isEmpty {
            phase = .failed
            message = Self.text(
                "独立 Chrome 配置仍被 Routekeeper Chrome 进程占用，未删除任何数据。",
                "The dedicated Chrome profile is still in use by a Routekeeper Chrome process; no data was removed."
            )
            return false
        }
        guard Self.isOwnedProfile(at: profileRoot) else {
            profileAvailable = false
            phase = .stopped
            message = Self.text(
                "没有找到由 Routekeeper 创建的 Chrome 配置。",
                "No Routekeeper-owned Chrome profile was found."
            )
            return false
        }
        do {
            try FileManager.default.removeItem(at: profileRoot)
            profileAvailable = false
            phase = .stopped
            message = Self.text(
                "已清除 Chrome 的独立配置、Cookie 和下载目录。",
                "The Chrome profile, cookies and download directory were removed."
            )
            return true
        } catch {
            phase = .failed
            message = Self.text(
                "无法清除 Chrome 配置：\(error.localizedDescription)",
                "Could not remove the Chrome profile: \(error.localizedDescription)"
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

    nonisolated static func markProfileCleanlyExited(profileURL: URL) throws {
        let preferencesURL = profileURL
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: false)
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else { return }

        let data = try Data(contentsOf: preferencesURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        var profile = root["profile"] as? [String: Any] ?? [:]
        profile["exit_type"] = "Normal"
        profile["exited_cleanly"] = true
        root["profile"] = profile
        let updated = try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
        try updated.write(to: preferencesURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: preferencesURL.path
        )
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
        try Self.ensureOwnedProfileRoot(at: profileRoot)
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

    /// Claims an existing dedicated profile only when every top-level entry is
    /// one Routekeeper manages. Existing browser data is never modified.
    @discardableResult
    static func ensureOwnedProfileRoot(at root: URL) throws -> Bool {
        let fileManager = FileManager.default
        let marker = root.appendingPathComponent(profileMarkerName)
        let managedEntries: Set<String> = [
            profileMarkerName, "ChromeProfile", "Home", "Temp",
            "Downloads", "Cache", "Logs"
        ]

        if fileManager.fileExists(atPath: root.path) {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw ownershipError()
            }
            if fileManager.fileExists(atPath: marker.path) {
                let markerValues = try marker.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard markerValues.isRegularFile == true,
                      markerValues.isSymbolicLink != true else {
                    throw ownershipError()
                }
                return false
            }
            let entries = try fileManager.contentsOfDirectory(atPath: root.path)
            guard Set(entries).isSubset(of: managedEntries) else {
                throw ownershipError()
            }
        } else {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try Data("Routekeeper Claude web browser profile\n".utf8)
            .write(to: marker, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        return true
    }

    private static func ownershipError() -> NSError {
        NSError(
            domain: "Routekeeper.ClaudeWeb",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: text(
                "Chrome 配置目录包含未知内容或符号链接。为避免覆盖现有数据，已拒绝使用。",
                "The Chrome profile directory contains unknown content or a symbolic link. It was left untouched to avoid overwriting existing data."
            )]
        )
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
                "Chrome 启动后立即退出。请确认没有其他窗口占用同一 Routekeeper 配置，然后重试。",
                "Chrome exited immediately. Make sure no other window is using the same Routekeeper profile, then try again."
            )
        } else {
            phase = .stopped
            message = Self.text(
                "Chrome 已关闭；独立配置和登录状态仍保留。",
                "Chrome is closed. Its dedicated profile and sign-in state remain saved."
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

    private func terminateProfileProcesses(_ initialPIDs: Set<pid_t>) async {
        for pid in initialPIDs where Darwin.kill(pid, 0) == 0 {
            _ = Darwin.kill(pid, SIGTERM)
        }
        for _ in 0..<20 {
            let remaining = profileProcessIdentifiers() ?? []
            if remaining.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let remaining = profileProcessIdentifiers() ?? initialPIDs
        for pid in remaining where Darwin.kill(pid, 0) == 0 {
            _ = Darwin.kill(pid, SIGKILL)
        }
        for _ in 0..<10 {
            if profileProcessIdentifiers()?.isEmpty == true { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func profileProcessIdentifiers() -> Set<pid_t>? {
        let result = Command.run(
            "/bin/ps",
            ["-ww", "-axo", "pid=,command="],
            timeout: 2,
            outputLimit: 2_000_000
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
