import SwiftUI
import GuardCore

struct AuthenticationPage: View {
    @Bindable var controller: CredentialController
    var launchAction: (() -> Void)? = nil

    @State private var showRefreshFlow = false
    @State private var showPasteStep = false
    @State private var showCredentialManagement = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    private var isUsingSavedCredential: Bool {
        controller.status == .saved && !showRefreshFlow
    }

    private var needsSetupFlow: Bool {
        !isUsingSavedCredential
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuardCard(
                title: text("Claude Code 登录凭证", "Claude Code sign-in"),
                subtitle: text(
                    "保存后重复使用；只有凭证失效时才重新获取。",
                    "Reuse the saved credential; acquire a new one only when it expires."
                )
            ) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(statusColor)
                        .frame(width: 38, height: 38)
                        .background(
                            statusColor.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .font(.callout.weight(.semibold))
                        Text(controller.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let savedAt = controller.savedAt, isUsingSavedCredential {
                            Text(text(
                                "保存于 \(savedAt.formatted(date: .abbreviated, time: .shortened))",
                                "Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))"
                            ))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if controller.busy {
                        ProgressView().controlSize(.small)
                    }
                }

                if isUsingSavedCredential {
                    AppHairline()
                    savedCredentialActions
                }
            }

            if needsSetupFlow {
                setupFlow
            } else {
                sandboxUsageCard
                credentialManagement
            }
        }
        .onAppear {
            controller.refresh()
        }
        .onChange(of: controller.status) { _, status in
            if status == .saved {
                showRefreshFlow = false
                showPasteStep = false
            }
        }
    }

    private var savedCredentialActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let launchAction {
                        launchAction()
                    } else {
                        controller.launchClaudeCode()
                    }
                } label: {
                    Label(text("启动 Claude Code", "Launch Claude Code"), systemImage: "play.fill")
                }
                .routekeeperProminentButton()
                .disabled(controller.busy)

                Button {
                    showRefreshFlow = true
                    showPasteStep = false
                } label: {
                    Label(text("凭证已失效，重新获取", "Credential expired — refresh"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .routekeeperSecondaryButton()
                Spacer()
            }

            Text(text(
                "启动时只读取现有 Keychain 凭证，不会重新登录或覆盖它。只有在 Claude Code 提示凭证失效后，才需要使用右侧的更新流程。",
                "Launch reads the existing Keychain credential without signing in again or overwriting it. Use the refresh flow only after Claude Code reports that the credential has expired."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setupFlow: some View {
        GuardCard(
            title: text("获取登录凭证", "Get a sign-in credential"),
            subtitle: text("按顺序完成，不需要修改项目文件。",
                           "Complete these steps in order without editing project files.")
        ) {
            credentialStep(
                number: 1,
                title: text("在终端登录 Claude", "Sign in with Terminal"),
                detail: text(
                    "打开官方 setup-token 命令，并按终端提示完成登录。",
                    "Run the official setup-token command and complete the sign-in shown in Terminal."
                )
            ) {
                Button {
                    showPasteStep = true
                    controller.openTokenSetup()
                } label: {
                    Label(text("打开终端获取凭证", "Open Terminal"), systemImage: "terminal")
                }
                .routekeeperProminentButton()
            }

            AppHairline()

            credentialStep(
                number: 2,
                title: text("粘贴并保存", "Paste and save"),
                detail: text(
                    "只把终端生成的 token 保存在 macOS 钥匙串中，不写入日志、报告或项目。",
                    "Store only the generated token in macOS Keychain. It is never written to logs, reports or projects."
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField(text("粘贴登录凭证（token）", "Paste Claude Code token"),
                                text: $controller.tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .disabled(controller.busy)
                        .accessibilityIdentifier("claude-token-input")

                    HStack {
                        Button(text("保存到钥匙串", "Save to Keychain")) {
                            controller.save()
                        }
                        .routekeeperProminentButton()
                        .disabled(
                            controller.tokenInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .count < 20 || controller.busy
                        )
                        .accessibilityIdentifier("claude-token-save")

                        if controller.status == .saved {
                            Button(text("取消更新", "Cancel refresh")) {
                                showRefreshFlow = false
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .disabled(!showPasteStep)
            .opacity(showPasteStep ? 1 : 0.58)

            if !showPasteStep {
                Button(text("已有凭证，直接粘贴", "I already have a credential")) {
                    showPasteStep = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(.leading, 38)
            }
        }
    }

    private var sandboxUsageCard: some View {
        GuardCard(
            title: text("在沙箱中如何使用", "How the sandbox uses it"),
            subtitle: text("仅注入本次启动。", "Used only for this launch.")
        ) {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    text("从钥匙串读取，不写入项目、日志或交换目录。",
                         "Read from Keychain; never written to projects, logs or the exchange folder."),
                    systemImage: "key.horizontal"
                )
                Label(
                    text("凭证失效前持续复用；更新需手动操作。",
                         "Reused until it expires; updates require an explicit action."),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(text(
                "Remote Control、/schedule 和 claude.ai 连接器可能不可用。",
                "Remote Control, /schedule and claude.ai connectors may be unavailable."
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialManagement: some View {
        DisclosureGroup(isExpanded: $showCredentialManagement) {
            HStack(alignment: .center, spacing: 12) {
                Text(text(
                    "删除后，下次启动 Claude Code 需要重新获取凭证。",
                    "After deletion, the next Claude Code launch requires a new credential."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(text("删除已保存凭证", "Delete saved credential"), role: .destructive) {
                    controller.delete()
                }
                .disabled(controller.busy)
            }
            .padding(.top, 8)
        } label: {
            Label(text("管理已保存凭证", "Manage saved credential"), systemImage: "key")
                .font(.callout.weight(.medium))
        }
        .padding(16)
        .cardSurface(corner: 18)
    }

    private func credentialStep<Actions: View>(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(appAccent)
                .frame(width: 24, height: 24)
                .background(
                    appAccent.opacity(0.10),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        switch controller.status {
        case .saved:
            return isUsingSavedCredential
                ? text("已保存，可直接启动", "Saved and ready")
                : text("正在更新凭证", "Updating credential")
        case .missing:
            return text("尚未配置", "Not configured")
        case .error:
            return text("需要处理", "Action required")
        }
    }

    private var statusSymbol: String {
        switch controller.status {
        case .saved:
            return isUsingSavedCredential ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
        case .missing:
            return "key.slash"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .saved:
            return isUsingSavedCredential ? .green : .orange
        case .missing:
            return .secondary
        case .error:
            return .orange
        }
    }
}
