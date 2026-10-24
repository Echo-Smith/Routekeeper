import GuardCore
import SwiftUI

struct GatewayVerificationPage: View {
    @Bindable var controller: GatewayVerificationController
    let mode: GatewayProtectionMode
    let onChangeMode: () -> Void
    var embedded = false
    var showsHeader = true
    var showsAction = true

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    private var status: GatewayVerificationStatus {
        controller.status(for: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(statusColor)
                        .frame(width: 46, height: 46)
                        .background(
                            statusColor.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusTitle)
                            .routekeeperFont(.title3, weight: .semibold)
                            .tracking(-0.2)
                            .accessibilityAddTraits(.isHeader)
                        Text(statusSubtitle)
                            .routekeeperFont(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if controller.busy {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if mode != .off {
                modeRow

                if showsAction {
                    actionRow
                } else {
                    actionInstruction
                }
            }

            if let record = controller.record,
               record.mode == mode,
               !record.allChecks.isEmpty {
                DisclosureGroup(text("查看检查证据", "View evidence")) {
                    evidenceList(record.allChecks)
                        .padding(.top, 8)
                }
                .routekeeperFont(.callout, weight: .medium)
            }

            if mode != .off, !controller.message.isEmpty {
                messageFootnote
            }
        }
        .padding(embedded ? 16 : 20)
        .appSurface(embedded ? .inset : .secondary)
        .accessibilityIdentifier("gateway-verification-card")
    }

    private var modeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: mode == .claudeOnly ? "scope" : "arrow.triangle.branch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text("当前保护方式", "Selected protection"))
                .routekeeperFont(.callout)
                .foregroundStyle(.secondary)
            Text(modeTitle)
                .routekeeperFont(.callout, weight: .semibold)
            Spacer(minLength: 12)
            Button(action: onChangeMode) {
                Label(
                    text("配置保护方式", "Configure protection"),
                    systemImage: "arrow.up.right"
                )
                .labelStyle(.titleAndIcon)
            }
                .buttonStyle(.borderless)
                .routekeeperFont(.callout, weight: .medium)
                .foregroundStyle(appAccent)
                .accessibilityIdentifier("gateway-change-mode")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageFootnote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: messageSymbol)
                .font(.system(size: 11, weight: .medium))
                .accessibilityHidden(true)
            Text(controller.message)
                .routekeeperFont(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(messageColor)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actionRow: some View {
        switch status {
        case .unverified, .failed, .expired:
            Button {
                Task { await controller.runBaseline(for: mode) }
            } label: {
                Label(
                    status == .unverified
                        ? text("检查当前代理路径", "Check current gateway")
                        : text("重新检查当前代理路径", "Check gateway again"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }
            .routekeeperProminentButton()
            .disabled(controller.busy)
            .accessibilityIdentifier("gateway-run-baseline")
        case .needsNodeFailureTest:
            VStack(alignment: .leading, spacing: 10) {
                instruction(
                    text(
                        "现在只停用所选海外节点，并保持代理客户端运行。若当前配置会把该流量切到其他节点，请先让智能体去掉回退节点。",
                        "Disable only the selected overseas node and keep the proxy client running. If the configuration falls back to another node, remove that fallback first."
                    )
                )
                Button {
                    Task { await controller.testNodeFailure(for: mode) }
                } label: {
                    Label(text("已在节点中停用，开始复测", "Node disabled; run test"), systemImage: "wifi.exclamationmark")
                }
                .routekeeperProminentButton()
                .disabled(controller.busy)
                .accessibilityIdentifier("gateway-test-node-failure")
            }
        case .needsClientExitTest:
            VStack(alignment: .leading, spacing: 10) {
                instruction(
                    text(
                        "先恢复节点，再完全退出代理客户端。Routekeeper 会检查 Claude 目标是否仍能连接；能连接就说明存在回落直连风险。",
                        "Restore the node, then quit the proxy client completely. Routekeeper will check whether the Claude target is still reachable; if it is, direct fallback is possible."
                    )
                )
                Button {
                    Task { await controller.testClientExit(for: mode) }
                } label: {
                    Label(text("代理已退出，检查是否断网", "Proxy exited; test isolation"), systemImage: "xmark.icloud")
                }
                .routekeeperProminentButton()
                .disabled(controller.busy)
                .accessibilityIdentifier("gateway-test-client-exit")
            }
        case .needsRecovery:
            VStack(alignment: .leading, spacing: 10) {
                instruction(
                    text(
                        "重新启动代理客户端并恢复原来的节点。确认正常联网后，再完成最后一次复测。",
                        "Restart the proxy client and restore the original node. Confirm normal connectivity, then run the final check."
                    )
                )
                Button {
                    Task { await controller.completeRecovery(for: mode) }
                } label: {
                    Label(text("代理已恢复，完成验证", "Proxy restored; finish"), systemImage: "checkmark.shield")
                }
                .routekeeperProminentButton()
                .disabled(controller.busy)
                .accessibilityIdentifier("gateway-complete-recovery")
            }
        case .verified:
            HStack(spacing: 10) {
                Label(text("本次网络会话已验证", "Verified for this network session"), systemImage: "checkmark.seal.fill")
                    .routekeeperFont(.callout, weight: .medium)
                    .foregroundStyle(appAccent)
                Spacer()
                Button(text("重新检查", "Verify again")) {
                    Task { await controller.runBaseline(for: mode) }
                }
                .routekeeperSecondaryButton()
                .disabled(controller.busy)
            }
        }
    }

    @ViewBuilder
    private var actionInstruction: some View {
        switch status {
        case .unverified:
            instruction(
                text(
                    "先确认当前保护方式和代理客户端状态，再从当前路径开始检查。",
                    "Confirm the selected protection and proxy client state, then start with the current path."
                )
            )
        case .failed:
            instruction(
                text(
                    "检查所选节点、TUN 模式和系统代理，确认代理入口与 Claude 路径使用同一出口后从头重测。",
                    "Check the selected node, TUN mode and system proxy. Confirm the proxy entry and Claude path use the same exit, then rerun from the start."
                )
            )
        case .expired:
            instruction(
                text(
                    "网络或设置已经变化，请重新检查当前代理路径，旧证据不能继续使用。",
                    "The network or settings changed. Check the current gateway path again; the old evidence can no longer be used."
                )
            )
        case .needsNodeFailureTest:
            instruction(
                text(
                    "现在只停用所选海外节点，并保持代理客户端运行。若当前配置会把该流量切到其他节点，请先让智能体去掉回退节点。",
                    "Disable only the selected overseas node and keep the proxy client running. If the configuration falls back to another node, remove that fallback first."
                )
            )
        case .needsClientExitTest:
            instruction(
                text(
                    "先恢复节点，再完全退出代理客户端。Routekeeper 会检查 Claude 目标是否仍能连接；能连接就说明存在回落直连风险。",
                    "Restore the node, then quit the proxy client completely. Routekeeper will check whether the Claude target is still reachable; if it is, direct fallback is possible."
                )
            )
        case .needsRecovery:
            instruction(
                text(
                    "重新启动代理客户端并恢复原来的节点。确认正常联网后，再完成最后一次复测。",
                    "Restart the proxy client and restore the original node. Confirm normal connectivity, then run the final check."
                )
            )
        case .verified:
            EmptyView()
        }
    }

    private func instruction(_ value: String) -> some View {
        Label(value, systemImage: "person.crop.circle.badge.exclamationmark")
            .routekeeperFont(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func evidenceList(_ checks: [GatewayCheckResult]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: checkSymbol(check.level))
                        .foregroundStyle(checkColor(check.level))
                        .frame(width: 18)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(check.title).routekeeperFont(.callout, weight: .medium)
                            if !check.required {
                                Text(text("参考", "Reference"))
                                    .routekeeperFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(check.detail)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 7)
                if index < checks.count - 1 { AppHairline() }
            }
        }
    }

    private var modeTitle: String {
        switch mode {
        case .off: return text("未启用", "Off")
        case .splitTraffic: return text("分流保护", "Split routing")
        case .claudeOnly: return text("仅限制 Claude", "Claude only")
        }
    }

    var statusTitle: String {
        Self.title(for: status)
    }

    static func title(for status: GatewayVerificationStatus) -> String {
        let en = L10n.resolvedEnglish
        switch status {
        case .unverified: return en ? "Gateway not checked" : "代理网关尚未检查"
        case .needsNodeFailureTest: return en ? "Current path passed; test node failure" : "已通过当前路径，待测节点断开"
        case .needsClientExitTest: return en ? "Node-failure test passed; test client exit" : "已通过节点断开测试，待测代理退出"
        case .needsRecovery: return en ? "Fail-closed tests passed; restore proxy" : "失败关闭测试通过，待恢复代理"
        case .verified: return en ? "Current gateway verified" : "当前代理网关已验证"
        case .failed: return en ? "Gateway check failed" : "代理网关检查未通过"
        case .expired: return en ? "Gateway evidence expired" : "代理网关证据已过期"
        }
    }

    var statusSubtitle: String {
        Self.subtitle(for: status, mode: mode)
    }

    static func subtitle(
        for status: GatewayVerificationStatus,
        mode: GatewayProtectionMode
    ) -> String {
        let en = L10n.resolvedEnglish
        switch status {
        case .unverified:
            return mode == .off
                ? (en ? "Choose split routing or Claude-only restriction in Check options first." : "先在检查选项中选择分流保护或仅限制 Claude。")
                : (en ? "Check the current path, node failure and client exit in order. One successful request is not enough." : "依次检查当前路径、节点断开和代理退出，不能只凭一次成功请求下结论。")
        case .needsNodeFailureTest:
            return en
                ? "The proxy currently works. Next, verify Claude does not fall back to a direct connection when the overseas node is unavailable."
                : "当前代理能用。下一步验证海外节点断开时 Claude 不会退回直连。"
        case .needsClientExitTest:
            return en
                ? "Claude failed closed with the node unavailable. Next, verify the TUN path does not reopen direct access when the client exits."
                : "节点断开时 Claude 已失败关闭。下一步验证代理客户端退出后 TUN 不会放出直连。"
        case .needsRecovery:
            return en
                ? "Both fail-closed tests passed. Restore the proxy and run the final check before marking verification complete."
                : "两项失败关闭测试均已通过。恢复代理并做最终复测后才会显示已验证。"
        case .verified:
            return en
                ? "Complete evidence was collected in this network session. Any network, proxy or system-settings change invalidates it."
                : "当前网络会话内已取得完整证据。网络、代理或系统设置一旦变化会立即作废。"
        case .failed:
            return en
                ? "At least one required item failed. Review the evidence, fix it and rerun from the start."
                : "有必需项目未通过。查看下方证据，修复后从头重测。"
        case .expired:
            return en
                ? "Network state or settings changed, so the old result cannot support a protection decision."
                : "网络状态或设置已经变化，旧结论不能再用于保护判断。"
        }
    }

    private var statusSymbol: String {
        switch status {
        case .verified: return "checkmark.shield.fill"
        case .failed, .expired: return "exclamationmark.shield.fill"
        case .needsNodeFailureTest, .needsClientExitTest, .needsRecovery: return "shield.lefthalf.filled"
        case .unverified: return "shield"
        }
    }

    private var statusColor: Color {
        switch status {
        case .verified: return appStatusSuccess
        case .failed, .expired: return appStatusFailure
        case .needsNodeFailureTest, .needsClientExitTest, .needsRecovery: return appStatusWarning
        case .unverified: return .secondary
        }
    }

    private var messageSymbol: String {
        if let record = controller.record,
           record.allChecks.contains(where: { $0.required && $0.level == .failed }) {
            return "exclamationmark.circle.fill"
        }
        return status == .verified ? "checkmark.circle.fill" : "info.circle"
    }

    private var messageColor: Color {
        messageSymbol == "exclamationmark.circle.fill" ? appStatusFailure : statusColor
    }

    private func checkSymbol(_ level: CheckLevel) -> String {
        switch level {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .warning, .unknown: return "questionmark.circle.fill"
        }
    }

    private func checkColor(_ level: CheckLevel) -> Color {
        switch level {
        case .passed: return appStatusSuccess
        case .failed: return appStatusFailure
        case .warning, .unknown: return appStatusWarning
        }
    }
}
