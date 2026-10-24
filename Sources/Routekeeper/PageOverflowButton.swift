import AppKit
import SwiftUI

struct PageOverflowAction {
    let title: String
    let systemImage: String
    var isDisabled = false
    var isDestructive = false
    let action: () -> Void
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

struct PageOverflowMenu: NSViewRepresentable {
    let label: String
    let entries: [PageOverflowEntry]

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PageOverflowControl?, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    func makeNSView(context: Context) -> PageOverflowControl {
        PageOverflowControl()
    }

    func updateNSView(_ view: PageOverflowControl, context: Context) {
        view.configure(label: label, entries: entries)
    }
}

@MainActor
final class PageOverflowControl: NSControl {
    private var entries: [PageOverflowEntry] = []
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    private var pressResetTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 44, height: 44)
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circleRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let fillOpacity: CGFloat = isPressed ? 0.22 : (isHovering ? 0.15 : 0.10)

        NSColor.labelColor.withAlphaComponent(fillOpacity).setFill()
        NSBezierPath(ovalIn: circleRect).fill()
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(ovalIn: circleRect)
        border.lineWidth = 0.5
        border.stroke()

        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 16,
            weight: .semibold
        ).applying(
            NSImage.SymbolConfiguration(paletteColors: [.labelColor])
        )
        if let image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration) {
            let imageSize = image.size
            image.draw(
                in: NSRect(
                    x: (bounds.width - imageSize.width) / 2,
                    y: (bounds.height - imageSize.height) / 2,
                    width: imageSize.width,
                    height: imageSize.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        pressResetTask?.cancel()
        pressResetTask = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasInside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard wasInside, !entries.isEmpty else { return }
        pressResetTask?.cancel()
        pressResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard let self, !Task.isCancelled else { return }
            self.isPressed = false
            self.needsDisplay = true
            self.pressResetTask = nil
        }
        openMenu()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !entries.isEmpty else { return }
        openMenu()
    }

    override func accessibilityPerformPress() -> Bool {
        guard !entries.isEmpty else { return false }
        openMenu()
        return true
    }

    func configure(label: String, entries: [PageOverflowEntry]) {
        self.entries = entries
        toolTip = label
        setAccessibilityLabel(label)
        isEnabled = !entries.isEmpty
        needsDisplay = true
    }

    private func openMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .action(let action):
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(PageOverflowActionTarget.perform(_:)),
                    keyEquivalent: ""
                )
                item.target = PageOverflowActionTarget.shared
                item.representedObject = PageOverflowActionBox(action.action)
                item.isEnabled = !action.isDisabled
                item.image = NSImage(
                    systemSymbolName: action.systemImage,
                    accessibilityDescription: nil
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

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: bounds.minX, y: bounds.maxY + 6),
            in: self
        )
    }
}

private final class PageOverflowActionBox {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

@MainActor
private final class PageOverflowActionTarget: NSObject {
    static let shared = PageOverflowActionTarget()

    @objc func perform(_ sender: NSMenuItem) {
        (sender.representedObject as? PageOverflowActionBox)?.action()
    }
}
