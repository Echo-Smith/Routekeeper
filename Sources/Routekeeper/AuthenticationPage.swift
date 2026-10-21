import SwiftUI
import GuardCore

struct AuthenticationPage: View {
    @Bindable var controller: CredentialController
    var launchAction: (() -> Void)? = nil
    private func text(_ zh: String, _ en: String) -> String { L10n.resolvedEnglish ? en : zh }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuardCard(title: text("Claude Code 登录凭证", "Claude Code sign-in"), subtitle: text("保存登录凭证，方便下次启动 Claude Code。凭证存放在这台 Mac 的系统钥匙串中。", "Reduce repeated web sign-ins. Credentials are stored only in macOS Keychain.")) {
                Label(statusText, systemImage: statusSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(controller.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let savedAt = controller.savedAt {
                    Text(text("保存时间：\(savedAt.formatted(date: .abbreviated, time: .shortened))", "Saved: \(savedAt.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GuardCard(title: text("获取登录凭证", "Get a sign-in token"), subtitle: text("点击下方按钮打开终端，按提示登录 Claude，再把生成的凭证（token）复制到这里。", "Run the official command in Terminal, then paste the generated token here.")) {
                Text(text("登录凭证相当于密码，请勿分享给他人。它不会出现在本应用的日志或导出报告中。", "Routekeeper does not read web sign-in, cookies or telemetry, and never writes the token to logs or exported reports."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        controller.openTokenSetup()
                    } label: {
                        Label(text("打开终端获取凭证", "Open claude setup-token"), systemImage: "terminal")
                    }
                    .routekeeperProminentButton()
                    Spacer()
                }
                SecureField(text("粘贴生成的登录凭证（token）", "Paste Claude Code token"), text: $controller.tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("claude-token-input")
                HStack {
                    Button(text("保存登录凭证", "Save to Keychain")) { controller.save() }
                        .routekeeperProminentButton()
                        .disabled(controller.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 || controller.busy)
                        .accessibilityIdentifier("claude-token-save")
                    Button(text("删除登录凭证", "Delete saved authentication"), role: .destructive) { controller.delete() }
                        .disabled(controller.status == .missing || controller.busy)
                    Spacer()
                    if controller.busy { ProgressView().controlSize(.small) }
                }
            }

            GuardCard(title: text("使用已保存的凭证启动", "Start with your saved token"), subtitle: text("启动时自动读取已保存的登录凭证，只供本次启动使用。", "Uses your saved token for the Claude Code process started here.")) {
                HStack {
                    Button {
                        if let launchAction { launchAction() }
                        else { controller.launchClaudeCode() }
                    } label: {
                        Label(text("启动 Claude Code", "Launch Claude Code from Keychain"), systemImage: "play.fill")
                    }
                    .routekeeperProminentButton()
                    .disabled(controller.status != .saved || controller.busy)
                    Spacer()
                }
                Text(text("请勿把凭证粘贴到项目文件或共享脚本中。使用这种登录方式时，远程控制（Remote Control）、定时任务（/schedule）和 claude.ai 连接器等功能可能不可用。", "Do not write the token to ~/.zshrc, project configuration or shared scripts. When the token is enabled, Claude Code may disable Remote Control, /schedule, claude.ai MCP connectors and related features."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GuardCard(title: text("凭证过期后怎么办？", "When your token expires"), subtitle: text("生成凭证时，终端会显示有效期。", "Check the expiry information shown when you generate the token.")) {
                Text(text("如果 Claude Code 提示凭证已过期或无效，点击“打开终端获取凭证”，重新登录，再把新凭证粘贴到这里保存。新凭证会替换旧凭证，需要你手动更新。", "If Claude Code says your token has expired or is invalid, generate a new one in Terminal and save it here. Saving replaces the old token. Updates are manual."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: String {
        switch controller.status {
        case .saved: return text("已保存登录凭证", "Sign-in token saved")
        case .missing: return text("尚未启用", "Not configured")
        case .error: return text("需要处理", "Action required")
        }
    }

    private var statusSymbol: String {
        switch controller.status {
        case .saved: return "checkmark.circle.fill"
        case .missing: return "key.slash"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .saved: return .green
        case .missing: return .secondary
        case .error: return .orange
        }
    }
}
