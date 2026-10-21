import Darwin
import Foundation

public enum CleanupScope: String, CaseIterable, Sendable, Equatable {
    case hostDesktop
    case hostCode
    case hostScience
    case currentSession
    case pastSession
    case persistentProfile
}

public enum CleanupBlockReason: String, Sendable, Equatable {
    case symbolicLink
    case processRunning
    case sessionRunning
    case profileInUse
    case processInspectionUnavailable
}

/// Cache cleanup never includes conversations, projects, settings, browser
/// storage, OAuth files or credentials. Paths are exact, predeclared targets.
public struct CleanupTarget: Identifiable, Sendable, Equatable {
    public var path: String
    public var labelZh: String
    public var labelEn: String
    public var kindZh: String
    public var kindEn: String
    public var scope: CleanupScope
    public var sizeBytes: Int64
    public var fileCount: Int
    public var exists: Bool
    public var blockedReason: CleanupBlockReason?
    /// The owned session or profile root used for the live-process check.
    public var owningRoot: String?

    public var id: String { path }
    public var isSelectable: Bool { exists && blockedReason == nil }
    public var label: String { labelZh }
    public var kind: String { kindZh }

    public init(
        path: String,
        labelZh: String,
        labelEn: String,
        kindZh: String,
        kindEn: String,
        scope: CleanupScope,
        sizeBytes: Int64 = 0,
        fileCount: Int = 0,
        exists: Bool = false,
        blockedReason: CleanupBlockReason? = nil,
        owningRoot: String? = nil
    ) {
        self.path = path
        self.labelZh = labelZh
        self.labelEn = labelEn
        self.kindZh = kindZh
        self.kindEn = kindEn
        self.scope = scope
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.exists = exists
        self.blockedReason = blockedReason
        self.owningRoot = owningRoot
    }

    public func label(english: Bool) -> String {
        english ? labelEn : labelZh
    }

    public func kind(english: Bool) -> String {
        english ? kindEn : kindZh
    }
}

public struct CleanupPlan: Sendable {
    public var targets: [CleanupTarget]
    public var warnings: [String]

    public var totalBytes: Int64 { targets.reduce(0) { $0 + $1.sizeBytes } }
    public var totalFiles: Int { targets.reduce(0) { $0 + $1.fileCount } }
    public var availableCount: Int { targets.filter { $0.exists && $0.fileCount > 0 }.count }
    public var selectableCount: Int { targets.filter { $0.exists && $0.fileCount > 0 && $0.isSelectable }.count }
    public var blockedCount: Int { targets.filter { $0.exists && $0.fileCount > 0 && $0.blockedReason != nil }.count }
    public var selectableBytes: Int64 {
        targets.filter { $0.exists && $0.fileCount > 0 && $0.isSelectable }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    public init(targets: [CleanupTarget], warnings: [String] = []) {
        self.targets = targets
        self.warnings = warnings
    }
}

public struct CleanupSafetyContext: Sendable, Equatable {
    public var processInspectionAvailable: Bool
    public var desktopRunning: Bool
    public var codeRunning: Bool
    public var scienceRunning: Bool
    public var runningSessionRoots: Set<String>
    public var runningSessionProfiles: Set<String>

    public init(
        processInspectionAvailable: Bool,
        desktopRunning: Bool = false,
        codeRunning: Bool = false,
        scienceRunning: Bool = false,
        runningSessionRoots: Set<String> = [],
        runningSessionProfiles: Set<String> = []
    ) {
        self.processInspectionAvailable = processInspectionAvailable
        self.desktopRunning = desktopRunning
        self.codeRunning = codeRunning
        self.scienceRunning = scienceRunning
        self.runningSessionRoots = runningSessionRoots
        self.runningSessionProfiles = runningSessionProfiles
    }
}

public enum CacheCleaner {
    private struct Definition {
        var path: String
        var labelZh: String
        var labelEn: String
        var kindZh: String
        var kindEn: String
        var scope: CleanupScope
        var owningRoot: String?
    }

    private struct Measurement {
        var exists: Bool
        var sizeBytes: Int64
        var fileCount: Int
        var isSymbolicLink: Bool
    }

    private static let desktopCacheEntries: [(String, String, String)] = [
        ("Cache", "网页缓存", "Web cache"),
        ("Code Cache", "编译代码缓存", "Compiled code cache"),
        ("GPUCache", "GPU 缓存", "GPU cache"),
        ("DawnCache", "图形后端缓存", "Graphics backend cache"),
        ("DawnGraphiteCache", "Graphite 图形缓存", "Graphite graphics cache"),
        ("DawnWebGPUCache", "WebGPU 缓存", "WebGPU cache"),
        ("GraphiteDawnCache", "Dawn 图形缓存", "Dawn graphics cache"),
        ("GPUPersistentCache", "持久图形缓存", "Persistent GPU cache"),
        ("ShaderCache", "着色器缓存", "Shader cache"),
        ("GrShaderCache", "Gr 着色器缓存", "Gr shader cache"),
        ("VideoDecodeStats", "视频解码统计缓存", "Video decode statistics"),
        ("Shared Dictionary", "共享字典缓存", "Shared dictionary cache"),
        ("SharedStorage", "共享存储缓存", "Shared storage cache"),
        ("component_crx_cache", "组件下载缓存", "Component download cache"),
        ("extensions_crx_cache", "扩展下载缓存", "Extension download cache"),
        ("Service Worker/CacheStorage", "离线页面缓存", "Offline page cache"),
        ("Service Worker/ScriptCache", "离线脚本缓存", "Offline script cache"),
        ("Crashpad", "崩溃报告暂存", "Crash report staging"),
        ("sentry", "诊断事件队列", "Diagnostic event queue"),
        ("logs", "桌面端运行日志", "Desktop runtime logs"),
        ("Logs", "桌面端运行日志", "Desktop runtime logs"),
    ]

    private static let codeCacheEntries: [(String, String, String)] = [
        ("cache", "Code 缓存", "Code cache"),
        ("stats-cache.json", "使用统计缓存", "Usage statistics cache"),
        ("telemetry", "本地遥测缓存", "Local telemetry cache"),
        ("usage-data", "用量缓存", "Usage data cache"),
        ("usage.jsonl", "用量记录", "Usage record"),
        ("usage.with-fix.jsonl", "用量修正记录", "Usage correction record"),
        ("paste-cache", "粘贴缓存", "Paste cache"),
        ("statsig", "功能开关缓存", "Feature flag cache"),
        ("downloads", "Code 下载缓存", "Code download cache"),
        ("debug", "Code 调试日志", "Code debug logs"),
        ("daemon", "后台守护进程状态", "Daemon state"),
        ("daemon.log", "后台守护进程日志", "Daemon log"),
        ("daemon.status.json", "后台守护进程状态", "Daemon status"),
        ("ide", "IDE 连接状态缓存", "IDE connection state"),
        (".last-cleanup", "上次清理时间戳", "Last cleanup timestamp"),
        (".last-update-result.json", "上次更新结果", "Last update result"),
    ]

    private static let scienceCacheEntries: [(String, String, String)] = [
        ("logs", "Science 运行日志", "Science runtime logs"),
        ("conda/pkgs", "Science Conda 包缓存", "Science Conda package cache"),
    ]

    /// Legacy accessor retained for callers that only need the host paths.
    public static func safePaths(home: String) -> [(path: String, label: String, kind: String)] {
        hostDefinitions(home: home).map { ($0.path, $0.labelZh, $0.kindZh) }
    }

    /// Scans only exact, declared cache/log paths. Session and profile roots are
    /// included only when Routekeeper's ownership marker is present.
    public static func scan(
        home: String,
        sessionsRoot: URL? = nil,
        profilesRoot: URL? = nil,
        currentSessionRoot: URL? = nil
    ) -> CleanupPlan {
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        let applicationSupport = homeURL.appendingPathComponent("Library/Application Support/Routekeeper", isDirectory: true)
        let resolvedSessionsRoot = sessionsRoot ?? applicationSupport.appendingPathComponent("Isolation", isDirectory: true)
        let resolvedProfilesRoot = profilesRoot ?? applicationSupport.appendingPathComponent("Profiles", isDirectory: true)
        let profileHome = resolvedProfilesRoot.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)

        var definitions = hostDefinitions(home: home)
        var warnings: [String] = []

        let sessions = ownedSessionRoots(in: resolvedSessionsRoot, warnings: &warnings)
        for root in sessions {
            let isCurrent = currentSessionRoot.map {
                $0.standardizedFileURL.path == root.standardizedFileURL.path
            } ?? false
            definitions += sessionDefinitions(
                root: root,
                scope: isCurrent ? .currentSession : .pastSession
            )
        }
        if let unowned = unownedSessionRootCount(in: resolvedSessionsRoot),
           unowned > 0 {
            warnings.append(
                "已跳过 \(unowned) 个没有 Routekeeper 会话标记的目录；不会清理无法确认归属的数据。"
            )
        }

        if ownsProfile(profileHome) {
            definitions += profileDefinitions(home: profileHome.path, owningRoot: profileHome.path)
        } else if FileManager.default.fileExists(atPath: profileHome.path) {
            warnings.append(
                "持久登录目录存在但没有 Routekeeper 标记，已保留且不会参与清理。"
            )
        }

        var seen = Set<String>()
        let targets = definitions.compactMap { definition -> CleanupTarget? in
            let normalized = URL(fileURLWithPath: definition.path).standardizedFileURL.path
            guard seen.insert(normalized).inserted else { return nil }
            let measurement = measure(normalized)
            return CleanupTarget(
                path: normalized,
                labelZh: definition.labelZh,
                labelEn: definition.labelEn,
                kindZh: definition.kindZh,
                kindEn: definition.kindEn,
                scope: definition.scope,
                sizeBytes: measurement.sizeBytes,
                fileCount: measurement.fileCount,
                exists: measurement.exists,
                blockedReason: measurement.isSymbolicLink ? .symbolicLink : nil,
                owningRoot: definition.owningRoot
            )
        }
        return CleanupPlan(targets: targets, warnings: warnings)
    }

    /// Captures process and owned-session state once, then marks every target
    /// that must be skipped. Failure to inspect processes is fail-closed.
    public static func scanWithLiveSafety(
        home: String,
        sessionsRoot: URL? = nil,
        profilesRoot: URL? = nil,
        currentSessionRoot: URL? = nil
    ) -> CleanupPlan {
        var plan = scan(
            home: home,
            sessionsRoot: sessionsRoot,
            profilesRoot: profilesRoot,
            currentSessionRoot: currentSessionRoot
        )
        let safety = liveSafety(
            home: home,
            sessionsRoot: sessionsRoot,
            profilesRoot: profilesRoot
        )
        plan.targets = plan.targets.map { target in
            var updated = target
            if updated.blockedReason == nil {
                updated.blockedReason = blocker(for: updated, safety: safety)
            }
            return updated
        }
        return plan
    }

    public static func liveSafety(
        home: String = NSHomeDirectory(),
        sessionsRoot: URL? = nil,
        profilesRoot: URL? = nil
    ) -> CleanupSafetyContext {
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        let applicationSupport = homeURL.appendingPathComponent("Library/Application Support/Routekeeper", isDirectory: true)
        let resolvedSessionsRoot = sessionsRoot ?? applicationSupport.appendingPathComponent("Isolation", isDirectory: true)
        let resolvedProfilesRoot = profilesRoot ?? applicationSupport.appendingPathComponent("Profiles", isDirectory: true)
        let profileHome = resolvedProfilesRoot.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        let desktopRoot = ApplicationDiscovery.path(bundleID: ApplicationDiscovery.desktopID, name: "Claude")
        let processScan = LocalProcesses.scan(desktopRoots: desktopRoot.map { [$0] } ?? [])
        let executablePaths = LocalProcesses.ownExecutablePaths()
        let scienceRunning = executablePaths.contains {
            URL(fileURLWithPath: $0).lastPathComponent == "claude-science"
        }
        let desktopExecutableRunning = executablePaths.contains {
            $0.hasSuffix(".app/Contents/MacOS/Claude")
        }

        var warnings: [String] = []
        let sessions = ownedSessionRoots(in: resolvedSessionsRoot, warnings: &warnings)
        var runningRoots = Set<String>()
        var profilesInUse = Set<String>()
        for root in sessions where sessionIsRunning(root) {
            runningRoots.insert(root.standardizedFileURL.path)
            guard ownsProfile(profileHome) else { continue }
            let profilePath = profileHome.standardizedFileURL.path
            let profileURL = root.appendingPathComponent("control/session.sb", isDirectory: false)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: profileURL.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  size > 0, size < 1_000_000,
                  let contents = try? String(contentsOf: profileURL, encoding: .utf8) else {
                continue
            }
            if contents.contains(profilePath) {
                profilesInUse.insert(profilePath)
            }
        }

        return CleanupSafetyContext(
            processInspectionAvailable: processScan.available,
            desktopRunning: desktopExecutableRunning
                || processScan.records.contains { $0.kind == .desktop },
            codeRunning: processScan.records.contains { $0.kind == .code },
            scienceRunning: scienceRunning,
            runningSessionRoots: runningRoots,
            runningSessionProfiles: profilesInUse
        )
    }

    public static func blocker(
        for target: CleanupTarget,
        safety: CleanupSafetyContext
    ) -> CleanupBlockReason? {
        guard safety.processInspectionAvailable else {
            return .processInspectionUnavailable
        }
        switch target.scope {
        case .hostDesktop:
            return safety.desktopRunning ? .processRunning : nil
        case .hostCode:
            return safety.codeRunning ? .processRunning : nil
        case .hostScience:
            return safety.scienceRunning ? .processRunning : nil
        case .currentSession, .pastSession:
            guard let root = target.owningRoot else { return .processInspectionUnavailable }
            return safety.runningSessionRoots.contains(root) ? .sessionRunning : nil
        case .persistentProfile:
            guard let root = target.owningRoot else { return .processInspectionUnavailable }
            return safety.runningSessionProfiles.contains(root) ? .profileInUse : nil
        }
    }

    public static func sessionIsRunning(_ root: URL) -> Bool {
        let control = root.appendingPathComponent("control", isDirectory: true)
        let pidText = try? String(contentsOf: control.appendingPathComponent("sandbox.pid"), encoding: .utf8)
        let startText = try? String(contentsOf: control.appendingPathComponent("sandbox.started"), encoding: .utf8)
        guard let pid = pidText.flatMap({ Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
              pid > 1,
              let expectedStart = startText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedStart.isEmpty else {
            return false
        }
        if Darwin.kill(pid, 0) != 0 {
            return errno != ESRCH
        }
        let process = Command.run(
            "/bin/ps",
            ["-p", String(pid), "-o", "lstart=,command="],
            timeout: 2
        )
        guard process.status == 0 else {
            return true
        }
        let line = process.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.hasPrefix(expectedStart)
    }

    static func directorySize(_ path: String) -> (Int64, Int) {
        let measurement = measure(path)
        return (measurement.sizeBytes, measurement.fileCount)
    }

    /// Moves the directory or file to Trash. Recoverable; never uses unlink/rm.
    @discardableResult
    public static func trash(_ path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path)
                || (try? fm.attributesOfItem(atPath: path)) != nil else {
            return true
        }
        do {
            try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public static func trash(_ target: CleanupTarget) -> Bool {
        guard target.isSelectable else { return false }
        return trash(target.path)
    }

    private static func hostDefinitions(home: String) -> [Definition] {
        var result: [Definition] = []
        let desktopRoots = [
            home + "/Library/Application Support/Claude",
            home + "/Library/Application Support/Claude-3p",
            home + "/Library/Application Support/com.anthropic.claudefordesktop",
        ]
        for root in desktopRoots {
            result += desktopDefinitions(
                root: root,
                scope: .hostDesktop,
                owningRoot: nil,
                labelSuffixZh: "",
                labelSuffixEn: ""
            )
        }

        result += exactDefinition(
            home + "/Library/Caches/Claude",
            labelZh: "Claude 桌面版缓存",
            labelEn: "Claude desktop cache",
            kindZh: "旧版系统缓存",
            kindEn: "Legacy system cache",
            scope: .hostDesktop
        )
        result += prefixedEntries(
            parent: home + "/Library/Caches",
            prefix: "com.anthropic.claudefordesktop",
            labelZh: "Claude 桌面版系统缓存",
            labelEn: "Claude desktop system cache",
            kindZh: "系统应用缓存与更新缓存",
            kindEn: "System app and updater cache",
            scope: .hostDesktop
        )
        result += exactDefinition(
            home + "/Library/Logs/Claude",
            labelZh: "Claude 桌面版日志",
            labelEn: "Claude desktop logs",
            kindZh: "运行与崩溃日志",
            kindEn: "Runtime and crash logs",
            scope: .hostDesktop
        )
        result += prefixedEntries(
            parent: home + "/Library/Logs/DiagnosticReports",
            prefix: "Claude",
            labelZh: "Claude 崩溃报告",
            labelEn: "Claude crash reports",
            kindZh: "系统诊断报告",
            kindEn: "System diagnostic reports",
            scope: .hostDesktop
        )
        result += prefixedEntries(
            parent: home + "/Library/Application Support/CrashReporter",
            prefix: "Claude",
            labelZh: "Claude 崩溃缓存",
            labelEn: "Claude crash cache",
            kindZh: "崩溃报告暂存",
            kindEn: "Crash report staging",
            scope: .hostDesktop
        )
        result += codeDefinitions(
            root: home,
            scope: .hostCode,
            owningRoot: nil,
            labelSuffixZh: "",
            labelSuffixEn: ""
        )
        result += scienceDefinitions(
            root: home,
            scope: .hostScience,
            owningRoot: nil,
            labelSuffixZh: "",
            labelSuffixEn: ""
        )
        return result
    }

    private static func sessionDefinitions(root: URL, scope: CleanupScope) -> [Definition] {
        let sessionID = String(root.lastPathComponent.prefix(8))
        let suffixZh = " · 会话 \(sessionID)"
        let suffixEn = " · session \(sessionID)"
        let home = root.appendingPathComponent("home", isDirectory: true).path
        var result: [Definition] = []
        for desktopRoot in [
            root.appendingPathComponent("home/Library/Application Support/Claude", isDirectory: true).path,
            root.appendingPathComponent("home/Library/Application Support/Claude-3p", isDirectory: true).path,
            root.appendingPathComponent("home/Library/Application Support/com.anthropic.claudefordesktop", isDirectory: true).path,
        ] {
            result += desktopDefinitions(
                root: desktopRoot,
                scope: scope,
                owningRoot: root.path,
                labelSuffixZh: suffixZh,
                labelSuffixEn: suffixEn
            )
        }
        result += exactDefinition(
            root.appendingPathComponent("home/Library/Caches/Claude", isDirectory: true).path,
            labelZh: "沙箱 Claude 缓存" + suffixZh,
            labelEn: "Sandbox Claude cache" + suffixEn,
            kindZh: "旧版系统缓存",
            kindEn: "Legacy system cache",
            scope: scope,
            owningRoot: root.path
        )
        result += prefixedEntries(
            parent: root.appendingPathComponent("home/Library/Caches", isDirectory: true).path,
            prefix: "com.anthropic.claudefordesktop",
            labelZh: "沙箱 Claude 系统缓存" + suffixZh,
            labelEn: "Sandbox Claude system cache" + suffixEn,
            kindZh: "系统应用缓存与更新缓存",
            kindEn: "System app and updater cache",
            scope: scope,
            owningRoot: root.path
        )
        result += exactDefinition(
            root.appendingPathComponent("home/Library/Logs/Claude", isDirectory: true).path,
            labelZh: "沙箱 Claude 日志" + suffixZh,
            labelEn: "Sandbox Claude logs" + suffixEn,
            kindZh: "运行与崩溃日志",
            kindEn: "Runtime and crash logs",
            scope: scope,
            owningRoot: root.path
        )
        result += codeDefinitions(
            root: home,
            scope: scope,
            owningRoot: root.path,
            labelSuffixZh: suffixZh,
            labelSuffixEn: suffixEn
        )
        result += scienceDefinitions(
            root: home,
            scope: scope,
            owningRoot: root.path,
            labelSuffixZh: suffixZh,
            labelSuffixEn: suffixEn
        )
        result += exactDefinition(
            root.appendingPathComponent("logs", isDirectory: true).path,
            labelZh: "沙箱会话日志" + suffixZh,
            labelEn: "Sandbox session logs" + suffixEn,
            kindZh: "启动、网络与 Science daemon 日志",
            kindEn: "Launch, network and Science daemon logs",
            scope: scope,
            owningRoot: root.path
        )
        for (prefix, labelZh, labelEn) in [
            ("claude-", "沙箱 Claude Code 临时文件", "Sandbox Claude Code temporary files"),
            ("Claude-", "沙箱 Claude Desktop 临时文件", "Sandbox Claude Desktop temporary files"),
        ] {
            result += prefixedEntries(
                parent: root.appendingPathComponent("tmp", isDirectory: true).path,
                prefix: prefix,
                labelZh: labelZh + suffixZh,
                labelEn: labelEn + suffixEn,
                kindZh: "会话内可再生成的临时数据",
                kindEn: "Regenerable session temporary data",
                scope: scope,
                owningRoot: root.path
            )
        }
        return result
    }

    private static func profileDefinitions(home: String, owningRoot: String) -> [Definition] {
        var result = desktopDefinitions(
            root: home + "/Library/Application Support/Claude",
            scope: .persistentProfile,
            owningRoot: owningRoot,
            labelSuffixZh: " · 持久登录",
            labelSuffixEn: " · persistent sign-in"
        )
        result += prefixedEntries(
            parent: home + "/Library/Caches",
            prefix: "com.anthropic.claudefordesktop",
            labelZh: "持久登录沙箱系统缓存",
            labelEn: "Persistent-profile sandbox system cache",
            kindZh: "系统应用缓存与更新缓存",
            kindEn: "System app and updater cache",
            scope: .persistentProfile,
            owningRoot: owningRoot
        )
        result += exactDefinition(
            home + "/Library/Logs/Claude",
            labelZh: "持久登录沙箱日志",
            labelEn: "Persistent-profile sandbox logs",
            kindZh: "运行与崩溃日志",
            kindEn: "Runtime and crash logs",
            scope: .persistentProfile,
            owningRoot: owningRoot
        )
        result += scienceDefinitions(
            root: home,
            scope: .persistentProfile,
            owningRoot: owningRoot,
            labelSuffixZh: " · 持久登录",
            labelSuffixEn: " · persistent sign-in"
        )
        return result
    }

    private static func desktopDefinitions(
        root: String,
        scope: CleanupScope,
        owningRoot: String?,
        labelSuffixZh: String,
        labelSuffixEn: String
    ) -> [Definition] {
        desktopCacheEntries.map { entry in
            Definition(
                path: root + "/" + entry.0,
                labelZh: "Claude 桌面版缓存" + labelSuffixZh,
                labelEn: "Claude desktop cache" + labelSuffixEn,
                kindZh: entry.1,
                kindEn: entry.2,
                scope: scope,
                owningRoot: owningRoot
            )
        }
    }

    private static func codeDefinitions(
        root: String,
        scope: CleanupScope,
        owningRoot: String?,
        labelSuffixZh: String,
        labelSuffixEn: String
    ) -> [Definition] {
        var result = codeCacheEntries.map { entry in
            Definition(
                path: root + "/.claude/" + entry.0,
                labelZh: "Claude Code 缓存" + labelSuffixZh,
                labelEn: "Claude Code cache" + labelSuffixEn,
                kindZh: entry.1,
                kindEn: entry.2,
                scope: scope,
                owningRoot: owningRoot
            )
        }
        result += exactDefinition(
            root + "/Library/Caches/claude-cli-nodejs",
            labelZh: "Claude Code 系统缓存" + labelSuffixZh,
            labelEn: "Claude Code system cache" + labelSuffixEn,
            kindZh: "CLI 系统缓存",
            kindEn: "CLI system cache",
            scope: scope,
            owningRoot: owningRoot
        )
        for path in [root + "/.cache/claude", root + "/.cache/anthropic"] {
            result += exactDefinition(
                path,
                labelZh: "Claude Code 用户缓存" + labelSuffixZh,
                labelEn: "Claude Code user cache" + labelSuffixEn,
                kindZh: "可重新生成的用户缓存",
                kindEn: "Regenerable user cache",
                scope: scope,
                owningRoot: owningRoot
            )
        }
        return result
    }

    private static func scienceDefinitions(
        root: String,
        scope: CleanupScope,
        owningRoot: String?,
        labelSuffixZh: String,
        labelSuffixEn: String
    ) -> [Definition] {
        var result = scienceCacheEntries.map { entry in
            Definition(
                path: root + "/.claude-science/" + entry.0,
                labelZh: "Claude Science 缓存" + labelSuffixZh,
                labelEn: "Claude Science cache" + labelSuffixEn,
                kindZh: entry.1,
                kindEn: entry.2,
                scope: scope,
                owningRoot: owningRoot
            )
        }
        result += exactDefinition(
            root + "/.cache/bun",
            labelZh: "Claude Science Bun 缓存" + labelSuffixZh,
            labelEn: "Claude Science Bun cache" + labelSuffixEn,
            kindZh: "运行时下载缓存",
            kindEn: "Runtime download cache",
            scope: scope,
            owningRoot: owningRoot
        )
        return result
    }

    private static func exactDefinition(
        _ path: String,
        labelZh: String,
        labelEn: String,
        kindZh: String,
        kindEn: String,
        scope: CleanupScope,
        owningRoot: String? = nil
    ) -> [Definition] {
        [Definition(
            path: path,
            labelZh: labelZh,
            labelEn: labelEn,
            kindZh: kindZh,
            kindEn: kindEn,
            scope: scope,
            owningRoot: owningRoot
        )]
    }

    private static func prefixedEntries(
        parent: String,
        prefix: String,
        labelZh: String,
        labelEn: String,
        kindZh: String,
        kindEn: String,
        scope: CleanupScope,
        owningRoot: String? = nil
    ) -> [Definition] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: parent, isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }
        return entries.compactMap { entry in
            guard entry.lastPathComponent.hasPrefix(prefix) else { return nil }
            return Definition(
                path: entry.path,
                labelZh: labelZh,
                labelEn: labelEn,
                kindZh: kindZh,
                kindEn: kindEn,
                scope: scope,
                owningRoot: owningRoot
            )
        }
    }

    private static func ownedSessionRoots(in sessionsRoot: URL, warnings: inout [String]) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }
        return entries.filter { entry in
            guard entry.deletingLastPathComponent().standardizedFileURL == sessionsRoot.standardizedFileURL else {
                warnings.append("已跳过路径边界异常的会话目录。")
                return false
            }
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                return false
            }
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                if values.isSymbolicLink == true {
                    warnings.append("已跳过符号链接形式的会话目录。")
                }
                return false
            }
            return ownsSession(entry)
        }
    }

    private static func unownedSessionRootCount(in sessionsRoot: URL) -> Int? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return nil
        }
        return entries.filter { entry in
            guard entry.deletingLastPathComponent().standardizedFileURL == sessionsRoot.standardizedFileURL,
                  let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return false
            }
            return !ownsSession(entry)
        }.count
    }

    private static func ownsSession(_ root: URL) -> Bool {
        isRegularFile(root.appendingPathComponent(".routekeeper-session", isDirectory: false))
    }

    private static func ownsProfile(_ home: URL) -> Bool {
        guard let values = try? home.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            return false
        }
        return isRegularFile(home.appendingPathComponent(".routekeeper-profile", isDirectory: false))
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeRegular
    }

    private static func measure(_ path: String) -> Measurement {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType else {
            return Measurement(exists: false, sizeBytes: 0, fileCount: 0, isSymbolicLink: false)
        }
        if type == .typeSymbolicLink {
            return Measurement(
                exists: true,
                sizeBytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                fileCount: 1,
                isSymbolicLink: true
            )
        }
        if type == .typeRegular {
            return Measurement(
                exists: true,
                sizeBytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                fileCount: 1,
                isSymbolicLink: false
            )
        }
        guard type == .typeDirectory else {
            return Measurement(exists: true, sizeBytes: 0, fileCount: 0, isSymbolicLink: false)
        }

        var size: Int64 = 0
        var count = 0
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return Measurement(exists: true, sizeBytes: 0, fileCount: 0, isSymbolicLink: false)
        }
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            ) else {
                continue
            }
            if values.isRegularFile == true || values.isSymbolicLink == true {
                size += Int64(values.fileSize ?? 0)
                count += 1
            }
        }
        return Measurement(exists: true, sizeBytes: size, fileCount: count, isSymbolicLink: false)
    }
}
