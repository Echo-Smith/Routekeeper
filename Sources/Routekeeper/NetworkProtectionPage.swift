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
        VStack(alignment: .leading, spacing: 20) {
            GuardCard(
                title: text("让 Claude 只能走代理", "Keep Claude on the proxy"),
                subtitle: text("可选。由代理客户端限制 Claude；节点不可用时断开连接，不回落直连。",
                               "Optional. Let the proxy client keep Claude on the selected route and fail closed when the node is unavailable.")
            ) {
                Text(text(
                    "这项限制适合交给代理客户端完成。Routekeeper 不会直接读取或修改代理配置，下面的提示词会要求 Agent 先核对客户端能力、备份配置并询问要使用的海外节点。",
                    "This is best handled by the proxy client. Routekeeper does not read or modify proxy settings directly. The prompt asks an agent to verify capabilities, back up the configuration and ask which overseas node to use."
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

                    Text(text("复制后粘贴给能操作本机的 Agent。", "Paste it into an agent that can operate this Mac."))
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

            GuardCard(
                title: text("分流保护", "Routing protection"),
                subtitle: text("国内流量直连，其余流量固定走海外节点；节点断开时不回落直连。",
                               "Send domestic traffic direct and everything else through the selected overseas node, with no direct fallback when the node disconnects.")
            ) {
                Text(text(
                    "实际分流规则需要在代理客户端中修改。下面的提示词会先让 Agent 核对客户端、版本和内核能力，并询问要使用的海外节点；缺信息时不会猜测。",
                    "Routing rules are changed in the proxy client. The prompt asks an agent to verify the client, version and core first, then ask which overseas node to use. Missing details are never guessed."
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

                    Text(text("复制后粘贴给能操作本机的 Agent。", "Paste it into an agent that can operate this Mac."))
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

                Text(text(
                    "分流保护不会自动修改代理配置，也不会擅自更换客户端或节点。",
                    "Routing protection does not change proxy settings automatically and does not replace your client or nodes."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            GuardCard(
                title: text("排查连接是否被拦截", "Investigate blocked connections"),
                subtitle: text("可选。记录短时间内的网络连接，方便对比断开代理前后的变化。",
                               "Optional. Record network activity briefly to compare what changes when the proxy is disconnected.")
            ) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text("自动识别当前网络路径", "Detect the current network route"))
                            .font(.callout.weight(.medium))
                        Text(text(
                            "\(store.capture.interface.isEmpty ? "正在识别" : store.capture.interface) → \(store.capture.destination)，记录 \(store.capture.seconds) 秒。开始后访问测试目标即可。",
                            "\(store.capture.interface.isEmpty ? "Detecting" : store.capture.interface) → \(store.capture.destination) for \(store.capture.seconds) seconds. Visit the test destination after recording starts."
                        ))
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
                        Text(text(
                            "通常不需要修改。网卡会自动跟随目标地址的当前路由；切换代理后也会重新识别。",
                            "Usually no changes are needed. The interface follows the current route to the destination and is refreshed after proxy changes."
                        ))
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
                    "记录需要管理员授权，最多保存 200 个数据包的包头摘要。没有记录到数据，不能证明拦截已经生效。",
                    "Recording requires administrator approval and saves summaries of at most 200 packet headers. No recorded traffic does not prove that traffic is blocked."
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
