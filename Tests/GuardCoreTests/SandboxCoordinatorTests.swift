import Foundation
import XCTest
@testable import GuardCore
@testable import Routekeeper

@MainActor
final class SandboxCoordinatorTests: XCTestCase {
    private let sharedConfigurationKey = "routekeeper-sandbox-shared-v1"
    private let legacyConfigurationKey = "routekeeper-isolation-configuration-v1"

    func testLegacyConfigurationMigratesOnlyTheSavedTarget() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let legacy = IsolationConfiguration(
            projectPath: fixture.temp.appendingPathComponent("Project").path,
            exchangePath: fixture.exchange.path,
            timezoneIdentifier: "UTC",
            upstream: IsolationUpstream(port: 8123),
            target: .claudeDesktop,
            persistClaudeLogin: true
        )
        fixture.defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: legacyConfigurationKey
        )

        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )

        XCTAssertEqual(coordinator.sharedConfiguration.enabledTargets, [.claudeDesktop])
        XCTAssertEqual(coordinator.codeSession.phase, .disabled)
        XCTAssertEqual(coordinator.desktopSession.phase, .ready)
        XCTAssertTrue(coordinator.sharedConfiguration.persistClaudeLogin)
        XCTAssertEqual(
            coordinator.codeSession.configuration.exchangePath,
            fixture.exchange.appendingPathComponent("Claude Code").path
        )
        XCTAssertEqual(
            coordinator.desktopSession.configuration.exchangePath,
            fixture.exchange.appendingPathComponent("Claude Desktop").path
        )
    }

    func testSharedSettingsApplyToBothSessionsAndPersistWithoutPassword() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        let upstream = IsolationUpstream(
            port: 9123,
            protocolType: .socks5,
            username: "routekeeper",
            password: "session-only"
        )
        coordinator.sharedConfiguration = SandboxSharedConfiguration(
            projectPath: fixture.temp.appendingPathComponent("Project").path,
            exchangePath: fixture.exchange.path,
            timezoneIdentifier: "Asia/Tokyo",
            upstream: upstream,
            enabledTargets: [.claudeCode, .claudeDesktop],
            persistClaudeLogin: true
        )

        for session in coordinator.sessions {
            XCTAssertEqual(session.configuration.upstream, upstream)
            XCTAssertEqual(session.configuration.timezoneIdentifier, "Asia/Tokyo")
            XCTAssertTrue(session.configuration.persistClaudeLogin)
        }

        let data = try XCTUnwrap(fixture.defaults.data(forKey: sharedConfigurationKey))
        let persisted = try JSONDecoder().decode(SandboxSharedConfiguration.self, from: data)
        XCTAssertEqual(persisted.upstream.username, "routekeeper")
        XCTAssertEqual(persisted.upstream.password, "")
        XCTAssertEqual(persisted.timezoneIdentifier, "Asia/Tokyo")
        XCTAssertTrue(persisted.persistClaudeLogin)
    }

    func testSessionOwnedSharedMutationSynchronizesAndPersists() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        let upstream = IsolationUpstream(port: 9234, protocolType: .socks5)

        coordinator.codeSession.configuration.upstream = upstream
        coordinator.desktopSession.configuration.persistClaudeLogin = true

        XCTAssertEqual(coordinator.sharedConfiguration.upstream, upstream)
        XCTAssertEqual(coordinator.desktopSession.configuration.upstream, upstream)
        XCTAssertTrue(coordinator.sharedConfiguration.persistClaudeLogin)
        XCTAssertTrue(coordinator.codeSession.configuration.persistClaudeLogin)

        let data = try XCTUnwrap(fixture.defaults.data(forKey: sharedConfigurationKey))
        let persisted = try JSONDecoder().decode(SandboxSharedConfiguration.self, from: data)
        XCTAssertEqual(persisted.upstream, upstream)
        XCTAssertTrue(persisted.persistClaudeLogin)
    }

    func testSharedLocaleEditsReachBothSessionLaunchConfigurationsAndPersist() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )

        coordinator.updateTimezoneIdentifier("America/Los_Angeles")
        coordinator.updateLanguageIdentifier("zh-Hans")

        for target in [IsolationApplicationTarget.claudeCode, .claudeDesktop] {
            let configuration = coordinator.sharedConfiguration.configuration(for: target)
            XCTAssertEqual(configuration.timezoneIdentifier, "America/Los_Angeles")
            XCTAssertEqual(configuration.languageIdentifier, "zh-Hans")
            XCTAssertEqual(coordinator.session(for: target).configuration, configuration)
            let environment = SandboxSession.baseEnvironment(
                configuration: configuration,
                paths: IsolationResolvedPaths(
                    originalProject: nil,
                    exchange: fixture.exchange,
                    layout: IsolationSessionLayout(root: fixture.sessions)
                ),
                relayEnvironment: [:]
            )
            XCTAssertEqual(environment["TZ"], "America/Los_Angeles")
            XCTAssertEqual(environment["AppleLocale"], "zh_CN")
        }
        let data = try XCTUnwrap(fixture.defaults.data(forKey: sharedConfigurationKey))
        let restored = try JSONDecoder().decode(SandboxSharedConfiguration.self, from: data)
        XCTAssertEqual(restored, coordinator.sharedConfiguration)
        XCTAssertFalse(restored.usesEgressRegionalDefaults)
    }

    func testEgressDefaultsApplyOnlyWhenFollowingAndUpdateBothSessions() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        let report = EgressAuditReport(
            snapshotTime: Date(),
            proxyConfigured: true,
            primaryIP: "203.0.113.1",
            families: [],
            services: [],
            intelligence: [IPIntelligence(
                ip: "203.0.113.1",
                sources: ["test"],
                countryCode: "JP",
                timezone: "Asia/Tokyo"
            )],
            intelligenceStatus: .available,
            assessment: EgressAssessment(level: .clear, findings: [])
        )

        coordinator.applyEgressRegionalDefaults(from: report)

        XCTAssertEqual(coordinator.codeSession.configuration.timezoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(coordinator.desktopSession.configuration.languageIdentifier, "ja-JP")
        coordinator.updateLanguageIdentifier("en-US")
        coordinator.applyEgressRegionalDefaults(from: report)
        XCTAssertEqual(coordinator.sharedConfiguration.languageIdentifier, "en-US")
    }

    func testRegionalRepairReplacesInvalidValuesWithValidEgressValues() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        var invalid = coordinator.sharedConfiguration
        invalid.timezoneIdentifier = ""
        invalid.languageIdentifier = ""
        coordinator.sharedConfiguration = invalid
        let report = EgressAuditReport(
            snapshotTime: Date(),
            proxyConfigured: true,
            primaryIP: "198.51.100.1",
            families: [],
            services: [],
            intelligence: [IPIntelligence(
                ip: "198.51.100.1",
                sources: ["test"],
                countryCode: "DE",
                timezone: "Europe/Berlin"
            )],
            intelligenceStatus: .available,
            assessment: EgressAssessment(level: .clear, findings: [])
        )

        XCTAssertTrue(coordinator.repairRegionalSettings(from: report))
        XCTAssertEqual(coordinator.sharedConfiguration.timezoneIdentifier, "Europe/Berlin")
        XCTAssertEqual(coordinator.sharedConfiguration.languageIdentifier, "de-DE")
        XCTAssertTrue(coordinator.sharedConfiguration.usesEgressRegionalDefaults)
        XCTAssertEqual(coordinator.desktopSession.configuration.timezoneIdentifier, "Europe/Berlin")
    }

    func testSharedConfigurationChangeClearsStaleWebLaunchValidationFailure() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        coordinator.webBrowser.phase = .failed
        coordinator.webBrowser.message = "请先设置有效的会话时区和语言。"
        coordinator.webBrowser.installation = ClaudeWebBrowserInstallation(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            executableURL: URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            signingIdentifier: "com.google.Chrome",
            teamIdentifier: "EQHXZ8M8AV",
            shortVersion: "156.0",
            bundleVersion: "8078.48"
        )

        var configuration = coordinator.sharedConfiguration
        configuration.timezoneIdentifier = "America/Los_Angeles"
        configuration.languageIdentifier = "en-US"
        coordinator.sharedConfiguration = configuration

        XCTAssertEqual(coordinator.webBrowser.phase, .stopped)
        XCTAssertEqual(
            coordinator.webBrowser.message,
            "共享设置已更新，可以重新打开 Chrome。"
        )
    }

    func testCommittingUnchangedSharedConfigurationClearsStaleWebLaunchFailure() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        coordinator.webBrowser.phase = .failed
        coordinator.webBrowser.message = "请先设置有效的会话时区和语言。"
        coordinator.webBrowser.installation = ClaudeWebBrowserInstallation(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            executableURL: URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            signingIdentifier: "com.google.Chrome",
            teamIdentifier: "EQHXZ8M8AV",
            shortVersion: "156.0",
            bundleVersion: "8078.48"
        )

        coordinator.commitSharedConfiguration()

        XCTAssertEqual(coordinator.webBrowser.phase, .stopped)
        XCTAssertEqual(
            coordinator.webBrowser.message,
            "共享设置已更新，可以重新打开 Chrome。"
        )
    }

    func testValidSharedConfigurationReplacesStaleInvalidWebMessageAfterFailure() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        coordinator.webBrowser.installation = ClaudeWebBrowserInstallation(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            executableURL: URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            signingIdentifier: "com.google.Chrome",
            teamIdentifier: "EQHXZ8M8AV",
            shortVersion: "156.0",
            bundleVersion: "8078.48"
        )
        coordinator.webBrowser.phase = .failed
        var invalid = coordinator.sharedConfiguration
        invalid.timezoneIdentifier = "Mars/Olympus"
        coordinator.sharedConfiguration = invalid
        XCTAssertEqual(coordinator.webBrowser.phase, .stopped)
        XCTAssertEqual(
            coordinator.webBrowser.message,
            "会话时区“Mars/Olympus”无效，请修正红色配置后再打开 Chrome。"
        )

        var valid = coordinator.sharedConfiguration
        valid.timezoneIdentifier = "Asia/Tokyo"
        valid.languageIdentifier = "ja-JP"
        coordinator.sharedConfiguration = valid

        XCTAssertEqual(coordinator.webBrowser.phase, .stopped)
        XCTAssertEqual(
            coordinator.webBrowser.message,
            "共享设置已更新，可以重新打开 Chrome。"
        )
    }

    func testTargetToggleKeepsOtherSessionIndependentAndResetsDisabledTarget() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        let codeRoot = fixture.sessions.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: codeRoot, withIntermediateDirectories: true)
        try Data("owned\n".utf8).write(to: codeRoot.appendingPathComponent(".routekeeper-session"))
        coordinator.codeSession.sessionRoot = codeRoot
        coordinator.codeSession.phase = .ended

        XCTAssertTrue(coordinator.setTarget(.claudeDesktop, enabled: false))
        XCTAssertEqual(coordinator.desktopSession.phase, .disabled)
        XCTAssertEqual(coordinator.codeSession.phase, .ended)
        XCTAssertTrue(FileManager.default.fileExists(atPath: codeRoot.path))

        XCTAssertTrue(coordinator.setTarget(.claudeDesktop, enabled: true))
        XCTAssertEqual(coordinator.desktopSession.phase, .ready)
        XCTAssertEqual(coordinator.codeSession.phase, .ended)

        coordinator.codeSession.phase = .ended
        XCTAssertTrue(coordinator.setTarget(.claudeCode, enabled: false))
        XCTAssertEqual(coordinator.codeSession.phase, .disabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: codeRoot.path))
        XCTAssertEqual(coordinator.desktopSession.phase, .ready)
    }

    func testOneActiveTargetDoesNotBlockManagingTheOther() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        coordinator.codeSession.phase = .running

        XCTAssertTrue(coordinator.setTarget(.claudeDesktop, enabled: false))
        XCTAssertEqual(coordinator.codeSession.phase, .running)
        XCTAssertFalse(coordinator.setTarget(.claudeCode, enabled: false))
        XCTAssertEqual(coordinator.codeSession.phase, .running)
    }

    func testBothCoordinatorSessionRootsAreMarkedAsCurrentForCleanup() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )
        let codeRoot = fixture.sessions.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let desktopRoot = fixture.sessions.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for root in [codeRoot, desktopRoot] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("home/Library/Caches/com.anthropic.claudefordesktop", isDirectory: true),
                withIntermediateDirectories: true
            )
            try Data("owned\n".utf8).write(to: root.appendingPathComponent(".routekeeper-session"))
            try Data("cache".utf8).write(
                to: root.appendingPathComponent("home/Library/Caches/com.anthropic.claudefordesktop/cache.bin")
            )
        }
        coordinator.codeSession.sessionRoot = codeRoot
        coordinator.desktopSession.sessionRoot = desktopRoot

        let plan = CacheCleaner.scan(
            home: fixture.temp.appendingPathComponent("Home").path,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            currentSessionRoots: coordinator.currentSessionRoots
        )

        for root in [codeRoot, desktopRoot] {
            let normalizedRoot = root.resolvingSymlinksInPath().path
            let targets = plan.targets.filter {
                guard let owningRoot = $0.owningRoot else { return false }
                return URL(fileURLWithPath: owningRoot).resolvingSymlinksInPath().path == normalizedRoot
            }
            XCTAssertFalse(targets.isEmpty)
            XCTAssertTrue(targets.allSatisfy { $0.scope == .currentSession })
        }
    }

    func testFreshConfigurationEnablesOnlyDetectedClients() {
        let codeOnly = makeFreshCoordinator(installedTargets: [.claudeCode])
        XCTAssertEqual(codeOnly.coordinator.sharedConfiguration.enabledTargets, [.claudeCode])
        XCTAssertEqual(codeOnly.coordinator.codeSession.phase, .ready)
        XCTAssertEqual(codeOnly.coordinator.desktopSession.phase, .disabled)
        codeOnly.fixture.cleanUp()

        let desktopOnly = makeFreshCoordinator(installedTargets: [.claudeDesktop])
        XCTAssertEqual(desktopOnly.coordinator.sharedConfiguration.enabledTargets, [.claudeDesktop])
        XCTAssertEqual(desktopOnly.coordinator.codeSession.phase, .disabled)
        XCTAssertEqual(desktopOnly.coordinator.desktopSession.phase, .ready)
        desktopOnly.fixture.cleanUp()
    }

    func testFreshConfigurationWithNoClientsStaysEmptyAndExplainsWhy() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: []
        )

        XCTAssertTrue(coordinator.sharedConfiguration.enabledTargets.isEmpty)
        XCTAssertEqual(coordinator.phase, .disabled)
        XCTAssertEqual(coordinator.statusTitle, "未检测到 Claude 应用")
        XCTAssertTrue(coordinator.message.contains("普通网络保护仍可使用"))
    }

    func testSavedEmptySelectionIsNeverRewrittenOnLaunch() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let saved = SandboxSharedConfiguration(enabledTargets: [])
        fixture.defaults.set(
            try JSONEncoder().encode(saved),
            forKey: sharedConfigurationKey
        )

        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: [.claudeCode, .claudeDesktop]
        )

        XCTAssertTrue(coordinator.sharedConfiguration.enabledTargets.isEmpty)
        XCTAssertEqual(coordinator.statusTitle, "选择要保护的应用")
    }

    private func makeFreshCoordinator(
        installedTargets: Set<IsolationApplicationTarget>
    ) -> (coordinator: SandboxCoordinator, fixture: Fixture) {
        let fixture = makeFixture()
        let coordinator = SandboxCoordinator(
            preferences: fixture.defaults,
            sessionsRoot: fixture.sessions,
            profilesRoot: fixture.profiles,
            installedTargets: installedTargets
        )
        return (coordinator, fixture)
    }

    private func makeFixture() -> Fixture {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-coordinator-\(UUID().uuidString)", isDirectory: true)
        let suite = "routekeeper-coordinator-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return Fixture(
            temp: temp,
            suite: suite,
            defaults: defaults,
            sessions: temp.appendingPathComponent("Isolation", isDirectory: true),
            profiles: temp.appendingPathComponent("Profiles", isDirectory: true),
            exchange: temp.appendingPathComponent("Exchange", isDirectory: true)
        )
    }

    private struct Fixture {
        let temp: URL
        let suite: String
        let defaults: UserDefaults
        let sessions: URL
        let profiles: URL
        let exchange: URL

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
