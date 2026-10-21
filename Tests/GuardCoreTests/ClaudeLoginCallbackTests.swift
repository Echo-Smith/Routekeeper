import Foundation
import XCTest
@testable import GuardCore

final class ClaudeLoginCallbackTests: XCTestCase {
    private let firstToken = "firstToken_1234567890"
    private let secondToken = "secondToken_1234567890"

    func testConvertsOfficialHTTPSMagicLinkToDesktopCallback() throws {
        let link = "https://claude.ai/magic-link?anon_id=abc#\(firstToken):\(secondToken)"
        let callback = try ClaudeLoginCallback.parse(link)

        XCTAssertEqual(callback.kind, .magicLink)
        XCTAssertEqual(callback.host, "claude.ai")
        XCTAssertEqual(
            callback.callbackURL.absoluteString,
            "claude://claude.ai/magic-link?anon_id=abc#\(firstToken):\(secondToken)"
        )
    }

    func testAcceptsExistingDesktopMagicCallback() throws {
        let link = "claude://claude.com/magic-link#\(firstToken):\(secondToken)"
        let callback = try ClaudeLoginCallback.parse(link)

        XCTAssertEqual(callback.kind, .magicLink)
        XCTAssertEqual(callback.host, "claude.com")
        XCTAssertEqual(callback.callbackURL.absoluteString, link)
    }

    func testAcceptsSSOAndGoogleDesktopCallbacks() throws {
        let sso = try ClaudeLoginCallback.parse(
            "claude://claude.ai/sso-callback?code=abcdefghijklmnop&anon_id=abc"
        )
        XCTAssertEqual(sso.kind, .ssoCallback)

        let google = try ClaudeLoginCallback.parse(
            "https://claude.ai/google-auth?code=abcdefghijklmnop&hop_nonce=abc"
        )
        XCTAssertEqual(google.kind, .googleAuth)
        XCTAssertEqual(google.callbackURL.scheme, "claude")
    }

    func testRejectsUnsafeSchemesHostsAndPaths() {
        for link in [
            "http://claude.ai/magic-link#\(firstToken):\(secondToken)",
            "file://claude.ai/magic-link#\(firstToken):\(secondToken)",
            "https://claude.ai.evil.example/magic-link#\(firstToken):\(secondToken)",
            "https://claude.ai@evil.example/magic-link#\(firstToken):\(secondToken)",
            "https://claude.ai:443/magic-link#\(firstToken):\(secondToken)",
            "https://claude.ai/login#\(firstToken):\(secondToken)",
            "https://claude.ai/magic-link/extra#\(firstToken):\(secondToken)"
        ] {
            XCTAssertThrowsError(try ClaudeLoginCallback.parse(link))
        }
    }

    func testRejectsMalformedOrOversizedMagicFragments() {
        for link in [
            "https://claude.ai/magic-link",
            "https://claude.ai/magic-link#\(firstToken)",
            "https://claude.ai/magic-link#\(firstToken):\(secondToken):thirdToken",
            "https://claude.ai/magic-link#short:\(secondToken)",
            "https://claude.ai/magic-link#\(firstToken):has space",
            "https://claude.ai/magic-link#\(firstToken):second\nToken",
            "https://claude.ai/magic-link#\(firstToken):\(String(repeating: "a", count: 9_000))"
        ] {
            XCTAssertThrowsError(try ClaudeLoginCallback.parse(link))
        }
    }

    func testErrorsNeverEchoTheSensitiveInput() {
        let secret = "sensitiveToken_1234567890"
        do {
            _ = try ClaudeLoginCallback.parse(
                "https://evil.example/magic-link#\(secret):\(secondToken)"
            )
            XCTFail("Expected rejection")
        } catch {
            XCTAssertFalse(String(describing: error).contains(secret))
        }
    }
}
