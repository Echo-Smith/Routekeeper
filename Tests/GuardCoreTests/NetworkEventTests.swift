import XCTest
import GuardCore
@testable import Routekeeper

private func passedSnapshot(_ settings: GuardSettings) -> DiagnosticSnapshot {
    DiagnosticSnapshot(settings: settings, checks: [.init("network", "network", "test", .passed)], proxyIP: settings.targetIP, tunnelIP: settings.targetIP, processes: [], desktopPath: nil, codePaths: [])
}
private actor ProbeGate {
    var calls = 0
    var pending: [CheckedContinuation<Void, Never>] = []
    func run(_ settings: GuardSettings) async -> DiagnosticSnapshot {
        calls += 1
        await withCheckedContinuation { pending.append($0) }
        return passedSnapshot(settings)
    }
    func release() { if !pending.isEmpty { pending.removeFirst().resume() } }
    func count() -> Int { calls }
}

final class NetworkEventTests: XCTestCase {
    private func waitForCalls(_ n: Int, gate: ProbeGate) async throws {
        for _ in 0..<200 {
            if await gate.count() >= n { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Probe was not invoked")
    }
    @MainActor
    func testSleepDuringArmRejectsOldResultWithoutTouchingUserDefaults() async throws {
        let suite = "RoutekeeperTests.\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = GuardSettings(); settings.targetIP = "1.2.3.4"
        defaults.set(try JSONEncoder().encode(settings), forKey: "guard-settings-v1")
        let gate = ProbeGate()
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false, runDiagnostic: { await gate.run($0) })
        let start = Task { await store.start() }
        try await waitForCalls(1, gate: gate)
        store.environmentChanged("sleep", sleeping: true)
        await gate.release(); await start.value
        XCTAssertFalse(store.monitoring); XCTAssertNil(store.snapshot); XCTAssertEqual(store.policy.phase, .idle)
        store.stop()
    }
    @MainActor
    func testWakeRechecksButNeverAutomaticallyRearmsIncident() async throws {
        let suite = "RoutekeeperTests.\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = GuardSettings(); settings.targetIP = "1.2.3.4"; settings.pollInterval = 300
        defaults.set(try JSONEncoder().encode(settings), forKey: "guard-settings-v1")
        let gate = ProbeGate()
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false, runDiagnostic: { await gate.run($0) })
        let start = Task { await store.start() }
        try await waitForCalls(1, gate: gate); await gate.release(); await start.value
        XCTAssertTrue(store.monitoring); XCTAssertEqual(store.policy.phase, .armed)
        store.environmentChanged("sleep", sleeping: true)
        XCTAssertNil(store.snapshot); XCTAssertEqual(store.policy.phase, .incident)
        store.environmentChanged("DNS changed during sleep", sleeping: false)
        try await Task.sleep(for: .milliseconds(650))
        let sleepingCalls = await gate.count(); XCTAssertEqual(sleepingCalls, 1)
        store.environmentChanged("wake", sleeping: false, waking: true)
        try await waitForCalls(2, gate: gate); await gate.release()
        for _ in 0..<100 {
            if store.snapshot != nil { break }; try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(store.snapshot); XCTAssertEqual(store.policy.phase, .incident)
        XCTAssertTrue(store.monitoring); store.stop()
    }
    func testRunnerSerializesCancelledAndReplacementRounds() async throws {
        let gate = ProbeGate(); var settings = GuardSettings(); settings.targetIP = "1.2.3.4"
        let selected = settings
        let runner = DiagnosticRunner(operation: { await gate.run($0) })
        let first = Task { await runner.run(selected) }
        try await waitForCalls(1, gate: gate)
        first.cancel()
        let second = Task { await runner.run(selected) }
        try await Task.sleep(for: .milliseconds(50))
        let count = await gate.count(); XCTAssertEqual(count, 1)
        await gate.release(); _ = await first.value
        try await waitForCalls(2, gate: gate); await gate.release(); _ = await second.value
    }
}
