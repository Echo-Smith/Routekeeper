import AppKit
import GuardCore
import SwiftUI

enum SandboxPageMode {
    case management
    case networkCheck
}

enum SandboxSection: String, CaseIterable, Identifiable {
    case overview, scope, network, diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L10n.resolvedEnglish ? "Overview" : "概览"
        case .scope: return L10n.resolvedEnglish ? "Scope" : "范围"
        case .network: return L10n.resolvedEnglish ? "Network" : "网络"
        case .diagnostics: return L10n.resolvedEnglish ? "Diagnostics" : "诊断"
        }
    }
}

struct SandboxPage: View {
    @Bindable var store: GuardStore
    @Bindable var session: SandboxSession
    let mode: SandboxPageMode
    @Binding private var section: SandboxSection
    @State private var showAllChecks = false
    @State private var claudeLoginLink = ""
    @State private var handoffPreview: HandoffActionItem?

    init(
        store: GuardStore,
        mode: SandboxPageMode = .management,
        section: Binding<SandboxSection>? = nil
    ) {
        self.store = store
        self.session = store.sandbox
        self.mode = mode
        _section = section ?? .constant(.overview)
    }

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(spacing: 16) {
            sandboxModeCard
            if store.settings.experimentalSandboxEnabled {
                switch mode {
                case .management:
                    sandboxSectionPicker
                    managementContent
                case .networkCheck:
                    networkCheckContent
                }
            } else {
                sandboxDisabledCard
            }
        }
        .onAppear { session.refreshDetectedProxy() }
        .onChange(of: session.phase) { _, phase in
            if phase != .failed { showAllChecks = false }
        }
        .onChange(of: store.settings.experimentalSandboxEnabled) { _, enabled in
            if !enabled { section = .overview }
        }
        .sheet(item: $handoffPreview) { item in
            handoffPreviewSheet(item)
        }
    }

    @ViewBuilder
    private var managementContent: some View {
        switch section {
        case .overview:
            statusCard
            setupGuideCard
            controlsCard
        case .scope:
            configurationCard
        case .network:
            proxyConfigurationCard
            boundaryCard
            if !hasSavedExit { sandboxExitCard }
            gatewayReferenceCard
        case .diagnostics:
            if session.checks.isEmpty {
                diagnosticsEmptyCard
            } else {
                checksCard
            }
            if session.configuration.target == .claudeDesktop,
               session.desktopInstallation?.runtimeFamily == .electron,
               session.phase == .running || session.phase == .networkPaused {
                claudeLoginCallbackCard
            }
            if session.phase.isActive || session.phase == .ended
                || !session.externalActions.items.isEmpty {
                authorizationHandoffCard
            }
            if session.phase == .ended || !session.changedFiles.isEmpty { reviewCard }
        }
    }

    private var diagnosticsEmptyCard: some View {
        GuardCard(
            title: text("尚无诊断结果", "No diagnostics yet"),
            subtitle: text("创建会话后显示启动检查与运行记录。",
                           "Start a session to collect preflight checks and run records.")
        ) {
            Label(
                text("当前没有检查结果或待处理请求。",
                     "There are no check results or pending requests."),
                systemImage: "stethoscope"
            )
            .routekeeperFont(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var sandboxSectionPicker: some View {
        HStack(spacing: 12) {
            Picker("", selection: $section) {
                ForEach(SandboxSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 440)
            .accessibilityLabel(text("沙箱页面", "Sandbox sections"))
            .accessibilityIdentifier("sandbox-section-picker")

            Spacer()

            if session.phase.isActive {
                Label(
                    text("设置已锁定", "Settings locked"),
                    systemImage: "lock.fill"
                )
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var networkCheckContent: some View {
        statusCard
        setupGuideCard
        proxyConfigurationCard
        if !hasSavedExit { sandboxExitCard }
        if !session.checks.isEmpty { checksCard }
        controlsCard
        sandboxManagementLinkCard
    }

    private var statusCard: some View {
        let desktop = session.configuration.target == .claudeDesktop
        return GuardCard(
            title: text("实验性进程沙箱", "Experimental process sandbox"),
            subtitle: desktop
                ? text(
                    "Claude Desktop 仅访问工作副本、交换目录和经中继的网络。",
                    "Claude Desktop can access only the workspace, exchange folder and relayed network."
                )
                : text(
                    "Claude Code 仅访问工作副本、交换目录和经中继的网络。",
                    "Claude Code can access only the workspace, exchange folder and relayed network."
                )
        ) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: session.statusSymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 42, height: 42)
                    .background(
                        statusColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.statusTitle)
                        .routekeeperFont(.headline)
                    Text(session.message)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if session.busy || session.networkValidationInProgress {
                    ProgressView().controlSize(.small)
                }
            }

            AppHairline()
            HStack(spacing: 18) {
                Label(
                    session.networkEnabled
                        ? text("网络已开启", "Network on")
                        : session.phase.isActive || session.phase == .ended
                            ? text("网络已关闭", "Network off")
                            : text("尚未建立网络", "Network not started"),
                    systemImage: session.networkEnabled ? "network" : "wifi.slash"
                )
                .foregroundStyle(session.networkEnabled ? appAccent : Color.orange)
                Label(
                    session.claudeRunning ? text("Claude 正在运行", "Claude running") : text("Claude 未运行", "Claude not running"),
                    systemImage: session.claudeRunning ? "terminal.fill" : "terminal"
                )
                .foregroundStyle(.secondary)
            }
            .routekeeperFont(.callout, weight: .medium)
        }
    }

    private var configurationCard: some View {
        GuardCard(
            title: text("会话范围", "Session scope"),
            subtitle: session.configuration.target == .claudeDesktop
                ? text("Chat 只需交换目录；使用 Code 时可选择项目。",
                       "Chat needs only an exchange folder; add a project for Code.")
                : text("原项目只读复制，修改留在工作副本中。",
                       "The original project is copied; changes stay in the workspace.")
        ) {
            VStack(spacing: 12) {
                LabeledContent {
                    Picker("", selection: $session.configuration.target) {
                        ForEach(IsolationApplicationTarget.allCases, id: \.self) { target in
                            Text(target.title).tag(target)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(minWidth: 240, maxWidth: 320)
                    .accessibilityLabel(text("运行目标", "Application"))
                } label: {
                    Text(text("运行目标", "Application"))
                }
                .accessibilityElement(children: .contain)

                desktopInstallationRow
                if session.configuration.target == .claudeDesktop {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top, spacing: 12) {
                            Toggle(
                                text("保留 Claude Desktop 登录状态", "Keep Claude Desktop signed in"),
                                isOn: $session.configuration.persistClaudeLogin
                            )
                            .toggleStyle(.switch)
                            Spacer()
                            if session.persistedClaudeProfileAvailable {
                                Button(role: .destructive) {
                                    _ = session.clearClaudeLoginState()
                                } label: {
                                    Label(text("清除登录数据", "Clear sign-in data"), systemImage: "key.slash")
                                }
                                .routekeeperSecondaryButton()
                                .disabled(session.busy || session.phase.isActive || session.claudeRunning)
                            }
                        }
                        Text(text(
                            "登录状态仅保存在 Routekeeper 专属目录，可随时清除。",
                            "Sign-in state stays in a Routekeeper-owned folder and can be cleared at any time."
                        ))
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                folderRow(
                    title: session.configuration.target == .claudeDesktop
                        ? text("项目文件夹（可选）", "Project folder (optional)")
                        : text("项目文件夹", "Project folder"),
                    value: $session.configuration.projectPath,
                    placeholder: session.configuration.target == .claudeDesktop
                        ? text("可选：选择供 Code 使用的项目", "Optional: choose a project for Code")
                        : text("选择要复制的项目", "Choose a project to copy")
                )
                folderRow(
                    title: text("交换文件夹", "Exchange folder"),
                    value: $session.configuration.exchangePath,
                    placeholder: text("选择单独的文件交换目录", "Choose a separate file-exchange folder")
                )
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("Asia/Shanghai", text: $session.configuration.timezoneIdentifier)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(text("会话时区", "Session timezone"))
                        Menu(text("常用", "Presets")) {
                            ForEach([
                                "Asia/Shanghai", "Asia/Tokyo", "UTC",
                                "Europe/London", "America/New_York", "America/Los_Angeles"
                            ], id: \.self) { identifier in
                                Button(identifier) {
                                    session.configuration.timezoneIdentifier = identifier
                                }
                            }
                        }
                        .fixedSize()
                        .accessibilityLabel(text("常用时区", "Timezone presets"))
                    }
                } label: {
                    Text(text("会话时区", "Session timezone"))
                }
                .accessibilityElement(children: .contain)
                LabeledContent {
                    Text(session.sessionLocaleIdentifier)
                        .routekeeperFont(.callout, design: .monospaced)
                } label: {
                    Text(text("会话语言", "Session locale"))
                }
                Text(text(
                    "时区和语言只用于本次会话，不修改系统设置。",
                    "Timezone and language apply only to this session."
                ))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if session.configuration.target == .claudeDesktop {
                    Text(text(
                        "系统浏览器登录可能失败；沙箱不会因此开放直连。",
                        "System-browser sign-in may fail; the sandbox will not open direct access for it."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!session.phase.canChangeConfiguration)
        }
    }

    @ViewBuilder
    private var desktopInstallationRow: some View {
        if session.configuration.target == .claudeDesktop {
            let installation = session.desktopInstallation
            let supported = installation?.supportsIsolatedLaunch == true
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: supported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(supported ? appAccent : Color.orange)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        installation?.runtimeFamily == .electron
                            && session.desktopAppRunningOutsideSandbox
                            && !session.claudeRunning
                            ? text("Claude Desktop 当前正在运行", "Claude Desktop is currently running")
                            : installation == nil
                                ? text("未找到已验证签名的官方 Claude Desktop", "Verified official Claude Desktop not found")
                                : !supported
                                    ? text("官方客户端缺少可隔离启动的窗口或 daemon", "The official app has no isolatable window or daemon")
                                    : text("已验证官方 Claude Desktop", "Official Claude Desktop verified")
                    )
                    .routekeeperFont(.callout, weight: .medium)
                    if installation?.runtimeFamily == .electron,
                       session.desktopAppRunningOutsideSandbox,
                       !session.claudeRunning {
                        Text(text(
                            "请先完全退出 Claude Desktop 及其菜单栏进程，再点“重新检测”。否则单实例机制可能只激活沙箱外实例。",
                            "Fully quit Claude Desktop and its menu-bar process first, then choose Detect again. Otherwise its single-instance behavior may only activate the instance outside the sandbox."
                        ))
                        .routekeeperFont(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if let installation {
                        Text(desktopInstallationDetail(installation))
                            .routekeeperFont(.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !installation.supportsIsolatedLaunch {
                            Text(text(
                                "这个安装包既没有内嵌窗口，也没有通过签名校验的本地 Web daemon。Routekeeper 会拒绝回退到沙箱外浏览器。",
                                "This package has neither a bundled window nor a signed local web daemon. Routekeeper refuses the outside-browser fallback."
                            ))
                            .routekeeperFont(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        } else if installation.runtimeFamily == .operonHostedWeb {
                            Text(text(
                                "官方 Science 包本身不含 Shell。Routekeeper 会在外层沙箱中启动已签名的 claude-science daemon，并用只允许两个回环端口的受控窗口承载官方 Web UI。",
                                "The official Science package has no shell. Routekeeper runs the signed claude-science daemon inside the outer sandbox and hosts the official web UI in a controlled window limited to its two loopback ports."
                            ))
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(text(
                            "请从 Anthropic 官方渠道安装。Routekeeper 只检测并隔离启动已安装的客户端，不捆绑、不静默安装，也不会复制应用或登录数据。",
                            "Install from Anthropic’s official channel. Routekeeper only detects and launches an installed client; it does not bundle, silently install, or copy the app or sign-in data."
                        ))
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button(text("重新检测", "Detect again")) {
                    session.refreshDesktopDiscovery()
                }
                .routekeeperSecondaryButton()
                if installation == nil || !supported {
                    Button(text("获取官方客户端", "Get official app")) {
                        if let url = URL(string: "https://claude.ai/download") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .routekeeperSecondaryButton()
                }
            }
            .padding(10)
            .background(
                (supported ? appAccent : Color.orange).opacity(0.055),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
    }

    private func desktopInstallationDetail(_ installation: ClaudeDesktopInstallation) -> String {
        let version = installation.shortVersion.map { " · \($0)" } ?? ""
        let team = installation.teamIdentifier.map { " · Team \($0)" } ?? ""
        let family = installation.runtimeFamily == .electron
            ? "Electron"
            : "signed daemon + Routekeeper window"
        return "\(installation.displayName) · \(installation.bundleIdentifier) · \(family)\n\(installation.appURL.path)\(version)\(team)"
    }

    private var setupGuideCard: some View {
        let steps = setupGuideSteps
        return GuardCard(
            title: text("安全启动向导", "Safe-start guide"),
            subtitle: text("完成检查后再启动应用。", "Complete the checks before launch.")
        ) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(steps) { step in
                    setupGuideStep(step)
                }
            }
            .accessibilityElement(children: .contain)

            AppHairline()

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: guideNextSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(guideNextColor)
                    .frame(width: 34, height: 34)
                    .background(
                        guideNextColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text("下一步", "Next step"))
                        .routekeeperFont(.caption, weight: .semibold)
                        .foregroundStyle(guideNextColor)
                    Text(guideNextText)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                if let action = guideAction {
                    Button(action.title) {
                        performGuideAction(action)
                    }
                    .routekeeperProminentButton()
                    .disabled(action == .prepare && !session.canPrepare)
                }
            }
        }
    }

    private func setupGuideStep(_ step: SandboxGuideStepItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: step.state.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(step.state.color)
                    .frame(width: 22, height: 22)
                    .background(
                        step.state.color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .accessibilityHidden(true)
                Text(step.title)
                    .routekeeperFont(.caption, weight: .semibold)
                    .foregroundStyle(step.state == .pending ? .secondary : .primary)
            }
            Text(step.detail)
                .routekeeperFont(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .padding(10)
        .background(
            step.state.color.opacity(step.state == .pending ? 0.025 : 0.065),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(step.state.color.opacity(step.state == .pending ? 0.06 : 0.16), lineWidth: 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title)。\(step.detail)")
        .accessibilityValue(step.state.accessibilityValue)
    }

    private var proxyConfigurationCard: some View {
        let consistent = session.configurationMatchesDetectedProxy
        let hasDetectedProxy = session.detectedProxy != nil
        let color = consistent ? appAccent : hasDetectedProxy ? Color.orange : Color.secondary
        return GuardCard(
            title: text("代理配置一致性", "Proxy configuration consistency"),
            subtitle: text("创建会话时自动对齐系统代理。",
                           "Aligns with the system proxy when a session starts.")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: consistent ? "link.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(color)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.proxyConsistencyTitle)
                            .routekeeperFont(.callout, weight: .medium)
                        Text(session.proxyConsistencyDetail)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(text("重新检测", "Detect again")) {
                        session.refreshDetectedProxy()
                    }
                    .routekeeperSecondaryButton()
                    .disabled(!session.phase.canChangeConfiguration)
                }
                if !session.proxyDetectionMessage.isEmpty {
                    Text(session.proxyDetectionMessage)
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                }
                let exitAnchors = [session.expectedExits.ipv4, session.expectedExits.ipv6]
                    .compactMap { $0 }
                if !exitAnchors.isEmpty {
                    Label(
                        text("用于核对 Claude 出口：\(exitAnchors.joined(separator: " / "))",
                             "Claude exit anchors: \(exitAnchors.joined(separator: " / "))"),
                        systemImage: "target"
                    )
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                }
                if session.expectedExits.ipv4 != nil {
                    Text(text(
                        "若 Claude 经代理节点显示轮换 IPv6，预检会用同一中继的稳定 IPv4 出口核对，并记录本次 IPv6 证据，不会声称两者字面相同。",
                        "If the proxy node presents a rotating IPv6 address to Claude, preflight verifies the same relay’s stable IPv4 exit and records the observed IPv6 as evidence; it does not claim the addresses are literally equal."
                    ))
                    .routekeeperFont(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var checksCard: some View {
        let failedChecks = session.checks.filter { !$0.passed }
        let passed = failedChecks.isEmpty
        return GuardCard(
            title: text("启动前检查", "Preflight checks"),
            subtitle: text("全部通过后才允许启动。",
                           "Launch is allowed only after every check passes.")
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: passed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(passed ? appAccent : Color.orange)
                        .accessibilityHidden(true)
                    Text(
                        passed
                            ? text("\(session.checks.count) 项检查全部通过", "\(session.checks.count) checks passed")
                            : text("\(failedChecks.count) 项需要处理，其余通过", "\(failedChecks.count) need attention; the rest passed")
                    )
                    .routekeeperFont(.callout, weight: .semibold)
                    Spacer()
                }
                .padding(.bottom, 8)

                if !failedChecks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(failedChecks.enumerated()), id: \.element.id) { index, check in
                            checkRow(check, showRemediation: true)
                            if index < failedChecks.count - 1 { AppHairline() }
                        }
                    }
                }

                DisclosureGroup(
                    isExpanded: $showAllChecks,
                    content: {
                        VStack(spacing: 0) {
                            ForEach(Array(session.checks.enumerated()), id: \.element.id) { index, check in
                                checkRow(check, showRemediation: false)
                                if index < session.checks.count - 1 { AppHairline() }
                            }
                        }
                        .padding(.top, 6)
                    },
                    label: {
                        Text(text("查看全部 \(session.checks.count) 项检查", "Show all \(session.checks.count) checks"))
                            .routekeeperFont(.caption, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                )
                .padding(.top, failedChecks.isEmpty ? 0 : 8)
            }
        }
    }

    private func checkRow(_ check: IsolationCheck, showRemediation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(check.passed ? appAccent : Color.orange)
                    .frame(width: 18)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                Text(check.title)
                    .routekeeperFont(.callout, weight: .medium)
                    .frame(width: 130, alignment: .leading)
                Text(check.detail)
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showRemediation, !check.passed {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(Color.orange)
                        .accessibilityHidden(true)
                    Text(sandboxRemediation(for: check.id))
                        .routekeeperFont(.caption)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 29)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            check.passed
                ? text("通过", "Passed")
                : text("未通过", "Failed")
        )
    }

    private var controlsCard: some View {
        let desktop = session.configuration.target == .claudeDesktop
        return GuardCard(
            title: text("会话操作", "Session actions"),
            subtitle: desktop
                ? text("验证边界后启动官方客户端。", "Verify the boundary, then launch the official app.")
                : text("验证边界后从钥匙串启动。", "Verify the boundary, then launch with the Keychain token.")
        ) {
            HStack(spacing: 10) {
                Button {
                    Task { await store.prepareSandbox() }
                } label: {
                    Label(text("创建隔离会话", "Create isolated session"), systemImage: "lock.shield")
                }
                .routekeeperProminentButton()
                .disabled(!session.canPrepare)

                if session.phase == .running {
                    Button {
                        store.pauseSandboxNetwork()
                    } label: {
                        Label(text("关闭网络", "Turn network off"), systemImage: "wifi.slash")
                    }
                    .disabled(!session.canPauseNetwork)
                } else if session.phase == .networkPaused {
                    Button {
                        Task { await store.resumeSandboxNetwork() }
                    } label: {
                        Label(text("恢复网络", "Turn network on"), systemImage: "wifi")
                    }
                    .disabled(!session.canResumeNetwork)
                }
                Spacer()
                if session.busy || session.networkValidationInProgress {
                    ProgressView().controlSize(.small)
                    if session.networkValidationInProgress {
                        Text(text("稳定后复检", "Revalidating"))
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if session.phase == .running || session.phase == .networkPaused {
                AppHairline()
                HStack(spacing: 10) {
                    Button {
                        store.launchClaudeInSandbox()
                    } label: {
                        Label(
                            desktop
                                ? (session.desktopInstallation?.runtimeFamily == .operonHostedWeb
                                    ? text("启动 Claude Science（隔离窗口）", "Launch Claude Science in isolated window")
                                    : text("启动官方 Claude Desktop", "Launch official Claude Desktop"))
                                : text("在终端启动 Claude Code", "Launch Claude Code in Terminal"),
                            systemImage: "play.fill"
                        )
                    }
                    .routekeeperProminentButton()
                    .disabled(
                        !session.canLaunchClaude
                            || (desktop
                                ? !session.desktopIsolationSupported
                                    || (session.desktopInstallation?.runtimeFamily == .electron
                                        && session.desktopAppRunningOutsideSandbox)
                                : store.authentication.status != .saved)
                    )

                    Button(role: .destructive) {
                        Task { await store.endSandboxSession() }
                    } label: {
                        Label(text("结束会话", "End session"), systemImage: "stop.circle")
                    }
                    .disabled(session.busy)
                    Spacer()
                }
                if !desktop, store.authentication.status != .saved {
                    Label(
                        text(
                            "尚未保存 Claude Code 登录凭证。请先在“工具 → 登录凭证”中保存。",
                            "No Claude Code sign-in token is saved. Add one under Tools → Sign-in first."
                        ),
                        systemImage: "key.slash"
                    )
                    .routekeeperFont(.caption)
                    .foregroundStyle(.orange)
                }
            }

            if session.phase == .ended || session.phase == .failed {
                AppHairline()
                HStack(spacing: 10) {
                    Button {
                        session.openWorkspace()
                    } label: {
                        Label(text("打开工作副本", "Open workspace copy"), systemImage: "folder")
                    }
                    Button {
                        session.reset()
                    } label: {
                        Label(text("清理本次会话", "Reset this session"), systemImage: "trash")
                    }
                    Spacer()
                }
            }
        }
    }

    private var claudeLoginCallbackCard: some View {
        let canSubmit = session.phase == .running
            && session.networkEnabled
            && session.claudeRunning
            && session.claudeLoginCallbackStatus != .waiting
        return GuardCard(
            title: text("邮件登录回调", "Email sign-in callback"),
            subtitle: text(
                "不要直接点击邮件里的登录按钮。请右键点击“Sign in”并选择“复制链接地址”，再粘贴到这里，由 Routekeeper 交给沙箱中的 Claude。",
                "Do not click the sign-in button in the email. Right-click “Sign in”, choose “Copy Link Address”, and paste it here so Routekeeper can hand it to the sandboxed Claude instance."
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    text(
                        "直接在默认浏览器打开会让 claude.ai 看到沙箱外的出口，并可能激活另一个 Claude 实例。Routekeeper 不读取邮箱、不访问该链接，也不会保存或记录链接中的一次性凭证。",
                        "Opening the link in the default browser exposes a network path outside the sandbox to claude.ai and may activate another Claude instance. Routekeeper does not read your mailbox, fetch the link, or save or log its one-time credential."
                    ),
                    systemImage: "exclamationmark.shield.fill"
                )
                .routekeeperFont(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    SecureField(
                        text(
                            "粘贴邮件中的 claude.ai/magic-link 链接",
                            "Paste the claude.ai/magic-link URL from the email"
                        ),
                        text: $claudeLoginLink
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(text("邮件登录链接", "Email sign-in URL"))
                    .accessibilityIdentifier("claude-login-link-input")

                    Button(text("交给沙箱 Claude", "Send to sandboxed Claude")) {
                        if session.submitClaudeLoginLink(claudeLoginLink) {
                            claudeLoginLink = ""
                        }
                    }
                    .routekeeperProminentButton()
                    .disabled(
                        !canSubmit
                            || claudeLoginLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("claude-login-link-submit")

                    if !claudeLoginLink.isEmpty {
                        Button(text("清除", "Clear")) {
                            claudeLoginLink = ""
                        }
                        .routekeeperSecondaryButton()
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    switch session.claudeLoginCallbackStatus {
                    case .waiting:
                        ProgressView().controlSize(.small)
                    case .delivered:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(appAccent)
                    case .invalid, .failed:
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.orange)
                    case .idle:
                        Image(systemName: "key.horizontal").foregroundStyle(Color.secondary)
                    }
                    Text(session.claudeLoginCallbackMessage)
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("claude-login-link-status")
            }
        }
    }

    private var gatewayReferenceCard: some View {
        let mode = store.settings.gatewayProtectionMode
        let status = store.gatewayVerification.status(for: mode)
        return GuardCard(
            title: text("代理网关检查", "Proxy gateway check"),
            subtitle: text(
                "作为代理链路的旁证显示；沙箱启动仍以本页自己的进程与网络预检为准。",
                "This is reference evidence for the proxy chain. Sandbox launch still depends on its own process and network preflight on this page."
            )
        ) {
            HStack(spacing: 12) {
                Image(systemName: status == .verified ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(status == .verified ? appAccent : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(gatewayReferenceTitle(status))
                        .routekeeperFont(.callout, weight: .semibold)
                    Text(text(
                        "沙箱网络只允许经过 Routekeeper 中继；代理不可用时直接失败，不会退回公网直连。",
                        "Sandbox traffic is allowed only through the Routekeeper relay. If the proxy is unavailable, it fails instead of falling back to direct internet access."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(text("网络保护", "Network protection")) {
                    AppNavigationRequest.request(.networkProtection)
                }
                .routekeeperSecondaryButton()
            }
        }
    }

    private func gatewayReferenceTitle(_ status: GatewayVerificationStatus) -> String {
        switch status {
        case .verified: return text("当前代理网关已验证", "Current proxy gateway verified")
        case .unverified: return text("当前代理网关尚未验证", "Current proxy gateway not verified")
        case .needsNodeFailureTest: return text("代理网关待测节点断开", "Gateway node-failure test pending")
        case .needsClientExitTest: return text("代理网关待测客户端退出", "Gateway client-exit test pending")
        case .needsRecovery: return text("代理网关待恢复并复测", "Gateway recovery check pending")
        case .failed: return text("代理网关检查未通过", "Gateway verification failed")
        case .expired: return text("代理网关证据已过期", "Gateway evidence expired")
        }
    }

    private var authorizationHandoffCard: some View {
        GuardCard(
            title: text("授权隔离", "Authorization handoff"),
            subtitle: text(
                "Claude 只能提交操作请求，不能读取 Git、Notion 或其他外部服务的凭据。只有经你确认后，宿主侧才会保存交付文件或应用补丁。",
                "Claude can submit an operation request but cannot read credentials for Git, Notion or other external services. The host acts only after your approval."
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(appAccent)
                        .frame(width: 36, height: 36)
                        .background(
                            appAccent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text("交接目录", "Handoff directory"))
                            .routekeeperFont(.callout, weight: .semibold)
                        Text(".routekeeper-actions")
                            .routekeeperFont(.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                        Text(session.externalActions.message)
                            .routekeeperFont(.caption)
                            .foregroundStyle(
                                session.externalActions.pendingCount > 0
                                    ? Color.orange
                                    : Color.secondary
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(text("复制请求格式", "Copy request format")) {
                        copyHandoffInstructions()
                    }
                    .routekeeperSecondaryButton()
                    Button(text("打开目录", "Open folder")) {
                        session.externalActions.openDirectory()
                    }
                    .routekeeperSecondaryButton()
                    .disabled(session.externalActions.directoryURL == nil)
                }

                if session.externalActions.items.isEmpty {
                    Label(
                        text(
                            "尚未收到请求。Claude 需要外部操作时，只能把 JSON 清单和交付文件写入该目录。",
                            "No requests yet. When Claude needs an external operation, it can only write a JSON manifest and payload into this directory."
                        ),
                        systemImage: "tray"
                    )
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(session.externalActions.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { AppHairline() }
                        handoffActionRow(item)
                    }
                }

                if !session.externalActions.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            text("已拒绝的请求", "Rejected requests"),
                            systemImage: "exclamationmark.shield"
                        )
                        .routekeeperFont(.caption, weight: .semibold)
                        .foregroundStyle(Color.orange)
                        ForEach(session.externalActions.issues.prefix(4)) { issue in
                            Text("\(issue.manifestName)：\(issue.message)")
                                .routekeeperFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if session.externalActions.issues.count > 4 {
                            Text(text(
                                "另有 \(session.externalActions.issues.count - 4) 条无效请求未显示。",
                                "\(session.externalActions.issues.count - 4) more invalid request(s) hidden."
                            ))
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func handoffActionRow(_ item: HandoffActionItem) -> some View {
        let request = item.package.request
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: request.kind == .applyGitPatch ? "arrow.down.doc" : "doc.badge.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(appAccent)
                    .frame(width: 32, height: 32)
                    .background(
                        appAccent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(request.title)
                            .routekeeperFont(.callout, weight: .semibold)
                        Text(handoffKindLabel(request.kind))
                            .routekeeperFont(.caption2, weight: .medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.055), in: Capsule())
                    }
                    if !request.summary.isEmpty {
                        Text(request.summary)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(
                        "\(request.suggestedName) · \(handoffByteCount(item.package.payloadBytes)) · SHA256 \(item.package.payloadSHA256.prefix(12))"
                    )
                    .routekeeperFont(.caption2, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                handoffStateBadge(item.state)
            }

            if let detail = handoffStateDetail(item.state) {
                Text(detail)
                    .routekeeperFont(.caption)
                    .foregroundStyle(handoffStateColor(item.state))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 43)
            }

            HStack(spacing: 8) {
                Button(text("查看内容", "Inspect")) {
                    handoffPreview = item
                }
                .routekeeperSecondaryButton()

                if request.kind == .exportFile {
                    Button(text("保存到…", "Save to…")) {
                        chooseHandoffDestination(item)
                    }
                    .routekeeperProminentButton()
                    .disabled(!item.state.isActionable)
                } else {
                    Button(text("应用到 Git 仓库…", "Apply to Git repository…")) {
                        chooseGitRepository(item)
                    }
                    .routekeeperProminentButton()
                    .disabled(!item.state.isActionable)
                    Button(text("另存补丁…", "Save patch…")) {
                        choosePatchDestination(item)
                    }
                    .routekeeperSecondaryButton()
                    .disabled(!item.state.isActionable)
                }

                if item.state.isActionable {
                    Button(text("拒绝", "Reject"), role: .destructive) {
                        session.externalActions.reject(item)
                    }
                    .routekeeperSecondaryButton()
                }
                if case .running = item.state {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            .padding(.leading, 43)
        }
    }

    private func handoffStateBadge(_ state: HandoffApprovalState) -> some View {
        Text(handoffStateTitle(state))
            .routekeeperFont(.caption2, weight: .semibold)
            .foregroundStyle(handoffStateColor(state))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(handoffStateColor(state).opacity(0.10), in: Capsule())
    }

    private func handoffStateTitle(_ state: HandoffApprovalState) -> String {
        switch state {
        case .pending: return text("待确认", "Pending")
        case .running: return text("执行中", "Running")
        case .completed: return text("已完成", "Completed")
        case .failed: return text("失败", "Failed")
        case .rejected: return text("已拒绝", "Rejected")
        }
    }

    private func handoffStateDetail(_ state: HandoffApprovalState) -> String? {
        switch state {
        case .completed(let message), .failed(let message): return message
        case .pending, .running, .rejected: return nil
        }
    }

    private func handoffStateColor(_ state: HandoffApprovalState) -> Color {
        switch state {
        case .pending: return .orange
        case .running: return appAccent
        case .completed: return .green
        case .failed: return .orange
        case .rejected: return .secondary
        }
    }

    private func handoffKindLabel(_ kind: HandoffActionKind) -> String {
        switch kind {
        case .exportFile: return text("文件交付", "File handoff")
        case .applyGitPatch: return text("Git 补丁", "Git patch")
        }
    }

    private func handoffByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func chooseHandoffDestination(_ item: HandoffActionItem) {
        let panel = NSSavePanel()
        panel.title = text("保存交付文件", "Save handoff file")
        panel.prompt = text("保存", "Save")
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.package.request.suggestedName
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        session.externalActions.export(item, to: destination)
        store.log(text("已提交宿主侧文件保存。", "Requested a host-side file save."))
    }

    private func choosePatchDestination(_ item: HandoffActionItem) {
        let panel = NSSavePanel()
        panel.title = text("保存审阅后的补丁", "Save reviewed patch")
        panel.prompt = text("保存", "Save")
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.package.request.suggestedName
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try item.package.payloadData.write(to: destination, options: .atomic)
            session.externalActions.message = text(
                "补丁已保存；不会自动提交或推送。",
                "The patch was saved; nothing was committed or pushed."
            )
            store.log(session.externalActions.message)
        } catch {
            session.externalActions.message = "保存补丁失败：\(error.localizedDescription)"
            store.log(session.externalActions.message, attention: true)
        }
    }

    private func chooseGitRepository(_ item: HandoffActionItem) {
        let panel = NSOpenPanel()
        panel.title = text("选择要应用补丁的 Git 仓库", "Choose the Git repository")
        panel.prompt = text("应用补丁", "Apply patch")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let repository = panel.url else { return }
        session.externalActions.applyGitPatch(item, repository: repository)
        store.log(text(
            "已提交宿主侧 Git 补丁应用；不会自动提交或推送。",
            "Requested host-side Git patch application; no commit or push will be performed."
        ))
    }

    private func copyHandoffInstructions() {
        let instructions = text(
            """
            如果本次任务需要外部操作，只能在 $ISOLATION_EXCHANGE/.routekeeper-actions 中写入请求，不要索取或输出任何密码、token、Cookie、真实账户链接或本地绝对路径。每个请求使用一个 JSON 清单和一个同目录交付文件：

            {
              "schemaVersion": 1,
              "requestID": "生成一个 UUID",
              "kind": "file.export",
              "title": "简短标题",
              "summary": "说明操作内容和包含的数据",
              "payload": "result.md",
              "suggestedName": "result.md"
            }

            可用 kind：
            - file.export：由用户在宿主侧选择位置保存交付文件。
            - git.applyPatch：payload 必须是 .patch 或 .diff，由用户在宿主侧选择仓库并应用；不会自动提交或推送。

            写入后停止外部操作，等待用户在 Routekeeper 中确认。
            """,
            """
            If this task needs an external operation, write the request only under $ISOLATION_EXCHANGE/.routekeeper-actions. Never request or output passwords, tokens, cookies, real account URLs or absolute local paths. Use one JSON manifest and one payload in the same directory:

            {
              "schemaVersion": 1,
              "requestID": "generate a UUID",
              "kind": "file.export",
              "title": "Short title",
              "summary": "Describe the operation and included data",
              "payload": "result.md",
              "suggestedName": "result.md"
            }

            Supported kinds:
            - file.export: the user chooses a host location for the payload.
            - git.applyPatch: payload must be .patch or .diff; the user chooses a host repository. Routekeeper never commits or pushes.

            After writing the request, stop external operations and wait for approval in Routekeeper.
            """
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(instructions, forType: .string)
        store.notice = text("已复制授权隔离请求格式。", "Copied the authorization-handoff request format.")
    }

    private func handoffPreviewSheet(_ item: HandoffActionItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.package.request.title)
                        .routekeeperFont(.title3, weight: .semibold)
                    Text(item.package.request.summary)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(text("关闭", "Close")) { handoffPreview = nil }
            }
            AppHairline()
            ScrollView {
                Text(handoffPreviewText(item.package))
                    .routekeeperFont(.caption, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .padding(18)
        .frame(minWidth: 720, minHeight: 480)
    }

    private func handoffPreviewText(_ package: HandoffActionPackage) -> String {
        let prefix = package.payloadData.prefix(256 * 1024)
        guard let text = String(data: prefix, encoding: .utf8) else {
            return text(
                "二进制交付文件 · \(handoffByteCount(package.payloadBytes))",
                "Binary payload · \(handoffByteCount(package.payloadBytes))"
            )
        }
        if package.payloadBytes > prefix.count {
            return text + "\n\n[预览已截断]"
        }
        return text
    }

    private var reviewCard: some View {
        GuardCard(
            title: text("审阅项目变化", "Review project changes"),
            subtitle: text(
                "Routekeeper 不会自动把工作副本覆盖回原项目。请先打开副本检查差异，再自行决定如何采用。",
                "Routekeeper never copies the workspace back automatically. Open the copy, review the changes, then decide how to apply them."
            )
        ) {
            if session.changedFiles.isEmpty {
                Label(
                    text("没有发现项目文件变化。", "No project file changes were found."),
                    systemImage: "equal.circle"
                )
                .foregroundStyle(.secondary)
            } else {
                Text(text("发现 \(session.changedFiles.count) 条文件差异", "\(session.changedFiles.count) file differences found"))
                    .routekeeperFont(.callout, weight: .medium)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(session.changedFiles, id: \.self) { line in
                        Text(line)
                            .routekeeperFont(.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var boundaryCard: some View {
        GuardCard(
            title: text("代理与边界", "Proxy and boundaries"),
            subtitle: text(
                "Routekeeper 只连接你填写的本机代理端口。HTTP CONNECT 与 SOCKS5 可对接本机代理客户端提供的中转端口。",
                "Routekeeper connects only to the local proxy port you enter. HTTP CONNECT and SOCKS5 work with local relay ports provided by proxy clients."
            )
        ) {
            VStack(spacing: 12) {
                LabeledContent {
                    HStack(spacing: 10) {
                        Picker("", selection: $session.configuration.upstream.protocolType) {
                            ForEach(IsolationUpstreamProtocol.allCases, id: \.self) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(minWidth: 210, maxWidth: 260)
                        .accessibilityLabel(text("上游协议", "Upstream protocol"))
                        Menu(text("常用本地端口", "Common local ports")) {
                            Button(text("混合代理 7890", "Mixed proxy 7890")) {
                                session.configuration.upstream.protocolType = .httpConnect
                                session.configuration.upstream.port = 7890
                            }
                            Button(text("HTTP 代理 10809", "HTTP proxy 10809")) {
                                session.configuration.upstream.protocolType = .httpConnect
                                session.configuration.upstream.port = 10809
                            }
                            Button(text("SOCKS 代理 10808", "SOCKS proxy 10808")) {
                                session.configuration.upstream.protocolType = .socks5
                                session.configuration.upstream.port = 10808
                            }
                            Button(text("SOCKS 代理 1080", "SOCKS proxy 1080")) {
                                session.configuration.upstream.protocolType = .socks5
                                session.configuration.upstream.port = 1080
                            }
                        }
                        .fixedSize()
                    }
                } label: {
                    Text(text("上游协议", "Upstream protocol"))
                }
                .accessibilityElement(children: .contain)
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField(
                            "7890",
                            value: $session.configuration.upstream.port,
                            format: .number.grouping(.never)
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .accessibilityLabel(text("本地端口", "Local port"))
                        Stepper("", value: $session.configuration.upstream.port, in: 1...65535)
                            .labelsHidden()
                            .accessibilityLabel(text("本地端口", "Local port"))
                    }
                } label: {
                    Text(text("本地端口", "Local port"))
                }
                .accessibilityElement(children: .contain)
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("", text: $session.configuration.upstream.username)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(text("用户名（可选）", "Username (optional)"))
                        SecureField(text("密码（可选）", "Password (optional)"), text: $session.configuration.upstream.password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(text("密码（可选）", "Password (optional)"))
                    }
                } label: {
                    Text(text("用户名（可选）", "Username (optional)"))
                }
                .accessibilityElement(children: .contain)
                Text(text(
                    "上游地址固定为本机；密码只用于本次运行。",
                    "The upstream is always local; the password is used only for this run."
                ))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(text(
                    "这是进程隔离，不是虚拟机；Claude 仍能读取本机网络配置。",
                    "This is process isolation, not a virtual machine; Claude can still read host network configuration."
                ))
                .routekeeperFont(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    session.configuration.target == .claudeDesktop
                        ? text(
                            "Chat 与派生的 helper 应继承同一沙箱边界；Code 模式依赖的本地服务仍以启动检查结果为准。",
                            "Chat and spawned helpers inherit the same boundary; Code-mode local services remain subject to preflight."
                        )
                        : text(
                            "沙箱不允许 localhost 服务器或默认浏览器；请结束会话后预览工作副本。",
                            "Localhost servers and the default browser are blocked; preview the workspace after ending the session."
                        )
                )
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!session.phase.canChangeConfiguration)
        }
    }

    private var sandboxModeCard: some View {
        GuardCard(
            title: text("独立沙箱", "Standalone sandbox"),
            subtitle: text("将 Claude 放入受限进程环境。",
                           "Run Claude inside a restricted process boundary.")
        ) {
            HStack(alignment: .center, spacing: 12) {
                Toggle(
                    text("启用沙箱模式", "Enable sandbox mode"),
                    isOn: Binding(
                        get: { store.settings.experimentalSandboxEnabled },
                        set: { enabled in
                            if !enabled && store.sandbox.phase.isActive {
                                store.notice = text(
                                    "请先结束当前沙箱会话，再关闭沙箱模式。",
                                    "End the active sandbox session before turning sandbox mode off."
                                )
                                return
                            }
                            store.settings.experimentalSandboxEnabled = enabled
                        }
                    )
                )
                .toggleStyle(.switch)
                .disabled(session.phase.isActive)
                Spacer()
                if store.settings.experimentalSandboxEnabled {
                    Text(session.statusTitle)
                        .routekeeperFont(.caption, weight: .medium)
                        .foregroundStyle(session.phase == .failed ? Color.orange : Color.secondary)
                }
            }
            if session.phase.isActive {
                Label(
                    text("结束当前会话后才能关闭沙箱。",
                         "End the active session before turning the sandbox off."),
                    systemImage: "lock.fill"
                )
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var sandboxDisabledCard: some View {
        GuardCard(
            title: text("沙箱尚未启用", "Sandbox is off"),
            subtitle: text("启用后在这里管理会话。",
                           "Enable it to manage sessions here.")
        ) {
            VStack(alignment: .leading, spacing: 9) {
                Label(text("文件修改只保留在本次工作副本中。",
                           "File changes remain in this session’s workspace copy."),
                      systemImage: "folder.badge.questionmark")
                Label(text("Claude 的网络流量只能经过 Routekeeper 中继，失败时不会回落直连。",
                           "Claude traffic can use only the Routekeeper relay and never falls back to a direct connection."),
                      systemImage: "network.slash")
                Label(text("Claude Code 自己的权限提示和内部沙箱仍应保持启用。",
                           "Keep Claude Code’s own permission prompts and internal sandbox enabled."),
                      systemImage: "checkmark.shield")
            }
            .routekeeperFont(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sandboxExitCard: some View {
        GuardCard(
            title: text("获取沙箱出口", "Detect sandbox exit"),
            subtitle: text(
                "沙箱会先保存当前一致出口，再用它核对 Claude 经中继看到的结果。",
                "Save the current matching exit first, then use it to verify what Claude observes through the relay."
            )
        ) {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text(text(
                    "检测不会启动 Claude，也不会创建会话。",
                    "Detection does not launch Claude or create a session."
                ))
                .routekeeperFont(.callout)
                .foregroundStyle(.secondary)
                Spacer()
                Button(text("检测并保存出口", "Detect and save exit")) {
                    Task { await store.detectExitForSandbox() }
                }
                .routekeeperSecondaryButton()
                .disabled(store.checking || session.busy || session.phase.isActive)
            }
        }
    }

    private var sandboxManagementLinkCard: some View {
        GuardCard(
            title: text("会话范围", "Session scope"),
            subtitle: text(
                "项目、交换文件夹、运行目标与启动操作在独立沙箱页管理。",
                "Manage projects, the exchange folder, launch target and start actions on the standalone Sandbox page."
            )
        ) {
            HStack {
                Text(session.configuration.target.title)
                    .routekeeperFont(.callout, weight: .medium)
                if !session.configuration.exchangePath.isEmpty {
                    Text(abbreviatedPath(session.configuration.exchangePath))
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(text("打开沙箱", "Open sandbox")) {
                    AppNavigationRequest.request(.sandbox)
                }
                .routekeeperSecondaryButton()
            }
        }
    }

    private var hasSavedExit: Bool {
        store.settings.target(for: .ipv4) != nil
            || store.settings.target(for: .ipv6) != nil
    }

    private var hasSessionScope: Bool {
        session.configuration.hasRequiredPaths
            && session.configuration.hasValidTimezone
            && session.configuration.upstream.isValid
    }

    private var preflightPassed: Bool {
        !session.checks.isEmpty && session.checks.allSatisfy(\.passed)
    }

    private var proxyStepComplete: Bool {
        if preflightPassed { return true }
        guard let detected = session.detectedProxy else { return false }
        return detected.isLoopback && session.configurationMatchesDetectedProxy
    }

    private var setupGuideSteps: [SandboxGuideStepItem] {
        let desktop = session.configuration.target == .claudeDesktop
        let clientReady = desktop ? session.desktopIsolationSupported : store.authentication.status == .saved
        let completed = [
            proxyStepComplete,
            hasSavedExit,
            hasSessionScope && clientReady,
            preflightPassed
        ]
        let titles = [
            text("1  代理", "1  Proxy"),
            text("2  出口", "2  Exit"),
            desktop
                ? text("3  范围与客户端", "3  Scope & app")
                : text("3  范围与登录", "3  Scope & sign-in"),
            text("4  隔离启动", "4  Isolation")
        ]
        var currentAssigned = false
        return titles.indices.map { index in
            let state: SandboxGuideStepState
            if completed[index] {
                state = .complete
            } else if index == 0, session.detectedProxy?.isLoopback == false {
                state = .attention
            } else if !currentAssigned {
                state = .current
                currentAssigned = true
            } else {
                state = .pending
            }
            return SandboxGuideStepItem(
                id: index,
                title: titles[index],
                detail: setupGuideDetail(for: index, state: state),
                state: state
            )
        }
    }

    private func setupGuideDetail(for index: Int, state: SandboxGuideStepState) -> String {
        switch index {
        case 0:
            if state == .complete, preflightPassed {
                return text("隔离进程已确认只能经过本地中继。", "The isolated process passed the relay checks.")
            }
            if let detected = session.detectedProxy, detected.isLoopback {
                return text(
                    "已识别 \(detected.protocolType.title) \(detected.port)",
                    "Detected \(detected.protocolType.title) \(detected.port)"
                )
            }
            if session.detectedProxy != nil {
                return text("代理入口需要改为本机地址。", "Use a local proxy entry.")
            }
            return text("使用 TUN 时，确认下方本地端口。", "For TUN, confirm the local port below.")
        case 1:
            if let exit = store.settings.target(for: .ipv4) ?? store.settings.target(for: .ipv6) {
                return text("已保存 \(exit)", "Saved \(exit)")
            }
            return text("体检并保存一个出口 IP。", "Run a check and save an exit IP.")
        case 2:
            if session.configuration.target == .claudeDesktop {
                if session.desktopInstallation?.runtimeFamily == .electron,
                   session.desktopAppRunningOutsideSandbox,
                   !session.claudeRunning {
                    return text("先完全退出当前 Claude Desktop，再重新检测。", "Fully quit the running Claude Desktop, then detect it again.")
                }
                if !session.desktopInstalled {
                    return text("选择交换目录，并安装官方 Claude Desktop。项目目录仅供 Code 模式按需选择。", "Choose an exchange folder and install official Claude Desktop. A project folder is optional for Code.")
                }
                if !session.desktopIsolationSupported {
                    return text(
                        "当前官方包没有可托管的窗口或签名 daemon，不能回退到沙箱外浏览器。",
                        "The current official package has no hostable window or signed daemon and cannot fall back to an outside browser."
                    )
                }
                return state == .complete
                    ? text("交换目录、可选项目和官方客户端已就绪。", "Exchange scope, optional project and the official app are ready.")
                    : text("选择交换目录；项目可按需选择，已检测到官方 Claude Desktop。", "Choose an exchange folder; a project is optional. Official Claude Desktop is installed.")
            }
            return state == .complete
                ? text("项目、交换目录和登录凭证已就绪。", "Folder scope and sign-in are ready.")
                : text("选择两个目录并保存登录凭证。", "Choose two folders and save sign-in.")
        case 3:
            return state == .complete
                ? text("失败断网、中继与出口均已通过。", "Fail-closed, relay and exit checks passed.")
                : text("通过检查后才允许启动 Claude。", "Claude launches only after all checks pass.")
        default:
            return ""
        }
    }

    private var guideAction: SandboxGuideAction? {
        if session.phase == .running { return nil }
        if session.phase == .networkPaused { return .resumeNetwork }
        if session.phase == .preparing || session.phase == .checking { return nil }
        if session.detectedProxy?.isLoopback == false { return .detectProxy }
        if !hasSavedExit { return .detectExit }
        if session.configuration.target == .claudeCode,
           session.configuration.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .chooseProject
        }
        if session.configuration.exchangePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .chooseExchange
        }
        if session.configuration.target == .claudeDesktop, !session.desktopIsolationSupported {
            return .desktopInstall
        }
        if session.configuration.target == .claudeDesktop,
           session.desktopInstallation?.runtimeFamily == .electron,
           session.desktopAppRunningOutsideSandbox,
           !session.claudeRunning {
            return .desktopRunning
        }
        if session.configuration.target == .claudeCode, store.authentication.status != .saved {
            return .authentication
        }
        if session.phase == .ended { return .openWorkspace }
        return .prepare
    }

    private var guideNextText: String {
        switch guideAction {
        case .resumeNetwork:
            return text(
                "网络已暂停。确认代理节点已恢复后，重新执行完整预检。",
                "Network is paused. Restore the proxy node, then rerun the complete preflight."
            )
        case .detectProxy:
            return text(
                "系统代理不是本机入口。请在代理客户端开启本机 HTTP、SOCKS 或混合端口。",
                "The system proxy is not a local endpoint. Enable a local HTTP, SOCKS or mixed port."
            )
        case .detectExit:
            return text(
                "先检测并保存当前稳定出口。沙箱会用同一中继核对 Claude 路径；节点轮换 IPv6 时使用 IPv4 锚点。",
                "Detect and save the current stable exit. The sandbox verifies Claude through the same relay and uses the IPv4 anchor when the node rotates IPv6."
            )
        case .chooseProject:
            return text("选择要复制的项目文件夹；原文件夹不会被直接修改。", "Choose the project to copy; the original is not edited directly.")
        case .chooseExchange:
            return text("选择一个单独的交换文件夹，用于有意传入或取出文件。", "Choose a separate exchange folder for intentional file transfer.")
        case .authentication:
            return text(
                "在“工具 → 登录凭证”中保存 token，避免启动时转到沙箱外的浏览器。",
                "Save a token under Tools → Sign-in so launch does not fall back to a browser outside the sandbox."
            )
        case .desktopInstall:
            if session.desktopInstallation?.supportsIsolatedLaunch == false {
                return text(
                    "当前官方安装包没有可安全托管的窗口或签名 daemon。Routekeeper 不会为了启动而降低隔离边界。",
                    "The installed official package has no safely hostable window or signed daemon. Routekeeper will not weaken isolation just to launch it."
                )
            }
            return text(
                "从 Anthropic 官方渠道安装 Claude Desktop。安装完成后回到本页，Routekeeper 会验证应用签名。",
                "Install Claude Desktop from Anthropic’s official channel. Return here and Routekeeper will verify the app signature."
            )
        case .desktopRunning:
            return text(
                "请先完全退出当前 Claude Desktop 及其菜单栏进程，再点“重新检测”。Routekeeper 不会接管沙箱外实例。",
                "Fully quit the current Claude Desktop app and menu-bar process, then choose Detect again. Routekeeper will not take over an instance outside the sandbox."
            )
        case .openWorkspace:
            return text("会话已结束。先审阅工作副本，再决定是否采用修改。", "The session ended. Review the workspace copy before applying changes.")
        case .prepare:
            return text("所需信息已齐。创建会话后会验证断网、代理、出口和进程边界。", "Inputs are ready. Creation verifies fail-closed networking, proxy, exit and process boundaries.")
        case nil:
            return session.phase == .running
                ? (session.configuration.target == .claudeDesktop
                    ? (session.desktopInstallation?.runtimeFamily == .operonHostedWeb
                        ? text("隔离环境已通过检查。可转到下方“会话操作”打开 Claude Science 受控窗口。", "Isolation passed. Use Session actions below to open the controlled Claude Science window.")
                        : text("隔离环境已通过检查。可转到下方“会话操作”启动官方 Claude Desktop。", "Isolation passed. Use Session actions below to launch official Claude Desktop."))
                    : text("隔离环境已通过检查。可转到下方“会话操作”启动 Claude Code。", "Isolation passed. Use Session actions below to launch Claude Code."))
                : text("正在执行检查，请等待当前步骤完成。", "A check is running. Wait for the current step to finish.")
        }
    }

    private var guideNextSymbol: String {
        guideAction == .detectProxy || guideAction == .desktopInstall || guideAction == .desktopRunning
            ? "exclamationmark.triangle.fill"
            : "arrow.right.circle.fill"
    }

    private var guideNextColor: Color {
        guideAction == .detectProxy
            || guideAction == .desktopInstall
            || guideAction == .desktopRunning ? .orange : appAccent
    }

    private func performGuideAction(_ action: SandboxGuideAction) {
        switch action {
        case .detectProxy:
            session.refreshDetectedProxy(alignIfNeeded: true)
        case .detectExit:
            Task { await store.detectExitForSandbox() }
        case .chooseProject:
            chooseFolder(for: $session.configuration.projectPath)
        case .chooseExchange:
            chooseFolder(for: $session.configuration.exchangePath)
        case .authentication:
            AppNavigationRequest.request(.authentication)
        case .desktopInstall:
            if let url = URL(string: "https://claude.ai/download") {
                NSWorkspace.shared.open(url)
            }
        case .desktopRunning:
            session.refreshDesktopDiscovery()
        case .prepare:
            Task { await store.prepareSandbox() }
        case .resumeNetwork:
            Task { await store.resumeSandboxNetwork() }
        case .openWorkspace:
            session.openWorkspace()
        }
    }

    private func sandboxRemediation(for checkID: String) -> String {
        switch checkID {
        case "desktop-signature":
            return text(
                "从 Anthropic 官方渠道安装 Claude Desktop，确认应用未被修改，再点“重新检测”。Routekeeper 不接受其他 Team ID 或未签名应用。",
                "Install Claude Desktop from Anthropic’s official channel, confirm the app is unmodified, then choose Detect again. Routekeeper rejects unsigned apps and other Team IDs."
            )
        case "system-proxy-config", "relay-network":
            return text(
                "重新打开代理客户端的本机 HTTP、SOCKS 或混合端口，点击“重新检测”，再创建会话。",
                "Enable a local HTTP, SOCKS or mixed proxy endpoint, select Detect again, then create the session."
            )
        case "claude-relay":
            return text(
                "确认代理客户端和节点可用，且相同网络下 Claude 能通过中继访问，再重新创建会话。",
                "Confirm the proxy client and node work and Claude can use the relay, then create the session again."
            )
        case "claude-exit-match":
            return text(
                "Claude 看到的 IPv6 可能由节点轮换。请确认已保存的稳定 IPv4 仍是当前代理出口，更新后再重建会话；不要直接粘贴轮换 IPv6。",
                "The IPv6 address seen by Claude may rotate at the node. Confirm the saved stable IPv4 is still the current proxy exit, update it, then recreate the session; do not paste a rotating IPv6 address directly."
            )
        case "timezone", "session-locale":
            return text(
                "选择一个有效的会话时区，然后重新创建会话。硬件销售地区不会被修改。",
                "Choose a valid session timezone and recreate the session. The Mac hardware sales region is not changed."
            )
        case "workspace-write", "exchange-write", "original-write":
            return text(
                "重新选择两个不重叠、可访问的普通文件夹；不要选择磁盘根目录或系统目录。",
                "Choose two separate accessible folders. Do not use a disk root or system directory."
            )
        case "direct-network", "direct-dns", "direct-udp":
            return text(
                "这项用于证明断网保护生效。请重新创建会话；若仍失败，停止使用并查看运行记录。",
                "This check proves fail-closed networking. Recreate the session; if it still fails, stop and inspect the run log."
            )
        default:
            return text(
                "重新创建会话再测一次。若仍失败，请不要用无限制模式启动 Claude，并查看运行记录。",
                "Recreate the session once. If it still fails, do not launch Claude without isolation; inspect the run log."
            )
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .running: return appAccent
        case .networkPaused, .failed: return .orange
        default: return .secondary
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func folderRow(title: String, value: Binding<String>, placeholder: String) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField(placeholder, text: value)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(title)
                Button(text("选择…", "Choose…")) {
                    chooseFolder(for: value)
                }
                .accessibilityLabel(text("选择\(title)", "Choose \(title)"))
            }
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .contain)
    }

    private func chooseFolder(for value: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = value.wrappedValue == session.configuration.exchangePath
        if !value.wrappedValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: value.wrappedValue, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        value.wrappedValue = url.path
    }
}

private enum SandboxGuideAction: Equatable {
    case detectProxy
    case detectExit
    case chooseProject
    case chooseExchange
    case authentication
    case desktopInstall
    case desktopRunning
    case prepare
    case resumeNetwork
    case openWorkspace

    var title: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .detectProxy: return en ? "Detect again" : "重新检测"
        case .detectExit: return en ? "Detect exit" : "检测并保存出口"
        case .chooseProject: return en ? "Choose project" : "选择项目"
        case .chooseExchange: return en ? "Choose exchange" : "选择交换目录"
        case .authentication: return en ? "Save sign-in" : "保存登录凭证"
        case .desktopInstall: return en ? "Get official app" : "获取官方客户端"
        case .desktopRunning: return en ? "Detect again" : "重新检测"
        case .prepare: return en ? "Create isolated session" : "创建隔离会话"
        case .resumeNetwork: return en ? "Restore network" : "恢复网络"
        case .openWorkspace: return en ? "Review workspace" : "查看工作副本"
        }
    }
}

private enum SandboxGuideStepState {
    case complete
    case current
    case pending
    case attention

    var color: Color {
        switch self {
        case .complete: return appAccent
        case .current: return .primary
        case .pending: return .secondary
        case .attention: return .orange
        }
    }

    var symbol: String {
        switch self {
        case .complete: return "checkmark"
        case .current: return "arrow.right"
        case .pending: return "circle"
        case .attention: return "exclamationmark"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .complete: return L10n.resolvedEnglish ? "Complete" : "已完成"
        case .current: return L10n.resolvedEnglish ? "Current step" : "当前步骤"
        case .pending: return L10n.resolvedEnglish ? "Pending" : "待完成"
        case .attention: return L10n.resolvedEnglish ? "Needs attention" : "需要处理"
        }
    }
}

private struct SandboxGuideStepItem: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let state: SandboxGuideStepState
}
