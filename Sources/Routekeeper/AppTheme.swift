import AppKit
import SwiftUI

let appAccent = Color(red: 0, green: 0.443, blue: 0.89)

struct AppPanelRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 116, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(.vertical, 8)
    }
}

struct AppHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }
}

extension View {
    func routekeeperProminentButton() -> some View {
        modifier(RoutekeeperProminentButtonModifier())
    }

    func routekeeperSecondaryButton() -> some View {
        modifier(RoutekeeperSecondaryButtonModifier())
    }

    func routekeeperGlassCapsule() -> some View {
        modifier(RoutekeeperCapsuleModifier())
    }

    func routekeeperSidebarSelection(selected: Bool, cornerRadius: CGFloat = 9) -> some View {
        modifier(RoutekeeperSidebarSelectionModifier(selected: selected, cornerRadius: cornerRadius))
    }
}

private struct RoutekeeperProminentButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let styledContent = content
            .font(.system(size: 14, weight: .semibold))
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 10))
        if #available(macOS 26.0, *) {
            styledContent.buttonStyle(.glassProminent)
        } else {
            styledContent.buttonStyle(.borderedProminent)
        }
    }
}

private struct RoutekeeperSecondaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13.5, weight: .medium))
            .controlSize(.large)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 9))
    }
}

private struct RoutekeeperCapsuleModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }
}

private struct RoutekeeperSidebarSelectionModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            if selected {
                content.glassEffect(
                    .regular.tint(appAccent.opacity(0.18)).interactive(),
                    in: shape
                )
            } else {
                content
            }
        } else {
            content.background(
                shape.fill(selected ? AnyShapeStyle(appAccent.opacity(0.10)) : AnyShapeStyle(Color.clear))
            )
        }
    }
}
