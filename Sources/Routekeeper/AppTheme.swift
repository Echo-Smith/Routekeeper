import AppKit
import GuardCore
import SwiftUI

let appAccent = Color(red: 0, green: 0.443, blue: 0.89)
let appStatusSuccess = Color.green
let appStatusWarning = Color.orange
let appStatusFailure = Color.red

enum AppActionTone {
    case primary
    case success
    case warning
    case danger
    case neutral

    var color: Color {
        switch self {
        case .primary: return appAccent
        case .success: return appStatusSuccess
        case .warning: return appStatusWarning
        case .danger: return appStatusFailure
        case .neutral: return Color(nsColor: .secondaryLabelColor)
        }
    }
}

extension CheckLevel {
    var routekeeperStatusColor: Color {
        switch self {
        case .passed: return appStatusSuccess
        case .failed: return appStatusFailure
        case .warning, .unknown: return appStatusWarning
        }
    }
}

extension EgressAssessmentLevel {
    var routekeeperStatusColor: Color {
        switch self {
        case .clear: return appStatusSuccess
        case .attention: return appStatusFailure
        case .insufficient: return appStatusWarning
        }
    }
}

extension GatewayVerificationStatus {
    var routekeeperStatusColor: Color {
        switch self {
        case .verified: return appStatusSuccess
        case .failed, .expired: return appStatusFailure
        case .unverified, .needsNodeFailureTest, .needsClientExitTest, .needsRecovery:
            return appStatusWarning
        }
    }
}

enum AppSurfaceTone {
    case primary
    case secondary
    case inset
}

enum AppCornerRadius {
    static let card: CGFloat = 14
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
                        colorScheme == .dark
                            ? Color(nsColor: .separatorColor).opacity(0.46)
                            : Color(nsColor: .tertiaryLabelColor).opacity(0.55),
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
    func appSurface(
        _ tone: AppSurfaceTone = .primary,
        corner: CGFloat = AppCornerRadius.card
    ) -> some View {
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
    func routekeeperProminentButton(_ tone: AppActionTone = .primary) -> some View {
        modifier(RoutekeeperProminentButtonModifier(tone: tone))
    }

    func routekeeperSecondaryButton(_ tone: AppActionTone = .neutral) -> some View {
        modifier(RoutekeeperSecondaryButtonModifier(tone: tone))
    }

    func routekeeperGlassCapsule(tint: Color = .clear) -> some View {
        modifier(RoutekeeperCapsuleModifier(tint: tint))
    }
}

private struct RoutekeeperProminentButtonModifier: ViewModifier {
    let tone: AppActionTone

    @ViewBuilder
    func body(content: Content) -> some View {
        let styledContent = content
            .routekeeperFont(.callout, weight: .semibold)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .tint(tone.color)
        if #available(macOS 26.0, *) {
            styledContent.buttonStyle(.glassProminent)
        } else {
            styledContent.buttonStyle(.borderedProminent)
        }
    }
}

private struct RoutekeeperSecondaryButtonModifier: ViewModifier {
    let tone: AppActionTone

    func body(content: Content) -> some View {
        content
            .routekeeperFont(.callout, weight: .medium)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 9))
            .tint(tone.color)
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
