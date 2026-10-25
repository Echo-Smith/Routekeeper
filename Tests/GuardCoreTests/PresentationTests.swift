import XCTest
import AppKit
import SwiftUI
@testable import GuardCore
@testable import Routekeeper

final class PresentationTests: XCTestCase {
    @MainActor func testPanelCloseKeepsAppAliveAndReopenRestoresDock() async {
        let app = NSApplication.shared
        let originalPolicy = app.activationPolicy()
        let delegate = RoutekeeperAppDelegate()
        let suite = "guard-menu-bar-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        defer {
            window.orderOut(nil)
            app.setActivationPolicy(originalPolicy)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            defaults.removePersistentDomain(forName: suite)
            _ = AppNavigationRequest.consumePendingPage()
        }
        delegate.configureStatusItem(store: store)
        XCTAssertTrue(delegate.isStatusItemConfigured)
        delegate.attach(window, openWindow: { XCTFail("Existing panel should be reused") })
        window.close()
        XCTAssertEqual(app.activationPolicy(), .accessory)
        XCTAssertTrue(delegate.isStatusItemConfigured)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(app))
        delegate.showLastActivePanel()
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(app.activationPolicy(), .regular)
        XCTAssertTrue(window.isVisible)
        XCTAssertNil(AppNavigationRequest.consumePendingPage())
        window.close()
        XCTAssertEqual(app.activationPolicy(), .accessory)
    }

    func testPersistedPageFallsBackToOverviewForUnknownValue() {
        XCTAssertEqual(
            GuardPage(rawValue: "sandbox"),
            .sandbox
        )
        XCTAssertNil(GuardPage(rawValue: "removed-page"))
    }

    func testUnknownAndFailedChecksStayVisibleEvenForOptionalProbes() {
        for id in ["dns", "udp-ipv4", "udp-ipv6", "target", "tun"] {
            for level in [CheckLevel.failed, .unknown] {
                let check = CheckItem(id, id, "test", level)
                XCTAssertTrue(check.needsAttention)
                XCTAssertFalse(check.nextStep.isEmpty)
            }
        }
        XCTAssertFalse(CheckItem("boundary", "", "", .warning).needsAttention)
        XCTAssertFalse(CheckItem("dns", "", "", .passed).needsAttention)
        XCTAssertTrue(CheckItem("desktop", "", "", .warning).needsAttention)
    }

    func testInspectionChecksCollapseIntoFourEvidenceGroups() {
        let checks = [
            CheckItem("target", "target", "", .passed),
            CheckItem("target-ipv4", "target format", "", .passed),
            CheckItem("scope", "scope", "", .passed),
            CheckItem("proxy-client", "proxy client", "", .passed),
            CheckItem("proxy", "proxy", "", .passed),
            CheckItem("interval", "interval", "", .passed),
            CheckItem("ipv4", "ipv4", "", .passed),
            CheckItem("ipv6", "ipv6", "", .passed),
            CheckItem("dns", "dns", "", .passed),
            CheckItem("udp-ipv4", "udp4", "", .passed),
            CheckItem("udp-ipv6", "udp6", "", .passed),
            CheckItem("tun", "tun", "", .passed),
            CheckItem("proxy-exit", "proxy exit", "", .passed),
            CheckItem("tun-exit", "system exit", "", .passed),
            CheckItem("ipinfo-exit", "ipinfo", "", .passed),
            CheckItem("claude-trace-exit", "trace", "", .passed),
            CheckItem("process-access", "process", "", .passed),
            CheckItem("claude-process-network", "process network", "", .passed),
            CheckItem("desktop", "desktop", "", .passed),
            CheckItem("code", "code", "", .passed),
            CheckItem("code-environment", "code environment", "", .passed),
            CheckItem("boundary", "boundary", "", .warning)
        ]

        let groups = InspectionCheckGrouping.groups(from: checks)

        XCTAssertEqual(groups.map(\.kind), [.configuration, .localPath, .externalServices, .claudeEnvironment])
        XCTAssertEqual(groups.map(\.checks.count), [6, 6, 4, 5])
        XCTAssertFalse(groups.flatMap(\.checks).contains { $0.id == "boundary" })
        XCTAssertTrue(groups.allSatisfy { $0.level == .passed })
    }

    func testInspectionGroupStatusUsesMostActionableEvidence() {
        let groups = InspectionCheckGrouping.groups(from: [
            CheckItem("target", "target", "", .warning),
            CheckItem("dns", "dns", "", .unknown),
            CheckItem("udp-ipv4", "udp", "", .failed),
            CheckItem("desktop", "desktop", "", .warning),
            CheckItem("custom-check", "custom", "", .passed)
        ])

        XCTAssertEqual(groups.first { $0.kind == .configuration }?.level, .notice)
        XCTAssertEqual(groups.first { $0.kind == .localPath }?.level, .needsAttention)
        XCTAssertEqual(groups.first { $0.kind == .claudeEnvironment }?.level, .notice)
        XCTAssertEqual(groups.first { $0.kind == .additional }?.checks.map(\.id), ["custom-check"])
    }

    @MainActor func testCleanupOnlySelectsDetectedNonemptyTargets() {
        let suite = "guard-presentation-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false)
        store.cleanupPlan = CleanupPlan(targets: [
            CleanupTarget(path: "/test/cache", labelZh: "cache", labelEn: "cache", kindZh: "cache", kindEn: "cache", scope: .hostCode, sizeBytes: 10, fileCount: 1, exists: true),
            CleanupTarget(path: "/test/empty", labelZh: "empty", labelEn: "empty", kindZh: "cache", kindEn: "cache", scope: .hostCode, exists: true),
            CleanupTarget(path: "/test/missing", labelZh: "missing", labelEn: "missing", kindZh: "cache", kindEn: "cache", scope: .hostCode)
        ])
        XCTAssertTrue(store.selectedCleanupTargets.isEmpty)
        store.cleanupSelection = ["/test/cache", "/test/empty", "/test/missing", "/unscanned"]
        XCTAssertEqual(store.selectedCleanupTargets.map(\.path), ["/test/cache"])
        store.cleanupPlan?.targets[0].blockedReason = .processRunning
        XCTAssertTrue(store.selectedCleanupTargets.isEmpty)
        store.cleanupSelection.remove("/test/cache")
        XCTAssertTrue(store.selectedCleanupTargets.isEmpty)
    }

    @MainActor func testApplyingCleanupPlanSelectsOnlySafeNonemptyTargets() {
        let suite = "guard-cleanup-defaults-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false)
        let previousRevision = store.cleanupPlanRevision
        store.applyCleanupPlan(CleanupPlan(targets: [
            CleanupTarget(
                path: "/test/cache",
                labelZh: "cache",
                labelEn: "cache",
                kindZh: "cache",
                kindEn: "cache",
                scope: .hostCode,
                sizeBytes: 10,
                fileCount: 1,
                exists: true
            ),
            CleanupTarget(
                path: "/test/empty",
                labelZh: "empty",
                labelEn: "empty",
                kindZh: "cache",
                kindEn: "cache",
                scope: .hostCode,
                exists: true
            ),
            CleanupTarget(
                path: "/test/locked",
                labelZh: "locked",
                labelEn: "locked",
                kindZh: "cache",
                kindEn: "cache",
                scope: .hostCode,
                sizeBytes: 20,
                fileCount: 1,
                exists: true,
                blockedReason: .processRunning
            ),
            CleanupTarget(
                path: "/test/past-session",
                labelZh: "past session",
                labelEn: "past session",
                kindZh: "log",
                kindEn: "log",
                scope: .pastSession,
                sizeBytes: 30,
                fileCount: 1,
                exists: true
            ),
            CleanupTarget(
                path: "/test/chrome-profile",
                labelZh: "Chrome",
                labelEn: "Chrome",
                kindZh: "profile",
                kindEn: "profile",
                scope: .chromeProfile,
                sizeBytes: 40,
                fileCount: 1,
                exists: true
            )
        ]))

        XCTAssertEqual(store.cleanupSelection, ["/test/cache"])
        XCTAssertEqual(store.selectedCleanupTargets.map(\.path), ["/test/cache"])
        XCTAssertFalse(store.cleanupIncludesLocalData)
        XCTAssertEqual(store.cleanupPlanRevision, previousRevision + 1)
    }

    @MainActor func testAttentionEventsRetainTheirSeverity() {
        let suite = "guard-events-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false)
        store.log("normal")
        store.log("incident", attention: true)
        XCTAssertTrue(store.events[0].isAttention)
        XCTAssertFalse(store.events[1].isAttention)
    }

    @MainActor func testDesktopInstalledUsesSignatureVerifiedDiscoveryBeforeAnySnapshot() async throws {
        guard let installation = ClaudeDesktopDiscovery.locate() else {
            throw XCTSkip("No signature-verified official Claude Desktop app is installed.")
        }
        let suite = "guard-desktop-discovery-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false)
        XCTAssertNil(store.snapshot)
        await store.loadDesktopInstallationIfNeeded()
        XCTAssertTrue(store.desktopInstalled)
        XCTAssertEqual(store.desktopInstallation?.appURL, installation.appURL)
    }

    @MainActor func testSandboxModeTakesStatusPriorityAndSkipsOrdinaryChecks() async {
        actor Calls {
            private(set) var value = 0
            func increment() { value += 1 }
            func count() -> Int { value }
        }
        let calls = Calls()
        let suite = "guard-sandbox-status-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(
            defaults: defaults,
            watchNetwork: false,
            notificationsEnabled: false,
            runDiagnostic: { settings in
                await calls.increment()
                return DiagnosticSnapshot(
                    settings: settings,
                    checks: [],
                    proxyIP: "1.2.3.4",
                    tunnelIP: "1.2.3.4",
                    processes: [],
                    desktopPath: nil,
                    codePaths: []
                )
            }
        )

        store.settings.experimentalSandboxEnabled = true
        store.sandbox.sharedConfiguration.enabledTargets = [.claudeCode]
        store.sandbox.codeSession.phase = .networkPaused
        await store.check()

        XCTAssertEqual(store.title, "网络已关闭")
        XCTAssertEqual(store.symbol, "wifi.slash")
        let callCount = await calls.count()
        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(store.monitoring)
    }

    @MainActor func testSandboxModeAllowsHostInspectionUntilSessionBecomesActive() async {
        actor Calls {
            private(set) var value = 0
            func increment() { value += 1 }
            func count() -> Int { value }
        }
        let calls = Calls()
        let suite = "guard-sandbox-inspection-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(
            defaults: defaults,
            watchNetwork: false,
            notificationsEnabled: false,
            runDiagnostic: { settings in
                await calls.increment()
                return DiagnosticSnapshot(
                    settings: settings,
                    checks: [.init("network", "network", "test", .passed)],
                    proxyIP: "1.2.3.4",
                    tunnelIP: "1.2.3.4",
                    processes: [],
                    desktopPath: nil,
                    codePaths: []
                )
            }
        )

        store.settings.experimentalSandboxEnabled = true
        store.sandbox.sharedConfiguration.enabledTargets = [.claudeCode]
        store.sandbox.codeSession.phase = .ready

        await store.check()

        let firstCallCount = await calls.count()
        XCTAssertEqual(firstCallCount, 1)
        XCTAssertNotNil(store.snapshot)
        XCTAssertFalse(store.monitoring)

        store.sandbox.codeSession.phase = .running
        await store.check()

        let secondCallCount = await calls.count()
        XCTAssertEqual(secondCallCount, 1)
        XCTAssertTrue(store.notice.contains("结束"))
    }

    @MainActor func testSandboxConfigurationPersistsWithoutProxyPassword() throws {
        let suite = "guard-sandbox-secret-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SandboxSession(preferences: defaults)

        session.configuration.target = .claudeDesktop
        session.configuration.persistClaudeLogin = true
        session.configuration.upstream.username = "routekeeper"
        session.configuration.upstream.password = "do-not-persist"

        let data = try XCTUnwrap(defaults.data(forKey: "routekeeper-isolation-configuration-v1"))
        let persisted = try JSONDecoder().decode(IsolationConfiguration.self, from: data)
        XCTAssertEqual(persisted.target, .claudeDesktop)
        XCTAssertTrue(persisted.persistClaudeLogin)
        XCTAssertEqual(persisted.upstream.username, "routekeeper")
        XCTAssertEqual(persisted.upstream.password, "")
        let restored = SandboxSession(preferences: defaults)
        XCTAssertEqual(restored.configuration.target, .claudeDesktop)
        XCTAssertTrue(restored.configuration.persistClaudeLogin)
        XCTAssertEqual(restored.configuration.upstream.password, "")
    }

    @MainActor func testClearClaudeLoginStateRemovesOnlyOwnedProfile() throws {
        let suite = "guard-profile-clear-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-profile-clear-\(UUID())", isDirectory: true)
        let profiles = temp.appendingPathComponent("Profiles", isDirectory: true)
        let ownedHome = profiles.appendingPathComponent("ClaudeDesktop/Home", isDirectory: true)
        let unowned = profiles.appendingPathComponent("Other/Home", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }
        try FileManager.default.createDirectory(at: ownedHome, withIntermediateDirectories: true)
        try Data("owned".utf8).write(to: ownedHome.appendingPathComponent(".routekeeper-profile"))
        try FileManager.default.createDirectory(at: unowned, withIntermediateDirectories: true)

        let session = SandboxSession(
            preferences: defaults,
            sessionsRoot: temp.appendingPathComponent("Isolation", isDirectory: true),
            profilesRoot: profiles
        )
        XCTAssertTrue(session.persistedClaudeProfileAvailable)
        XCTAssertTrue(session.clearClaudeLoginState())
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedHome.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unowned.path))
        XCTAssertFalse(session.persistedClaudeProfileAvailable)
    }

    @MainActor func testManuallySelectedClaudeCodeCommandPersistsAcrossSessions() async throws {
        let suite = "guard-claude-command-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-claude-command-\(UUID())", isDirectory: true)
        let command = temp.appendingPathComponent("claude")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: command)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: command.path
        )

        let session = SandboxSession(preferences: defaults)
        XCTAssertTrue(session.selectClaudeCodeCommand(at: command))
        XCTAssertEqual(session.claudeCodeInstallation?.source, .manuallySelected)

        let restored = SandboxSession(preferences: defaults)
        await restored.loadInstalledApplicationsIfNeeded()
        XCTAssertEqual(restored.claudeCodeInstallation?.executableURL, command.standardizedFileURL)
        XCTAssertEqual(restored.claudeCodeInstallation?.source, .manuallySelected)
    }

    @MainActor func testManualNetworkPauseSurvivesSleepAndNeverAutoResumes() {
        let suite = "guard-manual-pause-sleep-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SandboxSession(preferences: defaults)

        session.phase = .running
        session.networkEnabled = true
        session.pauseNetwork()
        session.networkEnvironmentChanged("系统即将休眠", sleeping: true, waking: false)

        XCTAssertEqual(session.pauseReason, .manual)
        XCTAssertFalse(session.networkValidationInProgress)

        session.networkEnvironmentChanged("系统已唤醒", sleeping: false, waking: true)

        XCTAssertEqual(session.pauseReason, .manual)
        XCTAssertFalse(session.networkValidationInProgress)
    }

    @MainActor func testClearLocalInformationRemovesOwnedDataAndSandboxCopies() async throws {
        let suite = "guard-local-data-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-local-data-\(UUID())", isDirectory: true)
        let sessionsRoot = temp.appendingPathComponent("Isolation", isDirectory: true)
        let ownedSession = sessionsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unownedDirectory = sessionsRoot.appendingPathComponent("keep-me", isDirectory: true)
        var credentialCleared = false

        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }
        try FileManager.default.createDirectory(at: ownedSession, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unownedDirectory, withIntermediateDirectories: true)
        try Data("owned\n".utf8).write(to: ownedSession.appendingPathComponent(".routekeeper-session"))

        let gateway = GatewayVerificationController(defaults: defaults, invalidateLoadedEvidence: false)
        let egress = EgressAuditController(defaults: defaults)
        let sandbox = SandboxCoordinator(
            preferences: defaults,
            sessionsRoot: sessionsRoot,
            profilesRoot: temp.appendingPathComponent("Profiles", isDirectory: true)
        )
        let store = GuardStore(
            defaults: defaults,
            watchNetwork: false,
            notificationsEnabled: false,
            gatewayVerification: gateway,
            egressAuditController: egress,
            sandbox: sandbox,
            credentialClearer: {
                credentialCleared = true
                return true
            },
            networkFilterDisabler: { nil }
        )
        store.settings.targetIP = "1.2.3.4"
        store.events = [GuardEvent(message: "private test event")]
        store.cleanupIncludesLocalData = true
        store.snapshot = DiagnosticSnapshot(
            settings: store.settings,
            checks: [],
            proxyIP: "1.2.3.4",
            tunnelIP: "1.2.3.4",
            processes: [],
            desktopPath: nil,
            codePaths: []
        )
        defaults.set(Data("secret".utf8), forKey: "routekeeper-test-private-value")
        defaults.set("2026-10-21.2", forKey: "routekeeper.disclaimer-accepted-version")
        defaults.set("zh-Hans", forKey: L10n.languageKey)

        let cleared = await store.clearLocalInformation()

        XCTAssertTrue(cleared)
        XCTAssertTrue(credentialCleared)
        XCTAssertEqual(store.settings, GuardSettings())
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertFalse(store.cleanupIncludesLocalData)
        XCTAssertNil(defaults.object(forKey: "guard-settings-v1"))
        XCTAssertNil(defaults.object(forKey: "routekeeper-test-private-value"))
        XCTAssertNil(defaults.object(forKey: L10n.languageKey))
        XCTAssertEqual(defaults.string(forKey: "routekeeper.disclaimer-accepted-version"), "2026-10-21.2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedSession.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unownedDirectory.path))
    }

    func testSandboxEnvironmentCarriesCanonicalIsolationPaths() throws {
        let root = URL(fileURLWithPath: "/private/tmp/routekeeper-environment-test", isDirectory: true)
        let layout = IsolationSessionLayout(root: root)
        let paths = IsolationResolvedPaths(
            originalProject: URL(fileURLWithPath: "/Users/example/Project", isDirectory: true),
            exchange: URL(fileURLWithPath: "/private/tmp/routekeeper-exchange", isDirectory: true),
            layout: layout
        )
        let environment = SandboxSession.baseEnvironment(
            configuration: IsolationConfiguration(
                projectPath: try XCTUnwrap(paths.originalProject).path,
                exchangePath: paths.exchange.path,
                timezoneIdentifier: "Asia/Shanghai"
            ),
            paths: paths,
            relayEnvironment: ["HTTPS_PROXY": "http://127.0.0.1:43123"]
        )

        XCTAssertEqual(environment["ISOLATION_WORKSPACE"], layout.workspace.path)
        XCTAssertEqual(environment["ISOLATION_EXCHANGE"], paths.exchange.path)
        XCTAssertEqual(environment["ISOLATION_ORIGINAL"], try XCTUnwrap(paths.originalProject).path)
        XCTAssertEqual(environment["ISOLATION_CONTROL"], layout.control.path)
        XCTAssertEqual(environment["HTTPS_PROXY"], "http://127.0.0.1:43123")
    }

    @MainActor func testAutoAdoptRunsFreshCheckWithoutPriorSnapshot() async {
        actor Calls {
            private(set) var value = 0
            func increment() { value += 1 }
            func count() -> Int { value }
        }
        let calls = Calls()
        let suite = "guard-auto-adopt-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false,
                               runDiagnostic: { settings in
            await calls.increment()
            var snapshot = DiagnosticSnapshot(
                settings: settings, checks: [.init("boundary", "边界", "test", .warning)],
                proxyIP: "1.2.3.4", tunnelIP: "1.2.3.4",
                processes: [], desktopPath: nil, codePaths: []
            )
            snapshot.familyExits = [
                .init(family: .ipv4, direct: "1.2.3.4", proxied: "1.2.3.4"),
                .init(family: .ipv6, direct: nil, proxied: nil)
            ]
            snapshot.enabledFamilies = [.ipv4]
            return snapshot
        })

        XCTAssertNil(store.snapshot)
        await store.adoptObservedExit(family: .ipv4)

        XCTAssertEqual(store.settings.fixedIPv4TargetIP, "1.2.3.4")
        let callCount = await calls.count()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(store.activeFamilies, Set([.ipv4]))
    }

    @MainActor
    func testSandboxProtectionAndAuthenticationAreTopLevelNavigation() throws {
        let pages = GuardPage.allCases
        XCTAssertTrue(pages.contains(.sandbox))
        XCTAssertLessThan(
            try XCTUnwrap(GuardPage.primaryNavigation.firstIndex(of: .networkProtection)),
            try XCTUnwrap(GuardPage.primaryNavigation.firstIndex(of: .sandbox))
        )
        XCTAssertEqual(GuardPage.sandbox.title, "实验性沙箱")
        XCTAssertEqual(GuardPage.sandbox.sidebarTitle, "沙箱")
        XCTAssertEqual(GuardPage.sandbox.sidebarBadge, "实验性")
        XCTAssertEqual(GuardPage.networkProtection.title, "网络保护")
        XCTAssertEqual(GuardPage.authentication.title, "Claude 登录")
        XCTAssertEqual(GuardPage.authentication.navigationTitle, "登录凭证")
        XCTAssertTrue(GuardPage.primaryNavigation.contains(.networkProtection))
        XCTAssertFalse(GuardPage.primaryNavigation.contains(.inspection))
        XCTAssertFalse(GuardPage.primaryNavigation.contains(.authentication))
        XCTAssertTrue(GuardPage.toolNavigation.contains(.authentication))
        XCTAssertEqual(GuardPage.toolNavigation, [.authentication, .activity, .cleanup])
    }

    @MainActor
    func testMenuBarContentGrowsWithAccessibilityTextScale() {
        let suite = "guard-menu-accessibility-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let previousScale = UserDefaults.standard.object(forKey: AppTextScale.storageKey)
        let delegate = RoutekeeperAppDelegate()
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            defaults.removePersistentDomain(forName: suite)
            if let previousScale {
                UserDefaults.standard.set(previousScale, forKey: AppTextScale.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppTextScale.storageKey)
            }
        }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false)

        func fittingSize(at scale: AppTextScale) -> NSSize {
            UserDefaults.standard.set(scale.rawValue, forKey: AppTextScale.storageKey)
            let host = NSHostingView(
                rootView: GuardMenu(store: store, appDelegate: delegate)
            )
            host.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
            host.layoutSubtreeIfNeeded()
            return host.fittingSize
        }

        let regular = fittingSize(at: .standard)
        let accessible = fittingSize(at: .extraLarge)

        XCTAssertEqual(regular.width, 300, accuracy: 1)
        XCTAssertGreaterThan(accessible.height, regular.height)
    }

    @MainActor
    func testSandboxExitDetectionRunsFreshCheckWhileSandboxModeIsEnabled() async {
        actor Calls {
            private(set) var value = 0
            func increment() { value += 1 }
            func count() -> Int { value }
        }
        let calls = Calls()
        let suite = "guard-sandbox-exit-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(
            defaults: defaults,
            watchNetwork: false,
            notificationsEnabled: false,
            runDiagnostic: { settings in
                await calls.increment()
                var snapshot = DiagnosticSnapshot(
                    settings: settings,
                    checks: [],
                    proxyIP: "4.3.2.1",
                    tunnelIP: "4.3.2.1",
                    processes: [],
                    desktopPath: nil,
                    codePaths: []
                )
                snapshot.familyExits = [
                    .init(family: .ipv4, direct: "4.3.2.1", proxied: "4.3.2.1"),
                    .init(family: .ipv6, direct: nil, proxied: nil)
                ]
                snapshot.enabledFamilies = [.ipv4]
                return snapshot
            }
        )

        store.settings.experimentalSandboxEnabled = true
        let detected = await store.detectExitForSandbox()

        XCTAssertTrue(detected)
        XCTAssertEqual(store.settings.fixedIPv4TargetIP, "4.3.2.1")
        XCTAssertEqual(store.snapshot?.proxyIP, "4.3.2.1")
        let callCount = await calls.count()
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(store.monitoring)
    }

    @MainActor
    func testEgressSnapshotRefreshesWhenStoredSnapshotIsStale() async {
        actor Calls {
            private(set) var value = 0
            func increment() { value += 1 }
            func count() -> Int { value }
        }
        let calls = Calls()
        let suite = "guard-egress-freshness-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false,
                               runDiagnostic: { settings in
            await calls.increment()
            return DiagnosticSnapshot(
                settings: settings, checks: [], proxyIP: "5.6.7.8", tunnelIP: "5.6.7.8",
                processes: [], desktopPath: nil, codePaths: []
            )
        })
        var stale = DiagnosticSnapshot(
            settings: store.settings, checks: [], proxyIP: "1.2.3.4", tunnelIP: "1.2.3.4",
            processes: [], desktopPath: nil, codePaths: []
        )
        stale.checkedAt = Date().addingTimeInterval(-120)
        store.snapshot = stale

        let refreshed = await store.snapshotForEgressAudit(maxAge: 45)
        XCTAssertEqual(refreshed?.proxyIP, "5.6.7.8")
        let count = await calls.count()
        XCTAssertEqual(count, 1)
    }
}
