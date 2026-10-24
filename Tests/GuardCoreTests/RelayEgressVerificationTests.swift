import XCTest
@testable import GuardCore
@testable import Routekeeper

final class RelayEgressVerificationTests: XCTestCase {
    func testExactClaudeExitMatchesFixedTarget() {
        let report = RelayEgressVerification.evaluate(
            claudeExitIP: "203.0.113.7",
            relayIPv4ExitIP: "203.0.113.7",
            apiReachable: true,
            expectedExits: IsolationExpectedExits(ipv4: "203.0.113.7")
        )

        XCTAssertEqual(report.level, .verified)
        XCTAssertEqual(report.basis, .exact)
        XCTAssertTrue(report.isVerified)
    }

    func testDynamicClaudeIPv6UsesStableRelayIPv4Anchor() {
        let report = RelayEgressVerification.evaluate(
            claudeExitIP: "2606:4700:4700::1111",
            relayIPv4ExitIP: "203.0.113.7",
            apiReachable: true,
            expectedExits: IsolationExpectedExits(ipv4: "203.0.113.7")
        )

        XCTAssertEqual(report.level, .verified)
        XCTAssertEqual(report.basis, .relayIPv4Anchor)
    }

    func testMismatchIsWarningButStillProvidesEvidence() {
        let report = RelayEgressVerification.evaluate(
            claudeExitIP: "198.51.100.4",
            relayIPv4ExitIP: "198.51.100.4",
            apiReachable: true,
            expectedExits: IsolationExpectedExits(ipv4: "203.0.113.7")
        )

        XCTAssertEqual(report.level, .warning)
        XCTAssertNil(report.basis)
        XCTAssertEqual(report.claudeExitIP, "198.51.100.4")
        XCTAssertTrue(report.detail.contains("198.51.100.4"))
        XCTAssertTrue(report.detail.contains("203.0.113.7"))
    }

    func testMissingFixedExitIsWarning() {
        let report = RelayEgressVerification.evaluate(
            claudeExitIP: "203.0.113.7",
            relayIPv4ExitIP: "203.0.113.7",
            apiReachable: true,
            expectedExits: IsolationExpectedExits()
        )

        XCTAssertEqual(report.level, .warning)
        XCTAssertTrue(report.detail.contains("203.0.113.7"))
    }

    func testMissingClaudeExitIsWarning() {
        let report = RelayEgressVerification.evaluate(
            claudeExitIP: nil,
            relayIPv4ExitIP: nil,
            apiReachable: false,
            expectedExits: IsolationExpectedExits(ipv4: "203.0.113.7")
        )

        XCTAssertEqual(report.level, .warning)
        XCTAssertFalse(report.isVerified)
    }

    func testAnthropicAPIFailureKeepsMatchedExitAsWarning() {
        let report = RelayEgressVerification.evaluate(
            claudeExitIP: "203.0.113.7",
            relayIPv4ExitIP: "203.0.113.7",
            apiReachable: false,
            expectedExits: IsolationExpectedExits(ipv4: "203.0.113.7")
        )

        XCTAssertEqual(report.level, .warning)
        XCTAssertEqual(report.basis, .exact)
        XCTAssertTrue(report.detail.contains("api.anthropic.com"))
    }

    func testSOCKS5ProxyUsesRemoteHostnameResolution() {
        XCTAssertEqual(
            RelayEgressVerification.remoteResolvingProxyURL("socks5://127.0.0.1:43123"),
            "socks5h://127.0.0.1:43123"
        )
        XCTAssertEqual(
            RelayEgressVerification.remoteResolvingProxyURL("http://127.0.0.1:7890"),
            "http://127.0.0.1:7890"
        )
    }

    func testAPIReachabilityRequiresHTTPStatusAndTLSHandshake() {
        XCTAssertTrue(
            RelayEgressVerification.apiIsReachable(
                output: "403\t0.182",
                exitStatus: 0
            )
        )
        XCTAssertFalse(
            RelayEgressVerification.apiIsReachable(
                output: "000\t0.000",
                exitStatus: 28
            )
        )
    }

    func testLiveRelayProbeWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["ROUTEKEEPER_TEST_RELAY_EGRESS"] == "1" else {
            throw XCTSkip("Set ROUTEKEEPER_TEST_RELAY_EGRESS=1 to probe through the current local proxy.")
        }
        guard let proxy = SystemProxyDescriptor.current(), proxy.isLoopback else {
            throw XCTSkip("A loopback system proxy is required for the live relay probe.")
        }

        let relay = LocalRelay()
        defer { relay.stop() }
        _ = try relay.start(
            upstream: IsolationUpstream(
                host: proxy.host,
                port: proxy.port,
                protocolType: proxy.protocolType
            )
        )
        let proxyURL = try XCTUnwrap(relay.socks5URL())
        let report = await RelayEgressVerification.check(
            proxyURL: proxyURL,
            expectedExits: IsolationExpectedExits()
        )

        XCTAssertNotNil(report.claudeExitIP, report.detail)
        XCTAssertNotNil(report.relayIPv4ExitIP, report.detail)
    }
}
