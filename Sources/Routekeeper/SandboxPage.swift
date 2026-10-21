import AppKit
import GuardCore
import SwiftUI

struct SandboxPage: View {
    @Bindable var store: GuardStore
    @Bindable var session: SandboxSession

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
                configurationCard
                boundaryCard
                if !session.checks.isEmpty { checksCard }
                controlsCard
                if session.phase == .ended || !session.changedFiles.isEmpty { reviewCard }
            } else {
                disabledCard
            }
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
                Text(text(
                    "只改变本次会话中的 TZ 环境变量，不会修改这台 Mac 的系统时区。",
                    "Only the session TZ environment variable changes. The Mac system timezone is not modified."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(!session.phase.canChangeConfiguration)
        }
    }

    private var checksCard: some View {
        GuardCard(
            title: text("启动前检查", "Preflight checks"),
            subtitle: text(
                "全部项目通过后才会显示“沙箱已隔离”。失败时不会启动普通、无限制的 Claude 进程。",
                "“Sandbox isolated” appears only after every check passes. On failure, Routekeeper does not fall back to an unrestricted launch."
            )
        ) {
            VStack(spacing: 0) {
                ForEach(Array(session.checks.enumerated()), id: \.element.id) { index, check in
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
                    .padding(.vertical, 7)
                    if index < session.checks.count - 1 { AppHairline() }
                }
            }
        }
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
