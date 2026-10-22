import AppKit
import GuardCore
import SwiftUI

enum AppTextScale: String, CaseIterable, Identifiable {
    case standard
    case large
    case extraLarge

    static let storageKey = "routekeeper.text-scale-v1"

    var id: String { rawValue }

    var multiplier: CGFloat {
        switch self {
        case .standard: return 1
        case .large: return 1.2
        case .extraLarge: return 1.4
        }
    }

    var title: String {
        switch self {
        case .standard: return L10n.resolvedEnglish ? "Standard" : "标准"
        case .large: return L10n.resolvedEnglish ? "Large" : "较大"
        case .extraLarge: return L10n.resolvedEnglish ? "Largest" : "最大"
        }
    }
}

private struct RoutekeeperFontModifier: ViewModifier {
    @AppStorage(AppTextScale.storageKey) private var scaleRaw = AppTextScale.standard.rawValue

    let style: Font.TextStyle
    let design: Font.Design
    let weight: Font.Weight?
    let usesMonospacedDigits: Bool

    func body(content: Content) -> some View {
        let scale = AppTextScale(rawValue: scaleRaw) ?? .standard
        let pointSize = NSFont.preferredFont(forTextStyle: nsTextStyle).pointSize
            * scale.multiplier
        let base = Font.system(size: pointSize, weight: weight, design: design)
        let font = usesMonospacedDigits ? base.monospacedDigit() : base
        return content.font(font)
    }

    private var nsTextStyle: NSFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

extension View {
    func routekeeperFont(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        weight: Font.Weight? = nil,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(RoutekeeperFontModifier(
            style: style,
            design: design,
            weight: weight,
            usesMonospacedDigits: monospacedDigit
        ))
    }
}
