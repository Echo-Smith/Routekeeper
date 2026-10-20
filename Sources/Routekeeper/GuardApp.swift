import SwiftUI
import GuardCore
import AppKit

extension Notification.Name {
    static let routekeeperShowChecks = Notification.Name("RoutekeeperShowChecks")
}

@MainActor
enum AppNavigationRequest {
    private static var pendingPage: GuardPage?

    static func request(_ page: GuardPage) {
        pendingPage = page
        NotificationCenter.default.post(name: .routekeeperShowChecks, object: nil)
    }

    static func consumePendingPage() -> GuardPage? {
        defer { pendingPage = nil }
        return pendingPage
    }
}

@MainActor
final class RoutekeeperAppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    private var attachedWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshDockIcon()
    }

    private func refreshDockIcon() {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              let url = Bundle.main.url(forResource: name, withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        // Load the bundled asset directly instead of relying on Launch Services' cached icon.
        NSApp.applicationIconImage = icon
        NSApp.dockTile.display()
    }

    func attach(_ window: NSWindow, openWindow: @escaping () -> Void) {
        if attachedWindow !== window {
            if let attachedWindow {
                NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: attachedWindow)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(mainWindowWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
        attachedWindow = window
        window.isReleasedWhenClosed = false
        openMainWindow = openWindow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        // Keep MenuBarExtra and monitoring alive while removing the Dock entry.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showChecksPanel()
        return true
    }

    func showChecksPanel() {
        NSApp.setActivationPolicy(.regular)
        refreshDockIcon()
        AppNavigationRequest.request(.inspection)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let window = self.mainWindow {
                self.present(window)
            } else {
                self.openMainWindow?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, let window = self.mainWindow else { return }
                    self.present(window)
                }
            }
        }
    }

    private var mainWindow: NSWindow? {
        // A closed window may report canBecomeMain == false until shown again.
        if let attachedWindow { return attachedWindow }
        return NSApp.windows.first(where: { $0.title == "Routekeeper" && $0.canBecomeMain })
            ?? NSApp.windows.first(where: { $0.identifier?.rawValue.localizedCaseInsensitiveContains("main") == true })
            ?? NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) })
    }

    private func present(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
enum Entry {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--egress-audit") {
            Task.detached { await runEgressAudit(args) }
            dispatchMain()
        }
        if args.contains("--self-check") {
            Task.detached { await runDiagnostics(args) }
            dispatchMain()
        }
        GuardApp.main()
    }
    private static func runDiagnostics(_ args: [String]) async {
            var settings = GuardSettings()
            if let i = args.firstIndex(of: "--target"), args.indices.contains(i + 1) { settings.targetIP = args[i + 1] }
            if let i = args.firstIndex(of: "--alternate-target"), args.indices.contains(i + 1) { settings.alternateTargetIP = args[i + 1] }
            if let i = args.firstIndex(of: "--proxy-client"), args.indices.contains(i + 1) {
                guard let client = ProxyClient(rawValue: args[i + 1]) else { fputs("Invalid proxy client.\n", stderr); exit(1) }
                settings.proxyClient = client
            }
            if let i = args.firstIndex(of: "--interval"), args.indices.contains(i + 1) {
                guard let interval = Double(args[i + 1]), interval.isFinite, (1...300).contains(interval) else { fputs("Interval must be 1–300 seconds.\n", stderr); exit(1) }
                settings.pollInterval = interval
            }
            settings.dnsProbeEnabled = !args.contains("--skip-dns")
            settings.udpProbeEnabled = !args.contains("--skip-udp")
            if args.contains("--desktop-only") { settings.protectCode = false }
            if args.contains("--code-only") { settings.protectDesktop = false }
            let result = await Diagnostics.run(settings: settings)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(result)
                if let i = args.firstIndex(of: "--output"), args.indices.contains(i + 1) { try data.write(to: URL(fileURLWithPath: args[i + 1]), options: .atomic) }
                else { FileHandle.standardOutput.write(data); print("") }
                exit(result.ready ? 0 : 2)
            } catch { fputs("Diagnostic report could not be written.\n", stderr); exit(1) }
    }

    private static func runEgressAudit(_ args: [String]) async {
        var settings = GuardSettings()
        if let i = args.firstIndex(of: "--target"), args.indices.contains(i + 1) { settings.targetIP = args[i + 1] }
        if let i = args.firstIndex(of: "--alternate-target"), args.indices.contains(i + 1) {
            settings.alternateTargetIP = args[i + 1]
        }
        settings.protectDesktop = false
        settings.protectCode = false
        settings.dnsProbeEnabled = false
        settings.udpProbeEnabled = false
        let snapshot = await Diagnostics.run(settings: settings)
        let report = await EgressAudit.run(
            snapshot: snapshot,
            includeIntelligence: args.contains("--include-intelligence")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(report)
            if let i = args.firstIndex(of: "--output"), args.indices.contains(i + 1) {
                try data.write(to: URL(fileURLWithPath: args[i + 1]), options: .atomic)
            } else {
                FileHandle.standardOutput.write(data)
                print("")
            }
            exit(0)
        } catch {
            fputs("Egress report could not be written.\n", stderr)
            exit(1)
        }
    }
}

@MainActor
struct GuardApp: App {
    @NSApplicationDelegateAdaptor(RoutekeeperAppDelegate.self) private var appDelegate
    @State private var store = GuardStore()
    var body: some Scene {
        Window("Routekeeper", id: "main") {
            Dashboard(store: store)
                .frame(minWidth: 920, minHeight: 600)
                .background(WindowCommandBridge(delegate: appDelegate))
                .task {
                    if store.snapshot == nil { await store.check() }
                    store.startEgressAuditAutomation()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("menu.about")) { NSApplication.shared.orderFrontStandardAboutPanel(options: [:]) }
            }
            CommandGroup(replacing: .appTermination) {
                Button(L("menu.quit")) { confirmQuit(store) }.keyboardShortcut("q")
            }
        }
        MenuBarExtra("Routekeeper", systemImage: store.symbol) {
            GuardMenu(store: store, appDelegate: appDelegate)
        }
    }
}

@MainActor
func confirmQuit(_ store: GuardStore) {
    if store.monitoring {
        let alert = NSAlert()
        alert.messageText = "退出后将停止监控"
        alert.informativeText = "Claude 和代理客户端会保持当前状态。已独立启用的系统过滤器会继续生效，需在高级网络保护或系统设置中关闭。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "停止监控并退出")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
    }
    store.stop(); NSApplication.shared.terminate(nil)
}

struct GuardMenu: View {
    @Bindable var store: GuardStore
    let appDelegate: RoutekeeperAppDelegate
    var body: some View {
        Text(store.title)
        Text(L10n.resolvedEnglish
             ? "Target: \(store.settings.targetIP.isEmpty ? "not set" : store.settings.targetIP)"
             : "目标：\(store.settings.targetIP.isEmpty ? "尚未设置" : store.settings.targetIP)")
        Divider()
        Button(L("menu.openPanel")) {
            appDelegate.showChecksPanel()
        }
        if store.monitoring { Button(L("menu.stopMonitor")) { store.stop() } }
        else { Button(L("menu.runCheck")) { Task { await store.check() } }.disabled(store.checking) }
        Divider()
        Button(L("menu.quitShort")) { confirmQuit(store) }
    }
}

private struct WindowCommandBridge: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow
    let delegate: RoutekeeperAppDelegate

    func makeNSView(context: Context) -> NSView {
        let view = WindowProbeView()
        view.onWindowChange = { [weak delegate, openWindow] window in
            guard let window, let delegate else { return }
            configureWindowChrome(window)
            delegate.attach(window, openWindow: { openWindow(id: "main") })
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        configureWindowChrome(window)
        delegate.attach(window, openWindow: { openWindow(id: "main") })
    }
}

private final class WindowProbeView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

@MainActor
private func configureWindowChrome(_ window: NSWindow) {
    window.styleMask.insert(.fullSizeContentView)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = true
}
