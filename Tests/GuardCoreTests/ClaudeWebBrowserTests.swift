import Foundation
import XCTest
@testable import GuardCore
@testable import Routekeeper

final class ClaudeWebBrowserTests: XCTestCase {
    func testLanguageAndTimezoneCanBeConfiguredIndependently() {
        let configuration = SandboxSharedConfiguration(
            timezoneIdentifier: "Asia/Tokyo",
            languageIdentifier: "en-US",
            upstream: IsolationUpstream(port: 7890)
        )
        let targetConfiguration = configuration.configuration(for: .claudeCode)

        XCTAssertEqual(targetConfiguration.timezoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(targetConfiguration.languageIdentifier, "en-US")
        XCTAssertEqual(
            IsolationSessionEnvironment.posixLocale(for: targetConfiguration.languageIdentifier),
            "en_US.UTF-8"
        )
    }

    func testPosixLocaleKeepsExplicitRegionsForLanguagesWithoutPresets() {
        XCTAssertEqual(
            IsolationSessionEnvironment.posixLocale(for: "es-MX"),
            "es_MX.UTF-8"
        )
        XCTAssertEqual(
            IsolationSessionEnvironment.posixLocale(for: "zh-Hant-HK"),
            "zh_HK.UTF-8"
        )
        XCTAssertEqual(
            IsolationSessionEnvironment.posixLocale(for: "pt-PT"),
            "pt_PT.UTF-8"
        )
    }

    func testLegacySharedConfigurationDerivesLanguageFromTimezone() throws {
        let json = """
        {
          "projectPath": "/tmp/project",
          "exchangePath": "/tmp/exchange",
          "timezoneIdentifier": "Asia/Tokyo",
          "upstream": {
            "host": "127.0.0.1",
            "port": 7890,
            "protocolType": "httpConnect",
            "username": "",
            "password": ""
          },
          "enabledTargets": ["claudeCode"],
          "persistClaudeLogin": false
        }
        """
        let configuration = try JSONDecoder().decode(
            SandboxSharedConfiguration.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(configuration.languageIdentifier, "ja-JP")
        XCTAssertTrue(configuration.hasValidLanguage)
    }

    func testChromeLaunchArgumentsKeepNativeSandboxAndApplyWebLanguage() {
        let profile = URL(fileURLWithPath: "/tmp/routekeeper-profile", isDirectory: true)
        let cache = URL(fileURLWithPath: "/tmp/routekeeper-cache", isDirectory: true)
        let downloads = URL(fileURLWithPath: "/tmp/routekeeper-downloads", isDirectory: true)

        let arguments = ClaudeWebBrowserController.launchArguments(
            languageIdentifier: "ja-JP",
            proxyURL: "socks5://127.0.0.1:43123",
            profileURL: profile,
            cacheURL: cache,
            downloadsURL: downloads
        )

        XCTAssertTrue(arguments.contains("--user-data-dir=\(profile.path)"))
        XCTAssertTrue(arguments.contains("--proxy-server=socks5://127.0.0.1:43123"))
        XCTAssertTrue(arguments.contains("--accept-lang=ja-JP,ja"))
        XCTAssertTrue(arguments.contains("--lang=ja-JP"))
        XCTAssertTrue(arguments.contains("--disable-quic"))
        XCTAssertFalse(arguments.contains("--no-sandbox"))
        XCTAssertEqual(arguments.last, "https://claude.ai/")
    }

    func testChromeEnvironmentUsesDedicatedHomeWithIndependentTimezoneAndLanguage() {
        let profileRoot = URL(fileURLWithPath: "/tmp/routekeeper-chrome", isDirectory: true)
        let environment = ClaudeWebBrowserController.launchEnvironment(
            languageIdentifier: "fr-FR",
            timezoneIdentifier: "America/Los_Angeles",
            profileRoot: profileRoot
        )

        XCTAssertEqual(environment["HOME"], profileRoot.appendingPathComponent("Home").path)
        XCTAssertEqual(environment["CFFIXED_USER_HOME"], environment["HOME"])
        XCTAssertEqual(environment["TZ"], "America/Los_Angeles")
        XCTAssertEqual(environment["LANG"], "fr_FR.UTF-8")
        XCTAssertEqual(environment["LANGUAGE"], "fr")
        XCTAssertEqual(environment["AppleLanguages"], "fr-FR")
    }

    func testInstalledGoogleChromePassesOfficialSignatureValidation() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app") else {
            throw XCTSkip("Google Chrome is not installed on this Mac.")
        }

        let installation = ClaudeWebBrowserDiscovery.locate()
        XCTAssertEqual(installation?.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(installation?.teamIdentifier, "EQHXZ8M8AV")
    }
}
