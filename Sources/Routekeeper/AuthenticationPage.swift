import SwiftUI
import GuardCore

struct AuthenticationPage: View {
    @Bindable var controller: CredentialController
    @Bindable var sandbox: SandboxCoordinator
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
                title: text("Claude Code 状态", "Claude Code status"),
                subtitle: text(
                    "登录凭证仅保存在 macOS 钥匙串；需要时可重新获取。",
                    "The credential is stored only in macOS Keychain and can be refreshed when needed."
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
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .routekeeperFont(.callout, weight: .semibold)
                        Text(controller.message)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let savedAt = controller.savedAt, isUsingSavedCredential {
                            Text(text(
                                "保存于 \(savedAt.formatted(date: .abbreviated, time: .shortened))",
                                "Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))"
                            ))
                            .routekeeperFont(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if controller.busy {
                        ProgressView().controlSize(.small)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(statusText), \(controller.message)")
                .accessibilityIdentifier("claude-credential-status")

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

            desktopLoginCard
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

        }
    }

    private var setupFlow: some View {
        GuardCard(
            title: text("获取 Claude Code 登录凭证", "Get a Claude Code credential"),
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
                    "仅保存到 macOS 钥匙串。",
                    "Store it only in macOS Keychain."
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text("登录凭证", "Claude Code token"))
                        .routekeeperFont(.caption, weight: .medium)
                        .foregroundStyle(.secondary)
                    SecureField(
                        text("粘贴 Claude Code 登录凭证", "Paste Claude Code token"),
                        text: $controller.tokenInput
                    )
                        .textFieldStyle(.roundedBorder)
                        .disabled(controller.busy)
                        .accessibilityLabel(text("Claude Code 登录凭证", "Claude Code token"))
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
                .routekeeperFont(.caption)
                .padding(.leading, 38)
            }
        }
    }

    private var sandboxUsageCard: some View {
        GuardCard(
            title: text("在沙箱中的用途", "Use in the sandbox"),
            subtitle: text("登录凭证可选，不阻止创建会话。",
                           "Sign-in is optional and never blocks session creation.")
        ) {
            Label(
                text("仅注入本次 Claude Code 启动。",
                     "Injected only for this Claude Code launch."),
                systemImage: "key.horizontal"
            )
            .routekeeperFont(.callout)
            .foregroundStyle(.secondary)

            Text(text(
                "Remote Control、/schedule 和 claude.ai 连接器可能不可用。",
                "Remote Control, /schedule and claude.ai connectors may be unavailable."
            ))
            .routekeeperFont(.caption)
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
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(text("删除已保存凭证", "Delete saved credential"), role: .destructive) {
                    controller.delete()
                }
                .disabled(controller.busy)
            }
            .padding(.top, 8)
        } label: {
            Label(text("管理 Claude Code 已保存凭证", "Manage the saved Claude Code credential"), systemImage: "key")
                .routekeeperFont(.callout, weight: .medium)
        }
        .padding(16)
        .cardSurface(corner: 18)
    }

    private var desktopLoginCard: some View {
        let session = sandbox.desktopSession
        let profileAvailable = session.persistedClaudeProfileAvailable
        let persist = sandbox.sharedConfiguration.persistClaudeLogin
        let enabled = sandbox.sharedConfiguration.isEnabled(.claudeDesktop)
        let statusColor = profileAvailable && persist ? appStatusSuccess : Color.secondary

        return GuardCard(
            title: text("Claude 登录", "Claude sign-in"),
            subtitle: text(
                "独立于 Claude Code 凭证。",
                "Separate from the Claude Code credential."
            )
        ) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: profileAvailable && persist
                    ? "checkmark.circle.fill"
                    : "person.crop.circle.badge.questionmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 38, height: 38)
                    .background(
                        statusColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(desktopProfileStatusTitle)
                        .routekeeperFont(.callout, weight: .semibold)
                    Text(desktopProfileStatusDetail)
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !enabled {
                    Text(text("保护对象未启用", "Target off"))
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.045), in: Capsule())
                }
            }

            AppHairline()

            Toggle(
                text("保留 Claude 登录状态", "Keep Claude sign-in"),
                isOn: $sandbox.sharedConfiguration.persistClaudeLogin
            )
            .toggleStyle(.switch)
            .disabled(session.phase.isActive || session.busy)

            Text(text(
                "登录状态保存在 Routekeeper 管理的独立配置中，不会交给 Claude Code。",
                "Sign-in is kept in a Routekeeper-managed profile and is never shared with Claude Code."
            ))
            .routekeeperFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if profileAvailable {
                AppHairline()
                HStack(alignment: .center, spacing: 12) {
                    Text(text(
                        "清除后，下次 Claude 会话需要重新登录。",
                        "After clearing, the next Claude session must sign in again."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(text("清除 Claude 登录数据", "Clear Claude sign-in data"), role: .destructive) {
                        _ = session.clearClaudeLoginState()
                    }
                    .disabled(session.phase.isActive || session.busy || session.claudeRunning)
                }
            }
        }
    }

    private var desktopProfileStatusTitle: String {
        let profileAvailable = sandbox.desktopSession.persistedClaudeProfileAvailable
        let persist = sandbox.sharedConfiguration.persistClaudeLogin
        if profileAvailable && persist {
            return text("已保留 Claude 登录状态", "Claude sign-in profile saved")
        }
        if profileAvailable {
            return text("已有 Claude 登录数据，但当前未启用保留",
                          "A Claude profile exists, but persistence is off")
        }
        if persist {
            return text("将在下次登录后保留 Claude 状态",
                          "Claude sign-in will be kept after the next login")
        }
        return text("当前使用临时 Claude 登录", "Claude currently uses a temporary sign-in")
    }

    private var desktopProfileStatusDetail: String {
        let profileAvailable = sandbox.desktopSession.persistedClaudeProfileAvailable
        let persist = sandbox.sharedConfiguration.persistClaudeLogin
        if profileAvailable && persist {
            return text(
                "后续隔离会话会继续使用这份登录数据；可以随时在下方清除。",
                "Future isolated sessions reuse this profile. You can clear it below at any time."
            )
        }
        if profileAvailable {
            return text(
                "现有登录数据不会删除；开启保留后才会再次使用。",
                "The existing profile is kept, but will be reused only after persistence is enabled."
            )
        }
        if persist {
            return text(
                "首次完成 Claude 登录后，登录状态会保存在独立配置中。",
                "After the first Claude sign-in, the session is stored in a separate profile."
            )
        }
        return text(
            "每次会话使用新的临时登录数据，会话结束后不会保留登录状态。",
            "Each session uses a fresh temporary profile and does not keep sign-in state afterward."
        )
    }

    private func credentialStep<Actions: View>(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .routekeeperFont(.caption, weight: .bold)
                .foregroundStyle(appAccent)
                .frame(width: 24, height: 24)
                .background(
                    appAccent.opacity(0.10),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .routekeeperFont(.callout, weight: .semibold)
                Text(detail)
                    .routekeeperFont(.caption)
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
