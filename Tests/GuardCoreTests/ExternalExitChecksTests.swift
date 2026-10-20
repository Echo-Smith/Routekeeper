import XCTest
@testable import GuardCore

final class ExternalExitChecksTests: XCTestCase {
    func testIPInfoAndClaudeTraceParsersNormalizeReturnedAddresses() {
        XCTAssertEqual(
            ExternalExitChecks.parseIPInfo(#"{"ip":"203.0.113.13","country":"US"}"#),
            "203.0.113.13"
        )
        XCTAssertEqual(
            ExternalExitChecks.parseClaudeTrace("""
            fl=test
            ip=2001:db8::12
            loc=US
            """),
            "2001:db8::12"
        )
        XCTAssertNil(ExternalExitChecks.parseIPInfo("not-json"))
        XCTAssertNil(ExternalExitChecks.parseClaudeTrace("ip=not-an-ip"))
    }

    func testExternalRowsUseTheMatchingAddressFamilyTarget() {
        var settings = GuardSettings()
        settings.fixedIPv4TargetIP = "203.0.113.13"
        settings.fixedIPv6TargetIP = "2001:db8::12"

        let ipv4 = ExternalExitChecks.row(
            id: "ipinfo",
            title: "ipinfo.io",
            service: "ipinfo.io",
            probe: .init(ip: "203.0.113.13", failure: nil),
            settings: settings
        )
        let ipv6 = ExternalExitChecks.row(
            id: "trace",
            title: "Claude",
            service: "Claude",
            probe: .init(ip: "2001:db8::12", failure: nil),
            settings: settings
        )
        XCTAssertEqual(ipv4.level, .passed)
        XCTAssertEqual(ipv6.level, .passed)
    }

    func testExternalRowsFailForMissingOrMismatchedAddress() {
        var settings = GuardSettings()
        settings.fixedIPv4TargetIP = "1.2.3.4"
        let mismatch = ExternalExitChecks.row(
            id: "ipinfo",
            title: "ipinfo.io",
            service: "ipinfo.io",
            probe: .init(ip: "5.6.7.8", failure: nil),
            settings: settings
        )
        let missing = ExternalExitChecks.row(
            id: "trace",
            title: "Claude",
            service: "Claude",
            probe: .init(ip: nil, failure: "timeout"),
            settings: settings
        )
        XCTAssertEqual(mismatch.level, .failed)
        XCTAssertTrue(mismatch.detail.contains("1.2.3.4"))
        XCTAssertEqual(missing.level, .failed)
    }
}
