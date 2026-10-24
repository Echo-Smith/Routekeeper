import AppKit
import GuardCore
import SwiftUI

struct SandboxScopeSheet: View {
    @Bindable var sandbox: SandboxCoordinator
    @Environment(\.dismiss) private var dismiss

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(
                title: text("会话范围", "Session scope"),
                subtitle: text(
                    "这些设置由两个保护对象共享。系统会为每个目标建立独立的工作副本和交换子目录。",
                    "These settings are shared by both protected targets. Routekeeper creates a separate workspace and exchange subfolder for each target."
                )
            )
            AppHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                        scopeFieldRow(
                            sandbox.sharedConfiguration.isEnabled(.claudeCode)
                            ? text("项目文件夹（Claude Code 必需）", "Project folder (required for Claude Code)")
                                : text("项目文件夹（Claude Code 已关闭）", "Project folder (Claude Code disabled)")
                        ) {
                            folderInput(
                                value: $sandbox.sharedConfiguration.projectPath,
                                placeholder: text("选择要复制的项目", "Choose a project to copy")
                            )
                        }
                        scopeFieldRow(text("交换根目录", "Exchange root")) {
                            folderInput(
                                value: $sandbox.sharedConfiguration.exchangePath,
                                placeholder: text("选择文件交换根目录", "Choose an exchange root"),
                                canCreate: true
                            )
                        }
                        scopeFieldRow(text("实际交换目录", "Actual exchange folders")) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(IsolationApplicationTarget.allCases, id: \.self) { target in
                                    LabeledContent(target.title) {
                                        Text(sandbox.sharedConfiguration.targetExchangePath(for: target))
                                            .routekeeperFont(.caption, design: .monospaced)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .appSurface(.inset, corner: 10)
                        }
                        scopeFieldRow(text("会话时区", "Session timezone")) {
                            HStack(spacing: 8) {
                                TextField("Asia/Shanghai", text: $sandbox.sharedConfiguration.timezoneIdentifier)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(text("会话时区", "Session timezone"))
                                Menu(text("常用", "Presets")) {
                                    ForEach(timezones, id: \.self) { identifier in
                                        Button(identifier) {
                                            sandbox.sharedConfiguration.timezoneIdentifier = identifier
                                        }
                                    }
                                }
                                .fixedSize()
                            }
                        }
                        scopeFieldRow(text("会话语言", "Session language")) {
                            HStack(spacing: 8) {
                                TextField("zh-Hans", text: $sandbox.sharedConfiguration.languageIdentifier)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(text("会话语言", "Session language"))
                                Menu(text("常用", "Presets")) {
                                    ForEach(languages, id: \.identifier) { language in
                                        Button(language.title) {
                                            sandbox.sharedConfiguration.languageIdentifier = language.identifier
                                        }
                                    }
                                }
                                .fixedSize()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(text(
                        "时区和语言只用于隔离会话与 Claude 网页版，不修改系统设置；语言不再根据时区自动推断。",
                        "Timezone and language apply only to isolated sessions and Claude on the web; they do not modify macOS settings, and language is no longer inferred from timezone."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(sandbox.anyActive || sandbox.busy)
            }
            AppHairline()
            HStack {
                if sandbox.anyActive {
                    Label(
                        text("结束所有活动会话后才能修改。", "End all active sessions before changing these settings."),
                        systemImage: "lock.fill"
                    )
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(text("完成", "Done")) {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    sandbox.commitSharedConfiguration()
                    dismiss()
                }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 450)
    }

    private var timezones: [String] {
        [
            "Asia/Shanghai", "Asia/Tokyo", "UTC",
            "Europe/London", "America/New_York", "America/Los_Angeles"
        ]
    }

    private var languages: [(title: String, identifier: String)] {
        [
            (text("简体中文", "Simplified Chinese"), "zh-Hans"),
            (text("繁體中文（香港）", "Traditional Chinese (Hong Kong)"), "zh-Hant-HK"),
            (text("繁體中文（台灣）", "Traditional Chinese (Taiwan)"), "zh-Hant"),
            (text("日本語", "Japanese"), "ja-JP"),
            (text("한국어", "Korean"), "ko-KR"),
            (text("English (US)", "English (US)"), "en-US"),
            (text("English (UK)", "English (UK)"), "en-GB"),
            (text("Français", "French"), "fr-FR"),
            (text("Deutsch", "German"), "de-DE")
        ]
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .routekeeperFont(.title2, weight: .semibold)
            Text(subtitle)
                .routekeeperFont(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scopeFieldRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func folderInput(
        value: Binding<String>,
        placeholder: String,
        canCreate: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(placeholder)
                .frame(maxWidth: .infinity)
            Button(text("选择…", "Choose…")) {
                chooseFolder(for: value, canCreate: canCreate)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private func chooseFolder(for value: Binding<String>, canCreate: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = canCreate
        if !value.wrappedValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: value.wrappedValue, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        value.wrappedValue = url.path
    }
}

struct SandboxProxySheet: View {
    @Bindable var sandbox: SandboxCoordinator
    @Environment(\.dismiss) private var dismiss

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text("代理配置一致性", "Proxy configuration consistency"))
                    .routekeeperFont(.title2, weight: .semibold)
                Text(text(
                    "系统代理会和共享上游设置比较；创建会话时只会自动采用本机回环代理。",
                    "The system proxy is compared with the shared upstream. Session creation only adopts a loopback proxy automatically."
                ))
                .routekeeperFont(.callout)
                .foregroundStyle(.secondary)
            }
            AppHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sandbox.sessions, id: \.configuration.target) { session in
                        proxyStatus(session)
                    }
                    Divider()
                    LabeledContent {
                        Picker("", selection: $sandbox.sharedConfiguration.upstream.protocolType) {
                            ForEach(IsolationUpstreamProtocol.allCases, id: \.self) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    } label: {
                        Text(text("上游协议", "Upstream protocol"))
                    }
                    LabeledContent(text("本地端口", "Local port")) {
                        HStack(spacing: 8) {
                            TextField(
                                "7890",
                                value: $sandbox.sharedConfiguration.upstream.port,
                                format: .number.grouping(.never)
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            Stepper("", value: $sandbox.sharedConfiguration.upstream.port, in: 1...65535)
                                .labelsHidden()
                        }
                    }
                    LabeledContent(text("用户名（可选）", "Username (optional)")) {
                        TextField("", text: $sandbox.sharedConfiguration.upstream.username)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent(text("密码（可选）", "Password (optional)")) {
                        SecureField("", text: $sandbox.sharedConfiguration.upstream.password)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text(text(
                        "上游地址固定为本机回环地址；密码只保留到本次应用运行。",
                        "The upstream host is always loopback; the password remains only for this app run."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(sandbox.anyActive || sandbox.busy)
            }
            AppHairline()
            HStack {
                Button(text("重新检测", "Detect again")) {
                    sandbox.refreshDetectedProxy()
                }
                .routekeeperSecondaryButton()
                .disabled(sandbox.busy)
                Spacer()
                Button(text("完成", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: 480)
    }

    private func proxyStatus(_ session: SandboxSession) -> some View {
        let color = session.configurationMatchesDetectedProxy
            ? appStatusSuccess
            : session.detectedProxy == nil ? Color.secondary : appStatusWarning
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: session.configurationMatchesDetectedProxy
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill")
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.configuration.target.title)
                    .routekeeperFont(.callout, weight: .semibold)
                Text(session.proxyConsistencyTitle)
                    .routekeeperFont(.callout)
                Text(session.proxyConsistencyDetail)
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appSurface(.inset, corner: 10)
    }
}

struct SandboxBoundarySheet: View {
    let openNetworkProtection: () -> Void
    @Environment(\.dismiss) private var dismiss

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text("代理与边界", "Proxy and boundaries"))
                    .routekeeperFont(.title2, weight: .semibold)
                Text(text(
                    "实验性沙箱限制进程的文件与网络路径，但不虚拟化 macOS。",
                    "The experimental sandbox constrains process file and network paths but does not virtualize macOS."
                ))
                .routekeeperFont(.callout)
                .foregroundStyle(.secondary)
            }
            AppHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    boundaryRow(
                        text("网络", "Network"),
                        text(
                            "每个会话只连接自己的本机 Routekeeper 中继。代理不可用时直接失败，不会回退到公网直连。",
                            "Each session reaches only its own local Routekeeper relay. If the proxy is unavailable, it fails instead of falling back to direct internet access."
                        ),
                        symbol: "network"
                    )
                    boundaryRow(
                        text("文件", "Files"),
                        text(
                            "Claude 只获得本次工作副本、独立临时目录和交换目录的写入权限；原项目保持只读来源。",
                            "Claude can write only to its session workspace, temporary directory and exchange folder; the original project remains a read-only source."
                        ),
                        symbol: "folder"
                    )
                    boundaryRow(
                        text("主机信息", "Host information"),
                        text(
                            "这是进程隔离，不是虚拟机。Claude 仍可能读取本机网卡名称、地址、路由和 DNS 解析器配置。",
                            "This is process isolation, not a virtual machine. Claude may still read host interface names, addresses, routes and DNS resolver configuration."
                        ),
                        symbol: "desktopcomputer"
                    )
                    boundaryRow(
                        text("浏览器与服务", "Browsers and services"),
                        text(
                            "沙箱不会使用默认浏览器，也不会开放任意 localhost 服务。需要外部操作时使用授权交接目录。",
                            "The sandbox does not use the default browser and does not expose arbitrary localhost services. External work uses the authorization handoff folder."
                        ),
                        symbol: "safari"
                    )
                    Button(text("打开网络保护", "Open network protection")) {
                        dismiss()
                        openNetworkProtection()
                    }
                    .routekeeperSecondaryButton()
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            AppHairline()
            HStack {
                Spacer()
                Button(text("完成", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 440)
    }

    private func boundaryRow(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .routekeeperFont(.callout, weight: .semibold)
                Text(detail)
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appSurface(.inset, corner: 10)
    }
}
