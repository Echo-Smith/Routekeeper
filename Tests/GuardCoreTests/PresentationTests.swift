import XCTest
import AppKit
@testable import GuardCore
@testable import Routekeeper

final class PresentationTests: XCTestCase {
    @MainActor func testPanelCloseKeepsAppAliveAndReopenRestoresDock() async {
        let app = NSApplication.shared
        let originalPolicy = app.activationPolicy()
        let delegate = RoutekeeperAppDelegate()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        defer {
            window.orderOut(nil)
            app.setActivationPolicy(originalPolicy)
            _ = AppNavigationRequest.consumePendingPage()
        }
        delegate.attach(window, openWindow: { XCTFail("Existing panel should be reused") })
        window.close()
        XCTAssertEqual(app.activationPolicy(), .accessory)
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
