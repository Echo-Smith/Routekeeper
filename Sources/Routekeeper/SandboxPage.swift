import AppKit
import GuardCore
import SwiftUI

struct SandboxPage: View {
    @Bindable var store: GuardStore
    @Bindable var session: SandboxSession
    @State private var showAllChecks = false

    init(store: GuardStore) {
        self.store = store
        self.session = store.sandbox
    }

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(spacing: 16) {
            if store.settings.experimentalSandboxEnabled {
                statusCard
                setupGuideCard
                configurationCard
                proxyConfigurationCard
                boundaryCard
                gatewayReferenceCard
                if !session.checks.isEmpty { checksCard }
                controlsCard
                if session.phase == .ended || !session.changedFiles.isEmpty { reviewCard }
            } else {
                disabledCard
            }
        }
        .onAppear { session.refreshDetectedProxy() }
        .onChange(of: session.phase) { _, phase in
            if phase != .failed { showAllChecks = false }
        }
    }

    private var statusCard: some View {
        GuardCard(
            title: text("实验性进程沙箱", "Experimental process sandbox"),
            subtitle: text(
                "受限的 Claude Code 只能访问本次工作副本、交换文件夹和经 Routekeeper 中继的网络。",
                "The restricted Claude Code process can access only this workspace copy, the exchange folder and network traffic through the Routekeeper relay."
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.statusTitle)
                        .font(.system(size: 17, weight: .semibold))
                    Text(session.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if session.busy {
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
            .font(.callout.weight(.medium))
        }
    }

    private var configurationCard: some View {
        GuardCard(
            title: text("会话范围", "Session scope"),
            subtitle: text(
                "原项目只用于复制，沙箱只会修改本次工作副本。交换文件夹用于有意传递文件。",
                "The original project is copied. The sandbox changes only this workspace copy. Use the exchange folder to pass files intentionally."
            )
        ) {
            VStack(spacing: 12) {
                folderRow(
                    title: text("项目文件夹", "Project folder"),
                    value: $session.configuration.projectPath,
                    placeholder: text("选择要复制的项目", "Choose a project to copy")
                )
                folderRow(
                    title: text("交换文件夹", "Exchange folder"),
                    value: $session.configuration.exchangePath,
                    placeholder: text("选择单独的文件交换目录", "Choose a separate file-exchange folder")
                )
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(text("会话时区", "Session timezone"))
                        .foregroundStyle(.secondary)
                        .frame(width: 116, alignment: .leading)
                    TextField("Asia/Shanghai", text: $session.configuration.timezoneIdentifier)
                        .textFieldStyle(.roundedBorder)
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
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(text("会话语言", "Session locale"))
                        .foregroundStyle(.secondary)
                        .frame(width: 116, alignment: .leading)
                    Text(session.sessionLocaleIdentifier)
                        .font(.system(.callout, design: .monospaced))
                    Spacer()
                }
                Text(text(
                    "时区、语言和 locale 只用于本次会话，并尽量保持一致；不会修改这台 Mac 的系统设置，也不能伪装硬件销售地区。",
                    "Timezone, language and locale apply only to this session and are kept consistent. The Mac's settings and hardware sales region are not changed."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!session.phase.canChangeConfiguration)
        }
    }

    private var setupGuideCard: some View {
        let steps = setupGuideSteps
        return GuardCard(
            title: text("安全启动向导", "Safe-start guide"),
            subtitle: text(
                "按顺序完成四步。Routekeeper 会自动读取系统代理，并在启动前核对你保存的出口。",
                "Complete four steps in order. Routekeeper detects the system proxy and verifies your saved exit before launch."
            )
        ) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(steps) { step in
                    setupGuideStep(step)
                }
            }

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
                VStack(alignment: .leading, spacing: 2) {
                    Text(text("下一步", "Next step"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(guideNextColor)
                    Text(guideNextText)
                        .font(.callout)
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
                Text(step.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(step.state == .pending ? .secondary : .primary)
            }
            Text(step.detail)
                .font(.caption2)
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
    }

    private var proxyConfigurationCard: some View {
        let consistent = session.configurationMatchesDetectedProxy
        let hasDetectedProxy = session.detectedProxy != nil
        let color = consistent ? appAccent : hasDetectedProxy ? Color.orange : Color.secondary
        return GuardCard(
            title: text("代理配置一致性", "Proxy configuration consistency"),
            subtitle: text(
                "创建会话时自动读取当前系统代理。能识别时，地址、端口和协议会自动对齐。",
                "The current system proxy is read when the session is created. Address, port and protocol align automatically when they can be detected."
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: consistent ? "link.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.proxyConsistencyTitle)
                            .font(.callout.weight(.medium))
                        Text(session.proxyConsistencyDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(text("重新检测", "Detect again")) {
                        session.refreshDetectedProxy()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.phase.canChangeConfiguration)
                }
                if !session.proxyDetectionMessage.isEmpty {
                    Text(session.proxyDetectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let exit = session.expectedExits.ipv4 ?? session.expectedExits.ipv6 {
                    Label(
                        text("用于核对 Claude 出口：\(exit)", "Claude exit to verify: \(exit)"),
                        systemImage: "target"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var checksCard: some View {
        let failedChecks = session.checks.filter { !$0.passed }
        let passed = failedChecks.isEmpty
        return GuardCard(
            title: text("启动前检查", "Preflight checks"),
            subtitle: text(
                "全部项目通过后才会显示“沙箱已隔离”。失败时不会启动普通、无限制的 Claude 进程。",
                "“Sandbox isolated” appears only after every check passes. On failure, Routekeeper does not fall back to an unrestricted launch."
            )
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: passed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(passed ? appAccent : Color.orange)
                    Text(
                        passed
                            ? text("\(session.checks.count) 项检查全部通过", "\(session.checks.count) checks passed")
                            : text("\(failedChecks.count) 项需要处理，其余通过", "\(failedChecks.count) need attention; the rest passed")
                    )
                    .font(.callout.weight(.semibold))
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
                            .font(.caption.weight(.medium))
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
                Text(check.title)
                    .font(.callout.weight(.medium))
                    .frame(width: 130, alignment: .leading)
                Text(check.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showRemediation, !check.passed {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(Color.orange)
                    Text(sandboxRemediation(for: check.id))
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 29)
            }
        }
        .padding(.vertical, 7)
    }

    private var controlsCard: some View {
        GuardCard(
            title: text("会话操作", "Session actions"),
            subtitle: text(
                "先验证隔离边界，再从 Keychain 读取凭证，在终端中启动 Claude Code。",
                "Verify the isolation boundary first, then launch Claude Code in Terminal with the Keychain credential."
            )
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
                if session.busy { ProgressView().controlSize(.small) }
            }

            if session.phase == .running || session.phase == .networkPaused {
                AppHairline()
                HStack(spacing: 10) {
                    Button {
                        store.launchClaudeInSandbox()
                    } label: {
                        Label(text("在终端启动 Claude Code", "Launch Claude Code in Terminal"), systemImage: "play.fill")
                    }
                    .routekeeperProminentButton()
                    .disabled(!session.canLaunchClaude || store.authentication.status != .saved)

                    Button(role: .destructive) {
                        Task { await store.endSandboxSession() }
                    } label: {
                        Label(text("结束会话", "End session"), systemImage: "stop.circle")
                    }
                    .disabled(session.busy)
                    Spacer()
                }
                if store.authentication.status != .saved {
                    Label(
                        text(
                            "尚未保存 Claude Code 登录凭证。请先在“保护 → Claude Code 登录凭证”中保存。",
                            "No Claude Code sign-in token is saved. Add one under Protection → Claude Code sign-in first."
                        ),
                        systemImage: "key.slash"
                    )
                    .font(.caption)
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(gatewayReferenceTitle(status))
                        .font(.callout.weight(.semibold))
                    Text(text(
                        "沙箱网络只允许经过 Routekeeper 中继；代理不可用时直接失败，不会退回公网直连。",
                        "Sandbox traffic is allowed only through the Routekeeper relay. If the proxy is unavailable, it fails instead of falling back to direct internet access."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(text("查看网关证据", "View gateway evidence")) {
                    AppNavigationRequest.request(.inspection)
                }
                .buttonStyle(.bordered)
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
                    .font(.callout.weight(.medium))
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(session.changedFiles, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
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
                HStack(spacing: 14) {
                    Text(text("上游协议", "Upstream protocol"))
                        .foregroundStyle(.secondary)
                        .frame(width: 116, alignment: .leading)
                    Picker("", selection: $session.configuration.upstream.protocolType) {
                        ForEach(IsolationUpstreamProtocol.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
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
                HStack(spacing: 14) {
                    Text(text("本地端口", "Local port"))
                        .foregroundStyle(.secondary)
                        .frame(width: 116, alignment: .leading)
                    TextField(
                        "7890",
                        value: $session.configuration.upstream.port,
                        format: .number.grouping(.never)
                    )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Stepper("", value: $session.configuration.upstream.port, in: 1...65535)
                        .labelsHidden()
                    Spacer()
                }
                HStack(spacing: 14) {
                    Text(text("用户名（可选）", "Username (optional)"))
                        .foregroundStyle(.secondary)
                        .frame(width: 116, alignment: .leading)
                    TextField("", text: $session.configuration.upstream.username)
                        .textFieldStyle(.roundedBorder)
                    SecureField(text("密码（可选）", "Password (optional)"), text: $session.configuration.upstream.password)
                        .textFieldStyle(.roundedBorder)
                }
                Text(text(
                    "上游地址固定为本机回环地址。上游代理密码只在本次运行中使用，写入设置时会清空，不会保存到偏好设置。",
                    "The upstream address is always loopback. The upstream password is used only for this run and is stripped before preferences are saved."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(text(
                    "这是进程与文件隔离功能：网络只允许经过中继，不等同于完整的虚拟机，也不能保证账号、设备指纹或服务端风控结果。",
                    "This isolates processes and files: network traffic must pass through the relay. It is not a full virtual machine and cannot guarantee account, device-fingerprint or server-side risk outcomes."
                ))
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                Text(text(
                    "为避免绕过，沙箱不允许启动 localhost 项目服务器，也不允许自动打开默认浏览器。如需预览生成的项目，请结束会话后打开工作副本；如需重新登录，请优先在“Claude Code 登录凭证”中保存令牌。外部浏览器不受沙箱网络限制。",
                    "To prevent bypasses, sandboxed processes cannot start localhost project servers or open the default browser. To preview generated work, end the session and open the workspace copy. For sign-in, save a token under Claude Code sign-in first. External browsers are outside the sandbox network boundary."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!session.phase.canChangeConfiguration)
        }
    }

    private var disabledCard: some View {
        GuardCard(
            title: text("实验性进程沙箱", "Experimental process sandbox"),
            subtitle: text(
                "这是一个可选模式。开启后，普通网络监控会让出状态显示，避免把两套网络状态混在一起。",
                "This optional mode gives the sandbox priority in status reporting so two different network models never appear as one."
            )
        ) {
            Text(text(
                "请在“保护 → 保护设置”中开启“实验性进程沙箱”。Claude Code 自己的权限提示和内部沙箱仍应保持启用。",
                "Turn on “Experimental process sandbox” under Protection → Protection settings. Keep Claude Code’s own permission prompts and internal sandbox enabled."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
        let completed = [
            proxyStepComplete,
            hasSavedExit,
            hasSessionScope && store.authentication.status == .saved,
            preflightPassed
        ]
        let titles = [
            text("1  代理", "1  Proxy"),
            text("2  出口", "2  Exit"),
            text("3  范围与登录", "3  Scope & sign-in"),
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
        if !hasSavedExit { return .networkCheck }
        if session.configuration.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .chooseProject
        }
        if session.configuration.exchangePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .chooseExchange
        }
        if store.authentication.status != .saved { return .authentication }
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
        case .networkCheck:
            return text(
                "先完成网络体检并保存出口。沙箱会用这个值核对 Claude 的真实出口。",
                "Run a network check and save an exit. The sandbox compares Claude’s actual exit with it."
            )
        case .chooseProject:
            return text("选择要复制的项目文件夹；原文件夹不会被直接修改。", "Choose the project to copy; the original is not edited directly.")
        case .chooseExchange:
            return text("选择一个单独的交换文件夹，用于有意传入或取出文件。", "Choose a separate exchange folder for intentional file transfer.")
        case .authentication:
            return text("保存 Claude Code 登录凭证，避免启动时转到沙箱外的浏览器。", "Save a Claude Code token so launch does not fall back to a browser outside the sandbox.")
        case .openWorkspace:
            return text("会话已结束。先审阅工作副本，再决定是否采用修改。", "The session ended. Review the workspace copy before applying changes.")
        case .prepare:
            return text("所需信息已齐。创建会话后会验证断网、代理、出口和进程边界。", "Inputs are ready. Creation verifies fail-closed networking, proxy, exit and process boundaries.")
        case nil:
            return session.phase == .running
                ? text("隔离环境已通过检查。可转到下方“会话操作”启动 Claude Code。", "Isolation passed. Use Session actions below to launch Claude Code.")
                : text("正在执行检查，请等待当前步骤完成。", "A check is running. Wait for the current step to finish.")
        }
    }

    private var guideNextSymbol: String {
        guideAction == .detectProxy ? "exclamationmark.triangle.fill" : "arrow.right.circle.fill"
    }

    private var guideNextColor: Color {
        guideAction == .detectProxy ? .orange : appAccent
    }

    private func performGuideAction(_ action: SandboxGuideAction) {
        switch action {
        case .detectProxy:
            session.refreshDetectedProxy(alignIfNeeded: true)
        case .networkCheck:
            AppNavigationRequest.request(.inspection)
        case .chooseProject:
            chooseFolder(for: $session.configuration.projectPath)
        case .chooseExchange:
            chooseFolder(for: $session.configuration.exchangePath)
        case .authentication:
            AppNavigationRequest.request(.protection, protectionSection: .authentication)
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
                "出口可能已变化。回到网络体检，确认并保存当前出口后再重新创建会话。",
                "The exit may have changed. Confirm and save the current exit in Network check, then create the session again."
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

    private func folderRow(title: String, value: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
            Button(text("选择…", "Choose…")) {
                chooseFolder(for: value)
            }
        }
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
    case networkCheck
    case chooseProject
    case chooseExchange
    case authentication
    case prepare
    case resumeNetwork
    case openWorkspace

    var title: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .detectProxy: return en ? "Detect again" : "重新检测"
        case .networkCheck: return en ? "Open network check" : "去网络体检"
        case .chooseProject: return en ? "Choose project" : "选择项目"
        case .chooseExchange: return en ? "Choose exchange" : "选择交换目录"
        case .authentication: return en ? "Save sign-in" : "保存登录凭证"
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
}

private struct SandboxGuideStepItem: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let state: SandboxGuideStepState
}
