import AppKit
import Foundation
import WebKit
import XCTest
@testable import GuardCore
@testable import Routekeeper

final class IsolationModelsTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var project: URL!
    private var exchange: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-isolation-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        project = home.appendingPathComponent("Projects/App", isDirectory: true)
        exchange = home.appendingPathComponent("Exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func configuration(
        project: URL? = nil,
        exchange: URL? = nil,
        timezone: String = "Asia/Shanghai",
        upstream: IsolationUpstream = IsolationUpstream(),
        target: IsolationApplicationTarget = .claudeCode,
        persistClaudeLogin: Bool = false
    ) -> IsolationConfiguration {
        .init(
            projectPath: (project ?? self.project).path,
            exchangePath: (exchange ?? self.exchange).path,
            timezoneIdentifier: timezone,
            upstream: upstream,
            target: target,
            persistClaudeLogin: persistClaudeLogin
        )
    }

    private func sessionRoot() -> URL {
        home.appendingPathComponent(
            "Library/Application Support/Routekeeper/Isolation/\(UUID().uuidString)",
            isDirectory: true
        )
    }

    func testValidatesExistingDirectoriesAndBuildsOwnedLayout() throws {
        let paths = try IsolationPathValidator.validate(
            configuration(),
            sessionRoot: sessionRoot(),
            home: home
        )
        XCTAssertEqual(try XCTUnwrap(paths.originalProject).resolvingSymlinksInPath(), project.resolvingSymlinksInPath())
        XCTAssertEqual(paths.exchange.resolvingSymlinksInPath(), exchange.resolvingSymlinksInPath())
        XCTAssertTrue(paths.layout.home.path.hasSuffix("/home"))
        XCTAssertTrue(paths.layout.workspace.path.hasSuffix("/workspace"))
    }

    func testRejectsOverlappingProjectAndExchange() throws {
        let nested = project.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(exchange: nested),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            XCTAssertEqual(error as? IsolationValidationError, .pathsOverlap)
        }
    }

    func testRejectsHomeRootAndNonDirectory() throws {
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(project: home),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            guard case .unsafePath(let value) = error as? IsolationValidationError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
            XCTAssertTrue(value.hasSuffix("/home"))
        }
        let file = project.appendingPathComponent("README.md")
        try Data("test".utf8).write(to: file)
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(project: file),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            guard case .notDirectory(let value) = error as? IsolationValidationError else {
                return XCTFail("Expected notDirectory, got \(error)")
            }
            XCTAssertTrue(value.hasSuffix("/home/Projects/App/README.md"))
        }
    }

    func testRejectsSessionRootOutsideApplicationSupportAndInputPathsInsideIt() throws {
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(),
            sessionRoot: home.appendingPathComponent("WrongPlace/Session", isDirectory: true),
            home: home
        )) { error in
            XCTAssertEqual(error as? IsolationValidationError, .sessionRootOutsideApplicationSupport)
        }

        let owned = sessionRoot()
        let ownedProject = owned.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: ownedProject, withIntermediateDirectories: true)
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(project: ownedProject),
            sessionRoot: owned,
            home: home
        ))
    }

    func testValidatesTimezoneAndLoopbackUpstream() {
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(timezone: "Mars/Olympus"),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            XCTAssertEqual(error as? IsolationValidationError, .invalidTimezone)
        }
        for upstream in [
            IsolationUpstream(host: "192.168.1.2", port: 7890),
            IsolationUpstream(host: "127.0.0.1", port: 0),
            IsolationUpstream(host: "127.0.0.1", port: 70000),
            IsolationUpstream(host: "127.0.0.1/path", port: 7890)
        ] {
            XCTAssertThrowsError(try IsolationPathValidator.validate(
                configuration(upstream: upstream),
                sessionRoot: sessionRoot(),
                home: home
            )) { error in
                XCTAssertEqual(error as? IsolationValidationError, .invalidUpstream)
            }
        }
        XCTAssertTrue(configuration(upstream: IsolationUpstream(host: "::1", port: 1080, protocolType: .socks5)).upstream.isValid)
    }

    func testDetectsAndMatchesSystemProxyWithoutGuessingWhenDisabled() {
        let detected = SystemProxyDescriptor.descriptor(from: [
            "HTTPSEnable": NSNumber(value: true),
            "HTTPSProxy": "localhost",
            "HTTPSPort": NSNumber(value: 7890),
            "HTTPEnable": NSNumber(value: true),
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": NSNumber(value: 10809)
        ])
        XCTAssertEqual(
            detected,
            .init(host: "localhost", port: 7890, protocolType: .httpConnect)
        )
        XCTAssertTrue(IsolationUpstream(host: "127.0.0.1", port: 7890, protocolType: .httpConnect).matches(detected))
        XCTAssertFalse(IsolationUpstream(host: "127.0.0.1", port: 10809, protocolType: .httpConnect).matches(detected))
        XCTAssertFalse(IsolationUpstream(host: "127.0.0.1", port: 7890, protocolType: .socks5).matches(detected))
        XCTAssertNil(SystemProxyDescriptor.descriptor(from: [
            "HTTPSEnable": NSNumber(value: false),
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": NSNumber(value: 7890)
        ]))
    }

    func testSessionLocaleAndSavedExitHelpersStayConsistent() {
        XCTAssertEqual(IsolationSessionEnvironment.localeIdentifier(for: "Asia/Tokyo"), "ja_JP.UTF-8")
        XCTAssertEqual(IsolationSessionEnvironment.localeIdentifier(for: "America/Los_Angeles"), "en_US.UTF-8")
        XCTAssertEqual(IsolationSessionEnvironment.languageIdentifier(forLocale: "zh_CN.UTF-8"), "zh")
        XCTAssertEqual(IsolationSessionEnvironment.appleLanguageIdentifier(forLocale: "zh_CN.UTF-8"), "zh-Hans")
        XCTAssertEqual(IsolationSessionEnvironment.appleLanguageIdentifier(forLocale: "zh_TW.UTF-8"), "zh-Hant")
        XCTAssertEqual(IsolationSessionEnvironment.appleLanguageIdentifier(forLocale: "en_US.UTF-8"), "en-US")

        let exits = IsolationExpectedExits(ipv4: "203.0.113.13", ipv6: "2001:db8::1")
        XCTAssertTrue(exits.hasAny)
        XCTAssertTrue(exits.contains("203.0.113.13"))
        XCTAssertTrue(exits.contains("2001:db8::1"))
        XCTAssertFalse(exits.contains("1.1.1.1"))
        XCTAssertFalse(IsolationExpectedExits().hasAny)
    }

    func testSandboxPreflightParsesIPv6ExitAndNewBoundaryChecks() {
        let output = """
        timezone=1
        session-locale=1
        home-write=1
        workspace-write=1
        exchange-write=1
        original-write=1
        control-read=1
        child-inherit=1
        direct-network=1
        direct-dns=1
        direct-udp=1
        relay-network=1
        direct-claude=1
        claude-relay=1
        claude-exit-ip=2001:db8::1
        claude-exit-match=1
        claude-exit-basis=exact
        loopback-listener=1
        external-app=1
        complete
        """
        let checks = SandboxSession.preflightChecks(output)
        XCTAssertTrue(checks.allSatisfy(\.passed))
        XCTAssertEqual(checks.first(where: { $0.id == "claude-exit-match" })?.detail, "Claude 路径返回 2001:db8::1，与已保存出口完全一致")
        XCTAssertTrue(checks.contains { $0.id == "loopback-listener" })
        XCTAssertTrue(checks.contains { $0.id == "external-app" })

        let mismatch = SandboxSession.preflightChecks(output.replacingOccurrences(of: "claude-exit-match=1", with: "claude-exit-match=0"))
        let mismatchCheck = mismatch.first(where: { $0.id == "claude-exit-match" })
        XCTAssertEqual(mismatchCheck?.passed, false)
        XCTAssertEqual(mismatchCheck?.isWarning, true)
        XCTAssertEqual(mismatchCheck?.blocksLaunch, false)
        XCTAssertEqual(
            mismatchCheck?.detail,
            "警告：Claude 路径返回 2001:db8::1，无法与已保存出口核对"
        )

        let hardFailure = SandboxSession.preflightChecks(
            output.replacingOccurrences(of: "direct-network=1", with: "direct-network=0")
        )
        let directNetwork = hardFailure.first(where: { $0.id == "direct-network" })
        XCTAssertEqual(directNetwork?.isWarning, false)
        XCTAssertEqual(directNetwork?.blocksLaunch, true)
    }

    func testSandboxPreflightAcceptsRotatingClaudeIPv6ThroughMatchingRelayIPv4Anchor() {
        let output = """
        timezone=1
        session-locale=1
        home-write=1
        workspace-write=1
        exchange-write=1
        original-project=0
        original-write=1
        control-read=1
        child-inherit=1
        direct-network=1
        direct-dns=1
        direct-udp=1
        relay-network=1
        direct-claude=1
        claude-relay=1
        relay-exit-ip=203.0.113.13
        claude-exit-ip=2001:db8::11
        claude-exit-match=1
        claude-exit-basis=relay-ipv4-anchor
        loopback-listener=1
        external-app=1
        complete
        """
        let checks = SandboxSession.preflightChecks(output, target: .claudeDesktop)
        let exitCheck = checks.first { $0.id == "claude-exit-match" }
        XCTAssertEqual(exitCheck?.passed, true)
        XCTAssertTrue(exitCheck?.detail.contains("节点轮换 IPv6") == true)
        XCTAssertTrue(exitCheck?.detail.contains("203.0.113.13") == true)

        let mismatch = SandboxSession.preflightChecks(
            output
                .replacingOccurrences(of: "claude-exit-match=1", with: "claude-exit-match=0")
                .replacingOccurrences(of: "claude-exit-basis=relay-ipv4-anchor",
                                      with: "claude-exit-basis=mismatch")
                .replacingOccurrences(of: "relay-exit-ip=203.0.113.13",
                                      with: "relay-exit-ip=198.51.100.9"),
            target: .claudeDesktop
        )
        let mismatchCheck = mismatch.first { $0.id == "claude-exit-match" }
        XCTAssertEqual(mismatchCheck?.passed, false)
        XCTAssertEqual(mismatchCheck?.isWarning, true)
        XCTAssertEqual(mismatchCheck?.blocksLaunch, false)
        XCTAssertTrue(mismatchCheck?.detail.contains("无法与已保存出口核对") == true)
        XCTAssertFalse(mismatchCheck?.detail.contains("完全一致") == true)
    }

    func testSandboxProfileOnlyWritesSessionWorkspaceExchangeAndLoopbackPort() throws {
        let paths = try IsolationPathValidator.validate(
            configuration(),
            sessionRoot: sessionRoot(),
            home: home
        )
        let profile = IsolationSandboxProfile.make(
            paths: paths,
            executableURL: URL(fileURLWithPath: "/usr/local/bin/claude"),
            relayPort: 43123
        )
        XCTAssertTrue(profile.contains("(deny default)"))
        XCTAssertTrue(profile.contains("(deny network*)"))
        XCTAssertTrue(profile.contains("(deny mach-lookup)"))
        XCTAssertTrue(profile.contains(paths.layout.workspace.path))
        XCTAssertTrue(profile.contains(paths.exchange.path))
        XCTAssertTrue(profile.contains("localhost:43123"))
        XCTAssertFalse(profile.contains("(allow network-outbound (remote ip \"*:"))
        XCTAssertFalse(profile.contains(#"(subpath "/Users")"#))
        XCTAssertFalse(profile.contains("workspace.sb\" injection"))
    }

    func testProfileEscapesQuotesAndBackslashesInPaths() throws {
        let weirdParent = root.appendingPathComponent(#"quote"folder\name"#, isDirectory: true)
        let weirdProject = weirdParent.appendingPathComponent("Project", isDirectory: true)
        let weirdExchange = weirdParent.appendingPathComponent("Exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: weirdProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: weirdExchange, withIntermediateDirectories: true)
        let paths = try IsolationPathValidator.validate(
            configuration(project: weirdProject, exchange: weirdExchange),
            sessionRoot: sessionRoot(),
            home: home
        )
        let profile = IsolationSandboxProfile.make(
            paths: paths,
            executableURL: URL(fileURLWithPath: "/usr/local/bin/claude"),
            relayPort: 43123
        )
        XCTAssertTrue(profile.contains(#"\""#))
        XCTAssertTrue(profile.contains(#"\\"#))
    }

    func testRelayTargetParsesAuthoritiesAndRejectsLocalDestinations() {
        XCTAssertEqual(RelayTarget(authority: "api.example.com:443"), .init(host: "api.example.com", port: 443))
        XCTAssertEqual(RelayTarget(authority: "[2001:4860:4860::8888]:443"), .init(host: "2001:4860:4860::8888", port: 443))
        for value in ["", "example.com", ":443", "example.com:0", "example.com:70000", "bare:abc"] {
            XCTAssertNil(RelayTarget(authority: value), value)
        }
        for value in [
            "localhost:443", "router.local:443", "127.0.0.1:443", "10.0.0.1:443",
            "172.20.1.1:443", "192.168.1.1:443", "169.254.1.1:443",
            "100.64.0.1:443", "[::1]:443", "[fd00::1]:443", "[fe80::1]:443"
        ] {
            XCTAssertTrue(RelayTarget(authority: value)?.blocksDirectLocalAccess == true, value)
        }
        XCTAssertFalse(RelayTarget(authority: "8.8.8.8:443")?.blocksDirectLocalAccess == true)
    }

    func testLegacyConfigurationMigratesToClaudeCodeTarget() throws {
        let json = """
        {
          "projectPath": "/tmp/project",
          "exchangePath": "/tmp/exchange",
          "timezoneIdentifier": "UTC",
          "upstream": {
            "host": "127.0.0.1",
            "port": 7890,
            "protocolType": "httpConnect",
            "username": "",
            "password": ""
          }
        }
        """
        let configuration = try JSONDecoder().decode(
            IsolationConfiguration.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(configuration.target, .claudeCode)
        XCTAssertFalse(configuration.persistClaudeLogin)
        XCTAssertEqual(IsolationApplicationTarget.claudeDesktop.title, "Claude Desktop")

        let encoded = try JSONEncoder().encode(configuration)
        let roundTrip = try JSONDecoder().decode(IsolationConfiguration.self, from: encoded)
        XCTAssertEqual(roundTrip.target, .claudeCode)
        XCTAssertFalse(roundTrip.persistClaudeLogin)
    }

    func testNetworkFingerprintTracksMaterialIdentityWithoutRetainingPassword() {
        let proxy = SystemProxyDescriptor(
            host: "localhost",
            port: 7890,
            protocolType: .httpConnect
        )
        let first = NetworkFingerprint(
            proxy: proxy,
            upstream: IsolationUpstream(username: "user", password: "secret-a"),
            upstreamReachable: true,
            exitAnchor: "203.0.113.13"
        )
        let rotated = NetworkFingerprint(
            proxy: proxy,
            upstream: IsolationUpstream(username: "user", password: "secret-a"),
            upstreamReachable: true,
            exitAnchor: "2001:db8::1"
        )
        let changedPassword = NetworkFingerprint(
            proxy: proxy,
            upstream: IsolationUpstream(username: "user", password: "secret-b"),
            upstreamReachable: true,
            exitAnchor: "203.0.113.13"
        )

        XCTAssertTrue(first.hasLiveRoute)
        XCTAssertTrue(first.materialConfigurationMatches(rotated))
        XCTAssertFalse(first.materialConfigurationMatches(changedPassword))
        XCTAssertNotEqual(first.authMarker, "anonymous")
        XCTAssertNotEqual(first.authMarker, changedPassword.authMarker)
        XCTAssertFalse(first.summary.contains("secret-a"))
        XCTAssertFalse(first.authMarker.contains("secret-a"))
    }

    func testInputMethodCompatibilityUsesOnlyReferencedApplicationBundles() throws {
        let inputRoot = root.appendingPathComponent("Input Methods", isDirectory: true)
        let enabledApp = inputRoot.appendingPathComponent("Enabled.app", isDirectory: true)
        let selectedApp = inputRoot.appendingPathComponent("Selected.app", isDirectory: true)
        let unreferencedApp = inputRoot.appendingPathComponent("Unreferenced.app", isDirectory: true)
        for app in [enabledApp, selectedApp, unreferencedApp] {
            try FileManager.default.createDirectory(
                at: app.appendingPathComponent("Contents", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "example.inputmethod.enabled"],
            format: .xml,
            options: 0
        ).write(to: enabledApp.appendingPathComponent("Contents/Info.plist"))
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "example.inputmethod.selected"],
            format: .xml,
            options: 0
        ).write(to: selectedApp.appendingPathComponent("Contents/Info.plist"))
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "example.inputmethod.unreferenced"],
            format: .xml,
            options: 0
        ).write(to: unreferencedApp.appendingPathComponent("Contents/Info.plist"))
        let escapedApp = root.appendingPathComponent("Outside/Escaped.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: escapedApp.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "example.inputmethod.escaped"],
            format: .xml,
            options: 0
        ).write(to: escapedApp.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createSymbolicLink(
            at: inputRoot.appendingPathComponent("Escaped.app", isDirectory: true),
            withDestinationURL: escapedApp
        )

        let suite = "routekeeper-input-method-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set([
            ["Bundle ID": "example.inputmethod.enabled", "InputSourceKind": "Input Mode"],
            ["Bundle ID": "example.inputmethod.escaped", "InputSourceKind": "Input Mode"]
        ], forKey: "AppleEnabledInputSources")
        preferences.set([
            ["Bundle ID": "example.inputmethod.selected", "InputSourceKind": "Input Mode"]
        ], forKey: "AppleSelectedInputSources")

        let applications = InputMethodCompatibility.enabledApplications(
            defaults: preferences,
            roots: [inputRoot]
        )
        XCTAssertEqual(applications.map(\.lastPathComponent), ["Enabled.app", "Selected.app"])
        XCTAssertEqual(
            InputMethodCompatibility.referencedBundleIdentifiers(
                in: preferences.dictionaryRepresentation()
            ),
            [
                "example.inputmethod.enabled",
                "example.inputmethod.escaped",
                "example.inputmethod.selected"
            ]
        )
    }

    func testDesktopSessionAllowsNoProjectButClaudeCodeDoesNot() throws {
        var desktop = configuration(target: .claudeDesktop)
        desktop.projectPath = ""
        XCTAssertTrue(desktop.hasRequiredPaths)

        let paths = try IsolationPathValidator.validate(
            desktop,
            sessionRoot: sessionRoot(),
            home: home
        )
        XCTAssertNil(paths.originalProject)
        XCTAssertEqual(paths.exchange.resolvingSymlinksInPath(), exchange.resolvingSymlinksInPath())

        var code = configuration(target: .claudeCode)
        code.projectPath = ""
        XCTAssertFalse(code.hasRequiredPaths)
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            code,
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            XCTAssertEqual(error as? IsolationValidationError, .missingProject)
        }
    }

    func testDesktopProfileKeepsNetworkBoundaryAndAddsGUIServices() throws {
        var configuration = configuration(target: .claudeDesktop)
        configuration.projectPath = ""
        let paths = try IsolationPathValidator.validate(
            configuration,
            sessionRoot: sessionRoot(),
            home: home
        )
        let profile = IsolationSandboxProfile.makeDesktop(
            paths: paths,
            applicationURL: URL(fileURLWithPath: "/Applications/Claude Science.app", isDirectory: true),
            relayPort: 43123,
            inputMethodApplications: [
                URL(fileURLWithPath: "/Library/Input Methods/WeType.app", isDirectory: true)
            ]
        )

        XCTAssertTrue(profile.contains("(deny network*)"))
        XCTAssertTrue(profile.contains("(allow mach-lookup)"))
        XCTAssertTrue(profile.contains(
            #"MachPortRendezvousServer\.[0-9]+$"#
        ))
        XCTAssertTrue(profile.contains(
            #"(global-name-prefix "org.chromium.crashpad.child_port_handshake.")"#
        ))
        XCTAssertTrue(profile.contains("(allow iokit-open)"))
        XCTAssertTrue(profile.contains("(allow network-outbound (remote ip \"localhost:43123\"))"))
        XCTAssertTrue(profile.contains(#"(allow network-outbound (remote ip "localhost:*"))"#))
        XCTAssertTrue(profile.contains(#"(regex #"^/private/tmp/op-mux-[^/]+(/|$)")"#))
        XCTAssertTrue(profile.contains(
            #"(allow network-bind network-inbound network-outbound (literal ""#
                + paths.layout.home
                    .appendingPathComponent(".claude-science/daemon.sock")
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                    .path
                + #""))"#
        ))
        XCTAssertTrue(profile.contains(#"(allow network-inbound (local ip "localhost:*"))"#))
        XCTAssertFalse(profile.contains("(allow network-outbound (remote ip \"*:"))
        XCTAssertFalse(profile.contains(#"(local ip "*:*")"#))
        XCTAssertFalse(profile.contains(#"(subpath "/Users")"#))
        XCTAssertTrue(profile.contains(
            #"(allow file-read* (subpath "/Library/Input Methods/WeType.app"))"#
        ))
        XCTAssertTrue(profile.contains(
            #"(allow file-map-executable (subpath "/Library/Input Methods/WeType.app"))"#
        ))
        XCTAssertFalse(profile.contains(#"(subpath "/Library")"#))
        XCTAssertFalse(profile.contains(#"(subpath "/Library/Input Methods")"#))
    }

    func testDesktopEnvironmentUsesIsolatedHomeAndProxyWithoutToken() {
        var configuration = configuration(target: .claudeDesktop)
        configuration.projectPath = ""
        let layout = IsolationSessionLayout(root: sessionRoot())
        let paths = IsolationResolvedPaths(
            originalProject: nil,
            exchange: exchange,
            layout: layout
        )
        let environment = SandboxSession.desktopEnvironment(
            configuration: configuration,
            paths: paths,
            relayEnvironment: ["HTTPS_PROXY": "http://127.0.0.1:43123"],
            inherited: ["USER": "tester", "LOGNAME": "tester"]
        )

        XCTAssertEqual(environment["HOME"], layout.home.path)
        XCTAssertEqual(environment["CFFIXED_USER_HOME"], layout.home.path)
        XCTAssertEqual(environment["TMPDIR"], layout.temporary.path)
        XCTAssertEqual(environment["HTTPS_PROXY"], "http://127.0.0.1:43123")
        XCTAssertEqual(environment["https_proxy"], "http://127.0.0.1:43123")
        XCTAssertEqual(environment["ISOLATION_ORIGINAL"], "")
        XCTAssertEqual(environment["ELECTRON_DISABLE_SANDBOX"], "1")
        XCTAssertNil(environment["CLAUDE_CODE_OAUTH_TOKEN"])
    }

    func testDesktopEnvironmentUsesPersistentIdentityHomeWhenProvided() {
        var configuration = configuration(target: .claudeDesktop, persistClaudeLogin: true)
        configuration.projectPath = ""
        let layout = IsolationSessionLayout(root: sessionRoot())
        let identityHome = root.appendingPathComponent("Profiles/ClaudeDesktop/Home", isDirectory: true)
        let paths = IsolationResolvedPaths(
            originalProject: nil,
            exchange: exchange,
            layout: layout,
            identityHome: identityHome
        )
        let environment = SandboxSession.desktopEnvironment(
            configuration: configuration,
            paths: paths,
            relayEnvironment: [:]
        )

        XCTAssertEqual(environment["HOME"], identityHome.path)
        XCTAssertEqual(environment["CFFIXED_USER_HOME"], identityHome.path)
        XCTAssertNotEqual(environment["HOME"], layout.home.path)
        XCTAssertEqual(environment["TMPDIR"], layout.temporary.path)
    }

    func testDesktopLocaleLaunchArgumentsOverrideMacOSUILanguage() {
        XCTAssertEqual(
            SandboxSession.desktopLocaleLaunchArguments(for: "America/Los_Angeles"),
            ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        )
        XCTAssertEqual(
            SandboxSession.desktopLocaleLaunchArguments(for: "Asia/Shanghai"),
            ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        )
    }

    func testOperonHostedEnvironmentSkipsInstallerWithoutElectronArguments() {
        var configuration = configuration(target: .claudeDesktop)
        configuration.projectPath = ""
        let layout = IsolationSessionLayout(root: sessionRoot())
        let paths = IsolationResolvedPaths(
            originalProject: nil,
            exchange: exchange,
            layout: layout
        )
        let environment = SandboxSession.desktopEnvironment(
            configuration: configuration,
            paths: paths,
            relayEnvironment: ["HTTPS_PROXY": "http://127.0.0.1:43123"],
            runtimeFamily: .operonHostedWeb
        )

        XCTAssertEqual(environment["OPERON_SKIP_INSTALL"], "1")
        XCTAssertEqual(environment["ELECTRON_DISABLE_SANDBOX"], "1")
        XCTAssertNil(environment["ELECTRON_EXTRA_LAUNCH_ARGS"])
    }

    func testListenerAuditRejectsWildcardAndLANBindsButAllowsLoopback() {
        let output = """
        p101
        cClaude
        n127.0.0.1:8000
        n[::1]:8001
        p102
        cClaude Helper
        n*:9000
        n0.0.0.0:9001
        n192.168.1.20:9002
        p999
        cUnrelated
        n0.0.0.0:7777
        """
        let violations = SandboxSession.nonLoopbackListeners(
            in: output,
            ownedPIDs: [101, 102]
        )
        XCTAssertEqual(
            violations,
            ["PID 102 *:9000", "PID 102 0.0.0.0:9001", "PID 102 192.168.1.20:9002"]
        )
        XCTAssertTrue(
            SandboxSession.nonLoopbackListeners(
                in: "p101\nn127.0.0.1:8000\nn[::1]:8001\n",
                ownedPIDs: [101]
            ).isEmpty
        )
    }

    func testScienceBoundaryAllowsOnlyDaemonLoopbackPorts() throws {
        let ports: Set<Int> = [63639, 63640]
        let json = try XCTUnwrap(ScienceWebBoundary.contentRuleListJSON(ports: ports))
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )
        XCTAssertEqual(rules.count, 14)
        XCTAssertEqual(
            (rules.first?["trigger"] as? [String: String])?["url-filter"],
            "^https?://"
        )
        XCTAssertTrue(json.contains("63639"))
        XCTAssertTrue(json.contains("63640"))

        XCTAssertTrue(ScienceWebBoundary.isAllowedNavigation(
            try XCTUnwrap(URL(string: "http://localhost:63639/?nonce=abc")),
            ports: ports
        ))
        XCTAssertTrue(ScienceWebBoundary.isAllowedNavigation(
            try XCTUnwrap(URL(string: "http://[::1]:63640/mcp_apps")),
            ports: ports
        ))
        XCTAssertFalse(ScienceWebBoundary.isAllowedNavigation(
            try XCTUnwrap(URL(string: "https://api.anthropic.com/")),
            ports: ports
        ))
        XCTAssertFalse(ScienceWebBoundary.isAllowedNavigation(
            try XCTUnwrap(URL(string: "http://localhost:3000/")),
            ports: ports
        ))
    }

    @MainActor
    func testScienceContentRulesCompileInWebKit() async throws {
        _ = NSApplication.shared
        let json = try XCTUnwrap(
            ScienceWebBoundary.contentRuleListJSON(ports: [63639, 63640])
        )
        let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "RoutekeeperScienceTest-\(UUID().uuidString)",
                encodedContentRuleList: json
            ) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(
                        throwing: error
                            ?? NSError(domain: "Routekeeper.ScienceTest", code: 1)
                    )
                }
            }
        }
        XCTAssertTrue(list.identifier.hasPrefix("RoutekeeperScienceTest-"))
    }

    func testScienceLoginURLIsExtractedAndRedactedFromDiagnostics() throws {
        let nonce = String(repeating: "ab", count: 32)
        let output = """
        [daemon] listening on 127.0.0.1:63639
          Web UI → http://localhost:63639/?nonce=\(nonce)
        set-cookie: operon_csrf=\(nonce)
        """
        let url = try XCTUnwrap(ScienceWebBoundary.loginURL(in: output))
        XCTAssertEqual(url.port, 63639)
        XCTAssertEqual(url.query, "nonce=\(nonce)")

        let redacted = ScienceWebBoundary.redactSecrets(in: output)
        XCTAssertFalse(redacted.contains(nonce))
        XCTAssertTrue(redacted.contains("nonce=<redacted>"))
        XCTAssertTrue(redacted.contains("operon_csrf=<redacted>"))
    }

    func testScienceListenerPortsIgnoreWildcardAndUnrelatedPIDs() {
        let output = """
        p101
        n127.0.0.1:63639
        n[::1]:63639
        n127.0.0.1:63640
        p102
        n0.0.0.0:9000
        p999
        n127.0.0.1:7777
        """
        XCTAssertEqual(
            ScienceWebBoundary.loopbackListenerPorts(
                in: output,
                ownedPIDs: [101, 102]
            ),
            [63639, 63640]
        )
    }

    func testDesktopDiscoveryRecognizesLegacyAndCurrentOfficialBundles() {
        XCTAssertTrue(ClaudeDesktopDiscovery.supportedBundleIdentifiers.contains("com.anthropic.claudefordesktop"))
        XCTAssertTrue(ClaudeDesktopDiscovery.supportedBundleIdentifiers.contains("com.anthropic.operon"))
        XCTAssertEqual(ClaudeDesktopDiscovery.teamIdentifier, "Q6L2SF6YDW")
    }

    func testMountedOfficialScienceAppIsDiscoveredWhenPresent() throws {
        let app = URL(
            fileURLWithPath: "/Volumes/Claude Science/Claude Science.app",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw XCTSkip("Claude Science is not mounted.")
        }
        let installation = try XCTUnwrap(ClaudeDesktopDiscovery.inspect(at: app))
        XCTAssertEqual(
            installation.appURL.standardizedFileURL.resolvingSymlinksInPath(),
            app.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(installation.bundleIdentifier, ClaudeDesktopDiscovery.currentBundleIdentifier)
    }

    func testUnsignedClaudeBundleIsRejected() throws {
        let app = root.appendingPathComponent("Fake Claude.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("FakeClaude")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let plist: [String: Any] = [
            "CFBundleIdentifier": ClaudeDesktopDiscovery.bundleIdentifier,
            "CFBundleExecutable": "FakeClaude",
            "CFBundleName": "Fake Claude",
            "CFBundlePackageType": "APPL"
        ]
        let info = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try info.write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertNil(ClaudeDesktopDiscovery.inspect(at: app))
    }

    func testInspectsOfficialClaudeBundleWhenIntegrationPathIsProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["ROUTEKEEPER_OFFICIAL_CLAUDE_APP"] else {
            throw XCTSkip("Set ROUTEKEEPER_OFFICIAL_CLAUDE_APP to run the signed-app integration check.")
        }
        let installation = try XCTUnwrap(
            ClaudeDesktopDiscovery.inspect(at: URL(fileURLWithPath: path, isDirectory: true))
        )
        XCTAssertTrue(ClaudeDesktopDiscovery.supportedBundleIdentifiers.contains(installation.bundleIdentifier))
        XCTAssertEqual(installation.teamIdentifier, ClaudeDesktopDiscovery.teamIdentifier)
        if installation.bundleIdentifier == ClaudeDesktopDiscovery.currentBundleIdentifier {
            XCTAssertEqual(installation.runtimeFamily, .operonHostedWeb)
        } else {
            XCTAssertEqual(installation.runtimeFamily, .electron)
        }
    }

    func testPreflightReportsProjectOptionalForDesktopWorkspace() {
        let output = """
        timezone=1
        session-locale=1
        home-write=1
        workspace-write=1
        exchange-write=1
        original-project=0
        original-write=1
        control-read=1
        child-inherit=1
        direct-network=1
        direct-dns=1
        direct-udp=1
        relay-network=1
        direct-claude=1
        claude-relay=1
        claude-exit-ip=203.0.113.13
        claude-exit-match=1
        claude-exit-basis=exact
        loopback-listener=1
        external-app=1
        complete
        """
        let checks = SandboxSession.preflightChecks(output)
        XCTAssertTrue(checks.allSatisfy(\.passed))
        XCTAssertEqual(
            checks.first(where: { $0.id == "original-write" })?.detail,
            "未选择原项目，Chat 使用独立空工作区"
        )
    }

    func testDesktopPreflightAllowsLoopbackListenerAndOmitsExternalAppCheck() {
        let output = """
        timezone=1
        session-locale=1
        home-write=1
        workspace-write=1
        exchange-write=1
        original-project=0
        original-write=1
        control-read=1
        child-inherit=1
        direct-network=1
        direct-dns=1
        direct-udp=1
        relay-network=1
        direct-claude=1
        claude-relay=1
        claude-exit-ip=203.0.113.13
        claude-exit-match=1
        claude-exit-basis=exact
        loopback-listener=1
        external-app=0
        complete
        """
        let checks = SandboxSession.preflightChecks(output, target: .claudeDesktop)
        XCTAssertTrue(checks.allSatisfy(\.passed))
        XCTAssertFalse(checks.contains { $0.id == "external-app" })
        XCTAssertEqual(
            checks.first(where: { $0.id == "loopback-listener" })?.detail,
            "官方客户端可以建立本机监听；启动后会持续审计并拒绝非回环地址"
        )
    }
}
