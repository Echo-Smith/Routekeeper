import GuardCore
import SwiftUI

enum SandboxDisableConfirmationStep: String, Identifiable {
    case initial
    case final

    var id: String { rawValue }
}

struct RoutekeeperConfirmationCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let stepLabel: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let isDestructive: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(
                        tint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .routekeeperFont(.title3, weight: .semibold)
                    Text(stepLabel)
                        .routekeeperFont(.caption, weight: .medium)
                        .foregroundStyle(.secondary)
                }
            }

            Text(message)
                .routekeeperFont(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                Button(cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(
                    confirmTitle,
                    role: isDestructive ? .destructive : nil,
                    action: onConfirm
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460, alignment: .leading)
    }
}

struct SandboxDisableConfirmationSheet: View {
    let step: SandboxDisableConfirmationStep
    let onCancel: () -> Void
    let onContinue: () -> Void

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        RoutekeeperConfirmationCard(
            symbol: step == .initial ? "exclamationmark.shield.fill" : "power.circle.fill",
            tint: step == .initial ? .orange : .red,
            title: step == .initial
                ? text("关闭实验性沙箱？", "Turn off the experimental sandbox?")
                : text("确认关闭实验性沙箱？", "Confirm sandbox shutdown"),
            stepLabel: step == .initial
                ? text("第 1 步，共 2 步", "Step 1 of 2")
                : text("第 2 步，共 2 步", "Step 2 of 2"),
            message: step == .initial
                ? text(
                    "共享设置、会话副本和交换文件都会保留；Claude 与 Chrome 都不会再从沙箱启动。",
                    "Shared settings, session copies and exchange files are retained. Neither Claude nor Chrome will launch from the sandbox."
                )
                : text(
                    "关闭后，Claude、Claude Code 和 Chrome 都不会再从沙箱启动；现有宿主应用不会被关闭。",
                    "After it is turned off, Claude, Claude Code and Chrome will no longer launch from the sandbox. Existing host applications will not be closed."
                ),
            cancelTitle: text("取消", "Cancel"),
            confirmTitle: step == .initial
                ? text("继续", "Continue")
                : text("关闭实验性沙箱", "Turn off experimental sandbox"),
            isDestructive: step == .final,
            onCancel: onCancel,
            onConfirm: onContinue
        )
    }
}
