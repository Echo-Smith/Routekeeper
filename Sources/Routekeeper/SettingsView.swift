import GuardCore
import SwiftUI

struct AppSettingsView: View {
    @Bindable var store: GuardStore
    @AppStorage(L10n.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppTextScale.storageKey) private var textScaleRaw = AppTextScale.standard.rawValue
    @State private var showDisclaimer = false

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
                Text(L("general.langNote"))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
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
            } header: {
                Text(text("通用", "General"))
            } footer: {
                Text(text(
                    "语言、外观与文字大小立即生效；系统菜单需重启应用后更新。",
                    "Language, appearance and text size apply immediately. System menus update after restarting the app."
                ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
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
        .routekeeperScrollEdge()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(appearanceOverride)
        .id(store.languageRevision)
        .sheet(isPresented: $showDisclaimer) {
            LegalNoticeSheet()
        }
        .accessibilityIdentifier("settings-content")
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
            }
        }
        .padding(24)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 650)
        .accessibilityIdentifier("legal-notice")
    }
}
