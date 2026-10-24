import AppKit
import GuardCore
import SwiftUI

struct ProxyModeConfigurationSheet: View {
    @Bindable var store: GuardStore

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedProxyClient: ProxyClient = .automatic
    @State private var copiedPrompt = false
    @State private var copyRevision = 0

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text("配置", "Configure") + " " + store.settings.gatewayProtectionMode.displayTitle)
                        .routekeeperFont(.title2, weight: .semibold)
                    Text(text("在代理客户端中应用当前保护方式。",
                              "Apply the selected protection mode in your proxy client."))
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(text("完成", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            AppHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, height: 38)
                            .background(Color.primary.opacity(0.05), in: Circle())
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(text("当前客户端", "Current client"))
                                .routekeeperFont(.callout, weight: .medium)
                            Text(clientName)
                                .routekeeperFont(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(text(
                        "Routekeeper 不会自动修改代理客户端。复制提示词给能操作本机的智能体，由它核对客户端能力、备份现有规则并完成配置。",
                        "Routekeeper does not modify the proxy client automatically. Copy the prompt to a local agent so it can verify client capabilities, back up existing rules and apply the configuration."
                    ))
                    .routekeeperFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button {
                            copyPrompt()
                        } label: {
                            Label(
                                copiedPrompt
                                    ? text("已复制提示词", "Prompt copied")
                                    : text("复制给智能体的提示词", "Copy agent prompt"),
                                systemImage: copiedPrompt ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                        }
                        .routekeeperProminentButton()
                        .accessibilityIdentifier(
                            store.settings.gatewayProtectionMode == .claudeOnly
                                ? "copy-claude-restriction-prompt"
                                : "copy-routing-agent-prompt"
                        )

                        if copiedPrompt {
                            Text(text("已复制", "Copied"))
                                .routekeeperFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    AppHairline()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(text("配置方向", "Configuration approach"))
                            .routekeeperFont(.headline)
                        Text(configurationApproach)
                            .routekeeperFont(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DisclosureGroup(text("查看完整提示词", "View the full prompt")) {
                        ScrollView {
                            Text(prompt)
                                .routekeeperFont(.caption, design: .monospaced)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 320)
                        .padding(12)
                        .appSurface(.inset, corner: 10)
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 480, idealHeight: 580)
        .task(id: store.settings.proxyClient) {
            resolvedProxyClient = ProxyAdapters.identify(store.settings.proxyClient).client
        }
        .task(id: copyRevision) {
            guard copiedPrompt else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copiedPrompt = false
        }
        .accessibilityIdentifier("proxy-mode-configuration-sheet")
    }

    private var clientName: String {
        let client = resolvedProxyClient == .automatic ? store.settings.proxyClient : resolvedProxyClient
        return client == .automatic
            ? text("自动识别", "Automatic")
            : client.title
    }

    private var prompt: String {
        let promptClient = resolvedProxyClient == .automatic ? store.settings.proxyClient : resolvedProxyClient
        let name = promptClient == .automatic
            ? text("当前代理客户端", "current proxy client")
            : promptClient.title
        switch store.settings.gatewayProtectionMode {
        case .splitTraffic:
            return RoutingProtection.agentPrompt(clientName: name)
        case .claudeOnly:
            return RoutingProtection.restrictionPrompt(clientName: name)
        case .off:
            return ""
        }
    }

    private var configurationApproach: String {
        switch store.settings.gatewayProtectionMode {
        case .splitTraffic:
            return text(
                "先备份现有分流规则。国内流量保持直连，其余流量进入只包含可信海外节点的代理组；最终兜底必须是断网或拒绝，不能包含 DIRECT。",
                "Back up the current routing rules first. Keep domestic traffic direct and send all other traffic through a proxy group containing only trusted overseas nodes. The final fallback must fail closed and must not contain DIRECT."
            )
        case .claudeOnly:
            return text(
                "优先使用进程或应用分流，把 Claude 和 Claude Code 固定到只包含海外节点的代理组。终端中的 Claude Code 还需要 TUN 或可识别进程的规则；最终兜底不能包含 DIRECT。",
                "Prefer process or application rules. Put Claude and Claude Code into a proxy group containing only overseas nodes. Claude Code in Terminal also needs TUN or process-aware rules, and the final fallback must not contain DIRECT."
            )
        case .off:
            return ""
        }
    }

    private func copyPrompt() {
        guard !prompt.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copiedPrompt = true
        copyRevision += 1
    }
}
