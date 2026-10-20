import XCTest
@testable import GuardCore
@testable import Routekeeper

final class EgressAuditControllerTests: XCTestCase {
    private func report(ip: String, at time: Date,
                        level: EgressAssessmentLevel) -> EgressAuditReport {
        .init(
            auditedAt: time,
            snapshotTime: time,
            proxyConfigured: true,
            primaryIP: ip,
            families: [],
            services: [],
            intelligence: [],
            intelligenceStatus: .disabled,
            assessment: .init(level: level, findings: [])
        )
    }

    @MainActor
    func testReportsPersistAcrossRestartAndComparisonUsesPreviousRun() async {
        let suite = "routekeeper-egress-controller-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = report(ip: "1.2.3.4", at: start, level: .clear)
        let second = report(ip: "5.6.7.8", at: start.addingTimeInterval(60), level: .attention)
        let snapshots = DiagnosticSnapshot(
            settings: GuardSettings(), checks: [], proxyIP: nil, tunnelIP: nil,
            processes: [], desktopPath: nil, codePaths: []
        )

        actor Sequence {
            private var values: [EgressAuditReport]
            private var index = 0
            init(_ values: [EgressAuditReport]) { self.values = values }
            func next() -> EgressAuditReport {
                defer { index += 1 }
                return values[min(index, values.count - 1)]
            }
        }
        let sequence = Sequence([first, second])
        let controller = EgressAuditController(defaults: defaults) { _, _ in
            await sequence.next()
        }
        let firstResult = await controller.run(
            snapshot: snapshots, includeIntelligence: false, trigger: .manual
        )
        XCTAssertEqual(firstResult, first)
        XCTAssertEqual(controller.lastRunTrigger, .manual)

        let restored = EgressAuditController(defaults: defaults) { _, _ in first }
        XCTAssertEqual(restored.report, first)
        XCTAssertNil(restored.previousReport)

        let secondResult = await controller.run(
            snapshot: snapshots, includeIntelligence: false, trigger: .scheduled
        )
        XCTAssertEqual(secondResult, second)
        XCTAssertEqual(controller.previousReport, first)
        XCTAssertEqual(controller.lastRunTrigger, .scheduled)
        XCTAssertEqual(controller.comparison?.previousPrimaryExit, "1.2.3.4")
        XCTAssertEqual(controller.comparison?.currentPrimaryExit, "5.6.7.8")

        let restoredAgain = EgressAuditController(defaults: defaults) { _, _ in second }
        XCTAssertEqual(restoredAgain.report, second)
        XCTAssertEqual(restoredAgain.previousReport, first)
        XCTAssertEqual(restoredAgain.lastRunTrigger, .scheduled)

        restoredAgain.clearStoredResults()
        let cleared = EgressAuditController(defaults: defaults) { _, _ in second }
        XCTAssertNil(cleared.report)
        XCTAssertNil(cleared.previousReport)
        XCTAssertNil(cleared.lastRunTrigger)
    }
}
