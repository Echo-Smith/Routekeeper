import XCTest
import AppKit
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
        delegate.showChecksPanel()
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(app.activationPolicy(), .regular)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(AppNavigationRequest.consumePendingPage(), .inspection)
        window.close()
        XCTAssertEqual(app.activationPolicy(), .accessory)
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

    @MainActor func testCleanupOnlySelectsDetectedNonemptyTargets() {
        let suite = "guard-presentation-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuardStore(defaults: defaults, watchNetwork: false, notificationsEnabled: false)
        store.cleanupPlan = CleanupPlan(targets: [
            CleanupTarget(path: "/test/cache", label: "cache", kind: "cache", sizeBytes: 10, fileCount: 1, exists: true),
            CleanupTarget(path: "/test/empty", label: "empty", kind: "cache", exists: true),
            CleanupTarget(path: "/test/missing", label: "missing", kind: "cache")
        ])
        XCTAssertTrue(store.selectedCleanupTargets.isEmpty)
        store.cleanupSelection = ["/test/cache", "/test/empty", "/test/missing", "/unscanned"]
        XCTAssertEqual(store.selectedCleanupTargets.map(\.path), ["/test/cache"])
        store.cleanupSelection.remove("/test/cache")
        XCTAssertTrue(store.selectedCleanupTargets.isEmpty)
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
        store.sandbox.phase = .networkPaused
        await store.check()

        XCTAssertEqual(store.title, "网络已关闭")
        XCTAssertEqual(store.symbol, "wifi.slash")
        let callCount = await calls.count()
        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(store.monitoring)
    }

    @MainActor func testSandboxConfigurationPersistsWithoutProxyPassword() throws {
        let suite = "guard-sandbox-secret-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SandboxSession(preferences: defaults)

        session.configuration.upstream.username = "routekeeper"
        session.configuration.upstream.password = "do-not-persist"

        let data = try XCTUnwrap(defaults.data(forKey: "routekeeper-isolation-configuration-v1"))
        let persisted = try JSONDecoder().decode(IsolationConfiguration.self, from: data)
        XCTAssertEqual(persisted.upstream.username, "routekeeper")
        XCTAssertEqual(persisted.upstream.password, "")
        let restored = SandboxSession(preferences: defaults)
        XCTAssertEqual(restored.configuration.upstream.password, "")
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
        let sandbox = SandboxSession(preferences: defaults, sessionsRoot: sessionsRoot)
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
        XCTAssertNil(defaults.object(forKey: "guard-settings-v1"))
        XCTAssertNil(defaults.object(forKey: "routekeeper-test-private-value"))
        XCTAssertNil(defaults.object(forKey: L10n.languageKey))
        XCTAssertEqual(defaults.string(forKey: "routekeeper.disclaimer-accepted-version"), "2026-10-21.2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedSession.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unownedDirectory.path))
    }

    func testSandboxEnvironmentCarriesCanonicalIsolationPaths() {
        let root = URL(fileURLWithPath: "/private/tmp/routekeeper-environment-test", isDirectory: true)
        let layout = IsolationSessionLayout(root: root)
        let paths = IsolationResolvedPaths(
            originalProject: URL(fileURLWithPath: "/Users/example/Project", isDirectory: true),
            exchange: URL(fileURLWithPath: "/private/tmp/routekeeper-exchange", isDirectory: true),
            layout: layout
        )
        let environment = SandboxSession.baseEnvironment(
            configuration: IsolationConfiguration(
                projectPath: paths.originalProject.path,
                exchangePath: paths.exchange.path,
                timezoneIdentifier: "Asia/Shanghai"
            ),
            paths: paths,
            relayEnvironment: ["HTTPS_PROXY": "http://127.0.0.1:43123"]
        )

        XCTAssertEqual(environment["ISOLATION_WORKSPACE"], layout.workspace.path)
        XCTAssertEqual(environment["ISOLATION_EXCHANGE"], paths.exchange.path)
        XCTAssertEqual(environment["ISOLATION_ORIGINAL"], paths.originalProject.path)
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
