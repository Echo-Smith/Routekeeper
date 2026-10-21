import AppKit
import GuardCore
import SwiftUI

struct NetworkProtectionPage: View {
    @Bindable var store: GuardStore
    @State private var resolvedProxyClient: ProxyClient = .automatic
    @State private var copiedRestrictionPrompt = false
    @State private var copiedRoutingPrompt = false
    @State private var restrictionCopyRevision = 0
    @State private var copyRevision = 0

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NetworkSettingsPage(store: store)

            if store.settings.gatewayProtectionMode == .claudeOnly {
                GuardCard(
                    title: text("让 Claude 只能走代理", "Keep Claude on the proxy"),
                    subtitle: text("在代理客户端中限制 Claude 进程。",
                                   "Restrict Claude processes in the proxy client.")
                ) {
                Text(text(
                    "复制提示词给能操作本机的 Agent，由它核对客户端并完成配置。",
                    "Copy the prompt to a local agent to verify the client and apply the rules."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        copyRestrictionPrompt()
                    } label: {
                        Label(
                            copiedRestrictionPrompt
                                ? text("已复制提示词", "Prompt copied")
                                : text("复制限制 Claude 的提示词", "Copy Claude restriction prompt"),
                            systemImage: copiedRestrictionPrompt ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }
                    .routekeeperProminentButton()
                    .accessibilityIdentifier("copy-claude-restriction-prompt")

                    Text(text("复制给能操作本机的 Agent。", "Paste into a local agent."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup(text("查看提示词和大致配置方法", "View the prompt and configuration approach")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(text("大致配置方法", "Configuration approach"))
                            .font(.callout.weight(.semibold))
                        Text(text(
                            "优先使用代理客户端的进程或应用分流功能，把 Claude Desktop 和 Claude Code 固定到只包含海外节点的代理组；最终兜底必须是断网或拒绝，不能包含 DIRECT。终端里的 Claude Code 还需要 TUN 或可识别进程的规则，才能确认它也走代理。",
                            "Prefer process or application rules in the proxy client. Put Claude Desktop and Claude Code into a proxy group that contains only the overseas node. The final fallback must fail closed and must not contain DIRECT. Claude Code in Terminal also needs TUN or process-aware rules."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        Text(text("给 Agent 的提示词", "Prompt for the agent"))
                            .font(.callout.weight(.semibold))
                        ScrollView {
                            Text(restrictionPrompt)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                        .padding(12)
                        .background(
                            Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .padding(.top, 8)
                }
                }
            }

            if store.settings.gatewayProtectionMode == .splitTraffic {
                GuardCard(
                    title: text("分流保护", "Routing protection"),
                    subtitle: text("国内直连，其余流量走海外节点。",
                                   "Domestic direct, other traffic through an overseas node.")
                ) {
                Text(text(
                    "复制提示词给能操作本机的 Agent，由它备份并修改代理规则。",
                    "Copy the prompt to a local agent to back up and update the routing rules."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        copyRoutingPrompt()
                    } label: {
                        Label(
                            copiedRoutingPrompt
                                ? text("已复制提示词", "Prompt copied")
                                : text("复制给 Agent 的提示词", "Copy agent prompt"),
                            systemImage: copiedRoutingPrompt ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }
                    .routekeeperProminentButton()
                    .accessibilityIdentifier("copy-routing-agent-prompt")

                    Text(text("复制给能操作本机的 Agent。", "Paste into a local agent."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup(text("查看提示词内容", "View the prompt")) {
                    ScrollView {
                        Text(routingPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 330)
                    .padding(12)
                    .background(
                        Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .padding(.top, 8)
                }

                }
            }

            GuardCard(
                title: text("排查连接是否被拦截", "Investigate blocked connections"),
                subtitle: text("短时记录连接，用于对比代理开启和关闭。",
                               "Record connections briefly to compare proxy on and off.")
            ) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text("自动识别当前网络路径", "Detect the current network route"))
                            .font(.callout.weight(.medium))
                        Text("\(store.capture.interface.isEmpty ? text("正在识别", "Detecting") : store.capture.interface) → \(store.capture.destination) · \(store.capture.seconds) 秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(text("开始记录", "Start recording")) {
                        store.capture.start()
                    }
                    .routekeeperProminentButton()
                    .disabled(!store.capture.valid || store.capture.busy)
                    .accessibilityIdentifier("capture-start")
                }
                .padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                DisclosureGroup(text("需要修改测试地址或时长？", "Change the test address or duration")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(text("通常无需修改。", "Usually no changes are needed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            TextField(text("目标 IP", "Destination IP"), text: $store.capture.destination)
                                .frame(width: 220)
                            Spacer()
                        }
                        .textFieldStyle(.roundedBorder)
                        Stepper(
                            text("记录 \(store.capture.seconds) 秒", "Record for \(store.capture.seconds) seconds"),
                            value: $store.capture.seconds,
                            in: 5...60
                        )
                    }
                    .padding(.top, 8)
                }

                Text(text(
                    "需要管理员授权；最多保存 200 个数据包的包头摘要。",
                    "Requires administrator approval; stores headers for at most 200 packets."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(text("导出本次记录…", "Export this recording…")) { store.capture.export() }
                        .disabled(store.capture.report.isEmpty || store.capture.busy)
                    if store.capture.busy {
                        ProgressView().controlSize(.small)
                    }
                }

                Text(store.capture.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !store.capture.report.isEmpty {
                    Text(store.capture.report)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(16)
                }
            }
            .disabled(store.capture.busy)
        }
        .task(id: store.settings.proxyClient) {
            store.networkFilter.refresh()
            resolvedProxyClient = ProxyAdapters.identify(store.settings.proxyClient).client
        }
        .task(id: store.capture.destination) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            store.capture.refreshRoute()
        }
        .task(id: copyRevision) {
            guard copiedRoutingPrompt else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copiedRoutingPrompt = false
        }
        .task(id: restrictionCopyRevision) {
            guard copiedRestrictionPrompt else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copiedRestrictionPrompt = false
        }
    }

    private var routingClientName: String {
        let client = resolvedProxyClient == .automatic ? store.settings.proxyClient : resolvedProxyClient
        return client == .automatic
            ? text("当前代理客户端", "current proxy client")
            : client.title
    }

    private var routingPrompt: String {
        RoutingProtection.agentPrompt(clientName: routingClientName)
    }

    private var restrictionPrompt: String {
        RoutingProtection.restrictionPrompt(clientName: routingClientName)
    }

    private func copyRestrictionPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(restrictionPrompt, forType: .string)
        copiedRestrictionPrompt = true
        restrictionCopyRevision += 1
    }

    private func copyRoutingPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(routingPrompt, forType: .string)
        copiedRoutingPrompt = true
        copyRevision += 1
    }
}
