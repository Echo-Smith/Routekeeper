import GuardCore
import SwiftUI

struct GatewayVerificationPage: View {
    @Bindable var controller: GatewayVerificationController
    let mode: GatewayProtectionMode
    let onChangeMode: () -> Void
    @State private var showMethodAndSteps = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    private var status: GatewayVerificationStatus {
        controller.status(for: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            if mode != .off {
                DisclosureGroup(isExpanded: $showMethodAndSteps) {
                    VStack(alignment: .leading, spacing: 12) {
                        modeRow
                        gatewaySteps
                    }
                    .padding(.top, 8)
                } label: {
                    Label(
                        text("检查方法与步骤", "Method and steps"),
                        systemImage: "list.number"
                    )
                    .routekeeperFont(.callout, weight: .medium)
                }

                if !controller.message.isEmpty {
                    Label(controller.message, systemImage: messageSymbol)
                        .routekeeperFont(.callout)
                        .foregroundStyle(messageColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            messageColor.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                actionRow
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
        }
        .padding(20)
        .appSurface(.secondary)
        .accessibilityIdentifier("gateway-verification-card")
    }

    private var modeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: mode == .claudeOnly ? "scope" : "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text("当前保护方式", "Selected protection"))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                Text(modeTitle)
                    .routekeeperFont(.callout, weight: .semibold)
            }
            Spacer()
            Button(text("更改方式", "Change mode"), action: onChangeMode)
                .buttonStyle(.borderless)
                .routekeeperFont(.callout, weight: .medium)
                .foregroundStyle(appAccent)
                .accessibilityIdentifier("gateway-change-mode")
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var gatewaySteps: some View {
        HStack(alignment: .top, spacing: 8) {
            gatewayStep(1, text("检查当前路径", "Check current path"), complete: stepComplete(1))
            Image(systemName: "chevron.right").routekeeperFont(.caption2).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            gatewayStep(2, text("停用节点后复测", "Retest with node off"), complete: stepComplete(2))
            Image(systemName: "chevron.right").routekeeperFont(.caption2).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            gatewayStep(3, text("退出代理后复测", "Retest with client off"), complete: stepComplete(3))
            Image(systemName: "chevron.right").routekeeperFont(.caption2).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            gatewayStep(4, text("恢复并完成", "Restore and finish"), complete: status == .verified)
        }
    }

    private func gatewayStep(_ number: Int, _ title: String, complete: Bool) -> some View {
        HStack(spacing: 7) {
            Text(complete ? "✓" : "\(number)")
                .routekeeperFont(.caption, weight: .bold)
                .foregroundStyle(complete ? Color.white : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    complete ? appAccent : Color.primary.opacity(0.07),
                    in: Circle()
                )
            Text(title)
                .routekeeperFont(.caption)
                .foregroundStyle(complete ? .primary : .secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        "现在只停用所选海外节点，并保持代理客户端运行。若当前配置会把该流量切到其他节点，请先让 Agent 去掉回退节点。",
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

    private var statusTitle: String {
        switch status {
        case .unverified: return text("代理网关尚未检查", "Gateway not checked")
        case .needsNodeFailureTest: return text("已通过当前路径，待测节点断开", "Current path passed; test node failure")
        case .needsClientExitTest: return text("已通过节点断开测试，待测代理退出", "Node-failure test passed; test client exit")
        case .needsRecovery: return text("失败关闭测试通过，待恢复代理", "Fail-closed tests passed; restore proxy")
        case .verified: return text("当前代理网关已验证", "Current gateway verified")
        case .failed: return text("代理网关检查未通过", "Gateway check failed")
        case .expired: return text("代理网关证据已过期", "Gateway evidence expired")
        }
    }

    private var statusSubtitle: String {
        switch status {
        case .unverified:
            return mode == .off
                ? text("先在检查设置中选择分流保护或仅限制 Claude。", "Choose split routing or Claude-only restriction in Check settings first.")
                : text("依次检查当前路径、节点断开和代理退出，不能只凭一次成功请求下结论。",
                       "Check the current path, node failure and client exit in order. One successful request is not enough.")
        case .needsNodeFailureTest:
            return text("当前代理能用。下一步验证海外节点断开时 Claude 不会退回直连。",
                        "The proxy currently works. Next, verify Claude does not fall back to a direct connection when the overseas node is unavailable.")
        case .needsClientExitTest:
            return text("节点断开时 Claude 已失败关闭。下一步验证代理客户端退出后 TUN 不会放出直连。",
                        "Claude failed closed with the node unavailable. Next, verify the TUN path does not reopen direct access when the client exits.")
        case .needsRecovery:
            return text("两项失败关闭测试均已通过。恢复代理并做最终复测后才会显示已验证。",
                        "Both fail-closed tests passed. Restore the proxy and run the final check before marking verification complete.")
        case .verified:
            return text("当前网络会话内已取得完整证据。网络、代理或系统设置一旦变化会立即作废。",
                        "Complete evidence was collected in this network session. Any network, proxy or system-settings change invalidates it.")
        case .failed:
            return text("有必需项目未通过。查看下方证据，修复后从头重测。",
                        "At least one required item failed. Review the evidence, fix it and rerun from the start.")
        case .expired:
            return text("网络状态或设置已经变化，旧结论不能再用于保护判断。",
                        "Network state or settings changed, so the old result cannot support a protection decision.")
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
        case .verified: return appAccent
        case .failed, .expired: return .orange
        case .needsNodeFailureTest, .needsClientExitTest, .needsRecovery: return .secondary
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
        messageSymbol == "exclamationmark.circle.fill" ? .orange : statusColor
    }

    private func stepComplete(_ number: Int) -> Bool {
        guard let record = controller.record, record.mode == mode else { return false }
        switch number {
        case 1: return record.baselinePassed
        case 2: return record.nodeFailureCheck?.level == .passed
        case 3: return record.clientExitCheck?.level == .passed
        case 4: return status == .verified
        default: return false
        }
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
        case .passed: return appAccent
        case .failed: return .orange
        case .warning, .unknown: return .secondary
        }
    }
}
