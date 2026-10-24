import XCTest
@testable import Routekeeper

final class TerminationConfirmationTests: XCTestCase {
    func testEnabledSandboxRequiresOneConfirmation() {
        XCTAssertEqual(
            QuitConfirmationPlan.steps(monitoring: false, sandboxModeEnabled: true),
            [.sandbox]
        )
        XCTAssertEqual(
            QuitConfirmationPlan.steps(monitoring: true, sandboxModeEnabled: true),
            [.sandbox]
        )
    }

    func testMonitoringRequiresOneConfirmation() {
        XCTAssertEqual(
            QuitConfirmationPlan.steps(monitoring: true, sandboxModeEnabled: false),
            [.monitoring]
        )
    }

    func testOrdinaryQuitDoesNotShowConfirmation() {
        XCTAssertEqual(
            QuitConfirmationPlan.steps(monitoring: false, sandboxModeEnabled: false),
            []
        )
    }
}
