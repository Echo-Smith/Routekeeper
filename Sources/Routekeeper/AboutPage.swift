import AppKit
import SwiftUI
import GuardCore

struct AboutPage: View {
    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.11"
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)

                VStack(spacing: 5) {
                    Text("Routekeeper")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                    Text(text("网络检查与监控辅助工具", "Network inspection and monitoring helper"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(text("版本 \(version)", "Version \(version)"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        .padding(28)
        .cardSurface(corner: 20)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityIdentifier("settings-about-page")
    }
}
