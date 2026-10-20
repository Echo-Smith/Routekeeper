import XCTest
@testable import GuardCore

final class LeakEgressAuditTests: XCTestCase {
    private func attempt(_ id: Int, family: IPFamily, total: Int,
                         reached: Bool = true) -> DualStackAttempt {
        let address = family == .ipv4 ? "1.2.3.4" : "2606:4700::1"
        return .init(
            id: id, reachedTLS: reached, remoteAddress: reached ? address : nil,
            family: reached ? family : nil, httpStatus: reached ? 404 : nil,
            connectMilliseconds: reached ? 10 : nil, tlsMilliseconds: reached ? 500 : nil,
            totalMilliseconds: reached ? total : nil, failure: reached ? nil : "timeout"
        )
    }

    func testDualStackParserPreservesFamilyAndTLSStatus() {
        let parsed = LeakEgressAudit.parseAttempt(
            "403\t0.010\t0.550\t0.700\t2606:4700::1",
            exitStatus: 0,
            id: 1
        )
        XCTAssertEqual(parsed.family, .ipv6)
        XCTAssertTrue(parsed.reachedTLS)
        XCTAssertEqual(parsed.httpStatus, 403)
        XCTAssertEqual(parsed.tlsMilliseconds, 550)
    }

    func testFallbackDetectsFamilySwitchFirstFailureAndSlowFirstAttempt() {
        let switched = LeakEgressAudit.evaluateFallback(
            target: "api.anthropic.com",
            attempts: [attempt(1, family: .ipv6, total: 1_200), attempt(2, family: .ipv4, total: 600)]
        )
        XCTAssertTrue(switched.switchedFamily)
        XCTAssertTrue(switched.fallbackSuspected)

        let failedThenSucceeded = LeakEgressAudit.evaluateFallback(
            target: "api.anthropic.com",
            attempts: [attempt(1, family: .ipv6, total: 1, reached: false),
                       attempt(2, family: .ipv4, total: 600)]
        )
        XCTAssertTrue(failedThenSucceeded.firstAttemptFailedThenSucceeded)
        XCTAssertTrue(failedThenSucceeded.fallbackSuspected)

        let slow = LeakEgressAudit.evaluateFallback(
            target: "api.anthropic.com",
            attempts: [attempt(1, family: .ipv4, total: 3_500), attempt(2, family: .ipv4, total: 600)]
        )
        XCTAssertTrue(slow.firstAttemptSlow)
        XCTAssertTrue(slow.fallbackSuspected)
    }

    func testStableDualStackPathDoesNotWarn() {
        let stable = LeakEgressAudit.evaluateFallback(
            target: "api.anthropic.com",
            attempts: [attempt(1, family: .ipv4, total: 650), attempt(2, family: .ipv4, total: 600)]
        )
        XCTAssertFalse(stable.fallbackSuspected)
    }

    func testLeakFindingsRaiseTheCorrectAssessmentSeverity() {
        let family = EgressFamilyObservation(
            family: .ipv4, directIP: "1.2.3.4", proxiedIP: "1.2.3.4", targetIP: "1.2.3.4"
        )
        let dnsFailure = LeakEgressReport(
            dns: .init(id: "dns", title: "DNS", detail: "outside tunnel", level: .failed),
            udpIPv4: nil, udpIPv6: nil, dualStack: nil
        )
        let attention = EgressAudit.assess(
            families: [family], services: [], intelligence: [],
            intelligenceStatus: .disabled, leaks: dnsFailure
        )
        XCTAssertEqual(attention.level, .attention)
        XCTAssertTrue(attention.findings.contains(.dnsPathLeakSuspected))

        let udpUnknown = LeakEgressReport(
            dns: nil,
            udpIPv4: .init(id: "udp-ipv4", title: "UDP · IPv4", detail: "timeout", level: .unknown),
            udpIPv6: nil, dualStack: nil
        )
        let insufficient = EgressAudit.assess(
            families: [family], services: [], intelligence: [],
            intelligenceStatus: .disabled, leaks: udpUnknown
        )
        XCTAssertEqual(insufficient.level, .insufficient)
        XCTAssertTrue(insufficient.findings.contains(.udpExitUnverified))
    }
}
