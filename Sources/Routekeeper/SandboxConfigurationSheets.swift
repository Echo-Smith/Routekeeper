import AppKit
import GuardCore
import SwiftUI

struct SandboxScopeSheet: View {
    @Bindable var store: GuardStore
    @Bindable var sandbox: SandboxCoordinator
    @AppStorage("routekeeper-egress-intelligence-v1") private var includeIntelligence = false
    @Environment(\.dismiss) private var dismiss
    @State private var detectingEgress = false
    @State private var egressNotice = ""
    @State private var timezoneDraft: String
    @State private var languageDraft: String

    init(store: GuardStore) {
        self.store = store
        self.sandbox = store.sandbox
        _timezoneDraft = State(initialValue: store.sandbox.sharedConfiguration.timezoneIdentifier)
        _languageDraft = State(initialValue: store.sandbox.sharedConfiguration.languageIdentifier)
    }

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    private var timezoneIsValid: Bool {
        TimeZone(identifier: timezoneDraft) != nil
    }

    private var languageIsValid: Bool {
        IsolationSessionEnvironment.normalizedLanguageIdentifier(languageDraft) != nil
    }

    private var regionalSettingsAreValid: Bool {
        timezoneIsValid && languageIsValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(
                title: text("共享环境", "Shared environment"),
                subtitle: text(
                    "项目、交换目录、时区、地区与出口默认值由三个 Claude 环境共享；每个环境仍保留独立的工作副本。",
                    "Project, exchange folder, timezone, region and exit defaults are shared by all three Claude environments, while each keeps its own workspace."
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
                        scopeFieldRow(
                            text("会话时区", "Session timezone"),
                            isInvalid: !timezoneIsValid
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    TextField("Asia/Shanghai", text: $timezoneDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(text("会话时区", "Session timezone"))
                                    .disabled(sandbox.sharedConfiguration.usesEgressRegionalDefaults)
                                    .overlay {
                                        if !timezoneIsValid {
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(appStatusFailure, lineWidth: 1.5)
                                        }
                                    }
                                    Menu(text("常用", "Presets")) {
                                        ForEach(timezones, id: \.self) { identifier in
                                            Button(identifier) {
                                                timezoneDraft = identifier
                                                sandbox.updateTimezoneIdentifier(identifier)
                                            }
                                        }
                                    }
                                    .fixedSize()
                                    .disabled(sandbox.sharedConfiguration.usesEgressRegionalDefaults)
                                }
                                if !timezoneIsValid {
                                    invalidFieldMessage(text(
                                        "无效的 IANA 时区，例如 Asia/Shanghai。",
                                        "Invalid IANA timezone, for example Asia/Shanghai."
                                    ))
                                }
                            }
                        }
                        scopeFieldRow(
                            text("会话语言 / 地区", "Session language / region"),
                            isInvalid: !languageIsValid
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    TextField("zh-Hans", text: $languageDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(text("会话语言与地区", "Session language and region"))
                                    .disabled(sandbox.sharedConfiguration.usesEgressRegionalDefaults)
                                    .overlay {
                                        if !languageIsValid {
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(appStatusFailure, lineWidth: 1.5)
                                        }
                                    }
                                    Menu(text("常用", "Presets")) {
                                        ForEach(languages, id: \.identifier) { language in
                                            Button(language.title) {
                                                languageDraft = language.identifier
                                                sandbox.updateLanguageIdentifier(language.identifier)
                                            }
                                        }
                                    }
                                    .fixedSize()
                                    .disabled(sandbox.sharedConfiguration.usesEgressRegionalDefaults)
                                }
                                if !languageIsValid {
                                    invalidFieldMessage(text(
                                        "无效的语言 / 地区标识，例如 zh-Hans 或 en-US。",
                                        "Invalid language or region identifier, for example zh-Hans or en-US."
                                    ))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !regionalSettingsAreValid {
                        HStack(spacing: 10) {
                            Label(
                                text(
                                    "红色配置项无效，当前无法创建会话或打开 Chrome。",
                                    "The red setting is invalid, so sessions and Chrome cannot start."
                                ),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .routekeeperFont(.caption, weight: .semibold)
                            .foregroundStyle(appStatusFailure)
                            Spacer()
                            Button(text("自动修复", "Repair automatically")) {
                                sandbox.repairRegionalSettings(from: store.egressAudit.report)
                                syncRegionalDrafts()
                                egressNotice = text(
                                    "已用有效的出口或系统默认值修复。",
                                    "Repaired with a valid exit or system default."
                                )
                            }
                            .routekeeperSecondaryButton(.warning)
                            .disabled(sandbox.anyActive || sandbox.busy)
                        }
                        .padding(10)
                        .background(
                            appStatusFailure.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }

                    Text(text(
                        "时区和语言只用于隔离会话与 Chrome，不修改系统设置。跟随出口仅在手动查询时获取第三方 IP 地区信息；固定设置不会被出口变化覆盖。",
                        "Timezone and language apply only to isolated sessions and Chrome, without changing macOS settings. Following the exit uses third-party IP location only when you request it. Fixed settings are never overwritten by exit changes."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .center, spacing: 10) {
                        Picker(text("时区 / 地区默认值", "Timezone / regional default"), selection: Binding(
                            get: { sandbox.sharedConfiguration.usesEgressRegionalDefaults },
                            set: { follow in
                                sandbox.sharedConfiguration.usesEgressRegionalDefaults = follow
                                if follow {
                                    sandbox.applyEgressRegionalDefaults(from: store.egressAudit.report)
                                    syncRegionalDrafts()
                                }
                                egressNotice = ""
                            }
                        )) {
                            Text(text("跟随当前出口", "Follow current exit")).tag(true)
                            Text(text("手动固定", "Fixed manually")).tag(false)
                        }
                        .pickerStyle(.segmented)
                        if sandbox.sharedConfiguration.usesEgressRegionalDefaults {
                            Button {
                                detectingEgress = true
                                egressNotice = ""
                                includeIntelligence = true
                                Task {
                                    let applied = await store.applyCurrentEgressToSandbox()
                                    detectingEgress = false
                                    egressNotice = applied
                                        ? text("已按当前出口更新。", "Updated for the current exit.")
                                        : text("未取得出口时区。请完成网络体检，或改为手动固定。",
                                               "No exit timezone was found. Run a network check or set the values manually.")
                                }
                            } label: {
                                if detectingEgress {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(text("按当前出口设置", "Use current exit"))
                                }
                            }
                            .routekeeperSecondaryButton(.warning)
                            .disabled(detectingEgress || store.egressAudit.busy || store.checking)
                        }
                    }
                    if !egressNotice.isEmpty {
                        Text(egressNotice)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    .disabled(!regionalSettingsAreValid)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 450)
        .onAppear {
            syncRegionalDrafts()
        }
        .onChange(of: sandbox.sharedConfiguration.timezoneIdentifier) { _, value in
            if timezoneDraft != value {
                timezoneDraft = value
            }
        }
        .onChange(of: sandbox.sharedConfiguration.languageIdentifier) { _, value in
            if languageDraft != value {
                languageDraft = value
            }
        }
        .onChange(of: timezoneDraft) { _, value in
            guard !sandbox.sharedConfiguration.usesEgressRegionalDefaults,
                  TimeZone(identifier: value) != nil,
                  value != sandbox.sharedConfiguration.timezoneIdentifier else { return }
            sandbox.updateTimezoneIdentifier(value)
        }
        .onChange(of: languageDraft) { _, value in
            guard !sandbox.sharedConfiguration.usesEgressRegionalDefaults,
                  IsolationSessionEnvironment.normalizedLanguageIdentifier(value) != nil,
                  value != sandbox.sharedConfiguration.languageIdentifier else { return }
            sandbox.updateLanguageIdentifier(value)
        }
    }

    private func syncRegionalDrafts() {
        timezoneDraft = sandbox.sharedConfiguration.timezoneIdentifier
        languageDraft = sandbox.sharedConfiguration.languageIdentifier
    }

    private func invalidFieldMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .routekeeperFont(.caption)
            .foregroundStyle(appStatusFailure)
            .fixedSize(horizontal: false, vertical: true)
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
        isInvalid: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Label {
                Text(label)
            } icon: {
                if isInvalid {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
            }
            .foregroundStyle(isInvalid ? appStatusFailure : Color.primary)
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
