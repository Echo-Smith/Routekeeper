import AppKit
import SwiftUI

let appAccent = Color(red: 0, green: 0.443, blue: 0.89)

enum AppSurfaceTone {
    case primary
    case secondary
    case inset
}

private struct AppSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let tone: AppSurfaceTone
    let corner: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content
            .background(background, in: shape)
            .overlay {
                if tone != .inset {
                    shape.strokeBorder(
                        Color(nsColor: .separatorColor)
                            .opacity(colorScheme == .dark ? 0.46 : 0.58),
                        lineWidth: 0.5
                    )
                }
            }
    }

    private var background: Color {
        switch tone {
        case .primary:
            return Color(nsColor: .textBackgroundColor)
        case .secondary:
            return Color(nsColor: .controlBackgroundColor)
        case .inset:
            return Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.035)
        }
    }
}

extension View {
    @ViewBuilder
    func routekeeperScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func routekeeperScaledNavigationTitle() -> some View {
        if #available(macOS 26.0, *) {
            self.toolbar(removing: .title)
        } else {
            self
        }
    }

    func appSurface(_ tone: AppSurfaceTone = .primary, corner: CGFloat = 14) -> some View {
        modifier(AppSurfaceModifier(tone: tone, corner: corner))
    }
}

struct BrandGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.clear.tint(.blue.opacity(0.58)), in: shape)
        } else {
            content.background(Color.blue, in: shape)
        }
    }
}

struct AppSectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .routekeeperFont(.headline)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AppHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
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

    func routekeeperGlassCapsule(tint: Color = .clear) -> some View {
        modifier(RoutekeeperCapsuleModifier(tint: tint))
    }
}

private struct RoutekeeperProminentButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let styledContent = content
            .routekeeperFont(.callout, weight: .semibold)
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
            .routekeeperFont(.callout, weight: .medium)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 9))
    }
}

private struct RoutekeeperCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(tint), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }
}
