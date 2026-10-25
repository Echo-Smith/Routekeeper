import XCTest
@testable import GuardCore

final class GuardCoreTests: XCTestCase {
    func testIPValidationAndNormalization() {
        XCTAssertEqual(IPAddress.normalized(" 1.2.3.4\n"), "1.2.3.4")
        XCTAssertEqual(IPAddress.normalized("2001:0db8:0:0:0:0:0:1"), "2001:db8::1")
        for input in ["", "example.com", "1.2.3.999", "https://1.2.3.4", "1.2.3.4;whoami", "1.2.3.4/24"] { XCTAssertNil(IPAddress.normalized(input)) }
    }
    func testCleanerSafePathsExcludeUserData() {
        let paths = CacheCleaner.safePaths(home: "/Users/test").map { $0.path }
        XCTAssertTrue(paths.contains("/Users/test/Library/Caches/Claude"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Logs/Claude"))
        XCTAssertTrue(paths.contains("/Users/test/.claude/statsig"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Application Support/Claude/Cache"))
        XCTAssertTrue(paths.contains("/Users/test/.claude-science/logs"))
        let forbidden = [
            "/projects/", "/sessions/", "settings.json", "credentials", ".oauth",
            "HTTPStorages", "IndexedDB", "Local Storage", "Session Storage",
            "WebStorage", "Cookies", "operon-cli.db", "encryption.key",
        ]
        XCTAssertFalse(paths.contains { path in forbidden.contains { path.contains($0) } })
        XCTAssertFalse(paths.contains("/Users/test/Library/Application Support/Claude"))
    }
    func testCleanerScanMissingPathIsZero() {
        let home = NSTemporaryDirectory() + "cleaner-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let plan = CacheCleaner.scan(home: home)
        XCTAssertEqual(plan.availableCount, 0)
        XCTAssertEqual(plan.totalBytes, 0)
    }
    func testCleanerScanMeasuresKnownCache() {
        let home = NSTemporaryDirectory() + "cleaner-\(UUID().uuidString)"
        let cache = home + "/Library/Caches/Claude"
        try? FileManager.default.createDirectory(atPath: cache, withIntermediateDirectories: true)
        try? Data("hello".utf8).write(to: URL(fileURLWithPath: cache + "/x"))
        defer { try? FileManager.default.removeItem(atPath: home) }
        let plan = CacheCleaner.scan(home: home)
        XCTAssertEqual(plan.availableCount, 1)
        XCTAssertEqual(plan.totalBytes, 5)
        XCTAssertEqual(plan.totalFiles, 1)
    }
    func testCleanerScansOnlyMarkerOwnedSessionsAndProfiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cleaner-owned-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let sessions = root.appendingPathComponent("Isolation", isDirectory: true)
        let profiles = root.appendingPathComponent("Profiles", isDirectory: true)
        let current = sessions.appendingPathComponent("CURRENT-\(UUID().uuidString)", isDirectory: true)
        let past = sessions.appendingPathComponent("PAST-\(UUID().uuidString)", isDirectory: true)
        let unowned = sessions.appendingPathComponent("UNOWNED-\(UUID().uuidString)", isDirectory: true)
        let profile = profiles.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        let chrome = profiles.appendingPathComponent("ClaudeWeb", isDirectory: true)
        let fm = FileManager.default

        for session in [current, past] {
            try fm.createDirectory(at: session, withIntermediateDirectories: true)
            try Data("owned\n".utf8).write(to: session.appendingPathComponent(".routekeeper-session"))
            let cache = session.appendingPathComponent("home/Library/Caches/com.anthropic.claudefordesktop", isDirectory: true)
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("1234567".utf8).write(to: cache.appendingPathComponent("cache.bin"))
        }
        try fm.createDirectory(at: unowned, withIntermediateDirectories: true)
        let unownedCache = unowned.appendingPathComponent("home/Library/Caches/Claude", isDirectory: true)
        try fm.createDirectory(at: unownedCache, withIntermediateDirectories: true)
        try Data("must-stay".utf8).write(to: unownedCache.appendingPathComponent("x"))

        try fm.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("owned\n".utf8).write(to: profile.appendingPathComponent(".routekeeper-profile"))
        let profileCache = profile.appendingPathComponent("Library/Application Support/Claude/GPUCache", isDirectory: true)
        try fm.createDirectory(at: profileCache, withIntermediateDirectories: true)
        try Data("profile".utf8).write(to: profileCache.appendingPathComponent("gpu.bin"))
        try fm.createDirectory(at: chrome, withIntermediateDirectories: true)
        try Data("owned\n".utf8).write(to: chrome.appendingPathComponent(".routekeeper-profile"))
        try Data("chrome-profile".utf8).write(
            to: chrome.appendingPathComponent("ChromeProfileData")
        )

        let plan = CacheCleaner.scan(
            home: home.path,
            sessionsRoot: sessions,
            profilesRoot: profiles,
            currentSessionRoot: current
        )
        XCTAssertTrue(plan.targets.contains { $0.scope == .currentSession && $0.path.hasPrefix(current.path) && $0.sizeBytes == 7 })
        XCTAssertTrue(plan.targets.contains { $0.scope == .pastSession && $0.path.hasPrefix(past.path) && $0.sizeBytes == 7 })
        XCTAssertTrue(plan.targets.contains { $0.scope == .persistentProfile && $0.path.hasPrefix(profile.path) && $0.sizeBytes == 7 })
        XCTAssertTrue(plan.targets.contains { $0.scope == .chromeProfile && $0.path == chrome.path })
        XCTAssertFalse(plan.targets.contains { $0.path.hasPrefix(unowned.path) })
        XCTAssertTrue(plan.warnings.contains { $0.contains("没有 Routekeeper 会话标记") })
    }
    func testCleanerRejectsUnownedProfileAndSymlinkTarget() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cleaner-symlink-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let sessions = root.appendingPathComponent("Isolation", isDirectory: true)
        let profiles = root.appendingPathComponent("Profiles", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        let profile = profiles.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        let profileCache = profile.appendingPathComponent("Library/Application Support/Claude/GPUCache", isDirectory: true)
        try fm.createDirectory(at: profileCache, withIntermediateDirectories: true)
        try Data("unowned".utf8).write(to: profileCache.appendingPathComponent("x"))

        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("outside-data".utf8).write(to: outside.appendingPathComponent("keep"))
        let cache = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: cache.appendingPathComponent("Claude", isDirectory: true),
            withDestinationURL: outside
        )

        let plan = CacheCleaner.scan(home: home.path, sessionsRoot: sessions, profilesRoot: profiles)
        let symlink = try XCTUnwrap(plan.targets.first {
            $0.path == cache.appendingPathComponent("Claude").path
        })
        XCTAssertEqual(symlink.blockedReason, .symbolicLink)
        XCTAssertFalse(symlink.isSelectable)
        XCTAssertFalse(plan.targets.contains { $0.scope == .persistentProfile })
        XCTAssertTrue(plan.warnings.contains { $0.contains("持久登录目录存在但没有 Routekeeper 标记") })
    }
    func testCleanerLiveSafetyIsScopedAndFailsClosed() {
        let session = "/tmp/routekeeper-session"
        let profile = "/tmp/routekeeper-profile"
        let desktop = CleanupTarget(
            path: "/tmp/desktop", labelZh: "d", labelEn: "d",
            kindZh: "c", kindEn: "c", scope: .hostDesktop,
            fileCount: 1, exists: true
        )
        let code = CleanupTarget(
            path: "/tmp/code", labelZh: "c", labelEn: "c",
            kindZh: "c", kindEn: "c", scope: .hostCode,
            fileCount: 1, exists: true
        )
        let science = CleanupTarget(
            path: "/tmp/science", labelZh: "s", labelEn: "s",
            kindZh: "c", kindEn: "c", scope: .hostScience,
            fileCount: 1, exists: true
        )
        let sandbox = CleanupTarget(
            path: session + "/cache", labelZh: "s", labelEn: "s",
            kindZh: "c", kindEn: "c", scope: .pastSession,
            fileCount: 1, exists: true, owningRoot: session
        )
        let saved = CleanupTarget(
            path: profile + "/cache", labelZh: "p", labelEn: "p",
            kindZh: "c", kindEn: "c", scope: .persistentProfile,
            fileCount: 1, exists: true, owningRoot: profile
        )
        let safety = CleanupSafetyContext(
            processInspectionAvailable: true,
            desktopRunning: true,
            codeRunning: true,
            scienceRunning: true,
            runningSessionRoots: [session],
            runningSessionProfiles: [profile]
        )
        XCTAssertEqual(CacheCleaner.blocker(for: desktop, safety: safety), .processRunning)
        XCTAssertEqual(CacheCleaner.blocker(for: code, safety: safety), .processRunning)
        XCTAssertEqual(CacheCleaner.blocker(for: science, safety: safety), .processRunning)
        XCTAssertEqual(CacheCleaner.blocker(for: sandbox, safety: safety), .sessionRunning)
        XCTAssertEqual(CacheCleaner.blocker(for: saved, safety: safety), .profileInUse)

        let unavailable = CleanupSafetyContext(processInspectionAvailable: false)
        XCTAssertEqual(CacheCleaner.blocker(for: desktop, safety: unavailable), .processInspectionUnavailable)
        XCTAssertEqual(CacheCleaner.blocker(for: sandbox, safety: unavailable), .processInspectionUnavailable)
    }

    func testChromeProfileCleanupIsBlockedWhileDedicatedBrowserRuns() {
        let profile = CleanupTarget(
            path: "/tmp/Routekeeper/Profiles/ClaudeWeb",
            labelZh: "Chrome",
            labelEn: "Chrome",
            kindZh: "profile",
            kindEn: "profile",
            scope: .chromeProfile,
            owningRoot: "/tmp/Routekeeper/Profiles/ClaudeWeb"
        )
        let running = CleanupSafetyContext(
            processInspectionAvailable: true,
            chromeProfileRunning: true
        )
        XCTAssertEqual(CacheCleaner.blocker(for: profile, safety: running), .browserRunning)

        let unavailable = CleanupSafetyContext(
            processInspectionAvailable: true,
            chromeProfileInspectionAvailable: false
        )
        XCTAssertEqual(
            CacheCleaner.blocker(for: profile, safety: unavailable),
            .processInspectionUnavailable
        )
        XCTAssertNil(
            CacheCleaner.blocker(
                for: profile,
                safety: CleanupSafetyContext(processInspectionAvailable: true)
            )
        )
    }

    func testCleanerDetectsRecordedRunningSession() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cleaner-running-\(UUID().uuidString)", isDirectory: true)
        let control = root.appendingPathComponent("control", isDirectory: true)
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 5", root.path]
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        let started = Command.run(
            "/bin/ps",
            ["-p", String(process.processIdentifier), "-o", "lstart="],
            timeout: 2
        )
        XCTAssertEqual(started.status, 0)
        try Data("\(process.processIdentifier)\n".utf8)
            .write(to: control.appendingPathComponent("sandbox.pid"))
        try Data((started.output + "\n").utf8)
            .write(to: control.appendingPathComponent("sandbox.started"))
        XCTAssertTrue(CacheCleaner.sessionIsRunning(root))
    }
    func testCommandDrainsOutputLargerThanPipeBuffer() {
        let result = Command.run(
            "/bin/sh",
            ["-c", "/usr/bin/yes routekeeper-output | /usr/bin/head -c 262144"],
            timeout: 2
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.output.utf8.count, 60_000)
        XCTAssertTrue(result.output.hasPrefix("routekeeper-output"))
    }
    func testCommandCanRaiseOutputLimitForProcessInventory() {
        let result = Command.run(
            "/bin/sh",
            ["-c", "/usr/bin/yes routekeeper-process | /usr/bin/head -c 262144"],
            timeout: 2,
            outputLimit: 1_000_000
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.output.utf8.count, 200_000)
        XCTAssertTrue(result.output.hasPrefix("routekeeper-process"))
    }
    func testTunnelRequiresTwoMatchingRoutes() {
        XCTAssertEqual(RouteEvidence.interface(from: "destination: default\n  interface: utun4\n flags: UP"), "utun4")
        XCTAssertEqual(RouteEvidence.sameTunnel(["utun4", "utun4"]), "utun4")
        for routes: [String?] in [["utun4"], ["utun4", nil], ["utun4", "en0"], ["utun4", "utun5"], ["en0", "en0"], ["utunbogus", "utunbogus"]] { XCTAssertNil(RouteEvidence.sameTunnel(routes)) }
    }
    func testCodeRecognitionRejectsPromptAndOtherNodePrograms() {
        let node = "/opt/homebrew/bin/node"
        let script = "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        XCTAssertEqual(ProcessClassifier.classify(executable: node, arguments: [node, script], desktopRoots: [], home: "/Users/test"), .code)
        XCTAssertNil(ProcessClassifier.classify(executable: node, arguments: [node, "/tmp/server.js", script], desktopRoots: [], home: "/Users/test"))
        XCTAssertNil(ProcessClassifier.classify(executable: "/bin/zsh", arguments: ["zsh", script], desktopRoots: [], home: "/Users/test"))
        XCTAssertNil(ProcessClassifier.classify(executable: node, arguments: [node, "--eval", script], desktopRoots: [], home: "/Users/test"))
        XCTAssertEqual(ProcessClassifier.classify(executable: "/Users/test/.local/share/claude/versions/2.1.0", arguments: [], desktopRoots: [], home: "/Users/test"), .code)
        XCTAssertNil(ProcessClassifier.classify(executable: "/Users/other/.local/share/claude/versions/2.1.0", arguments: [], desktopRoots: [], home: "/Users/test"))
    }
    func testDesktopPathBoundary() {
        XCTAssertEqual(ProcessClassifier.classify(executable: "/Applications/Claude.app/Contents/MacOS/Claude", arguments: [], desktopRoots: ["/Applications/Claude.app"], home: "/Users/test"), .desktop)
        XCTAssertNil(ProcessClassifier.classify(executable: "/Applications/Claude.app.evil/Contents/MacOS/Claude", arguments: [], desktopRoots: ["/Applications/Claude.app"], home: "/Users/test"))
    }
    func testEditorExtensionOnlyMatchesClaudeBinary() {
        let root = "/Users/test/.vscode/extensions/anthropic.claude-code-2.1.301-darwin-arm64/"
        XCTAssertEqual(ProcessClassifier.classify(executable: root + "resources/native-binary/claude", arguments: [], desktopRoots: [], home: "/Users/test"), .code)
        XCTAssertNil(ProcessClassifier.classify(executable: root + "other/claude", arguments: [], desktopRoots: [], home: "/Users/test"))
        XCTAssertNil(ProcessClassifier.classify(executable: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", arguments: [], desktopRoots: [], home: "/Users/test"))
    }
    func testNoSignalAcrossPIDReuseUserOrScope() {
        var settings = GuardSettings()
        let record = ProcessIdentity(pid: 123, uid: 501, startSeconds: 100, startMicroseconds: 4, executable: "/native/claude", kind: .code)
        XCTAssertTrue(ProcessClassifier.mayTerminate(record: record, current: record, settings: settings, uid: 501))
        var reused = record; reused.startSeconds += 1
        XCTAssertFalse(ProcessClassifier.mayTerminate(record: record, current: reused, settings: settings, uid: 501))
        XCTAssertFalse(ProcessClassifier.mayTerminate(record: record, current: nil, settings: settings, uid: 501))
        XCTAssertFalse(ProcessClassifier.mayTerminate(record: record, current: record, settings: settings, uid: 502))
        settings.protectCode = false
        XCTAssertFalse(ProcessClassifier.mayTerminate(record: record, current: record, settings: settings, uid: 501))
    }
    private func snapshot(_ settings: GuardSettings, passed: Bool = true) -> DiagnosticSnapshot {
        .init(settings: settings, checks: [.init("network", "网络", "test", passed ? .passed : .failed)], proxyIP: "1.2.3.4", tunnelIP: "1.2.3.4", processes: [], desktopPath: nil, codePaths: [])
    }
    func testIncidentDoesNotAutomaticallyRearm() {
        var settings = GuardSettings(); settings.targetIP = "1.2.3.4"
        var policy = GuardPolicy()
        XCTAssertTrue(policy.arm(snapshot(settings), settings: settings))
        policy.observe(snapshot(settings, passed: false))
        XCTAssertEqual(policy.phase, .incident)
        policy.observe(snapshot(settings))
        XCTAssertEqual(policy.phase, .incident)
        policy.stop(); XCTAssertEqual(policy.phase, .idle)
        XCTAssertTrue(policy.arm(snapshot(settings), settings: settings))
    }
    func testFailedStaleAndMismatchedResultsCannotArm() {
        var settings = GuardSettings(); settings.targetIP = "1.2.3.4"
        var policy = GuardPolicy()
        XCTAssertFalse(policy.arm(snapshot(settings, passed: false), settings: settings))
        var stale = snapshot(settings); stale.checkedAt = Date().addingTimeInterval(-30)
        XCTAssertFalse(policy.arm(stale, settings: settings))
        var changed = settings; changed.protectCode = false
        XCTAssertFalse(policy.arm(snapshot(settings), settings: changed))
        settings.protectCode = false; settings.protectDesktop = false
        XCTAssertFalse(policy.arm(snapshot(settings), settings: settings))
    }
    func testBothExitsMustMatchTargetEvenIfRowsAreIncorrectlyGreen() {
        var settings = GuardSettings(); settings.targetIP = "1.2.3.4"
        var result = snapshot(settings)
        result.tunnelIP = "5.6.7.8"; XCTAssertFalse(result.ready)
        result.tunnelIP = nil; XCTAssertFalse(result.ready)
        result.tunnelIP = "1.2.3.4"; result.proxyIP = nil; XCTAssertFalse(result.ready)
        settings.targetIP = ""; XCTAssertFalse(snapshot(settings).ready)
    }
}
