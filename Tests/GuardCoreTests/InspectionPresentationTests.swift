import XCTest
@testable import GuardCore
@testable import Routekeeper

final class InspectionPresentationTests: XCTestCase {
    func testNoSnapshotRequiresInitialCheck() {
        let state = resolve(hasSnapshot: false, snapshotReady: false)

        XCTAssertEqual(state.outcome, .notRun)
        XCTAssertNil(state.primaryIssue)
        XCTAssertEqual(state.primaryAction, .runFullCheck)
    }

    func testRunningTakesPriorityOverExistingEvidence() {
        let state = resolve(isRunning: true, hasSnapshot: true, snapshotReady: true)

        XCTAssertEqual(state.outcome, .running)
        XCTAssertNil(state.primaryIssue)
        XCTAssertNil(state.primaryAction)
    }

    func testGatewayIssueTakesPriorityAndUsesStagedAction() {
        let failed = resolve(
            hasSnapshot: true,
            snapshotReady: false,
            gatewayMode: .claudeOnly,
            gatewayStatus: .failed,
            checks: [CheckItem("dns", "DNS", "no evidence", .failed)]
        )
        XCTAssertEqual(failed.outcome, .attention)
        XCTAssertEqual(failed.primaryIssue, .gateway(.failed))
        XCTAssertEqual(failed.primaryAction, .gatewayBaseline)

        let nodeTest = resolve(
            hasSnapshot: true,
            snapshotReady: true,
            gatewayMode: .claudeOnly,
            gatewayStatus: .needsNodeFailureTest
        )
        XCTAssertEqual(nodeTest.primaryAction, .gatewayNodeFailureTest)

        let clientExitTest = resolve(
            hasSnapshot: true,
            snapshotReady: true,
            gatewayMode: .claudeOnly,
            gatewayStatus: .needsClientExitTest
        )
        XCTAssertEqual(clientExitTest.primaryAction, .gatewayClientExitTest)

        let recovery = resolve(
            hasSnapshot: true,
            snapshotReady: true,
            gatewayMode: .claudeOnly,
            gatewayStatus: .needsRecovery
        )
        XCTAssertEqual(recovery.primaryAction, .gatewayRecovery)
    }

    func testUnverifiedGatewayIsPendingNotFailed() {
        let state = resolve(
            hasSnapshot: true,
            snapshotReady: true,
            gatewayMode: .splitTraffic,
            gatewayStatus: .unverified
        )

        XCTAssertEqual(state.outcome, .attention)
        XCTAssertEqual(state.primaryIssue, .gateway(.unverified))
        XCTAssertEqual(state.primaryAction, .gatewayBaseline)
    }

    func testFailedCheckWinsOverUnknownCheck() {
        let state = resolve(
            hasSnapshot: true,
            snapshotReady: false,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            checks: [
                CheckItem("dns", "DNS", "unknown", .unknown),
                CheckItem("tun", "TUN", "failed", .failed)
            ]
        )

        XCTAssertEqual(state.outcome, .attention)
        XCTAssertEqual(state.primaryIssue, .check(id: "tun", level: .failed))
        XCTAssertEqual(state.primaryAction, .rerunFullCheck)
    }

    func testInsufficientAuditStaysIncompleteInsteadOfPassing() {
        let state = resolve(
            hasSnapshot: true,
            snapshotReady: true,
            hasAuditReport: true,
            auditLevel: .insufficient,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            checks: [CheckItem("dns", "DNS", "unknown", .unknown)]
        )

        XCTAssertEqual(state.outcome, .incomplete)
        XCTAssertEqual(state.primaryIssue, .assessment)
        XCTAssertNotEqual(state.outcome, .passed)
    }

    func testMissingAuditRemainsIncompleteAfterLocalPass() {
        let state = resolve(
            hasSnapshot: true,
            snapshotReady: true,
            hasAuditReport: false,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            checks: [CheckItem("dns", "DNS", "passed", .passed)]
        )

        XCTAssertEqual(state.outcome, .incomplete)
        XCTAssertEqual(state.primaryIssue, .assessment)
    }

    func testOnlyExplicitlyPassedChecksEnterPassedPartition() {
        let checks = [
            CheckItem("passed", "Passed", "", .passed),
            CheckItem("warning", "Warning", "", .warning),
            CheckItem("unknown", "Unknown", "", .unknown),
            CheckItem("failed", "Failed", "", .failed),
            CheckItem("boundary", "Boundary", "", .warning)
        ]

        XCTAssertEqual(
            InspectionPresentationResolver.passedChecks(from: checks).map(\.id),
            ["passed"]
        )
        XCTAssertEqual(
            Set(InspectionPresentationResolver.unresolvedChecks(from: checks).map(\.id)),
            Set(["warning", "unknown", "failed"])
        )
    }

    func testClearEvidenceProducesPassedState() {
        let state = resolve(
            hasSnapshot: true,
            snapshotReady: true,
            hasAuditReport: true,
            auditLevel: .clear,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            checks: [CheckItem("dns", "DNS", "passed", .passed)]
        )

        XCTAssertEqual(state.outcome, .passed)
        XCTAssertNil(state.primaryIssue)
        XCTAssertEqual(state.primaryAction, .rerunFullCheck)
    }

    private func resolve(
        isRunning: Bool = false,
        hasSnapshot: Bool = true,
        snapshotReady: Bool,
        hasAuditReport: Bool = true,
        auditLevel: EgressAssessmentLevel? = .clear,
        gatewayMode: GatewayProtectionMode = .off,
        gatewayStatus: GatewayVerificationStatus = .unverified,
        checks: [CheckItem] = []
    ) -> InspectionPresentationState {
        InspectionPresentationResolver.resolve(
            isRunning: isRunning,
            hasSnapshot: hasSnapshot,
            snapshotReady: snapshotReady,
            hasAuditReport: hasAuditReport,
            auditLevel: auditLevel,
            gatewayMode: gatewayMode,
            gatewayStatus: gatewayStatus,
            checks: checks
        )
    }
}
