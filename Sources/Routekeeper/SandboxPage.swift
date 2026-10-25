import AppKit
import GuardCore
import SwiftUI

struct SandboxPage: View {
    @Bindable var store: GuardStore
    @Bindable var sandbox: SandboxCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var showScopeSheet = false
    @State private var showProxySheet = false
    @State private var showBoundarySheet = false
    @State private var disableConfirmationStep: SandboxDisableConfirmationStep?
    @State private var expandedChecks: Set<IsolationApplicationTarget> = []
    @State private var claudeLoginLink = ""
    @State private var handoffPreview: HandoffActionItem?
    @State private var toolbarOwner = UUID()
    @State private var targetHeaderHeight: CGFloat = 0
    @State private var targetStatusHeight: CGFloat = 0
    @State private var targetDetailHeight: CGFloat = 0
    @State private var targetDetailPrimaryHeight: CGFloat = 0
    @State private var targetDetailSecondaryHeight: CGFloat = 0
    @State private var targetDetailActionsHeight: CGFloat = 0
    @State private var targetGridWidth: CGFloat = 0
    @State private var terminalAutomationPermission: TerminalAutomationPermission = .checking
    @State private var authorizationSettingsOpened = false

    init(store: GuardStore) {
        self.store = store
        self.sandbox = store.sandbox
    }

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(spacing: 16) {
            if store.settings.experimentalSandboxEnabled {
                enabledContent
            } else {
                sandboxDisabledCard
            }
        }
        .onAppear {
            sandbox.refreshDetectedProxy()
        }
        .task {
            for session in sandbox.sessions {
                await session.loadInstalledApplicationsIfNeeded()
            }
        }
        .task {
            while !Task.isCancelled {
                terminalAutomationPermission = await TerminalAutomationPermissionProbe.current()
                let delay: Duration = terminalAutomationPermission.showsAuthorizationCard
                    ? .seconds(1)
                    : .seconds(3)
                try? await Task.sleep(for: delay)
            }
        }
        .task(id: store.settings.experimentalSandboxEnabled) {
            guard store.settings.experimentalSandboxEnabled else { return }
            await sandbox.webBrowser.discoverIfNeeded()
        }
        // Installation discovery performs deep code-signature validation.
        // Session state is refreshed on launch, explicit detection and target enablement.
        .onAppear {
            RoutekeeperToolbarCoordinator.shared.setSandbox(
                owner: toolbarOwner,
                label: text("更多沙箱操作", "More sandbox actions"),
                entries: pageOverflowEntries
            )
        }
        .onChange(of: sandboxToolbarSignature) { _, _ in
            RoutekeeperToolbarCoordinator.shared.setSandbox(
                owner: toolbarOwner,
                label: text("更多沙箱操作", "More sandbox actions"),
                entries: pageOverflowEntries
            )
        }
        .onDisappear {
            RoutekeeperToolbarCoordinator.shared.clear(owner: toolbarOwner)
        }
        .sheet(isPresented: $showScopeSheet) {
            SandboxScopeSheet(store: store)
        }
        .sheet(isPresented: $showProxySheet) {
            SandboxProxySheet(sandbox: sandbox)
        }
        .sheet(isPresented: $showBoundarySheet) {
            SandboxBoundarySheet {
                AppNavigationRequest.request(.networkProtection)
            }
        }
        .sheet(item: $handoffPreview) { item in
            handoffPreviewSheet(item)
        }
        .sheet(item: $disableConfirmationStep) { step in
            SandboxDisableConfirmationSheet(
                step: step,
                onCancel: {
                    disableConfirmationStep = nil
                },
                onContinue: {
                    if step == .initial {
                        disableConfirmationStep = .final
                    } else {
                        disableConfirmationStep = nil
                        sandbox.resetInactiveSessions()
                        store.settings.experimentalSandboxEnabled = false
                    }
                }
            )
        }
        .confirmationDialog(
            text("出口检查未确认", "Exit check needs attention"),
            isPresented: Binding(
                get: { sandbox.webBrowser.pendingLaunchWarning != nil },
                set: { presented in
                    if !presented {
                        sandbox.webBrowser.cancelPendingLaunch()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(text("仍然打开", "Open anyway")) {
                Task { await store.confirmClaudeWebBrowserLaunch() }
            }
            Button(text("取消", "Cancel"), role: .cancel) {
                sandbox.webBrowser.cancelPendingLaunch()
            }
        } message: {
            Text(
                sandbox.webBrowser.pendingLaunchWarning
                    ?? text(
                        "没有取得可确认的 Chrome 出口。",
                        "No verifiable Chrome exit is available."
                    )
            )
        }
    }

    @ViewBuilder
    private var enabledContent: some View {
        overviewCard
        if terminalAutomationPermission.showsAuthorizationCard {
            macOSAuthorizationCard
        }
        targetGrid
        if !sandbox.sharedConfiguration.enabledTargets.isEmpty {
            if store.settings.gatewayProtectionMode != .off {
                gatewayReferenceCard
            }
            sessionOperations
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: sandbox.statusSymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(overviewStatusColor)
                    .frame(width: 44, height: 44)
                    .background(
                        overviewStatusColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sandbox.statusTitle)
                        .routekeeperFont(.title3, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(sandbox.message)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    helpButton
                    Button(text("关闭实验性沙箱…", "Turn off experimental sandbox…"), role: .destructive) {
                        disableConfirmationStep = .initial
                    }
                    .routekeeperSecondaryButton(.danger)
                    .disabled(sandbox.anyActive || sandbox.busy)
                    .help(sandbox.anyActive
                        ? text("结束所有活动会话后才能关闭。", "End every active session before turning it off.")
                        : text("关闭实验性沙箱", "Turn off the experimental sandbox"))
                }
            }

            AppHairline()

            sharedReadinessSummary
        }
        .padding(18)
        .appSurface(.primary)
    }

    private var macOSAuthorizationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(appStatusWarning)
                .frame(width: 34, height: 34)
                .background(
                    appStatusWarning.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(text("macOS 需要授权", "macOS authorization required"))
                        .routekeeperFont(.callout, weight: .semibold)
                    Label(
                        text("等待允许", "Waiting for permission"),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .routekeeperFont(.caption, weight: .medium)
                    .foregroundStyle(appStatusWarning)
                }
                Text(text(
                    "沙箱通过自动化权限在终端中创建会话。请在“隐私与安全性 > 自动化”中允许 Routekeeper 控制“终端”；授权后这张卡片会自动消失。",
                    "The sandbox uses Automation permission to create sessions in Terminal. Under Privacy & Security > Automation, allow Routekeeper to control Terminal; this card disappears automatically after authorization."
                ))
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if authorizationSettingsOpened {
                    Label(
                        text(
                            "系统设置已打开。允许 Routekeeper 后，此处会自动消失。",
                            "System Settings is open. This card disappears after Routekeeper is allowed."
                        ),
                        systemImage: "arrow.clockwise.circle"
                    )
                    .routekeeperFont(.caption, weight: .medium)
                    .foregroundStyle(appStatusWarning)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(text("打开系统设置", "Open System Settings")) {
                    openPrivacySettings(anchor: "Privacy_Automation")
                }
                .routekeeperSecondaryButton()
                Button(text("重新检查", "Check again")) {
                    Task {
                        terminalAutomationPermission = await TerminalAutomationPermissionProbe.current()
                    }
                }
                .routekeeperSecondaryButton()
            }
            .fixedSize()
        }
        .padding(14)
        .appSurface(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sandbox-macos-authorization")
    }

    private func openPrivacySettings(anchor: String) {
        authorizationSettingsOpened = true
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private var sharedReadinessSummary: some View {
        if sandbox.sharedConfiguration.enabledTargets.isEmpty {
            Label(
                text(
                    sandbox.webBrowser.installation == nil
                        ? "先启用上方已安装的 Claude 应用；不需要沙箱时可直接使用普通网络保护。"
                        : "Chrome 可独立打开；启用 Claude 后还可使用各自的隔离会话。",
                    sandbox.webBrowser.installation == nil
                        ? "Enable an installed Claude app above. Regular network protection remains available without the sandbox."
                        : "Chrome is available independently. Enable Claude to use its separate isolated session."
                ),
                systemImage: "info.circle"
            )
            .routekeeperFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            let incomplete = sharedReadinessItems.filter { $0.state != .complete }
            VStack(alignment: .leading, spacing: 9) {
                Group {
                    if incomplete.isEmpty {
                        Label(
                            text("共享准备已完成", "Shared preparation is complete"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .routekeeperFont(.caption, weight: .medium)
                        .foregroundStyle(appStatusSuccess)
                    } else {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(text("共享准备", "Shared readiness"))
                                .routekeeperFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                            ForEach(incomplete) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: item.state.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(item.state.color)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .routekeeperFont(.caption, weight: .medium)
                                        Text(item.detail)
                                            .routekeeperFont(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                if !hasSavedExit {
                    Button(text("检测出口", "Detect exit")) {
                        Task { _ = await store.detectExitForSandbox() }
                    }
                    .routekeeperSecondaryButton(.warning)
                }
            }
        }
    }

    private var targetGrid: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                targetCard(
                    sandbox.codeSession,
                    headerHeight: targetHeaderHeight,
                    statusHeight: targetStatusHeight,
                    detailHeight: targetDetailHeight,
                    primaryDetailHeight: targetDetailPrimaryHeight,
                    secondaryDetailHeight: targetDetailSecondaryHeight,
                    detailActionsHeight: targetDetailActionsHeight
                )
                    .frame(width: targetCardWidth)
                targetCard(
                    sandbox.desktopSession,
                    headerHeight: targetHeaderHeight,
                    statusHeight: targetStatusHeight,
                    detailHeight: targetDetailHeight,
                    primaryDetailHeight: targetDetailPrimaryHeight,
                    secondaryDetailHeight: targetDetailSecondaryHeight,
                    detailActionsHeight: targetDetailActionsHeight
                )
                    .frame(width: targetCardWidth)
                webBrowserCard(
                    headerHeight: targetHeaderHeight,
                    statusHeight: targetStatusHeight,
                    detailHeight: targetDetailHeight,
                    primaryDetailHeight: targetDetailPrimaryHeight,
                    secondaryDetailHeight: targetDetailSecondaryHeight,
                    detailActionsHeight: targetDetailActionsHeight
                )
                    .frame(width: targetCardWidth)
            }
            .scrollTargetLayout()
        }
        .onPreferenceChange(SandboxCardHeaderHeightKey.self) {
            targetHeaderHeight = $0
        }
        .onPreferenceChange(SandboxCardStatusHeightKey.self) {
            targetStatusHeight = $0
        }
        .onPreferenceChange(SandboxCardDetailHeightKey.self) {
            targetDetailHeight = $0
        }
        .onPreferenceChange(SandboxCardDetailPrimaryHeightKey.self) {
            targetDetailPrimaryHeight = $0
        }
        .onPreferenceChange(SandboxCardDetailSecondaryHeightKey.self) {
            targetDetailSecondaryHeight = $0
        }
        .onPreferenceChange(SandboxCardDetailActionsHeightKey.self) {
            targetDetailActionsHeight = $0
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SandboxCardGridWidthKey.self,
                    value: proxy.size.width
                )
            }
        )
        .onPreferenceChange(SandboxCardGridWidthKey.self) {
            targetGridWidth = $0
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppCornerRadius.card,
                style: .continuous
            )
        )
        .scrollIndicators(.visible)
        .accessibilityIdentifier("sandbox-target-cards")
        .accessibilityElement(children: .contain)
    }

    private var targetCardWidth: CGFloat {
        guard targetGridWidth > 0 else { return 256 }
        // Two full cards plus half of the next one signal horizontal scrolling.
        let widthForNextCardPreview = targetGridWidth * 0.4 - 11.2
        return max(232, min(360, widthForNextCardPreview))
    }

    private func sandboxCardHeader<Accessory: View>(
        symbol: String,
        color: Color,
        title: String,
        subtitle: String,
        height: CGFloat,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(
                    color.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .routekeeperFont(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                Text(subtitle)
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            accessory()
        }
        .frame(minHeight: height, alignment: .topLeading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SandboxCardHeaderHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
    }

    private func sandboxCardStatus(
        symbol: String,
        title: String,
        message: String?,
        color: Color,
        height: CGFloat,
        helpAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .routekeeperFont(.callout, weight: .semibold)
                if let message, !message.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(message)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let helpAction {
                            Button(action: helpAction) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                            .help(text("打开 Chrome 帮助", "Open Chrome help"))
                            .accessibilityLabel(text("打开 Chrome 帮助", "Open Chrome help"))
                        }
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .frame(minHeight: height, alignment: .topLeading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SandboxCardStatusHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
    }

    private func sandboxCardDetailBlock<Content: View>(
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(10)
        .frame(minHeight: height, alignment: .topLeading)
        .appSurface(.inset, corner: 10)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SandboxCardDetailHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
    }

    private func measuredSandboxCardDetailRow<Content: View, Key: PreferenceKey>(
        height: CGFloat,
        key: Key.Type,
        @ViewBuilder content: () -> Content
    ) -> some View where Key.Value == CGFloat {
        content()
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: key, value: proxy.size.height)
                }
            )
    }

    private func sandboxCardFooter<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppHairline()
            HStack(spacing: 6) {
                leading()
                    .routekeeperFont(.caption, weight: .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                trailing()
                    .layoutPriority(1)
            }
        }
    }

    private func webBrowserCard(
        headerHeight: CGFloat,
        statusHeight: CGFloat,
        detailHeight: CGFloat,
        primaryDetailHeight: CGFloat,
        secondaryDetailHeight: CGFloat,
        detailActionsHeight: CGFloat
    ) -> some View {
        let browser = sandbox.webBrowser
        return VStack(alignment: .leading, spacing: 12) {
            sandboxCardHeader(
                symbol: "safari",
                color: webBrowserStatusColor,
                title: "Chrome",
                subtitle: text("独立浏览器配置", "Dedicated browser profile"),
                height: headerHeight
            ) {
                EmptyView()
            }

            sandboxCardStatus(
                symbol: browser.statusSymbol,
                title: browser.statusTitle,
                message: browser.showsReadySummary
                    ? text("Chrome 使用独立沙箱配置", "Chrome uses a dedicated sandbox profile")
                    : browser.message,
                color: webBrowserStatusColor,
                height: statusHeight,
                helpAction: openClaudeWebHelp
            )

            sandboxCardDetailBlock(height: detailHeight) {
                webBrowserDetailContent(
                    primaryHeight: primaryDetailHeight,
                    secondaryHeight: secondaryDetailHeight,
                    actionsHeight: detailActionsHeight
                )
            }

            Spacer(minLength: 0)

            sandboxCardFooter {
                Label(
                    browser.phase.isRunning
                        ? text("运行中", "Running")
                        : text("未启动", "Not running"),
                    systemImage: browser.phase.isRunning ? "lock.shield.fill" : "browser"
                )
                .foregroundStyle(browser.phase.isRunning ? appStatusSuccess : Color.secondary)
            } trailing: {
                webBrowserPrimaryControl
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSurface(.primary)
        .accessibilityIdentifier("sandbox-target-claude-web")
    }

    @ViewBuilder
    private func webBrowserDetailContent(
        primaryHeight: CGFloat,
        secondaryHeight: CGFloat,
        actionsHeight: CGFloat
    ) -> some View {
        let browser = sandbox.webBrowser
        measuredSandboxCardDetailRow(
            height: primaryHeight,
            key: SandboxCardDetailPrimaryHeightKey.self
        ) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "globe")
                    .foregroundStyle(browser.installation == nil ? appStatusWarning : appStatusSuccess)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(
                    browser.installation?.shortVersion.map { "Google Chrome \($0)" }
                        ?? text("未检测到 Google Chrome", "Google Chrome not detected")
                )
                .routekeeperFont(.caption, weight: .medium)
                Spacer(minLength: 8)
            }
        }

        measuredSandboxCardDetailRow(
            height: secondaryHeight,
            key: SandboxCardDetailSecondaryHeightKey.self
        ) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(browser.profileAvailable ? appStatusSuccess : Color.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(
                    browser.profileAvailable
                        ? text("Chrome 登录状态已保留", "Chrome sign-in saved")
                        : text("Chrome 使用独立登录状态", "Chrome uses a separate sign-in profile")
                )
                .routekeeperFont(.caption, weight: .medium)
                Spacer(minLength: 8)
            }
        }

        measuredSandboxCardDetailRow(
            height: actionsHeight,
            key: SandboxCardDetailActionsHeightKey.self
        ) {
            VStack(alignment: .leading, spacing: 7) {
                Button(text("重新检测", "Detect again")) {
                    Task { await browser.refreshInstallation() }
                }
                .routekeeperSecondaryButton()
                .disabled(browser.busy || browser.discovering || browser.phase.isRunning)

                if browser.egressChecking {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(text("正在核对 Routekeeper 中继出口", "Checking the Routekeeper relay exit"))
                    }
                    .routekeeperFont(.caption2)
                    .foregroundStyle(.secondary)
                } else if let warning = browser.egressWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .routekeeperFont(.caption2)
                        .foregroundStyle(appStatusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var webBrowserPrimaryControl: some View {
        let browser = sandbox.webBrowser
        return Group {
            if browser.busy || browser.discovering || browser.phase == .launching {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(
                        browser.discovering
                            ? text("正在检测", "Detecting")
                            : text("正在准备", "Preparing")
                    )
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if browser.phase.isRunning {
                HStack(spacing: 8) {
                    if browser.phase == .networkPaused {
                        Button(text("恢复网络", "Restore network")) {
                            Task { _ = await browser.resumeNetwork() }
                        }
                        .routekeeperSecondaryButton(.warning)
                    }
                    Button(text("关闭浏览器", "Close browser")) {
                        Task { await browser.stop() }
                    }
                    .routekeeperSecondaryButton(.danger)
                }
            } else if browser.installation == nil {
                Button(text("获取 Google Chrome", "Get Google Chrome")) {
                    if let url = URL(string: "https://www.google.com/chrome/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .routekeeperProminentButton(.primary)
            } else {
                Button(
                    browser.phase == .failed
                        ? text("重试", "Retry")
                        : text("打开 Chrome", "Open Chrome")
                ) {
                    Task { await store.launchClaudeWebBrowser() }
                }
                .routekeeperProminentButton(browser.phase == .failed ? .warning : .primary)
            }
        }
    }

    private func targetCard(
        _ session: SandboxSession,
        headerHeight: CGFloat,
        statusHeight: CGFloat,
        detailHeight: CGFloat,
        primaryDetailHeight: CGFloat,
        secondaryDetailHeight: CGFloat,
        detailActionsHeight: CGFloat
    ) -> some View {
        let target = session.configuration.target
        let enabled = sandbox.sharedConfiguration.isEnabled(target)
        let color = targetStatusColor(session, enabled: enabled)
        return VStack(alignment: .leading, spacing: 12) {
            sandboxCardHeader(
                symbol: target == .claudeCode ? "terminal" : "macwindow",
                color: color,
                title: target.title,
                subtitle: targetSubtitle(target),
                height: headerHeight
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { enabled },
                        set: { sandbox.setTarget(target, enabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(enabled ? appStatusSuccess : Color(nsColor: .tertiaryLabelColor))
                .disabled(session.phase.isActive || session.busy)
                .accessibilityLabel(text("启用 \(target.title)", "Enable \(target.title)"))
            }

            sandboxCardStatus(
                symbol: enabled ? session.statusSymbol : "pause.circle",
                title: enabled ? session.statusTitle : text("未启用", "Not enabled"),
                message: enabled && !(session.phase == .ready && session.configuration.hasRequiredPaths)
                    ? session.message
                    : nil,
                color: color,
                height: statusHeight
            )

            if target == .claudeDesktop {
                desktopInstallationBlock(
                    session,
                    height: detailHeight,
                    primaryHeight: primaryDetailHeight,
                    secondaryHeight: secondaryDetailHeight,
                    actionsHeight: detailActionsHeight
                )
            } else {
                claudeCodeInstallationBlock(
                    session,
                    height: detailHeight,
                    primaryHeight: primaryDetailHeight,
                    secondaryHeight: secondaryDetailHeight,
                    actionsHeight: detailActionsHeight
                )
            }

            Spacer(minLength: 0)
            sandboxCardFooter {
                if !enabled {
                    Label(text("未启用", "Not enabled"), systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                } else {
                    if session.phase.isActive {
                        Label(
                            session.networkEnabled
                                ? text("中继网络已开启", "Relay network on")
                                : text("网络已关闭", "Network off"),
                            systemImage: session.networkEnabled ? "network" : "wifi.slash"
                        )
                        .foregroundStyle(session.networkEnabled ? appStatusSuccess : appStatusWarning)
                    }
                    if session.claudeRunning {
                        Label(text("Claude 正在运行", "Claude running"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(appStatusSuccess)
                    } else if target == .claudeCode {
                        let signedIn = store.authentication.status == .saved
                        Label(
                            signedIn
                                ? text("登录凭证已保存", "Sign-in saved")
                                : text("登录凭证可选", "Sign-in optional"),
                            systemImage: signedIn ? "key.fill" : "key.slash"
                        )
                        .foregroundStyle(signedIn ? appStatusSuccess : Color.secondary)
                    } else if target == .claudeDesktop {
                        Label(
                            session.desktopIsolationSupported
                                ? text("已验证", "Verified")
                                : text("需处理", "Needs attention"),
                            systemImage: session.desktopIsolationSupported
                                ? "checkmark.seal.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(session.desktopIsolationSupported ? appStatusSuccess : appStatusWarning)
                    }
                }
            } trailing: {
                if enabled {
                    targetPrimaryControl(session)
                }
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .appSurface(.primary)
        .accessibilityIdentifier("sandbox-target-\(target.rawValue)")
    }

    private func targetSubtitle(_ target: IsolationApplicationTarget) -> String {
        switch target {
        case .claudeCode:
            return text("项目副本与终端会话", "Workspace and Terminal session")
        case .claudeDesktop:
            return text("官方应用与隔离会话", "Official app and isolated session")
        }
    }

    private func desktopLoginSummary(_ session: SandboxSession) -> String {
        let persists = sandbox.sharedConfiguration.persistClaudeLogin
        let profileAvailable = session.persistedClaudeProfileAvailable
        if persists && profileAvailable {
            return text("已保留 Claude 登录状态", "Claude sign-in profile saved")
        }
        if persists {
            return text("下次登录后保留 Claude 登录状态", "Claude profile will be kept after sign-in")
        }
        if profileAvailable {
            return text("已有登录数据，当前使用临时登录", "Sign-in data exists; current sessions use temporary sign-in")
        }
        return text("每次会话使用临时登录", "Each session uses temporary sign-in")
    }

    private func claudeCodeInstallationBlock(
        _ session: SandboxSession,
        height: CGFloat,
        primaryHeight: CGFloat,
        secondaryHeight: CGFloat,
        actionsHeight: CGFloat
    ) -> some View {
        let installation = session.claudeCodeInstallation
        let manuallySelected = installation?.source == .manuallySelected
        return sandboxCardDetailBlock(height: height) {
            measuredSandboxCardDetailRow(
                height: primaryHeight,
                key: SandboxCardDetailPrimaryHeightKey.self
            ) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: installation == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(installation == nil ? appStatusWarning : appStatusSuccess)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            installation == nil
                                ? text("未检测到 Claude Code", "Claude Code not detected")
                                : manuallySelected
                                    ? text("已选择现有 Claude Code 命令", "Existing Claude Code command selected")
                                    : text("已检测到现有 Claude Code", "Existing Claude Code detected")
                        )
                        .routekeeperFont(.caption, weight: .medium)
                        if installation == nil {
                            Text(text(
                                "安装后用“重新检测”，或在非默认位置手动选择 claude 命令。",
                                "After installation, detect again or manually choose the claude command in a custom location."
                            ))
                            .routekeeperFont(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                }
            }

            measuredSandboxCardDetailRow(
                height: secondaryHeight,
                key: SandboxCardDetailSecondaryHeightKey.self
            ) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: store.authentication.status == .saved ? "key.fill" : "key.slash")
                        .foregroundStyle(store.authentication.status == .saved ? appStatusSuccess : Color.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(
                        store.authentication.status == .saved
                            ? text("Claude Code 登录凭证已保存", "Claude Code sign-in saved")
                            : text("登录凭证可选，可直接创建会话", "Sign-in is optional; you can create a session now")
                    )
                    .routekeeperFont(.caption, weight: .medium)
                    Spacer(minLength: 8)
                }
            }

            measuredSandboxCardDetailRow(
                height: actionsHeight,
                key: SandboxCardDetailActionsHeightKey.self
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        claudeCodeLocationActions(session, installation: installation)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        claudeCodeLocationActions(session, installation: installation)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func claudeCodeLocationActions(
        _ session: SandboxSession,
        installation: ClaudeCodeInstallation?
    ) -> some View {
        if installation == nil {
            Button(text("安装说明", "Install guide")) {
                if let url = URL(string: "https://code.claude.com/docs/en/setup") {
                    NSWorkspace.shared.open(url)
                }
            }
            .routekeeperSecondaryButton()
        }
        Button(text("重新检测", "Detect again")) {
            session.refreshClaudeCodeDiscovery()
        }
        .routekeeperSecondaryButton()
        Button(text("选择命令…", "Choose command…")) {
            chooseClaudeCodeCommand(session)
        }
        .routekeeperSecondaryButton()
        if session.workspaceAvailable {
            Button(text("在 Finder 中显示", "Show in Finder")) {
                session.revealWorkspace()
            }
            .routekeeperSecondaryButton()
        }
    }

    private func chooseClaudeCodeCommand(_ session: SandboxSession) {
        let panel = NSOpenPanel()
        panel.title = text("选择 claude 命令", "Choose the claude command")
        panel.prompt = text("选择", "Choose")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url, !session.selectClaudeCodeCommand(at: url) {
            let alert = NSAlert()
            alert.messageText = text("无法使用所选命令", "The selected command cannot be used")
            alert.informativeText = session.message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @ViewBuilder
    private func desktopInstallationBlock(
        _ session: SandboxSession,
        height: CGFloat,
        primaryHeight: CGFloat,
        secondaryHeight: CGFloat,
        actionsHeight: CGFloat
    ) -> some View {
        let installation = session.desktopInstallation
        let supported = installation?.supportsIsolatedLaunch == true
        sandboxCardDetailBlock(height: height) {
            measuredSandboxCardDetailRow(
                height: primaryHeight,
                key: SandboxCardDetailPrimaryHeightKey.self
            ) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: supported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(supported ? appStatusSuccess : appStatusWarning)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            installation == nil
                                ? text("未找到已验证签名的 Claude", "Verified Claude app not found")
                                : supported
                                    ? text("已验证官方 Claude", "Official Claude verified")
                                    : text("官方客户端缺少可隔离启动的入口", "The official app has no isolatable launch path")
                        )
                        .routekeeperFont(.caption, weight: .medium)
                        if let installation {
                            Text(desktopInstallationDetail(installation))
                                .routekeeperFont(.caption2, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        if session.desktopAppRunningOutsideSandbox, !session.claudeRunning {
                            Text(text(
                                "请先完全退出正在运行的 Claude，再重新检测。",
                                "Fully quit the running Claude app before detecting it again."
                            ))
                            .routekeeperFont(.caption2)
                            .foregroundStyle(appStatusWarning)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                }
            }

            measuredSandboxCardDetailRow(
                height: secondaryHeight,
                key: SandboxCardDetailSecondaryHeightKey.self
            ) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(appStatusSuccess)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(desktopLoginSummary(session))
                        .routekeeperFont(.caption, weight: .medium)
                    Spacer(minLength: 8)
                }
            }

            measuredSandboxCardDetailRow(
                height: actionsHeight,
                key: SandboxCardDetailActionsHeightKey.self
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        desktopLocationActions(session, installation: installation)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        desktopLocationActions(session, installation: installation)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func desktopLocationActions(
        _ session: SandboxSession,
        installation: ClaudeDesktopInstallation?
    ) -> some View {
        Button(text("重新检测", "Detect again")) {
            session.refreshDesktopDiscovery()
        }
        .routekeeperSecondaryButton()
        if installation == nil || installation?.supportsIsolatedLaunch != true {
            Button(text("获取客户端", "Get app")) {
                if let url = URL(string: "https://claude.ai/download") {
                    NSWorkspace.shared.open(url)
                }
            }
            .routekeeperSecondaryButton()
        }
        Button(text("管理登录…", "Manage sign-in…")) {
            AppNavigationRequest.request(.authentication)
        }
        .routekeeperSecondaryButton()
        if session.workspaceAvailable {
            Button(text("在 Finder 中显示", "Show in Finder")) {
                session.revealWorkspace()
            }
            .routekeeperSecondaryButton()
        }
    }

    @ViewBuilder
    private func targetPrimaryControl(_ session: SandboxSession) -> some View {
        if session.busy || session.phase == .preparing || session.phase == .checking {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(text("正在准备", "Preparing"))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if session.phase == .running, !session.claudeRunning {
            launchClaudeButton(session)
        } else if let action = guideAction(for: session) {
            Button(action.title) {
                perform(action, session: session)
            }
            .routekeeperProminentButton(action.tone)
            .disabled(action == .prepare && !session.canPrepare)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func launchClaudeButton(_ session: SandboxSession) -> some View {
        let desktop = session.configuration.target == .claudeDesktop
        return Button {
            store.launchClaudeInSandbox(target: session.configuration.target)
        } label: {
            Label(
                desktop
                    ? (session.desktopInstallation?.runtimeFamily == .operonHostedWeb
                        ? text("启动 Claude Science", "Launch Claude Science")
                        : text("启动 Claude", "Launch Claude"))
                    : text("在终端启动 Claude Code", "Launch Claude Code"),
                systemImage: "play.fill"
            )
        }
        .routekeeperProminentButton(.primary)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(
            !session.canLaunchClaude
                || (desktop
                    ? !session.desktopIsolationSupported
                        || (session.desktopInstallation?.runtimeFamily == .electron
                            && session.desktopAppRunningOutsideSandbox)
                    : false)
        )
    }

    private var gatewayReferenceCard: some View {
        let mode = store.settings.gatewayProtectionMode
        let status = store.gatewayVerification.status(for: mode)
        let statusColor = status == .failed || status == .expired
            ? appStatusFailure
            : appStatusWarning
        return Group {
            if status != .verified {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                    Text(gatewayReferenceTitle(status))
                        .routekeeperFont(.callout, weight: .semibold)
                        .foregroundStyle(statusColor)
                    Spacer(minLength: 8)
                    Button(text("前往处理", "Review")) {
                        AppNavigationRequest.request(.networkProtection)
                    }
                    .routekeeperSecondaryButton(status == .failed || status == .expired ? .danger : .warning)
                }
                .padding(14)
                .appSurface(.secondary, corner: 12)
            }
        }
    }

    @ViewBuilder
    private var sessionOperations: some View {
        ForEach(sandbox.sessions, id: \.configuration.target) { session in
            if sandbox.sharedConfiguration.isEnabled(session.configuration.target),
               shouldShowOperations(session) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(text("\(session.configuration.target.title) 会话详情",
                                   "\(session.configuration.target.title) session details"))
                            .routekeeperFont(.headline)
                        Spacer()
                    }
                    .padding(.top, 2)

                    if !session.checks.isEmpty {
                        checksCard(session)
                    }
                    if session.configuration.target == .claudeDesktop,
                       session.desktopInstallation?.runtimeFamily == .electron,
                       session.phase == .running || session.phase == .networkPaused {
                        claudeLoginCallbackCard(session)
                    }
                    if session.phase.isActive || session.phase == .ended
                        || !session.externalActions.items.isEmpty {
                        authorizationHandoffCard(session)
                    }
                    if session.phase == .ended || !session.changedFiles.isEmpty {
                        reviewCard(session)
                    }
                }
            }
        }
    }

    private func shouldShowOperations(_ session: SandboxSession) -> Bool {
        !session.checks.isEmpty
            || session.phase.isActive
            || session.phase == .ended
            || !session.externalActions.items.isEmpty
            || !session.changedFiles.isEmpty
    }

    private func checksCard(_ session: SandboxSession) -> some View {
        let blocking = session.checks.filter(\.blocksLaunch)
        let warnings = session.checks.filter { $0.isWarning && !$0.passed }
        let passed = blocking.isEmpty
        let target = session.configuration.target
        return GuardCard(
            title: text("启动前检查", "Preflight checks"),
            subtitle: passed
                ? text("安全边界必须通过；出口核对警告不会阻止启动，由你决定是否继续。",
                       "Security boundaries must pass. Exit-check warnings do not block launch, and you decide whether to continue.")
                : text("阻断项必须处理后才能启动这个保护对象。",
                       "Blocking items must be resolved before this target can start.")
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: !passed
                        ? "xmark.shield.fill"
                        : warnings.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(!passed
                            ? appStatusFailure
                            : warnings.isEmpty ? appStatusSuccess : appStatusWarning)
                    Text(!passed
                        ? text("\(blocking.count) 项阻断检查", "\(blocking.count) blocking checks")
                        : warnings.isEmpty
                            ? text("\(session.checks.count) 项检查全部通过", "\(session.checks.count) checks passed")
                            : text("安全边界已通过，\(warnings.count) 项警告",
                                   "Security boundaries passed with \(warnings.count) warnings"))
                    .routekeeperFont(.callout, weight: .semibold)
                    Spacer()
                }
                .padding(.bottom, blocking.isEmpty && warnings.isEmpty ? 0 : 8)

                let issues = blocking + warnings
                if !issues.isEmpty {
                    ForEach(Array(issues.enumerated()), id: \.element.id) { index, check in
                        checkRow(check, showRemediation: true)
                        if index < issues.count - 1 { AppHairline() }
                    }
                }

                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedChecks.contains(target) },
                        set: { expanded in
                            if expanded {
                                expandedChecks.insert(target)
                            } else {
                                expandedChecks.remove(target)
                            }
                        }
                    ),
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
                        Text(text("查看全部 \(session.checks.count) 项检查",
                                  "Show all \(session.checks.count) checks"))
                            .routekeeperFont(.caption, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                )
                .padding(.top, issues.isEmpty ? 0 : 8)
            }
        }
    }

    private func checkRow(_ check: IsolationCheck, showRemediation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: check.passed
                    ? "checkmark.circle.fill"
                    : check.isWarning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                    .foregroundStyle(check.passed
                        ? appStatusSuccess
                        : check.isWarning ? appStatusWarning : appStatusFailure)
                    .frame(width: 18)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title)
                        .routekeeperFont(.callout, weight: .medium)
                    Text(check.detail)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showRemediation, !check.passed {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(appStatusWarning)
                    Text(sandboxRemediation(for: check.id))
                        .routekeeperFont(.caption)
                        .foregroundStyle(appStatusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func claudeLoginCallbackCard(_ session: SandboxSession) -> some View {
        let canSubmit = session.phase == .running
            && session.networkEnabled
            && session.claudeRunning
            && session.claudeLoginCallbackStatus != .waiting
        return GuardCard(
            title: text("Claude 邮件登录回调", "Claude email sign-in callback"),
            subtitle: text(
                "不要直接点击邮件里的登录按钮。右键复制“Sign in”链接，再交给沙箱中的 Claude。",
                "Do not click the email sign-in button. Copy the Sign in link and hand it to the sandboxed Claude instance."
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    text(
                        "直接在默认浏览器打开会让 claude.ai 看到沙箱外的出口。Routekeeper 不读取邮箱、不访问该链接，也不保存链接中的一次性凭证。",
                        "Opening the link in the default browser exposes an outside exit to claude.ai. Routekeeper does not read email, fetch the link or save its one-time credential."
                    ),
                    systemImage: "exclamationmark.shield.fill"
                )
                .routekeeperFont(.callout)
                .foregroundStyle(appStatusWarning)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    SecureField(
                        text("粘贴邮件中的 Claude 登录链接", "Paste the Claude sign-in URL from your email"),
                        text: $claudeLoginLink
                    )
                    .textFieldStyle(.roundedBorder)
                    Button(text("交给沙箱 Claude", "Send to sandboxed Claude")) {
                        if session.submitClaudeLoginLink(claudeLoginLink) {
                            claudeLoginLink = ""
                        }
                    }
                    .routekeeperProminentButton(.success)
                    .disabled(!canSubmit || claudeLoginLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !claudeLoginLink.isEmpty {
                        Button(text("清除", "Clear")) {
                            claudeLoginLink = ""
                        }
                        .routekeeperSecondaryButton()
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    switch session.claudeLoginCallbackStatus {
                    case .waiting:
                        ProgressView().controlSize(.small)
                    case .delivered:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(appStatusSuccess)
                    case .invalid, .failed:
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(appStatusFailure)
                    case .idle:
                        Image(systemName: "key.horizontal").foregroundStyle(.secondary)
                    }
                    Text(session.claudeLoginCallbackMessage)
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func authorizationHandoffCard(_ session: SandboxSession) -> some View {
        GuardCard(
            title: text("授权隔离", "Authorization handoff"),
            subtitle: text(
                "Claude 只能提交操作请求，不能读取 Git、Notion 或其他外部服务的凭据。宿主侧只在你确认后执行。",
                "Claude can submit an operation request but cannot read credentials for Git, Notion or other external services. The host acts only after your approval."
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(appAccent)
                        .frame(width: 36, height: 36)
                        .background(appAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text("交接目录", "Handoff directory"))
                            .routekeeperFont(.callout, weight: .semibold)
                        Text(".routekeeper-actions")
                            .routekeeperFont(.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                        Text(session.externalActions.message)
                            .routekeeperFont(.caption)
                            .foregroundStyle(session.externalActions.pendingCount > 0
                                ? appStatusWarning
                                : Color.secondary)
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
                        text("尚未收到请求。需要外部操作时，Claude 只能写入 JSON 清单和交付文件。",
                             "No requests yet. For external work, Claude can write only a JSON manifest and payload."),
                        systemImage: "tray"
                    )
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(session.externalActions.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { AppHairline() }
                        handoffActionRow(item, session: session)
                    }
                }

                if !session.externalActions.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(text("已拒绝的请求", "Rejected requests"), systemImage: "exclamationmark.shield")
                            .routekeeperFont(.caption, weight: .semibold)
                            .foregroundStyle(appStatusWarning)
                        ForEach(session.externalActions.issues.prefix(4)) { issue in
                            Text("\(issue.manifestName)：\(issue.message)")
                                .routekeeperFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func handoffActionRow(_ item: HandoffActionItem, session: SandboxSession) -> some View {
        let request = item.package.request
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: request.kind == .applyGitPatch ? "arrow.down.doc" : "doc.badge.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(appAccent)
                    .frame(width: 32, height: 32)
                    .background(appAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                    Text("\(request.suggestedName) · \(handoffByteCount(item.package.payloadBytes)) · SHA256 \(item.package.payloadSHA256.prefix(12))")
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
                        chooseHandoffDestination(item, session: session)
                    }
                    .routekeeperProminentButton(.success)
                    .disabled(!item.state.isActionable)
                } else {
                    Button(text("应用到 Git 仓库…", "Apply to Git repository…")) {
                        chooseGitRepository(item, session: session)
                    }
                    .routekeeperProminentButton(.success)
                    .disabled(!item.state.isActionable)
                    Button(text("另存补丁…", "Save patch…")) {
                        choosePatchDestination(item, session: session)
                    }
                    .routekeeperSecondaryButton()
                    .disabled(!item.state.isActionable)
                }
                if item.state.isActionable {
                    Button(text("拒绝", "Reject"), role: .destructive) {
                        session.externalActions.reject(item)
                    }
                    .routekeeperSecondaryButton(.danger)
                }
                if case .running = item.state {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            .padding(.leading, 43)
        }
    }

    private func reviewCard(_ session: SandboxSession) -> some View {
        GuardCard(
            title: text("审阅项目变化", "Review project changes"),
            subtitle: text(
                "Routekeeper 不会自动把工作副本覆盖回原项目。请先打开副本检查差异，再自行决定如何采用。",
                "Routekeeper never copies a workspace back automatically. Open the copy, review the changes, then decide how to apply them."
            )
        ) {
            if session.changedFiles.isEmpty {
                Label(text("没有发现项目文件变化。", "No project file changes were found."), systemImage: "equal.circle")
                    .foregroundStyle(.secondary)
            } else {
                Text(text("发现 \(session.changedFiles.count) 条文件差异",
                          "\(session.changedFiles.count) file differences found"))
                    .routekeeperFont(.callout, weight: .medium)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(session.changedFiles, id: \.self) { line in
                        Text(line)
                            .routekeeperFont(.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Spacer()
                    Button(text("打开工作副本", "Open workspace")) {
                        session.openWorkspace()
                    }
                    .routekeeperSecondaryButton()
                }
            }
        }
    }

    private var sandboxDisabledCard: some View {
        GuardCard(
            title: text("隔离运行 Claude", "Run Claude in isolation"),
            subtitle: text(
                "为 Claude Code、Claude 和 Chrome 提供独立的项目副本、登录数据与网络路径。",
                "Give Claude Code, Claude and Chrome separate workspaces, sign-in data and network paths."
            )
        ) {
            HStack(alignment: .top, spacing: 12) {
                sandboxIntroFeature(
                    title: text("独立副本", "Separate workspace"),
                    detail: text("修改留在本次会话", "Changes stay in this session"),
                    symbol: "square.on.square"
                )
                sandboxIntroFeature(
                    title: text("断网保护", "Fail closed"),
                    detail: text("代理失败时停止联网", "No direct fallback"),
                    symbol: "network.slash"
                )
                sandboxIntroFeature(
                    title: text("共享环境", "Shared setup"),
                    detail: text("时区、地区与出口", "Time, region and exit"),
                    symbol: "slider.horizontal.3"
                )
            }

            AppHairline()
            HStack {
                Label(
                    text("实验性功能，启动前会执行完整边界检查。",
                         "Experimental; every launch runs full boundary checks."),
                    systemImage: "lock.shield"
                )
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(text("启用实验性沙箱", "Enable experimental sandbox")) {
                    store.settings.experimentalSandboxEnabled = true
                }
                .routekeeperProminentButton(.primary)
            }
        }
    }

    private func sandboxIntroFeature(
        title: String,
        detail: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(appAccent)
                .frame(width: 38, height: 38)
                .background(appAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .routekeeperFont(.callout, weight: .semibold)
            Text(detail)
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appSurface(.inset, corner: 10)
    }

    private var pageOverflowEntries: [PageOverflowEntry] {
        let actionableSessions = sandbox.enabledSessions.filter {
            $0.phase == .running || $0.phase == .networkPaused || $0.phase.isActive
        }
        let browser = sandbox.webBrowser
        let hasBrowserNetworkAction = browser.canPauseNetwork || browser.canResumeNetwork
        var result: [PageOverflowEntry] = [
            .action(PageOverflowAction(
                title: text("共享环境、时区与地区…", "Shared environment, timezone and region…"),
                systemImage: "slider.horizontal.3"
            ) {
                showScopeSheet = true
            }),
            .separator,
            .action(PageOverflowAction(
                title: text("代理配置一致性…", "Proxy configuration consistency…"),
                systemImage: "link.circle"
            ) {
                showProxySheet = true
            }),
            .action(PageOverflowAction(
                title: text("代理与边界…", "Proxy and boundaries…"),
                systemImage: "shield.lefthalf.filled"
            ) {
                showBoundarySheet = true
            }),
            .separator
        ]

        for session in actionableSessions {
            if session.phase == .running {
                result.append(.action(PageOverflowAction(
                    title: text(
                        "关闭 \(session.configuration.target.title) 网络",
                        "Turn off \(session.configuration.target.title) network"
                    ),
                    systemImage: "wifi.slash"
                ) {
                    sandbox.pauseNetwork(target: session.configuration.target)
                }))
            } else if session.phase == .networkPaused {
                result.append(.action(PageOverflowAction(
                    title: text(
                        "恢复 \(session.configuration.target.title) 网络",
                        "Restore \(session.configuration.target.title) network"
                    ),
                    systemImage: "wifi"
                ) {
                    Task { await sandbox.resumeNetwork(target: session.configuration.target) }
                }))
            }
            if session.phase.isActive {
                result.append(.action(PageOverflowAction(
                    title: text(
                        "结束 \(session.configuration.target.title) 会话",
                        "End \(session.configuration.target.title) session"
                    ),
                    systemImage: "stop.circle",
                    isDestructive: true
                ) {
                    Task { await sandbox.endSession(target: session.configuration.target) }
                }))
            }
        }
        if browser.canPauseNetwork {
            result.append(.action(PageOverflowAction(
                title: text("关闭 Chrome 网络", "Turn off Chrome network"),
                systemImage: "wifi.slash"
            ) {
                browser.pauseNetwork()
            }))
        } else if browser.canResumeNetwork {
            result.append(.action(PageOverflowAction(
                title: text("恢复 Chrome 网络", "Restore Chrome network"),
                systemImage: "wifi"
            ) {
                Task { _ = await browser.resumeNetwork() }
            }))
        }
        if !actionableSessions.isEmpty || hasBrowserNetworkAction {
            result.append(.separator)
        }
        result.append(.action(PageOverflowAction(
            title: text("Chrome 帮助…", "Chrome help…"),
            systemImage: "globe"
        ) {
            openClaudeWebHelp()
        }))
        result.append(.action(PageOverflowAction(
            title: text("实验性沙箱帮助…", "Experimental sandbox help…"),
            systemImage: "questionmark.circle"
        ) {
            openSandboxHelp()
        }))
        return result
    }

    private var sandboxToolbarSignature: String {
        let sessions = sandbox.enabledSessions
            .map { "\($0.configuration.target)|\($0.phase)" }
            .joined(separator: ",")
        let browser = sandbox.webBrowser
        return "\(L10n.resolvedEnglish)|\(sessions)|\(browser.profileAvailable)|\(browser.phase)"
    }

    private var helpButton: some View {
        Button {
            openSandboxHelp()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .contentShape(Circle())
        .help(text("打开实验性沙箱帮助", "Open experimental sandbox help"))
        .accessibilityLabel(text("打开实验性沙箱帮助", "Open experimental sandbox help"))
    }

    private func openSandboxHelp() {
        RoutekeeperHelpNavigation.request(.sandboxOverview)
        openWindow(id: "routekeeper-help")
    }

    private func openClaudeWebHelp() {
        RoutekeeperHelpNavigation.request(.sandboxWeb)
        openWindow(id: "routekeeper-help")
    }

    private var hasSavedExit: Bool {
        store.settings.target(for: .ipv4) != nil
            || store.settings.target(for: .ipv6) != nil
    }

    private var sharedScopeComplete: Bool {
        let configuration = sandbox.sharedConfiguration
        guard !configuration.enabledTargets.isEmpty else { return false }
        guard !configuration.exchangePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard TimeZone(identifier: configuration.timezoneIdentifier) != nil,
              configuration.hasValidLanguage,
              configuration.upstream.isValid else { return false }
        if configuration.isEnabled(.claudeCode) {
            return !configuration.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var sharedReadinessItems: [SandboxReadinessItem] {
        let enabled = sandbox.enabledSessions
        let nonLoopback = enabled.compactMap(\.detectedProxy).first { !$0.isLoopback }
        let proxyItem = SandboxReadinessItem(
            id: "proxy",
            title: text("代理", "Proxy"),
            detail: nonLoopback == nil
                ? text("本机回环代理入口可用。", "A loopback proxy entry is available.")
                : text("系统代理不是本机端口；代理客户端需要提供本机 HTTP 或 SOCKS 入口。",
                       "The system proxy is not loopback; the proxy app must expose a local HTTP or SOCKS endpoint."),
            state: nonLoopback == nil ? .complete : .attention
        )
        let exitItem = SandboxReadinessItem(
            id: "exit",
            title: text("固定出口", "Fixed exit"),
            detail: hasSavedExit
                ? text("已保存用于核对 Claude 的出口。", "A fixed exit is saved for Claude verification.")
                : text("运行出口检测并保存一个 IPv4 或 IPv6 出口。",
                       "Detect and save an IPv4 or IPv6 exit."),
            state: hasSavedExit ? .complete : .current
        )
        let scopeItem = SandboxReadinessItem(
            id: "scope",
            title: text("共享范围", "Shared scope"),
            detail: sharedScopeComplete
                ? text("目录、时区、语言与上游代理已就绪。", "Folders, timezone, language and upstream proxy are ready.")
                : text("完成保护对象、项目、交换根目录、时区、语言和本机代理。",
                       "Complete protected targets, project, exchange root, timezone, language and local proxy."),
            state: sharedScopeComplete ? .complete : .current
        )
        return [proxyItem, exitItem, scopeItem]
    }

    private func guideAction(for session: SandboxSession) -> SandboxPageAction? {
        guard sandbox.sharedConfiguration.isEnabled(session.configuration.target) else { return nil }
        if session.phase == .running || session.phase == .preparing || session.phase == .checking {
            return nil
        }
        if session.phase == .networkPaused { return .resumeNetwork }
        if session.phase == .ended { return .openWorkspace }
        if session.configuration.target == .claudeDesktop, !session.desktopIsolationSupported {
            return .desktopInstall
        }
        if session.configuration.target == .claudeCode, session.claudeCodeInstallation == nil {
            return .codeInstall
        }
        if !sharedScopeComplete { return .configureScope }
        if session.detectedProxy?.isLoopback == false { return .detectProxy }
        if session.configuration.target == .claudeDesktop,
           session.desktopAppRunningOutsideSandbox,
           !session.claudeRunning {
            return .desktopRunning
        }
        return .prepare
    }

    private func perform(_ action: SandboxPageAction, session: SandboxSession) {
        switch action {
        case .configureScope:
            showScopeSheet = true
        case .detectProxy:
            session.refreshDetectedProxy(alignIfNeeded: true)
        case .desktopInstall:
            if let url = URL(string: "https://claude.ai/download") {
                NSWorkspace.shared.open(url)
            }
        case .codeInstall:
            if let url = URL(string: "https://code.claude.com/docs/en/setup") {
                NSWorkspace.shared.open(url)
            }
        case .desktopRunning:
            session.refreshInstalledApplications()
        case .prepare:
            Task { await store.prepareSandbox(target: session.configuration.target) }
        case .resumeNetwork:
            Task { await sandbox.resumeNetwork(target: session.configuration.target) }
        case .openWorkspace:
            session.openWorkspace()
        }
    }

    private func displayPath(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let home = NSHomeDirectory()
        return trimmed.hasPrefix(home) ? "~" + trimmed.dropFirst(home.count) : trimmed
    }

    private func desktopInstallationDetail(_ installation: ClaudeDesktopInstallation) -> String {
        let version = installation.shortVersion.map { " · \($0)" } ?? ""
        return "\(installation.bundleIdentifier)\(version)"
    }

    private func targetStatusColor(_ session: SandboxSession, enabled: Bool) -> Color {
        guard enabled else { return .secondary }
        switch session.phase {
        case .running: return appStatusSuccess
        case .networkPaused: return appStatusWarning
        case .failed: return appStatusFailure
        case .preparing, .checking: return appAccent
        default: return .secondary
        }
    }

    private var webBrowserStatusColor: Color {
        switch sandbox.webBrowser.phase {
        case .running: return appStatusSuccess
        case .networkPaused, .launching: return appStatusWarning
        case .failed: return appStatusFailure
        case .stopped:
            if sandbox.webBrowser.discovering { return .secondary }
            return sandbox.webBrowser.installation == nil ? appStatusWarning : .secondary
        }
    }

    private var overviewStatusColor: Color {
        switch sandbox.phase {
        case .running: return appStatusSuccess
        case .networkPaused, .preparing, .checking: return appStatusWarning
        case .failed: return appStatusFailure
        default: return .secondary
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

    private func sandboxRemediation(for checkID: String) -> String {
        switch checkID {
        case "desktop-signature":
            return text("从 Anthropic 官方渠道安装并重新检测客户端。", "Install from Anthropic's official channel and detect the app again.")
        case "system-proxy-config", "relay-network":
            return text("开启代理客户端的本机 HTTP、SOCKS 或混合端口，再重新检测。",
                        "Enable the proxy app's local HTTP, SOCKS or mixed endpoint and detect again.")
        case "claude-relay":
            return text("确认代理客户端和节点可用，再重新创建会话。",
                        "Confirm the proxy app and node work, then create the session again.")
        case "claude-exit-match":
            return text("这是启动警告，不会阻止会话。若出口不符合预期，请先核对节点与固定出口。",
                        "This is a launch warning and does not block the session. If the exit is unexpected, review the node and fixed exit.")
        case "timezone", "session-locale":
            return text("选择有效的会话时区，然后重新创建会话。",
                        "Choose a valid session timezone and recreate the session.")
        case "workspace-write", "exchange-write", "original-write":
            return text("重新选择两个不重叠、可访问的普通文件夹。",
                        "Choose two separate accessible folders.")
        case "direct-network", "direct-dns", "direct-udp":
            return text("这项证明断网保护生效；若仍失败，请停止使用并查看运行记录。",
                        "This proves fail-closed networking. If it still fails, stop and inspect activity.")
        default:
            return text("重新创建会话再测一次；若仍失败，请查看运行记录。",
                        "Recreate the session once. If it still fails, inspect activity.")
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
        case .pending: return appStatusWarning
        case .running: return appAccent
        case .completed: return appStatusSuccess
        case .failed: return appStatusFailure
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

    private func chooseHandoffDestination(_ item: HandoffActionItem, session: SandboxSession) {
        let panel = NSSavePanel()
        panel.title = text("保存交付文件", "Save handoff file")
        panel.prompt = text("保存", "Save")
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.package.request.suggestedName
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        session.externalActions.export(item, to: destination)
        store.log(text("已提交宿主侧文件保存。", "Requested a host-side file save."))
    }

    private func choosePatchDestination(_ item: HandoffActionItem, session: SandboxSession) {
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

    private func chooseGitRepository(_ item: HandoffActionItem, session: SandboxSession) {
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

            file.export 由用户在宿主侧选择保存位置；git.applyPatch 的 payload 必须是 .patch 或 .diff。写入后停止外部操作并等待用户确认。
            """,
            """
            If this task needs an external operation, write the request only under $ISOLATION_EXCHANGE/.routekeeper-actions. Never request or output passwords, tokens, cookies, real account URLs or absolute local paths. Use one JSON manifest and one payload:

            {
              "schemaVersion": 1,
              "requestID": "generate a UUID",
              "kind": "file.export",
              "title": "Short title",
              "summary": "Describe the operation and included data",
              "payload": "result.md",
              "suggestedName": "result.md"
            }

            file.export asks the user for a host save location. git.applyPatch requires a .patch or .diff payload. After writing, stop external operations and wait for approval.
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
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
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
        return package.payloadBytes > prefix.count ? text + "\n\n[预览已截断]" : text
    }
}

private struct SandboxCardHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SandboxCardStatusHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SandboxCardDetailHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SandboxCardDetailPrimaryHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SandboxCardDetailSecondaryHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SandboxCardDetailActionsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SandboxCardGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum SandboxPageAction: Equatable {
    case configureScope
    case detectProxy
    case desktopInstall
    case codeInstall
    case desktopRunning
    case prepare
    case resumeNetwork
    case openWorkspace

    var title: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .configureScope: return en ? "Edit shared settings" : "编辑共享设置"
        case .detectProxy: return en ? "Detect again" : "重新检测"
        case .desktopInstall: return en ? "Get official app" : "获取官方客户端"
        case .codeInstall: return en ? "Get Claude Code" : "获取 Claude Code"
        case .desktopRunning: return en ? "Detect again" : "重新检测"
        case .prepare: return en ? "Create isolated session" : "创建隔离会话"
        case .resumeNetwork: return en ? "Restore network" : "恢复网络"
        case .openWorkspace: return en ? "Review workspace" : "查看工作副本"
        }
    }

    var tone: AppActionTone {
        switch self {
        case .prepare:
            return .primary
        case .resumeNetwork, .configureScope, .detectProxy,
             .desktopRunning:
            return .warning
        case .desktopInstall, .codeInstall:
            return .primary
        case .openWorkspace:
            return .neutral
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
        case .complete: return appStatusSuccess
        case .current: return .primary
        case .pending: return .secondary
        case .attention: return appStatusWarning
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

private struct SandboxReadinessItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let state: SandboxGuideStepState
}
