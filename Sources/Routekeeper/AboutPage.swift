import AppKit
import GuardCore
import SwiftUI

struct AboutPage: View {
    let onQuit: () -> Void

    @AppStorage("routekeeper.disclaimer-accepted-version") private var acceptedVersion = ""
    @State private var showFullNotice = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.12"
    }

    private var noticeAccepted: Bool {
        acceptedVersion == DisclaimerDocument.currentVersion
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("Routekeeper")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                    Text(text("网络检查、监控与 Claude 环境边界辅助工具",
                              "Network inspection, monitoring and Claude environment boundaries"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(text("版本 \(version)", "Version \(version)"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .cardSurface(corner: 20)

            VStack(alignment: .leading, spacing: 12) {
                DisclaimerScopeNotice()
                AppHairline()
                HStack(spacing: 10) {
                    Label(
                        noticeAccepted
                            ? text("已同意当前版本", "Current notice accepted")
                            : text("尚未同意当前版本", "Current notice not accepted"),
                        systemImage: noticeAccepted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(noticeAccepted ? Color.green : Color.orange)

                    Spacer()

                    if !noticeAccepted {
                        Button(text("同意", "Agree")) {
                            acceptedVersion = DisclaimerDocument.currentVersion
                        }
                        .routekeeperProminentButton()
                        Button(text("退出应用", "Quit"), role: .destructive, action: onQuit)
                    }
                }
            }
            .padding(20)
            .cardSurface(corner: 18)

            DisclosureGroup(isExpanded: $showFullNotice) {
                VStack(alignment: .leading, spacing: 16) {
                    AppHairline()
                    DisclaimerBody()
                }
                .padding(.top, 12)
            } label: {
                HStack(spacing: 10) {
                    Label(text("完整免责声明", "Full disclaimer"), systemImage: "doc.text")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(text("使用限制、隐私、责任范围", "Usage, privacy and liability"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .cardSurface(corner: 18)
            .accessibilityIdentifier("about-disclaimer")
        }
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityIdentifier("settings-about-page")
    }
}
