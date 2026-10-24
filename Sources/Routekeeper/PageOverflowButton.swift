import AppKit
import SwiftUI

struct PageOverflowAction {
    let id: UUID
    let title: String
    let systemImage: String
    var isDisabled = false
    var isDestructive = false
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        isDisabled: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        id = UUID()
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isDestructive = isDestructive
        self.action = action
    }
}

enum PageOverflowEntry {
    case action(PageOverflowAction)
    case separator
}

@MainActor
final class RoutekeeperToolbarCoordinator: ObservableObject {
    static let shared = RoutekeeperToolbarCoordinator()
    @Published private(set) var label = ""
    @Published private(set) var entries: [PageOverflowEntry] = []
    private var owner: UUID?

    func setInspection(owner: UUID, label: String, entries: [PageOverflowEntry]) {
        configure(owner: owner, label: label, entries: entries)
    }

    func setSandbox(owner: UUID, label: String, entries: [PageOverflowEntry]) {
        configure(owner: owner, label: label, entries: entries)
    }

    func clear(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        label = ""
        entries = []
    }

    private func configure(owner: UUID, label: String, entries: [PageOverflowEntry]) {
        self.owner = owner
        self.label = label
        self.entries = entries
    }
}

struct PageOverflowToolbarHost: NSViewRepresentable {
    @ObservedObject private var coordinator = RoutekeeperToolbarCoordinator.shared

    func makeNSView(context: Context) -> PageOverflowToolbarHostView {
        let view = PageOverflowToolbarHostView()
        view.coordinator = coordinator
        return view
    }

    func updateNSView(_ view: PageOverflowToolbarHostView, context: Context) {
        view.synchronize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: PageOverflowToolbarHostView?,
        context: Context
    ) -> CGSize? {
        .zero
    }
}

@MainActor
final class PageOverflowToolbarHostView: NSView {
    weak var coordinator: RoutekeeperToolbarCoordinator? {
        didSet { synchronize() }
    }

    private var toolbar: NSToolbar?
    private var toolbarObservation: NSKeyValueObservation?
    private var toolbarNotifications: [NSObjectProtocol] = []
    private var resynchronizeTask: Task<Void, Never>?
    private var isSynchronizing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowToolbar()
        synchronize()
    }

    func synchronize() {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }

        guard let toolbar, let coordinator else { return }
        PageOverflowToolbar.prepare(toolbar)
        let item = toolbar.items.first {
            $0.itemIdentifier == PageOverflowToolbar.identifier
        } as? NSMenuToolbarItem

        guard !coordinator.entries.isEmpty else {
            if let item {
                let index = toolbar.items.firstIndex { $0 === item }
                if let index {
                    toolbar.removeItem(at: index)
                }
            }
            return
        }

        let menuItem: NSMenuToolbarItem
        if let item {
            menuItem = item
        } else {
            toolbar.insertItem(
                withItemIdentifier: PageOverflowToolbar.identifier,
                at: toolbar.items.count
            )
            guard let inserted = toolbar.items.first(where: {
                $0.itemIdentifier == PageOverflowToolbar.identifier
            }) as? NSMenuToolbarItem else { return }
            menuItem = inserted
        }

        PageOverflowToolbar.configure(
            menuItem,
            label: coordinator.label,
            entries: coordinator.entries
        )
    }

    private func observeWindowToolbar() {
        toolbarObservation?.invalidate()
        toolbarObservation = nil
        removeToolbarObservers()
        guard let window else {
            toolbar = nil
            return
        }

        toolbar = window.toolbar
        toolbarObservation = window.observe(\.toolbar, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor in
                self?.toolbar = self?.window?.toolbar
                self?.synchronize()
            }
        }

        let center = NotificationCenter.default
        toolbarNotifications = [
            center.addObserver(
                forName: NSToolbar.didRemoveItemNotification,
                object: toolbar,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    guard let self,
                          let item = notification.userInfo?[NSToolbarUserInfoKey.itemKey] as? NSToolbarItem,
                          item.itemIdentifier == PageOverflowToolbar.identifier else { return }
                    self.scheduleResynchronize()
                }
            },
            center.addObserver(
                forName: NSToolbar.willAddItemNotification,
                object: toolbar,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    guard let self,
                          let item = notification.userInfo?[NSToolbarUserInfoKey.itemKey] as? NSMenuToolbarItem,
                          item.itemIdentifier == PageOverflowToolbar.identifier,
                          let coordinator = self.coordinator else { return }
                    PageOverflowToolbar.configure(
                        item,
                        label: coordinator.label,
                        entries: coordinator.entries
                    )
                }
            }
        ]
    }

    private func removeToolbarObservers() {
        toolbarNotifications.forEach(NotificationCenter.default.removeObserver)
        toolbarNotifications = []
    }

    private func scheduleResynchronize() {
        guard resynchronizeTask == nil else { return }
        resynchronizeTask = Task { @MainActor [weak self] in
            // SwiftUI can finish rebuilding its toolbar after AppKit posts the
            // removal notification. Reinsert once that update has settled.
            try? await Task.sleep(for: .milliseconds(40))
            guard let self, !Task.isCancelled else { return }
            self.resynchronizeTask = nil
            self.synchronize()
        }
    }
}

@MainActor
enum PageOverflowToolbar {
    static let identifier = NSToolbarItem.Identifier(
        "local.routekeeper.page-overflow"
    )

    static let delegate = PageOverflowToolbarDelegate()

    static func makeItem() -> NSMenuToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = "更多"
        item.paletteLabel = "更多"
        item.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: "更多"
        )
        item.showsIndicator = false
        item.visibilityPriority = .high
        return item
    }

    static func configure(
        _ item: NSMenuToolbarItem,
        label: String,
        entries: [PageOverflowEntry]
    ) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.menu = makeMenu(entries)
        item.isEnabled = !entries.isEmpty
    }

    static func makeMenu(_ entries: [PageOverflowEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .action(let action):
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(PageOverflowToolbarActionTarget.performPageOverflowAction(_:)),
                    keyEquivalent: ""
                )
                item.target = PageOverflowToolbarActionTarget.shared
                item.representedObject = action
                item.isEnabled = !action.isDisabled
                item.image = NSImage(
                    systemSymbolName: action.systemImage,
                    accessibilityDescription: action.title
                )
                if action.isDestructive {
                    item.attributedTitle = NSAttributedString(
                        string: action.title,
                        attributes: [.foregroundColor: NSColor.systemRed]
                    )
                }
                menu.addItem(item)
            }
        }
        return menu
    }
}

@MainActor
final class PageOverflowToolbarDelegate: NSObject, NSToolbarDelegate {
    static var previousDelegates: [NSToolbar.Identifier: NSToolbarDelegate] = [:]

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == PageOverflowToolbar.identifier {
            return PageOverflowToolbar.makeItem()
        }
        return previousDelegate(for: toolbar)?.toolbar?(
            toolbar,
            itemForItemIdentifier: itemIdentifier,
            willBeInsertedIntoToolbar: flag
        )
    }

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        var identifiers = previousDelegate(for: toolbar)?
            .toolbarDefaultItemIdentifiers?(toolbar)
            ?? toolbar.items.map(\.itemIdentifier)
        if !RoutekeeperToolbarCoordinator.shared.entries.isEmpty,
           !identifiers.contains(PageOverflowToolbar.identifier) {
            identifiers.append(PageOverflowToolbar.identifier)
        }
        return identifiers
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        var identifiers = previousDelegate(for: toolbar)?
            .toolbarAllowedItemIdentifiers?(toolbar)
            ?? toolbar.items.map(\.itemIdentifier)
        if !identifiers.contains(PageOverflowToolbar.identifier) {
            identifiers.append(PageOverflowToolbar.identifier)
        }
        return identifiers
    }

    private func previousDelegate(for toolbar: NSToolbar) -> NSToolbarDelegate? {
        Self.previousDelegates[toolbar.identifier]
    }
}

@MainActor
final class PageOverflowToolbarActionTarget: NSObject {
    static let shared = PageOverflowToolbarActionTarget()

    @objc func performPageOverflowAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? PageOverflowAction else { return }
        // AppKit runs menu actions inside menu tracking. Presenting SwiftUI
        // sheets or windows synchronously can be swallowed by that event loop.
        DispatchQueue.main.async {
            action.action()
        }
    }
}

extension PageOverflowToolbar {
    static func prepare(_ toolbar: NSToolbar) {
        guard toolbar.delegate !== delegate else { return }
        PageOverflowToolbarDelegate.previousDelegates[toolbar.identifier] = toolbar.delegate
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.delegate = delegate
    }
}
