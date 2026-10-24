import AppKit
import GuardCore
import SwiftUI

struct AppSettingsView: View {
    @Bindable var store: GuardStore
    @AppStorage(L10n.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppTextScale.storageKey) private var textScaleRaw = AppTextScale.standard.rawValue
    @State private var updateChecker = AppUpdateChecker()
    @State private var showDisclaimer = false
    @State private var showUpdateAlert = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    private var appearanceOverride: ColorScheme? {
        switch AppAppearance(rawValue: appearanceRaw) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var body: some View {
        Form {
            Section {
                Picker(L("general.language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                Picker(L("general.appearance"), selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Picker(text("文字大小", "Text size"), selection: $textScaleRaw) {
                    ForEach(AppTextScale.allCases) { scale in
                        Text(scale.title).tag(scale.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings-text-scale")
                LabeledContent {
                    HStack(spacing: 10) {
                        updateStatus
                        Button(text("检查更新", "Check for updates")) {
                            checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(updateChecker.state == .checking)
                        .accessibilityIdentifier("settings-check-updates")
                    }
                } label: {
                    Label(text("软件更新", "Software update"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text(text("通用", "General"))
            }

            Section {
                Button {
                    showDisclaimer = true
                } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    } label: {
                        Label(text("用途、隐私与免责声明", "Purpose, privacy and disclaimer"),
                              systemImage: "doc.text")
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings-open-disclaimer")
            } header: {
                Text(text("法律与隐私", "Legal & privacy"))
            }
        }
        .routekeeperFont(.body)
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(appearanceOverride)
        .id(store.languageRevision)
        .sheet(isPresented: $showDisclaimer) {
            LegalNoticeSheet()
        }
        .alert(text("发现新版本", "Update available"), isPresented: $showUpdateAlert) {
            if case let .available(_, packageURL) = updateChecker.state {
                Button(text("前往下载", "Download update")) {
                    NSWorkspace.shared.open(packageURL)
                }
            }
            Button(text("取消", "Cancel"), role: .cancel) {}
        } message: {
            if case let .available(version, _) = updateChecker.state {
                Text(text(
                    "当前版本 \(updateChecker.currentVersion)，GitHub 上的最新版本是 \(version)。",
                    "Current version \(updateChecker.currentVersion); the latest GitHub release is \(version)."
                ))
            }
        }
        .accessibilityIdentifier("settings-content")
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.state {
        case .idle:
            EmptyView()
        case .checking:
            Text(text("检查中…", "Checking…"))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
        case .upToDate:
            Text(text("没有新版本", "No update available"))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
        case let .available(version, _):
            Text(text("发现 \(version)", "Version \(version) available"))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text(text("检查失败", "Check failed"))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkForUpdates() {
        Task { @MainActor in
            await updateChecker.check()
            if case .available = updateChecker.state {
                showUpdateAlert = true
            }
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { L10n.language },
            set: { language in
                L10n.language = language
                if language == .system {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set(
                        [language == .en ? "en" : "zh-Hans"],
                        forKey: "AppleLanguages"
                    )
                }
                store.languageRevision += 1
                store.notifyLanguageChanged()
            }
        )
    }
}

private struct LegalNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(text("法律与隐私", "Legal & privacy"), systemImage: "doc.text")
                    .routekeeperFont(.title2, weight: .semibold)
                Spacer()
                Button(text("完成", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DisclaimerScopeNotice()
                    AppHairline()
                    DisclaimerBody()
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.trailing, 8)
                .padding(.bottom, 16)
            }
        }
        .padding(24)
        .frame(
            minWidth: 680,
            idealWidth: 760,
            maxWidth: 920,
            minHeight: 560,
            idealHeight: 650,
            maxHeight: 820
        )
        .accessibilityIdentifier("legal-notice")
    }
}
