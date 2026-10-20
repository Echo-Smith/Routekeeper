import XCTest
@testable import GuardCore

final class IPv6EgressAuditTests: XCTestCase {
    private func probe(_ target: String = "api.anthropic.com",
                       kind: IPv6RouteKind,
                       reached: Bool = true) -> ClaudeIPv6Probe {
        .init(target: target, resolvedAddresses: ["2606:4700::1"], remoteAddress: "2606:4700::1",
              routeInterface: kind == .tunnel ? "utun4" : kind == .physical ? "en0" : nil,
              routeKind: kind, reachedTLS: reached, httpStatus: reached ? 404 : nil,
              tlsMilliseconds: reached ? 580 : nil, failure: reached ? nil : "timeout")
    }

    func testRouteClassification() {
        XCTAssertEqual(IPv6EgressAudit.routeKind("utun4"), .tunnel)
        XCTAssertEqual(IPv6EgressAudit.routeKind("en0"), .physical)
        XCTAssertEqual(IPv6EgressAudit.routeKind("pdp_ip0"), .physical)
        XCTAssertEqual(IPv6EgressAudit.routeKind("lo0"), .other)
        XCTAssertEqual(IPv6EgressAudit.routeKind(nil), .noRoute)
    }

    func testAAAAResolutionKeepsOnlyNormalizedIPv6Addresses() {
        let output = """
        claude.ai.
        2606:4700:10::6816:2b5b
        2606:4700:10::6816:2b5b
        not-an-ip
        1.2.3.4
        """
        XCTAssertEqual(
            IPv6EgressAudit.resolvedAddresses(from: output),
            ["2606:4700:10::6816:2b5b"]
        )
    }

    func testDirectIPv6ExposureIsDetected() {
        XCTAssertEqual(
            IPv6EgressAudit.exposureState(
                localAddress: "2001:db8::10",
                probes: [probe(kind: .physical)],
                systemPublicExit: "2001:db8::20",
                proxyPublicExit: nil
            ),
            .directExposure
        )
    }

    func testTunneledIPv6NeedsMatchingSystemAndProxyExits() {
        XCTAssertEqual(
            IPv6EgressAudit.exposureState(
                localAddress: "2001:db8::10",
                probes: [probe(kind: .tunnel)],
                systemPublicExit: "2001:db8::20",
                proxyPublicExit: "2001:db8::20"
            ),
            .tunneled
        )
        XCTAssertEqual(
            IPv6EgressAudit.exposureState(
                localAddress: "2001:db8::10",
                probes: [probe(kind: .tunnel)],
                systemPublicExit: "2001:db8::20",
                proxyPublicExit: nil
            ),
            .tunnelUnconfirmed
        )
        XCTAssertEqual(
            IPv6EgressAudit.exposureState(
                localAddress: "2001:db8::10",
                probes: [probe(kind: .tunnel)],
                systemPublicExit: "2001:db8::20",
                proxyPublicExit: "2001:db8::30"
            ),
            .tunnelExitMismatch
        )
    }

    func testNoIPv6ClaudePathAndDisabledStates() {
        XCTAssertEqual(
            IPv6EgressAudit.exposureState(
                localAddress: "2001:db8::10",
                probes: [probe(kind: .noRoute, reached: false)],
                systemPublicExit: nil,
                proxyPublicExit: nil
            ),
            .noClaudePath
        )
        XCTAssertEqual(
            IPv6EgressAudit.exposureState(
                localAddress: nil,
                probes: [probe(kind: .physical)],
                systemPublicExit: "2001:db8::20",
                proxyPublicExit: nil
            ),
            .disabled
        )
    }

    func testDirectExposureRaisesAssessmentAttention() {
        let family = EgressFamilyObservation(
            family: .ipv4, directIP: "1.2.3.4", proxiedIP: "1.2.3.4", targetIP: "1.2.3.4"
        )
        let ipv6 = IPv6EgressReport(
            localAddress: "2001:db8::10",
            systemPublicExit: "2001:db8::20",
            proxyPublicExit: nil,
            probes: [probe(kind: .physical)],
            state: .directExposure
        )
        let assessment = EgressAudit.assess(
            families: [family], services: [], intelligence: [],
            intelligenceStatus: .disabled, ipv6: ipv6
        )
        XCTAssertEqual(assessment.level, .attention)
        XCTAssertTrue(assessment.findings.contains(.ipv6DirectExposure))
    }
}
