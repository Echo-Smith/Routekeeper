import Foundation
import XCTest
@testable import GuardCore
@testable import Routekeeper

final class ClaudeWebBrowserTests: XCTestCase {
    func testLanguageAndTimezoneCanBeConfiguredIndependently() {
        XCTAssertEqual(
            IsolationSessionEnvironment.normalizedLanguageIdentifier("en-US"),
            "en-US"
        )
        XCTAssertNil(
            IsolationSessionEnvironment.normalizedLanguageIdentifier("en\u{2014}US")
        )
        let configuration = SandboxSharedConfiguration(
            timezoneIdentifier: "Asia/Tokyo",
            languageIdentifier: "en-US",
            upstream: IsolationUpstream(port: 7890)
        )
        let targetConfiguration = configuration.configuration(for: .claudeCode)

        XCTAssertEqual(targetConfiguration.timezoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(targetConfiguration.languageIdentifier, "en-US")
        XCTAssertTrue(configuration.hasValidLanguage)
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
        XCTAssertFalse(configuration.usesEgressRegionalDefaults)
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

    func testCleanExitMarkerPreservesChromeProfilePreferences() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-chrome-preferences-\(UUID())", isDirectory: true)
        let profile = root.appendingPathComponent("Claude", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let preferencesURL = profile.appendingPathComponent("Preferences")
        let original: [String: Any] = [
            "profile": [
                "exit_type": "Crashed",
                "name": "Claude"
            ],
            "keep_me": ["nested": true]
        ]
        try JSONSerialization.data(withJSONObject: original)
            .write(to: preferencesURL, options: .atomic)

        try ClaudeWebBrowserController.markProfileCleanlyExited(profileURL: root)

        let updated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: preferencesURL))
                as? [String: Any]
        )
        let updatedProfile = try XCTUnwrap(updated["profile"] as? [String: Any])
        XCTAssertEqual(updatedProfile["exit_type"] as? String, "Normal")
        XCTAssertEqual(updatedProfile["exited_cleanly"] as? Bool, true)
        XCTAssertEqual(updatedProfile["name"] as? String, "Claude")
        XCTAssertEqual((updated["keep_me"] as? [String: Bool])?["nested"], true)
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

    @MainActor
    func testReadySummaryRequiresDetectionAndAStoppedBrowser() {
        let profileRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-chrome-summary-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: profileRoot) }
        let controller = ClaudeWebBrowserController(profilesRoot: profileRoot, discover: false)

        XCTAssertFalse(controller.showsReadySummary)

        controller.discovering = false
        controller.installation = ClaudeWebBrowserInstallation(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            executableURL: URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            bundleIdentifier: ClaudeWebBrowserDiscovery.bundleIdentifier,
            displayName: "Google Chrome",
            signingIdentifier: ClaudeWebBrowserDiscovery.bundleIdentifier,
            teamIdentifier: ClaudeWebBrowserDiscovery.teamIdentifier,
            shortVersion: "156.0",
            bundleVersion: "8078.48"
        )

        XCTAssertTrue(controller.showsReadySummary)
        controller.phase = .running
        XCTAssertFalse(controller.showsReadySummary)
    }

    @MainActor
    func testSuccessfulChromeDiscoveryReplacesTransientVerificationMessage() async throws {
        guard FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app") else {
            throw XCTSkip("Google Chrome is not installed on this Mac.")
        }
        let profileRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-chrome-discovery-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: profileRoot) }
        let controller = ClaudeWebBrowserController(profilesRoot: profileRoot, discover: false)
        controller.phase = .stopped
        controller.message = "正在验证 Google Chrome 的官方签名与版本。"

        await controller.refreshInstallation()

        XCTAssertNotNil(controller.installation)
        XCTAssertEqual(
            controller.message,
            "Google Chrome 已就绪。Chrome 会使用独立配置和当前会话的语言、时区与代理。"
        )
    }

    @MainActor
    func testOwnedProfileRootAdoptsManagedDataWithoutChangingIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-profile-adoption-\(UUID())", isDirectory: true)
        let savedFile = root.appendingPathComponent("ChromeProfile/Claude/Cookies")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: savedFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("existing-cookie-data".utf8)
        try original.write(to: savedFile)

        XCTAssertTrue(try ClaudeWebBrowserController.ensureOwnedProfileRoot(at: root))
        XCTAssertEqual(try Data(contentsOf: savedFile), original)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".routekeeper-profile").path
            )
        )
        XCTAssertFalse(try ClaudeWebBrowserController.ensureOwnedProfileRoot(at: root))
    }

    @MainActor
    func testOwnedProfileRootRejectsUnknownTopLevelContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-profile-unknown-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: root.appendingPathComponent("user-data.txt"))

        XCTAssertThrowsError(try ClaudeWebBrowserController.ensureOwnedProfileRoot(at: root))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".routekeeper-profile").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("user-data.txt").path
            )
        )
    }
}
