import GuardCore
import SwiftUI

struct NetworkSettingsPage: View {
    @Bindable var store: GuardStore

    @State private var showModeConfiguration = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let lockHint {
                Label(lockHint, systemImage: "lock.shield")
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.inset, corner: 10)
            }

            protectionScopeSection
                .appSurface(.primary)
                .id(DashboardScrollID.section(.scope))
            protectionModeSection
                .appSurface(.primary)
                .id(DashboardScrollID.section(.protectionMode))
            exitsAndMonitoringSection
                .appSurface(.primary)
        }
        .sheet(isPresented: $showModeConfiguration) {
            ProxyModeConfigurationSheet(store: store)
        }
    }

    private var protectionScopeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppSectionHeading(
                title: text("保护范围", "Protection scope")
            )

            protectToggle(
                isOn: $store.settings.protectDesktop,
                icon: "macwindow",
                label: L("protect.desktop"),
                available: store.desktopInstalled,
                unavailableHint: L("protect.desktop.unavailable")
            )
            protectToggle(
                isOn: $store.settings.protectCode,
                icon: "terminal",
                label: L("protect.code"),
                available: store.codeInstalled,
                unavailableHint: L("protect.code.unavailable")
            )
        }
        .padding(20)
        .disabled(settingsLocked)
    }

    private var protectionModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppSectionHeading(
                title: text("保护方式", "Protection mode"),
                subtitle: text("决定节点断开或代理退出时，Claude 是否能够继续联网。",
                               "Choose whether Claude can stay online when the node fails or the proxy exits.")
            )

            Picker("", selection: $store.settings.gatewayProtectionMode) {
                ForEach(GatewayProtectionMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.displayTitle)
                            .routekeeperFont(.body, weight: .medium)
                        Text(mode.displayExplanation)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .accessibilityLabel(text("保护方式", "Protection mode"))
            .accessibilityIdentifier("network-settings-protection-mode")
            .disabled(settingsLocked)

            if store.settings.gatewayProtectionMode != .off {
                AppHairline()

                HStack(alignment: .center, spacing: 14) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(text("代理客户端规则", "Proxy-client rules"))
                                .routekeeperFont(.callout, weight: .medium)
                            Text(text("Routekeeper 不会自动修改代理客户端。",
                                      "Routekeeper does not modify the proxy client automatically."))
                                .routekeeperFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button {
                        showModeConfiguration = true
                    } label: {
                        Label(text("配置此模式…", "Configure this mode…"),
                              systemImage: "doc.on.doc")
                    }
                    .routekeeperSecondaryButton()
                    .accessibilityIdentifier("configure-protection-mode")
                }
            }
        }
        .padding(20)
    }

    private var exitsAndMonitoringSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppSectionHeading(
                title: text("出口与异常处理", "Exits and incident handling")
            )

            settingsSectionTitle(text("固定出口", "Fixed exits"))
            fixedExitRow(
                family: .ipv4,
                label: text("IPv4 固定出口", "IPv4 fixed exit"),
                placeholder: text("IPv4 出口地址", "IPv4 exit address")
            )
            fixedExitRow(
                family: .ipv6,
                label: text("IPv6 固定出口", "IPv6 fixed exit"),
                placeholder: text("IPv6 出口地址", "IPv6 exit address")
            )

            AppHairline()

            settingsSectionTitle(text("异常动作", "Incident action"))
            Picker(text("检测到异常时", "On incident"), selection: $store.settings.action) {
                ForEach(IncidentAction.allCases, id: \.self) { action in
                    Text(action == .notify ? L("action.notify") : L("action.terminate"))
                        .tag(action)
                }
            }
            .pickerStyle(.menu)

            Text(store.settings.action == .terminate
                 ? L("action.terminate.hint")
                 : L("action.notify.hint"))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .disabled(settingsLocked)
    }

    private var settingsLocked: Bool {
        store.monitoring
            || store.checking
            || store.networkFilter.configured
            || store.networkFilter.busy
            || store.sandbox.anyActive
            || store.sandbox.busy
    }

    private var lockHint: String? {
        if store.sandbox.anyActive || store.sandbox.busy {
            return text(
                "沙箱会话运行或准备期间，网络保护设置暂时只读。结束会话后即可修改。",
                "Network protection settings are read-only while a sandbox session is active or preparing. End the session to make changes."
            )
        }
        if store.networkFilter.configured || store.networkFilter.busy {
            return text("系统网络过滤正在使用，设置暂时只读。",
                        "System network filtering is active, so settings are read-only.")
        }
        if store.monitoring {
            return text("监控运行期间设置只读。", "Settings are read-only while monitoring.")
        }
        if store.checking {
            return text("体检运行期间设置只读。", "Settings are read-only while checking.")
        }
        return nil
    }

    private func settingsSectionTitle(_ value: String) -> some View {
        Text(value)
            .routekeeperFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func fixedExitRow(family: IPFamily, label: String, placeholder: String) -> some View {
        let availabilityKnown = store.activeFamilies != nil
        let available = family == .ipv4 || !availabilityKnown || store.activeFamilies?.contains(family) == true

        if available {
            LabeledContent {
                HStack(spacing: 10) {
                    TextField(placeholder, text: Binding(
                        get: { store.settings.fixedExit(for: family) },
                        set: { store.settings.setFixedExit($0, for: family) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .routekeeperFont(.body, design: .monospaced)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("network-settings-fixed-exit-\(family.rawValue)")

                    Button {
                        Task { await store.adoptObservedExit(family: family) }
                    } label: {
                        Label(L("action.autoExit"), systemImage: "wand.and.stars")
                    }
                    .disabled(store.monitoring || store.checking)
                }
            } label: {
                Label(label, systemImage: family == .ipv4 ? "4.circle" : "6.circle")
            }
            .accessibilityElement(children: .contain)
        } else {
            LabeledContent {
                Text(text("当前网络未启用", "Not active on this network"))
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
            } label: {
                Label(label, systemImage: family == .ipv4 ? "4.circle" : "6.circle")
            }
        }
    }

    @ViewBuilder
    private func protectToggle(
        isOn: Binding<Bool>,
        icon: String,
        label: String,
        available: Bool,
        unavailableHint: String
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
            if !available {
                Text(unavailableHint)
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { available && isOn.wrappedValue },
                set: { guard available else { return }; isOn.wrappedValue = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(label)
            .disabled(!available)
        }
    }
}

extension GatewayProtectionMode {
    var displayTitle: String {
        switch self {
        case .off:
            return L10n.resolvedEnglish ? "Off" : "关闭"
        case .splitTraffic:
            return L10n.resolvedEnglish ? "Split routing" : "分流保护"
        case .claudeOnly:
            return L10n.resolvedEnglish ? "Claude only" : "仅限制 Claude"
        }
    }

    var displayExplanation: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .off:
            return en
                ? "Run network checks without verifying fail-closed behavior."
                : "只做网络体检，不验证代理失败关闭。"
        case .splitTraffic:
            return en
                ? "Domestic traffic connects directly; other traffic uses the overseas node and fails closed when the node is lost."
                : "国内直连，其余流量走海外节点；节点断开时断网。"
        case .claudeOnly:
            return en
                ? "Restrict Claude and Claude Code only; the proxy client must support process rules."
                : "只限制 Claude 与 Claude Code；需要客户端支持进程分流。"
        }
    }
}
