import XCTest
@testable import GuardCore
@testable import Routekeeper

final class GatewayVerificationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func requiredPass(_ id: String) -> GatewayCheckResult {
        .init(id: id, title: id, detail: "passed", level: .passed)
    }

    func testGatewayEvidenceRequiresEveryFailClosedStageAndExpires() {
        var record = GatewayVerificationRecord(sessionID: UUID(), mode: .splitTraffic)
        record.baselineAt = start
        record.baselinePassed = true
        record.baselineChecks = [requiredPass("baseline")]

        XCTAssertEqual(record.status(at: start), .needsNodeFailureTest)
        record.invalidatedAt = start.addingTimeInterval(1)
        XCTAssertEqual(record.status(at: start.addingTimeInterval(1)), .needsNodeFailureTest)
        record.invalidatedAt = nil

        record.nodeFailureAt = start.addingTimeInterval(10)
        record.nodeFailureCheck = requiredPass("node")
        XCTAssertEqual(record.status(at: start.addingTimeInterval(20)), .needsClientExitTest)

        record.clientExitAt = start.addingTimeInterval(20)
        record.clientExitCheck = requiredPass("client")
        XCTAssertEqual(record.status(at: start.addingTimeInterval(30)), .needsRecovery)

        record.recoveredAt = start.addingTimeInterval(30)
        record.recoveryChecks = [requiredPass("recovery")]
        XCTAssertEqual(record.status(at: start.addingTimeInterval(40)), .verified)
        XCTAssertEqual(
            record.status(at: start.addingTimeInterval(16 * 60)),
            .expired
        )
    }

    func testMissingCurrentNetworkRecoveryEvidenceIsNotACompletedVerification() {
        var record = GatewayVerificationRecord(sessionID: UUID(), mode: .claudeOnly)
        record.baselineAt = start
        record.baselinePassed = true
        record.nodeFailureCheck = requiredPass("node")
        record.clientExitCheck = requiredPass("client")
        record.recoveredAt = start.addingTimeInterval(20)
        record.recoveryChecks = [
            .init(id: "recovery", title: "recovery", detail: "missing", level: .failed)
        ]

        XCTAssertEqual(record.status(at: start.addingTimeInterval(30)), .failed)
    }

    func testOptionalReferenceFailureDoesNotTurnBaselineIntoPass() {
        let passed = GatewayProbeReport(checks: [
            requiredPass("required"),
            .init(id: "optional", title: "optional", detail: "unknown", level: .unknown, required: false)
        ])
        let failed = GatewayProbeReport(checks: [
            .init(id: "required", title: "required", detail: "failed", level: .failed)
        ])
        XCTAssertTrue(passed.passed)
        XCTAssertFalse(failed.passed)
    }

    func testEvidenceFromAnotherModeOrNetworkInvalidationCannotPass() {
        var record = GatewayVerificationRecord(sessionID: UUID(), mode: .splitTraffic)
        record.baselineAt = start
        record.baselinePassed = true
        record.nodeFailureCheck = requiredPass("node")
        record.clientExitCheck = requiredPass("client")
        record.recoveredAt = start
        record.recoveryChecks = [requiredPass("recovery")]

        XCTAssertEqual(
            record.status(at: start, currentMode: .claudeOnly),
            .unverified
        )
        record.invalidatedAt = start.addingTimeInterval(1)
        record.invalidationReason = "network changed"
        XCTAssertEqual(record.status(at: start.addingTimeInterval(2)), .expired)
    }

    @MainActor
    func testControllerWalksTheRequiredStagesAndPersistsOnlyStructuredEvidence() async {
        let suite = "routekeeper-gateway-controller-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let report = GatewayProbeReport(checks: [requiredPass("baseline")])
        let blocked = requiredPass("blocked")
        let controller = GatewayVerificationController(
            defaults: defaults,
            invalidateLoadedEvidence: false,
            now: { [start] in start },
            baselineProbe: { report },
            blockedProbe: { blocked }
        )

        await controller.runBaseline(for: .splitTraffic)
        XCTAssertEqual(controller.status(for: .splitTraffic), .needsNodeFailureTest)
        controller.invalidate(reason: "node was disabled")
        XCTAssertEqual(controller.status(for: .splitTraffic), .needsNodeFailureTest)
        await controller.testNodeFailure(for: .splitTraffic)
        XCTAssertEqual(controller.status(for: .splitTraffic), .needsClientExitTest)
        controller.invalidate(reason: "proxy client exited")
        await controller.testClientExit(for: .splitTraffic)
        XCTAssertEqual(controller.status(for: .splitTraffic), .needsRecovery)
        await controller.completeRecovery(for: .splitTraffic)
        XCTAssertEqual(controller.status(for: .splitTraffic), .verified)

        let restored = GatewayVerificationController(
            defaults: defaults,
            invalidateLoadedEvidence: false,
            now: { [start] in start },
            baselineProbe: { report },
            blockedProbe: { blocked }
        )
        XCTAssertEqual(restored.record?.allChecks.count, 4)
        XCTAssertEqual(restored.status(for: .splitTraffic), .verified)

        let restarted = GatewayVerificationController(
            defaults: defaults,
            now: { [start] in start.addingTimeInterval(1) },
            baselineProbe: { report },
            blockedProbe: { blocked }
        )
        XCTAssertEqual(restarted.status(for: .splitTraffic), .expired)
    }

    @MainActor
    func testSelectedGatewayModeBlocksMonitoringWithoutFreshEvidence() async {
        actor Calls {
            private var value = 0
            func increment() { value += 1 }
            func count() -> Int { value }
        }
        let calls = Calls()
        let suite = "routekeeper-gateway-gate-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = GatewayVerificationController(
            defaults: defaults,
            invalidateLoadedEvidence: false,
            baselineProbe: { .init(checks: []) },
            blockedProbe: {
                .init(id: "blocked", title: "blocked", detail: "passed", level: .passed)
            }
        )
        let store = GuardStore(
            defaults: defaults,
            watchNetwork: false,
            notificationsEnabled: false,
            gatewayVerification: controller,
            runDiagnostic: { settings in
                await calls.increment()
                return DiagnosticSnapshot(
                    settings: settings,
                    checks: [],
                    proxyIP: "1.2.3.4",
                    tunnelIP: "1.2.3.4",
                    processes: [],
                    desktopPath: nil,
                    codePaths: []
                )
            }
        )
        store.settings.targetIP = "1.2.3.4"
        store.settings.gatewayProtectionMode = .splitTraffic
        await store.start()
        XCTAssertFalse(store.monitoring)
        let blockedCalls = await calls.count()
        XCTAssertEqual(blockedCalls, 0)

        var record = GatewayVerificationRecord(sessionID: UUID(), mode: .splitTraffic)
        record.baselineAt = Date()
        record.baselinePassed = true
        record.nodeFailureCheck = requiredPass("node")
        record.clientExitCheck = requiredPass("client")
        record.recoveredAt = Date()
        record.recoveryChecks = [requiredPass("recovery")]
        controller.record = record

        await store.start()
        XCTAssertTrue(store.monitoring)
        let allowedCalls = await calls.count()
        XCTAssertEqual(allowedCalls, 1)
        store.stop()
    }

    @MainActor
    func testSandboxCreationReportsGatewayWarningWithoutBlocking() async {
        let suite = "routekeeper-sandbox-gateway-gate-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-sandbox-gateway-\(UUID())", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }
        let controller = GatewayVerificationController(
            defaults: defaults,
            invalidateLoadedEvidence: false,
            now: { [start] in start },
            baselineProbe: { .init(checks: []) },
            blockedProbe: {
                .init(id: "blocked", title: "blocked", detail: "passed", level: .passed)
            }
        )
        let sandbox = SandboxCoordinator(
            preferences: defaults,
            sessionsRoot: temp.appendingPathComponent("Isolation", isDirectory: true)
        )
        sandbox.sharedConfiguration = SandboxSharedConfiguration(
            projectPath: temp.appendingPathComponent("Project").path,
            exchangePath: temp.appendingPathComponent("Exchange").path,
            timezoneIdentifier: "UTC",
            upstream: IsolationUpstream(port: 7890),
            enabledTargets: [.claudeDesktop]
        )
        let store = GuardStore(
            defaults: defaults,
            watchNetwork: false,
            notificationsEnabled: false,
            gatewayVerification: controller,
            sandbox: sandbox
        )
        store.settings.experimentalSandboxEnabled = true
        store.settings.gatewayProtectionMode = .claudeOnly
        store.settings.targetIP = "1.2.3.4"

        XCTAssertFalse(store.gatewayEvidenceReady)
        await store.prepareSandbox(target: .claudeDesktop)

        XCTAssertTrue(sandbox.desktopSession.message.contains("代理网关"))
        XCTAssertFalse(sandbox.desktopSession.message.contains("请先在“网络保护”中完成"))
        XCTAssertTrue(store.events.contains { $0.message.contains("代理网关检查尚未完成") })
    }
}
