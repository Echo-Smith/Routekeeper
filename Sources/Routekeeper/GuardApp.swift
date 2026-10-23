import SwiftUI
import GuardCore
import AppKit

extension Notification.Name {
    static let routekeeperShowChecks = Notification.Name("RoutekeeperShowChecks")
}

@MainActor
enum AppNavigationRequest {
    private static var pendingPage: GuardPage?
    private static var pendingSettings = false

    static func requestSettings() {
        pendingPage = nil
        pendingSettings = true
        NotificationCenter.default.post(name: .routekeeperShowChecks, object: nil)
    }

    static func consumeSettingsRequest() -> Bool {
        defer { pendingSettings = false }
        return pendingSettings
    }

    static func request(_ page: GuardPage) {
        pendingSettings = false
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
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var statusRefreshTask: Task<Void, Never>?
    private var statusPopoverOutsideMonitor: Any?
    private var displayedStatusSymbol: String?
    private var statusButtonView: StatusItemButtonView?
    private weak var store: GuardStore?

    var isStatusItemConfigured: Bool {
        statusButtonView?.image != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshDockIcon()
    }

    func configureStatusItem(store: GuardStore) {
        guard self.store !== store else { return }
        self.store = store

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.toolTip = "Routekeeper"
            let buttonView = StatusItemButtonView()
            buttonView.onPrimaryClick = { [weak self] in
                self?.handleStatusItemPrimaryClick()
            }
            buttonView.onContextClick = { [weak self] in
                self?.showStatusPopover()
            }
            item.button?.addSubview(buttonView)
            buttonView.frame = item.button?.bounds ?? .zero
            buttonView.autoresizingMask = [.width, .height]
            statusButtonView = buttonView
            statusItem = item
        }

        if statusPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let controller = NSHostingController(rootView: GuardMenu(store: store, appDelegate: self))
            if #available(macOS 13.0, *) {
                controller.sizingOptions = [.preferredContentSize]
            }
            popover.contentViewController = controller
            popover.contentSize = controller.preferredContentSize
            statusPopover = popover
        }

        refreshStatusItem()
        statusRefreshTask?.cancel()
        statusRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshStatusItem()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        removeStatusPopoverOutsideMonitor()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusButtonView = nil
        statusItem = nil
        statusPopover = nil
    }

    private func handleStatusItemPrimaryClick() {
        guard let popover = statusPopover else { return }
        if popover.isShown {
            closeStatusPopover()
        } else {
            showStatusPopover()
        }
    }

    private func showStatusPopover() {
        guard let button = statusItem?.button, let popover = statusPopover, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installStatusPopoverOutsideMonitor()
    }

    func closeStatusPopover() {
        statusPopover?.performClose(nil)
        removeStatusPopoverOutsideMonitor()
    }

    private func installStatusPopoverOutsideMonitor() {
        removeStatusPopoverOutsideMonitor()
        statusPopoverOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.statusPopover?.isShown == true else { return }
            let mouseLocation = NSEvent.mouseLocation
            if let button = self.statusItem?.button,
               let window = button.window,
               window.convertToScreen(button.convert(button.bounds, to: nil)).contains(mouseLocation) {
                return
            }
            if let popoverWindow = self.statusPopover?.contentViewController?.view.window,
               popoverWindow.frame.contains(mouseLocation) {
                return
            }
            self.closeStatusPopover()
        }
    }

    private func removeStatusPopoverOutsideMonitor() {
        if let statusPopoverOutsideMonitor {
            NSEvent.removeMonitor(statusPopoverOutsideMonitor)
            self.statusPopoverOutsideMonitor = nil
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button, let buttonView = statusButtonView, let store else { return }
        let title = store.title
        if displayedStatusSymbol != store.symbol {
            displayedStatusSymbol = store.symbol
            let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let image = NSImage(
                systemSymbolName: store.symbol,
                accessibilityDescription: "Routekeeper · \(title)"
            )?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            buttonView.image = image
            button.setAccessibilityLabel("Routekeeper")
        }
        button.toolTip = "Routekeeper · \(title)"
        button.setAccessibilityValue(title)
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
        // Keep the explicit status item and monitoring alive while removing the Dock entry.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showChecksPanel()
        return true
    }

    func showChecksPanel() {
        showPanel(page: .inspection)
    }

    func showSandboxPanel() {
        showPanel(page: .sandbox)
    }

    func showStandardAboutPanel() {
        closeStatusPopover()
        let credits = NSAttributedString(
            string: L10n.resolvedEnglish
                ? "Network inspection, monitoring and Claude environment boundaries.\nLocal checks do not alter server-side records or guarantee anonymity."
                : "网络体检、监控与 Claude 环境边界辅助工具。\n本机检查不会更改服务端记录，也不保证匿名性。",
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .callout),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func showSettingsPanel() {
        AppNavigationRequest.requestSettings()
        showPanel(page: nil)
    }

    private func showPanel(page: GuardPage?) {
        statusPopover?.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        refreshDockIcon()
        if let page { AppNavigationRequest.request(page) }
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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Routekeeper", id: "main") {
            Dashboard(store: store)
                .frame(minWidth: 920, minHeight: 600)
                .background(WindowCommandBridge(delegate: appDelegate))
                .task {
                    appDelegate.configureStatusItem(store: store)
                    if store.snapshot == nil { await store.check() }
                    store.startEgressAuditAutomation()
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.resolvedEnglish ? "Settings…" : "设置…") {
                    appDelegate.showSettingsPanel()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(replacing: .appInfo) {
                Button(L("menu.about")) { appDelegate.showStandardAboutPanel() }
            }
            CommandGroup(replacing: .appTermination) {
                Button(L("menu.quit")) { confirmQuit(store) }.keyboardShortcut("q")
            }
            CommandGroup(replacing: .help) {
                Button(L10n.resolvedEnglish ? "Routekeeper Help" : "Routekeeper 帮助") {
                    RoutekeeperHelpNavigation.request(.quickStart)
                    openWindow(id: "routekeeper-help")
                }
                .keyboardShortcut("?", modifiers: .command)
                Button(L10n.resolvedEnglish ? "Experimental Sandbox Help" : "实验性沙箱帮助") {
                    RoutekeeperHelpNavigation.request(.sandboxOverview)
                    openWindow(id: "routekeeper-help")
                }
            }
            SidebarCommands()
        }

        Window(L10n.resolvedEnglish ? "Routekeeper Help" : "Routekeeper 帮助", id: "routekeeper-help") {
            RoutekeeperHelpView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 650)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
func confirmQuit(_ store: GuardStore) {
    let sandboxActive = store.sandbox.phase.isActive
    if store.monitoring || sandboxActive {
        let alert = NSAlert()
        if sandboxActive {
            alert.messageText = "退出后将结束沙箱会话"
            alert.informativeText = "Routekeeper 会先终止本次隔离的 Claude 进程并关闭本地中继。沙箱工作副本会保留，原项目不会被自动修改。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "结束沙箱并退出")
        } else {
            alert.messageText = "退出后将停止监控"
            alert.informativeText = "Claude 和代理客户端会保持当前状态。已独立启用的系统过滤器会继续生效，需在网络保护或系统设置中关闭。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "停止监控并退出")
        }
        guard alert.runModal() == .alertSecondButtonReturn else { return }
    }
    Task {
        await store.prepareForTermination()
        NSApplication.shared.terminate(nil)
    }
}

struct GuardMenu: View {
    @Bindable var store: GuardStore
    let appDelegate: RoutekeeperAppDelegate
    @FocusState private var primaryActionFocused: Bool
    @AppStorage(AppTextScale.storageKey) private var textScaleRaw = AppTextScale.standard.rawValue
    @State private var isQuitHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            primaryAction
                .focused($primaryActionFocused)
            summary
            if let event = store.events.first, event.isAttention {
                Label(event.message, systemImage: "exclamationmark.triangle.fill")
                    .routekeeperFont(.caption)
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AppHairline()
            bottomActions
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .defaultFocus($primaryActionFocused, true)
        .onExitCommand {
            appDelegate.closeStatusPopover()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                primaryActionFocused = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: store.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 30, height: 30)
                .background(
                    statusColor.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(store.title)
                    .routekeeperFont(.headline)
                Text(statusDetail)
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if store.policy.phase == .armed || store.sandbox.phase == .running {
                Text(L10n.resolvedEnglish ? "Active" : "运行中")
                    .routekeeperFont(.caption2, weight: .semibold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status-popover-header")
    }

    @ViewBuilder
    private var primaryAction: some View {
        if #available(macOS 26.0, *) {
            primaryActionButton
                .buttonStyle(.glassProminent)
        } else {
            primaryActionButton
                .buttonStyle(.borderedProminent)
        }
    }

    private var primaryActionButton: some View {
        Button {
            if store.settings.experimentalSandboxEnabled {
                appDelegate.showSandboxPanel()
            } else {
                appDelegate.showChecksPanel()
            }
        } label: {
            Label(
                store.settings.experimentalSandboxEnabled
                    ? (L10n.resolvedEnglish ? "Open sandbox" : "打开沙箱")
                    : (L10n.resolvedEnglish ? "Open network protection" : "打开网络保护"),
                systemImage: store.settings.experimentalSandboxEnabled ? "lock.shield" : "rectangle.inset.filled"
            )
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityIdentifier("status-popover-primary")
    }

    private var summary: some View {
        VStack(spacing: 0) {
            ForEach(Array(summaryRows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.055))
                        .frame(height: 0.5)
                        .padding(.leading, 8)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 72 * textScale, alignment: .leading)
                    Text(row.value)
                        .routekeeperFont(.caption, weight: .medium)
                        .foregroundStyle(row.isAttention ? Color.orange : Color.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if row.isAttention {
                        Image(systemName: "exclamationmark.circle.fill")
                            .routekeeperFont(.caption2)
                            .foregroundStyle(Color.orange)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityIdentifier("status-popover-summary")
    }

    private var secondaryActions: some View {
        VStack(spacing: 2) {
            if store.settings.experimentalSandboxEnabled {
                if store.sandbox.externalActionsPendingCount > 0 {
                    StatusMenuActionButton(
                        title: L10n.resolvedEnglish
                            ? "Review \(store.sandbox.externalActionsPendingCount) handoff request(s)"
                            : "审核 \(store.sandbox.externalActionsPendingCount) 个外部操作",
                        systemImage: "person.badge.key"
                    ) {
                        appDelegate.showSandboxPanel()
                    }
                    .accessibilityIdentifier("status-popover-review")
                }

                if store.sandbox.phase == .running {
                    StatusMenuActionButton(
                        title: L10n.resolvedEnglish ? "Turn sandbox network off" : "关闭沙箱网络",
                        systemImage: "wifi.slash"
                    ) {
                        store.pauseSandboxNetwork()
                    }
                    .accessibilityIdentifier("status-popover-network")
                } else if store.sandbox.phase == .networkPaused {
                    StatusMenuActionButton(
                        title: L10n.resolvedEnglish ? "Turn sandbox network on" : "恢复沙箱网络",
                        systemImage: "wifi"
                    ) {
                        Task { await store.resumeSandboxNetwork() }
                    }
                    .accessibilityIdentifier("status-popover-network")
                }

                if store.sandbox.phase.isActive {
                    StatusMenuActionButton(
                        title: L10n.resolvedEnglish ? "End sandbox session" : "结束沙箱会话",
                        systemImage: "stop.circle"
                    ) {
                        Task { await store.endSandboxSession() }
                    }
                    .accessibilityIdentifier("status-popover-end-sandbox")
                }
            } else if store.monitoring {
                StatusMenuActionButton(
                    title: L("menu.stopMonitor"),
                    systemImage: "pause.circle"
                ) {
                    store.stop()
                }
                .accessibilityIdentifier("status-popover-stop-monitor")
            } else {
                StatusMenuActionButton(
                    title: L("menu.runCheck"),
                    systemImage: "arrow.clockwise",
                    isEnabled: !store.checking
                ) {
                    Task { await store.check() }
                }
                .accessibilityIdentifier("status-popover-run-check")
            }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 8) {
            secondaryActions
            Spacer(minLength: 8)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 20)
            Button {
                confirmQuit(store)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { isQuitHovered = $0 }
            .background(
                isQuitHovered ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .help(L("menu.quitShort"))
            .accessibilityLabel(L("menu.quitShort"))
            .accessibilityIdentifier("status-popover-quit")
        }
        .padding(.top, 4)
    }

    private var statusColor: Color {
        if store.policy.phase == .incident || store.sandbox.phase == .failed {
            return .orange
        }
        if store.sandbox.phase == .networkPaused || store.sandbox.phase == .preparing
            || store.sandbox.phase == .checking {
            return .orange
        }
        if store.policy.phase == .armed || store.sandbox.phase == .running {
            return appAccent
        }
        return .secondary
    }

    private var textScale: CGFloat {
        (AppTextScale(rawValue: textScaleRaw) ?? .standard).multiplier
    }

    private var statusDetail: String {
        if store.settings.experimentalSandboxEnabled {
            return store.sandbox.message
        }
        if store.monitoring {
            return L10n.resolvedEnglish
                ? "Monitoring the selected Claude processes."
                : "正在监控所选 Claude 进程。"
        }
        if store.checking {
            return L10n.resolvedEnglish ? "Network check in progress." : "正在运行网络体检。"
        }
        return store.notice
    }

    private var summaryRows: [MenuSummaryRow] {
        if store.settings.experimentalSandboxEnabled {
            return sandboxSummaryRows
        }
        return standardSummaryRows
    }

    private var sandboxSummaryRows: [MenuSummaryRow] {
        let session = store.sandbox
        let passed = session.checks.filter(\.passed).count
        let checkValue: String
        let checkAttention: Bool
        if session.checks.isEmpty {
            checkValue = L10n.resolvedEnglish ? "Not verified" : "尚未验证"
            checkAttention = session.phase == .failed
        } else {
            checkValue = L10n.resolvedEnglish
                ? "\(passed)/\(session.checks.count) passed"
                : "\(passed)/\(session.checks.count) 项通过"
            checkAttention = passed != session.checks.count
        }
        return [
            .init(
                label: L10n.resolvedEnglish ? "Network" : "网络",
                value: sandboxNetworkSummary,
                isAttention: session.phase == .networkPaused
            ),
            .init(
                label: L10n.resolvedEnglish ? "Exit" : "出口",
                value: sandboxExitSummary,
                isAttention: !session.expectedExits.hasAny
            ),
            .init(
                label: L10n.resolvedEnglish ? "Approval" : "待授权",
                value: store.sandbox.externalActionsPendingCount == 0
                    ? (L10n.resolvedEnglish ? "None" : "无")
                    : (L10n.resolvedEnglish
                        ? "\(store.sandbox.externalActionsPendingCount) pending"
                        : "\(store.sandbox.externalActionsPendingCount) 项待确认"),
                isAttention: store.sandbox.externalActionsPendingCount > 0
            ),
            .init(
                label: L10n.resolvedEnglish ? "Checks" : "检查",
                value: checkValue,
                isAttention: checkAttention
            )
        ]
    }

    private var standardSummaryRows: [MenuSummaryRow] {
        let exit = store.settings.targetIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastCheck: String
        if let snapshot = store.snapshot {
            lastCheck = snapshot.checkedAt.formatted(date: .omitted, time: .shortened)
        } else {
            lastCheck = L10n.resolvedEnglish ? "Not run" : "尚未运行"
        }
        return [
            .init(
                label: L10n.resolvedEnglish ? "Exit" : "目标出口",
                value: exit.isEmpty ? (L10n.resolvedEnglish ? "Not set" : "尚未设置") : exit,
                isAttention: exit.isEmpty
            ),
            .init(
                label: L10n.resolvedEnglish ? "Last check" : "最近体检",
                value: lastCheck
            ),
            .init(
                label: L10n.resolvedEnglish ? "Monitor" : "监控",
                value: store.monitoring
                    ? (L10n.resolvedEnglish ? "On" : "已开启")
                    : (L10n.resolvedEnglish ? "Off" : "已关闭")
            )
        ]
    }

    private var sandboxNetworkSummary: String {
        let session = store.sandbox
        if session.phase == .running, session.networkEnabled {
            if let port = session.relayPort {
                return L10n.resolvedEnglish ? "On · relay \(port)" : "已开启 · 中继 \(port)"
            }
            return L10n.resolvedEnglish ? "On" : "已开启"
        }
        if session.phase == .networkPaused {
            return L10n.resolvedEnglish ? "Off" : "已关闭"
        }
        if session.phase == .preparing || session.phase == .checking {
            return L10n.resolvedEnglish ? "Verifying" : "验证中"
        }
        return L10n.resolvedEnglish ? "Not started" : "尚未启动"
    }

    private var sandboxProxySummary: String {
        guard let proxy = store.sandbox.detectedProxy else {
            return L10n.resolvedEnglish ? "Not detected" : "尚未检测"
        }
        return "\(proxy.protocolType.title) · \(proxy.host):\(proxy.port)"
    }

    private var sandboxExitSummary: String {
        let exits = store.sandbox.expectedExits
        let values = [
            exits.ipv4.map { "IPv4 \($0)" },
            exits.ipv6.map { "IPv6 \($0)" }
        ].compactMap { $0 }
        return values.isEmpty
            ? (L10n.resolvedEnglish ? "Not saved" : "尚未保存")
            : values.joined(separator: " · ")
    }
}

private struct MenuSummaryRow {
    let label: String
    let value: String
    var isAttention = false
}

private struct StatusMenuActionButton: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .routekeeperFont(.callout)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            isHovered = hovering && isEnabled
        }
        .background(
            isHovered ? Color.primary.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

@MainActor
private final class StatusItemButtonView: NSView {
    var onPrimaryClick: (() -> Void)?
    var onContextClick: (() -> Void)?
    var image: NSImage? {
        didSet {
            imageView.image = image
            needsDisplay = true
        }
    }

    private let imageView = NSImageView()
    private var isPressed = false {
        didSet {
            imageView.alphaValue = isPressed ? 0.55 : 1
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds.insetBy(dx: 3, dy: 3)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        onPrimaryClick?()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextClick?()
    }

    override func mouseExited(with event: NSEvent) {
        isPressed = false
    }

    override var acceptsFirstResponder: Bool { false }
}

private struct WindowCommandBridge: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow
    let delegate: RoutekeeperAppDelegate

    func makeNSView(context: Context) -> NSView {
        let view = WindowProbeView()
        view.onWindowChange = { [weak delegate, openWindow] window in
            guard let window, let delegate else { return }
            delegate.attach(window, openWindow: { openWindow(id: "main") })
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        delegate.attach(window, openWindow: { openWindow(id: "main") })
    }
}

private final class WindowProbeView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    private var fullScreenObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeFullScreenChanges()
        updateTitlebarSeparator()
        onWindowChange?(window)
    }

    override func layout() {
        super.layout()
        updateTitlebarSeparator()
    }

    deinit {
        removeFullScreenObservers()
    }

    private func observeFullScreenChanges() {
        removeFullScreenObservers()
        guard let window else { return }
        let center = NotificationCenter.default
        fullScreenObservers = [
            center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.updateTitlebarSeparator()
            },
            center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.updateTitlebarSeparator()
            }
        ]
    }

    private func removeFullScreenObservers() {
        let center = NotificationCenter.default
        fullScreenObservers.forEach(center.removeObserver)
        fullScreenObservers.removeAll()
    }

    private func updateTitlebarSeparator() {
        guard let window else { return }
        let style: NSTitlebarSeparatorStyle = window.styleMask.contains(.fullScreen)
            ? .none
            : .automatic
        if window.titlebarSeparatorStyle != style {
            window.titlebarSeparatorStyle = style
        }
    }
}
