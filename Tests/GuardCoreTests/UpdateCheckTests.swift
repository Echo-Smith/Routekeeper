import XCTest
@testable import GuardCore

final class UpdateCheckTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppUpdateCheck.isNewer("v0.3.13", than: "0.3.12"))
        XCTAssertTrue(AppUpdateCheck.isNewer("0.4", than: "0.3.99"))
        XCTAssertFalse(AppUpdateCheck.isNewer("0.3.12.0", than: "0.3.12"))
        XCTAssertFalse(AppUpdateCheck.isNewer("v0.3.11", than: "0.3.12"))
    }

    func testReleaseWithDMGReturnsAvailableUpdate() throws {
        let result = try AppUpdateCheck.evaluate(
            releaseData: releaseData(tag: "v0.3.13", includeDMG: true),
            currentVersion: "0.3.12"
        )

        guard case let .available(current, latest, packageURL, releaseURL) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(current, "0.3.12")
        XCTAssertEqual(latest, "0.3.13")
        XCTAssertEqual(packageURL.absoluteString, "https://example.com/Routekeeper-v0.3.13.dmg")
        XCTAssertEqual(releaseURL.absoluteString, "https://example.com/releases/v0.3.13")
    }

    func testSameReleaseReturnsUpToDate() throws {
        let result = try AppUpdateCheck.evaluate(
            releaseData: releaseData(tag: "v0.3.12", includeDMG: true),
            currentVersion: "0.3.12"
        )
        XCTAssertEqual(result, .upToDate(currentVersion: "0.3.12"))
    }

    func testReleaseWithoutDMGIsRejected() {
        XCTAssertThrowsError(
            try AppUpdateCheck.evaluate(
                releaseData: releaseData(tag: "v0.3.13", includeDMG: false),
                currentVersion: "0.3.12"
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateCheckError, .missingPackage)
        }
    }

    func testMalformedReleaseIsRejected() {
        XCTAssertThrowsError(
            try AppUpdateCheck.evaluate(
                releaseData: Data("{}".utf8),
                currentVersion: "0.3.12"
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateCheckError, .invalidResponse)
        }
    }

    private func releaseData(tag: String, includeDMG: Bool) -> Data {
        let dmg = includeDMG
            ? #"{"name":"Routekeeper-v0.3.13.dmg","browser_download_url":"https://example.com/Routekeeper-v0.3.13.dmg"}"#
            : #"{"name":"Routekeeper-v0.3.13.zip","browser_download_url":"https://example.com/Routekeeper-v0.3.13.zip"}"#
        return Data("""
        {
          "tag_name": "\(tag)",
          "html_url": "https://example.com/releases/\(tag)",
          "assets": [\(dmg)]
        }
        """.utf8)
    }
}
