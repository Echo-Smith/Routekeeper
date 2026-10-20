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
        XCTAssertFalse(paths.contains { $0.contains("/projects/") || $0.contains("settings.json") || $0.contains("credentials") || $0.contains("Application Support") })
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
