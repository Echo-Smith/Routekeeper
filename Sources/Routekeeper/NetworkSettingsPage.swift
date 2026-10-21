import GuardCore
import SwiftUI

struct NetworkSettingsPage: View {
    @Bindable var store: GuardStore

    @AppStorage("routekeeper-egress-intelligence-v1") private var includeIntelligence = false
    @State private var confirmClearHistory = false
    @State private var confirmClearReports = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let lockHint {
                Label(lockHint, systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            scopeAndModeCard
            exitsAndProbesCard
            responseAndPrivacyCard
        }
        .confirmationDialog(
            text("清除本机出口历史？", "Clear local exit history?"),
            isPresented: $confirmClearHistory
        ) {
            Button(text("清除历史", "Clear history"), role: .destructive) {
                store.egressAudit.clearHistory()
            }
        } message: {
            Text(text(
                "只删除本机出口 IP 历史。",
                "Only local exit-IP history is removed."
            ))
        }
        .confirmationDialog(
            text("清除最近两次体检报告？", "Clear the two most recent egress reports?"),
            isPresented: $confirmClearReports
        ) {
            Button(text("清除报告", "Clear reports"), role: .destructive) {
                store.egressAudit.clearStoredResults()
            }
        } message: {
            Text(text(
                "只删除本机保存的完整体检报告。",
                "Only locally stored egress reports are removed."
            ))
        }
    }

    private var scopeAndModeCard: some View {
        GuardCard(
            title: text("保护范围与方式", "Protection scope and mode"),
            subtitle: text("保护对象与失败关闭方式。",
                           "Protected apps and fail-closed behavior.")
        ) {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionTitle(text("保护对象", "Protected apps"))
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

                AppHairline()

                settingsSectionTitle(text("保护方式", "Protection mode"))
                Picker("", selection: $store.settings.gatewayProtectionMode) {
                    ForEach(GatewayProtectionMode.allCases, id: \.self) { mode in
                        Text(modeTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 460)
                .accessibilityIdentifier("network-settings-protection-mode")

                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Label(text("系统过滤", "System filter"), systemImage: "line.3.horizontal.decrease.circle")
                        .font(.callout)
                    Spacer()
                    Text(store.networkFilter.canInstall
                         ? text("当前构建可用", "Available in this build")
                         : text("当前签名不可用", "Unavailable with this signature"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(store.networkFilter.canInstall ? appAccent : Color.orange)
                }
                if !store.networkFilter.canInstall {
                    Text(text(
                        "当前为临时签名构建，无法启用系统扩展。分流与 Claude-only 仍需在代理客户端配置。",
                        "This temporary-signature build cannot install the system extension. Split routing and Claude-only rules still require proxy-client configuration."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(settingsLocked)
        }
    }

    private var exitsAndProbesCard: some View {
        GuardCard(
            title: text("出口与检查参数", "Exits and check parameters"),
            subtitle: text("目标出口、代理客户端与探测。",
                           "Target exits, proxy client and probes.")
        ) {
            VStack(alignment: .leading, spacing: 16) {
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

                settingsSectionTitle(text("探测参数", "Probe settings"))
                HStack(spacing: 12) {
                    Text(text("代理客户端", "Proxy client"))
                        .frame(width: 132, alignment: .leading)
                    Menu {
                        ForEach(ProxyClient.allCases, id: \.self) { client in
                            Button(client.title) {
                                store.settings.proxyClient = client
                            }
                        }
                    } label: {
                        Text(store.settings.proxyClient.title)
                    }
                    .accessibilityIdentifier("network-settings-proxy-client")
                    Spacer()
                }

                HStack(spacing: 12) {
                    Text(text("检查间隔", "Check interval"))
                        .frame(width: 132, alignment: .leading)
                    TextField("1–300", value: $store.settings.pollInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .accessibilityIdentifier("network-settings-poll-interval")
                    Text(text("秒", "seconds"))
                        .foregroundStyle(.secondary)
                    Stepper("", value: $store.settings.pollInterval, in: 1...300, step: 1)
                        .labelsHidden()
                    Spacer()
                }
                if !store.settings.validInterval {
                    Text(text("请输入 1–300 秒。", "Enter a value from 1 to 300."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle(
                    text("检测 DNS 解析器路由与响应", "Probe DNS resolver routes and responses"),
                    isOn: $store.settings.dnsProbeEnabled
                )
                .toggleStyle(.switch)
                Toggle(
                    text("用两处 STUN 服务检测 UDP 出口", "Probe UDP egress with two STUN servers"),
                    isOn: $store.settings.udpProbeEnabled
                )
                .toggleStyle(.switch)
            }
            .disabled(settingsLocked)
        }
    }

    private var responseAndPrivacyCard: some View {
        GuardCard(
            title: text("异常与本地数据", "Incidents and local data"),
            subtitle: text("异常处理、第三方查询与本机记录。",
                           "Incident handling, third-party lookup and local evidence.")
        ) {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionTitle(text("异常处理", "On incident"))
                Picker(text("检测到异常时", "On incident"), selection: $store.settings.action) {
                    ForEach(IncidentAction.allCases, id: \.self) { action in
                        Text(action == .notify ? L("action.notify") : L("action.terminate")).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 430)
                .disabled(settingsLocked)
                Text(store.settings.action == .terminate ? L("action.terminate.hint") : L("action.notify.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AppHairline()

                settingsSectionTitle(text("第三方查询", "Third-party lookup"))
                Toggle(
                    text("查询第三方 IP 信息", "Query third-party IP intelligence"),
                    isOn: $includeIntelligence
                )
                .toggleStyle(.switch)
                .accessibilityIdentifier("network-settings-third-party-intelligence")
                Text(text(
                    "手动体检会把出口 IP 发送给 ipwho.is / ipapi.is。",
                    "Manual checks send the exit IP to ipwho.is / ipapi.is."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                AppHairline()

                settingsSectionTitle(text("本机证据", "Local evidence"))
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        confirmClearReports = true
                    } label: {
                        Label(text("清除已保存报告", "Clear stored reports"), systemImage: "doc.badge.minus")
                    }
                    .routekeeperSecondaryButton()
                    .disabled(store.egressAudit.report == nil && store.egressAudit.previousReport == nil)

                    Button(role: .destructive) {
                        confirmClearHistory = true
                    } label: {
                        Label(text("清除出口历史", "Clear exit history"), systemImage: "clock.arrow.circlepath")
                    }
                    .routekeeperSecondaryButton()
                    .disabled(store.egressAudit.history.isEmpty)

                    Spacer(minLength: 0)
                }
                Text(text(
                    "最近两次报告和最多 20 条出口历史仅保存在本机。",
                    "The two latest reports and up to 20 exits stay on this Mac."
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var settingsLocked: Bool {
        store.monitoring
            || store.checking
            || store.networkFilter.configured
            || store.networkFilter.busy
            || store.settings.experimentalSandboxEnabled
    }

    private var lockHint: String? {
        if store.settings.experimentalSandboxEnabled {
            return store.sandbox.phase.isActive
                ? text(
                    "沙箱运行中，无法进行设置。请先结束并关闭沙箱。",
                    "Sandbox is active. End and close it before changing settings."
                )
                : text(
                    "沙箱已启用，网络保护设置暂不可更改。请先在沙箱页关闭沙箱。",
                    "Sandbox mode is on. Close it on the Sandbox page before changing network protection."
                )
        }
        if store.networkFilter.configured || store.networkFilter.busy {
            return text("系统网络过滤正在使用，设置暂时只读。", "System network filtering is active, so settings are read-only.")
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func fixedExitRow(family: IPFamily, label: String, placeholder: String) -> some View {
        let availabilityKnown = store.activeFamilies != nil
        let available = family == .ipv4 || !availabilityKnown || store.activeFamilies?.contains(family) == true
        HStack(spacing: 10) {
            Label(label, systemImage: family == .ipv4 ? "4.circle" : "6.circle")
                .frame(width: 132, alignment: .leading)
            TextField(placeholder, text: Binding(
                get: { store.settings.fixedExit(for: family) },
                set: { store.settings.setFixedExit($0, for: family) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityIdentifier("network-settings-fixed-exit-\(family.rawValue)")
            Button {
                Task { await store.adoptObservedExit(family: family) }
            } label: {
                Label(L("action.autoExit"), systemImage: "wand.and.stars")
            }
            .disabled(!available || store.monitoring || store.checking)
            if !available {
                Text(text("未启用，已关闭", "Disabled on this Mac"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!available || store.monitoring || store.checking)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { available && isOn.wrappedValue },
                set: { guard available else { return }; isOn.wrappedValue = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!available)
        }
    }

    private func modeTitle(_ mode: GatewayProtectionMode) -> String {
        switch mode {
        case .off: return text("关闭", "Off")
        case .splitTraffic: return text("分流保护", "Split routing")
        case .claudeOnly: return text("仅限制 Claude", "Claude only")
        }
    }

    private var modeExplanation: String {
        switch store.settings.gatewayProtectionMode {
        case .off:
            return text(
                "只做网络体检，不验证代理失败关闭。",
                "Checks the network without fail-closed verification."
            )
        case .splitTraffic:
            return text(
                "国内直连，其余流量走海外节点；节点断开时断网。",
                "Direct for domestic traffic, overseas node for the rest, fail closed on node loss."
            )
        case .claudeOnly:
            return text(
                "只限制 Claude Desktop 与 Claude Code；需要客户端支持进程分流。",
                "Restrict Claude Desktop and Claude Code only; the proxy client must support process rules."
            )
        }
    }

}
