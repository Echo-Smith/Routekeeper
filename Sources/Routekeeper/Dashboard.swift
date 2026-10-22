import AppKit
import SwiftUI
import GuardCore

enum GuardPage: String, CaseIterable, Identifiable {
    case home, inspection, sandbox, networkProtection, authentication, activity, cleanup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return L10n.resolvedEnglish ? "Overview" : "概览"
        case .inspection: return L10n.resolvedEnglish ? "Network check" : "网络体检"
        case .sandbox: return L10n.resolvedEnglish ? "Sandbox" : "沙箱"
        case .networkProtection: return L10n.resolvedEnglish ? "Network protection" : "网络保护"
        case .authentication: return L10n.resolvedEnglish ? "Claude Code sign-in" : "Claude Code 登录凭证"
        case .activity: return L10n.resolvedEnglish ? "Activity" : "运行记录"
        case .cleanup: return L10n.resolvedEnglish ? "Cleanup" : "清理"
        }
    }
    var navigationTitle: String {
        switch self {
        case .authentication: return L10n.resolvedEnglish ? "Sign-in" : "登录凭证"
        default: return title
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .inspection: return "waveform.path.ecg.rectangle"
        case .sandbox: return "lock.shield"
        case .networkProtection: return "shield.lefthalf.filled"
        case .authentication: return "key"
        case .activity: return "clock.arrow.circlepath"
        case .cleanup: return "trash"
        }
    }

    static let primaryNavigation: [GuardPage] = [
        .home, .inspection, .sandbox, .networkProtection
    ]

    static let toolNavigation: [GuardPage] = [
        .authentication, .activity, .cleanup
    ]
}

struct Dashboard: View {
    @Bindable var store: GuardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: GuardPage = .home
    @State private var detailPath: [String] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sandboxSection: SandboxSection = .overview
    private func text(_ zh: String, _ en: String) -> String { L10n.resolvedEnglish ? en : zh }
    @AppStorage(L10n.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppTextScale.storageKey) private var textScaleRaw = AppTextScale.standard.rawValue
    @AppStorage("routekeeper.disclaimer-accepted-version") private var disclaimerAcceptedVersion = ""
    @State private var showDisclaimerGate = false
    @State private var confirmLocalDataInCleanup = false
    @State private var expandedCleanupGroups: Set<String> = []
    var statusColor: Color {
        if store.settings.experimentalSandboxEnabled {
            switch store.sandbox.phase {
            case .running: return appAccent
            case .networkPaused, .failed: return .orange
            default: return .secondary
            }
        }
        return store.policy.phase == .incident ? .orange : store.policy.phase == .armed ? appAccent : .secondary
    }
    private var pageHorizontalPadding: CGFloat { 22 }
    private var textScale: CGFloat {
        (AppTextScale(rawValue: textScaleRaw) ?? .standard).multiplier
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 228, max: 300)
        } detail: {
            NavigationStack(path: $detailPath) {
            ScrollView {
                pageBody
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 22)
                    .padding(.bottom, 26)
                    .frame(maxWidth: 1040, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .routekeeperScrollEdge()
            .id(navigationIdentity)
            .navigationDestination(for: String.self) { _ in
                AppSettingsView(store: store)
                    .navigationTitle(text("设置", "Settings"))
                    .navigationSubtitle("")
            }
            .navigationTitle(page.navigationTitle)
            .navigationSubtitle(currentSectionTitle ?? "")
            .routekeeperScaledNavigationTitle()
            .toolbar {
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .navigation) {
                        Text(page.navigationTitle)
                            .routekeeperFont(.title3, weight: .semibold)
                            .tracking(-0.2)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.leading, 8)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                if page == .sandbox || page == .networkProtection {
                    if #available(macOS 26.0, *) {
                        ToolbarSpacer(.flexible)
                    }
                    ToolbarItem(placement: .automatic) {
                        pageStatusPill
                    }
                }
            }
        }
        }
        .navigationSplitViewStyle(.balanced)
        .id(store.languageRevision)
        .preferredColorScheme(appearanceOverride)
        .onAppear {
            applyNavigationRequest()
            if disclaimerAcceptedVersion != DisclaimerDocument.currentVersion {
                showDisclaimerGate = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .routekeeperShowChecks)) { _ in
            applyNavigationRequest()
        }
        .sheet(isPresented: $showDisclaimerGate) {
            DisclaimerConsentSheet(
                onAgree: {
                    disclaimerAcceptedVersion = DisclaimerDocument.currentVersion
                    showDisclaimerGate = false
                },
                onQuit: {
                    showDisclaimerGate = false
                    confirmQuit(store)
                }
            )
            .interactiveDismissDisabled()
        }

    }

    var appearanceOverride: ColorScheme? {
        switch AppAppearance(rawValue: appearanceRaw) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    private func applyNavigationRequest() {
        if AppNavigationRequest.consumeSettingsRequest() {
            detailPath = ["settings"]
            return
        }
        if let requested = AppNavigationRequest.consumePendingPage() {
            selectPage(requested)
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .modifier(BrandGlassModifier())
                    .accessibilityHidden(true)
                Text(L("app.name"))
                    .routekeeperFont(.title3, weight: .bold)
                    .tracking(-0.25)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("app.name"))
            .accessibilityValue(store.title)

            List(selection: sidebarSelection) {
                Section(text("主要", "Main")) {
                    ForEach(GuardPage.primaryNavigation) { item in
                        sidebarPageRow(item)
                    }
                }
                Section(text("工具", "Tools")) {
                    ForEach(GuardPage.toolNavigation) { item in
                        sidebarPageRow(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(.clear)
            .background(SidebarTableAppearance())

            Divider()
                .padding(.horizontal, 12)

            Button {
                detailPath = ["settings"]
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text(text("设置", "Settings"))
                        .routekeeperFont(.callout)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nav-settings")
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func sidebarPageRow(_ item: GuardPage) -> some View {
        Label {
            Text(item.navigationTitle)
                .routekeeperFont(.callout)
        } icon: {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 18, alignment: .center)
        }
        .foregroundStyle(.primary)
        .tint(Color(nsColor: .labelColor))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(detailPath.isEmpty && page == item ? Color.primary.opacity(0.10) : Color.clear)
                .padding(.horizontal, 10)
                .padding(.vertical, 1)
        )
        .tag(item)
        .accessibilityIdentifier("nav-\(item.rawValue)")
        .accessibilityLabel(item.title)
        .help(item.title)
    }

    private var sidebarSelection: Binding<GuardPage?> {
        Binding(
            get: { detailPath.isEmpty ? page : nil },
            set: { newValue in
                guard let newValue else { return }
                if newValue == page {
                    detailPath.removeAll()
                } else {
                    selectPage(newValue)
                }
            }
        )
    }

    private var pageStatusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(capsuleText)
                .routekeeperFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text("当前状态", "Current status"))
        .accessibilityValue(capsuleText)
        .accessibilityIdentifier("page-status")
    }

    private var currentSectionTitle: String? {
        switch page {
        case .sandbox:
            return sandboxSection == .overview ? nil : sandboxSection.title
        case .home, .inspection, .networkProtection, .authentication, .activity, .cleanup: return nil
        }
    }

    private var navigationIdentity: String {
        switch page {
        case .sandbox: return "sandbox-\(sandboxSection.rawValue)"
        case .home, .inspection, .networkProtection, .authentication, .activity, .cleanup: return page.rawValue
        }
    }

    private func selectPage(_ newPage: GuardPage) {
        detailPath.removeAll()
        if newPage == .sandbox {
            sandboxSection = .overview
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            page = newPage
        }
    }

    var capsuleText: String {
        if store.settings.experimentalSandboxEnabled {
            return store.sandbox.statusTitle
        }
        if store.checking { return L("status.checking") }
        if store.policy.phase == .incident { return L("status.incident") }
        if store.monitoring { return L("status.armed") }
        if store.settings.gatewayProtectionMode != .off {
            switch store.gatewayVerification.status(for: store.settings.gatewayProtectionMode) {
            case .verified:
                break
            case .needsNodeFailureTest: return text("待测节点断开", "Node test pending")
            case .needsClientExitTest: return text("待测代理退出", "Client test pending")
            case .needsRecovery: return text("待恢复代理", "Restore proxy")
            case .failed: return text("代理网关未通过", "Gateway failed")
            case .expired: return text("网关证据已过期", "Gateway evidence expired")
            case .unverified: return text("代理网关待检查", "Gateway not checked")
            }
        }
        guard let snapshot = store.snapshot else { return L("capsule.noCheck") }
        guard let family = snapshot.proxyIP.map(IPFamily.of),
              let target = store.settings.target(for: family) else { return L("capsule.noTarget") }
        let match = snapshot.proxyIP == snapshot.tunnelIP && snapshot.proxyIP == target
        return "\(L("capsule.last")) \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened)) · \(match ? L("capsule.match") : L("capsule.mismatch"))"
    }

    @ViewBuilder var pageBody: some View {
        switch page {
        case .home: homePage
        case .inspection:
            if store.settings.experimentalSandboxEnabled {
                SandboxPage(store: store, mode: .networkCheck)
            } else {
                InspectionPage(
                    store: store,
                    audit: store.egressAudit,
                    onOpenNetworkSettings: {
                        selectPage(.networkProtection)
                    }
                )
            }
        case .sandbox:
            SandboxPage(store: store, mode: .management, section: $sandboxSection)
        case .networkProtection:
            NetworkProtectionPage(store: store)
        case .authentication:
            AuthenticationPage(
                controller: store.authentication,
                launchAction: { store.launchFromAuthentication() }
            )
        case .activity: eventsPage
        case .cleanup: cleanupPage
        }
    }

    var homePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.settings.experimentalSandboxEnabled {
                homeSandboxOverview
            } else {
                homeStatusOverview
            }
            homeDetailWorkspace
        }
    }

    private var homeSandboxOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: store.sandbox.statusSymbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(statusColor)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.sandbox.statusTitle)
                        .routekeeperFont(.title2, weight: .semibold)
                        .tracking(-0.3)
                    Text(store.sandbox.message)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(text("实验性", "Experimental"))
                    .routekeeperFont(.caption, weight: .medium)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 18) {
                Label(
                    store.sandbox.networkEnabled ? text("中继网络已开启", "Relay network on") : text("网络已关闭", "Network off"),
                    systemImage: store.sandbox.networkEnabled ? "network" : "wifi.slash"
                )
                .foregroundStyle(store.sandbox.networkEnabled ? Color.secondary : Color.orange)
                Label(
                    store.sandbox.claudeRunning ? text("Claude 正在运行", "Claude running") : text("Claude 未运行", "Claude not running"),
                    systemImage: "terminal"
                )
                .foregroundStyle(.secondary)
            }
            .routekeeperFont(.callout, weight: .medium)

            AppHairline()

            HStack {
                Text(text("普通网络监控已暂停", "Ordinary monitoring is paused"))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    selectPage(.sandbox)
                } label: {
                    Label(text("打开沙箱", "Open sandbox"), systemImage: "lock.shield")
                }
                .routekeeperProminentButton()
                .accessibilityIdentifier("home-open-sandbox")
            }
        }
        .padding(20)
        .appSurface(.primary)
    }

    private var homeStatusOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: store.symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(statusColor)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(headline)
                            .routekeeperFont(.title2, weight: .semibold)
                            .tracking(-0.3)
                        if showsInlineCheckAction {
                            Button(action: homePrimaryAction) {
                                Label(homePrimaryTitle, systemImage: homePrimarySymbol)
                            }
                            .routekeeperProminentButton()
                            .controlSize(.regular)
                            .disabled(store.checking)
                            .accessibilityIdentifier("home-inline-check")
                        }
                    }
                    Text(store.notice.isEmpty ? L("overview.unmonitored.sub") : store.notice)
                        .routekeeperFont(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if let snapshot = store.snapshot {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(homePassedChecks)/\(snapshot.checks.count)")
                            .routekeeperFont(.title2, weight: .semibold, monospacedDigit: true)
                            .fontDesign(.rounded)
                            .monospacedDigit()
                        Text(homeCheckSummary)
                            .routekeeperFont(.caption2)
                            .foregroundStyle(homeAttentionChecks > 0 ? Color.orange : Color.secondary)
                    }
                }
            }

            VStack(spacing: 0) {
                homeSummaryRow(id: "target", title: L("overview.tile.target"), symbol: "target")
                AppHairline()
                homeSummaryRow(id: "proxy-exit", title: L("overview.tile.proxy"), symbol: "network")
                AppHairline()
                homeSummaryRow(id: "tun", title: L("overview.tile.tun"), symbol: "wifi.router")
            }

            if store.policy.phase == .incident {
                Button { page = .inspection } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(store.policy.reason).routekeeperFont(.callout).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").routekeeperFont(.caption).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.borderless)
            }

            AppHairline()

            HStack(spacing: 12) {
                if let snapshot = store.snapshot {
                    Text(text("最近体检 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))",
                              "Last checked \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))"))
                        .routekeeperFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !showsInlineCheckAction {
                    Button(action: homePrimaryAction) {
                        Label(homePrimaryTitle, systemImage: homePrimarySymbol)
                    }
                    .routekeeperProminentButton()
                    .controlSize(.large)
                    .disabled(store.checking)
                    .accessibilityIdentifier(store.monitoring ? "stop-monitor" : "home-primary")
                }
            }
        }
        .padding(20)
        .appSurface(.primary)
    }

    private var homeDetailWorkspace: some View {
        HStack(alignment: .top, spacing: 16) {
            homeProtectionSection
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .appSurface(.primary)

            Group {
                if store.settings.gatewayProtectionMode != .off {
                    homeGatewaySection
                } else {
                    homeEgressSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .appSurface(.primary)
        }
    }

    private var homeGatewaySection: some View {
        let mode = store.settings.gatewayProtectionMode
        let status = store.gatewayVerification.status(for: mode)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                AppSectionHeading(
                    title: text("代理网关", "Proxy gateway"),
                    subtitle: text(
                        "检查代理可用、节点断开失败关闭，以及代理退出后不会回落直连。",
                        "Check reachability and fail-closed behavior without a node or proxy client."
                    )
                )
                Spacer(minLength: 8)
                Button(text("打开检查", "Open check")) {
                    selectPage(.inspection)
                }
                .buttonStyle(.borderless)
                .routekeeperFont(.callout, weight: .medium)
                .foregroundStyle(appAccent)
                .accessibilityIdentifier("home-gateway-open-check")
            }

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: homeGatewaySymbol(status))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(homeGatewayColor(status))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(homeGatewayTitle(status, mode: mode))
                        .routekeeperFont(.callout, weight: .semibold)
                    Text(homeGatewayModeTitle(mode))
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var homeProtectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                AppSectionHeading(
                    title: text("Claude 保护范围", "Claude protection"),
                    subtitle: text("应用是否纳入监控，以及发现异常后的处理方式。",
                                   "Which Claude apps are monitored and what happens after an incident.")
                )
                Spacer(minLength: 8)
                Button {
                    selectPage(.networkProtection)
                } label: {
                    Label(text("管理保护范围", "Manage protection"), systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .routekeeperFont(.callout, weight: .medium)
                .foregroundStyle(appAccent)
                .accessibilityIdentifier("home-manage-protection")
            }

            homeProtectionRow(kind: .desktop)
            AppHairline()
            homeProtectionRow(kind: .code)
            AppHairline()
            HStack(spacing: 10) {
                Label(text("发现异常时", "On incident"), systemImage: "bell.badge")
                    .routekeeperFont(.callout)
                Spacer()
                Text(store.settings.action == .notify
                     ? text("仅提醒", "Notify only")
                     : text("请求退出所选进程", "Request selected exits"))
                    .routekeeperFont(.callout, weight: .medium)
                    .foregroundStyle(store.settings.action == .notify ? Color.secondary : Color.orange)
            }
            AppHairline()
            HStack(spacing: 10) {
                Image(systemName: store.events.contains(where: \.isAttention)
                      ? "exclamationmark.triangle.fill"
                      : "checkmark.circle")
                    .foregroundStyle(store.events.contains(where: \.isAttention) ? Color.orange : Color.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text("最近异常", "Latest incident"))
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(homeLatestAttentionText)
                        .routekeeperFont(.callout)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let incident = store.events.first(where: \.isAttention) {
                    Text(homeRelativeTime(incident.time))
                        .routekeeperFont(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func homeProtectionRow(kind: ProtectedKind) -> some View {
        let enabled = store.settings.includes(kind)
        let installed: Bool = {
            if kind == .desktop {
                return store.desktopInstalled
            }
            return store.codeInstalled
        }()
        let running = store.snapshot?.processes.filter { $0.kind == kind }.count ?? 0
        let status: (title: String, color: Color) = {
            guard enabled else { return (text("未保护", "Not protected"), .secondary) }
            guard installed else { return (text("未发现安装", "Not installed"), .orange) }
            if running > 0 {
                return (text("\(running) 个进程", "\(running) running"), Color.secondary)
            }
            return (text("已启用 · 等待启动", "On · waiting to launch"), .secondary)
        }()

        HStack(spacing: 12) {
            Image(systemName: kind == .desktop ? "macwindow" : "terminal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .desktop ? "Claude Desktop" : "Claude Code")
                    .routekeeperFont(.callout, weight: .medium)
                Text(enabled
                     ? text("已纳入异常检测", "Included in incident checks")
                     : text("不会处理该应用的异常", "Excluded from incident handling"))
                    .routekeeperFont(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status.title)
                .routekeeperFont(.caption, weight: .medium)
                .foregroundStyle(status.color)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.title), \(kind == .desktop ? "Claude Desktop" : "Claude Code")")
    }

    private var homeEgressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeading(
            title: text("最近出口体检", "Latest egress check"),
            subtitle: text("出口一致性、IPv6、服务可达性与自动体检节奏。",
                           "Exit consistency, IPv6, service reachability and automatic-check timing.")
            )

            if let report = store.egressAudit.report {
                homeSignalRow(
                    title: text("体检结论", "Assessment"),
                    value: homeAssessmentTitle(report.assessment.level),
                    symbol: homeAssessmentSymbol(report.assessment.level),
                    color: homeAssessmentColor(report.assessment.level)
                )
                AppHairline()
                homeSignalRow(
                    title: text("主出口", "Primary exit"),
                    value: report.primaryIP ?? text("未取得", "Not observed"),
                    symbol: "network",
                    color: report.primaryIP == nil ? .orange : .primary,
                    monospaced: report.primaryIP != nil
                )
                AppHairline()
                homeSignalRow(
                    title: "IPv6",
                    value: homeIPv6Title(report.ipv6?.state),
                    symbol: homeIPv6Symbol(report.ipv6?.state),
                    color: homeIPv6Color(report.ipv6?.state)
                )
                AppHairline()
                homeSignalRow(
                    title: text("Claude 服务", "Claude services"),
                    value: text(
                        "\(report.services.filter(\.reachedTLS).count)/\(report.services.count) 项可达",
                        "\(report.services.filter(\.reachedTLS).count)/\(report.services.count) reachable"
                    ),
                    symbol: "checkmark.icloud",
                    color: report.services.allSatisfy(\.reachedTLS) ? .secondary : .orange
                )
                if let drift = store.egressAudit.drift {
                    Label(text("出口已从 \(drift.previousIP) 变化为 \(drift.currentIP)",
                               "Exit changed from \(drift.previousIP) to \(drift.currentIP)"),
                          systemImage: "arrow.triangle.swap")
                        .routekeeperFont(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(homeNextAuditText)
                    .routekeeperFont(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(text("最近 \(report.auditedAt.formatted(date: .abbreviated, time: .shortened))",
                              "Last \(report.auditedAt.formatted(date: .abbreviated, time: .shortened))"))
                        .routekeeperFont(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button(text("查看检查详情", "View evidence")) { selectPage(.inspection) }
                        .buttonStyle(.borderless)
                        .routekeeperFont(.callout, weight: .medium)
                        .foregroundStyle(appAccent)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .routekeeperFont(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text("还没有出口体检结果", "No egress report yet"))
                            .routekeeperFont(.callout, weight: .semibold)
                        Text(text("完成体检后可在这里查看出口一致性、IPv6 路径与服务可达性。",
                                  "Run a check to see exit consistency, IPv6 routing and service reachability here."))
                            .routekeeperFont(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(homeNextAuditText)
                    .routekeeperFont(.caption2)
                    .foregroundStyle(.tertiary)
                Button {
                    selectPage(.inspection)
                } label: {
                    Label(text("开始出口体检", "Run egress check"),
                          systemImage: "arrow.up.right")
                }
                .routekeeperSecondaryButton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func homeSignalRow(
        title: String,
        value: String,
        symbol: String,
        color: Color,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(title).routekeeperFont(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .routekeeperFont(.callout, design: monospaced ? .monospaced : .default)
                .foregroundStyle(color)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private var homePassedChecks: Int {
        store.snapshot?.checks.filter { $0.level == .passed }.count ?? 0
    }

    private var homeAttentionChecks: Int {
        store.snapshot?.checks.filter(\.needsAttention).count ?? 0
    }

    private var homeCheckSummary: String {
        guard homeAttentionChecks > 0 else { return text("项检查通过", "checks passed") }
        return text("\(homeAttentionChecks) 项待处理", "\(homeAttentionChecks) need attention")
    }

    private var homeLatestAttentionText: String {
        store.events.first(where: \.isAttention)?.message
            ?? text("近期没有记录到需要处理的异常", "No incident requiring attention in recent history")
    }

    private var homeNextAuditText: String {
        guard store.automaticEgressAuditEnabled else {
            return text("自动出口体检已关闭", "Automatic egress checks are off")
        }
        let interval = store.automaticEgressAuditIntervalMinutes
        guard let report = store.egressAudit.report else {
            return text("自动出口体检每 \(interval) 分钟运行",
                        "Automatic egress checks run every \(interval) minutes")
        }
        let next = report.auditedAt.addingTimeInterval(TimeInterval(interval * 60))
        if next > Date() {
            return text("自动体检每 \(interval) 分钟 · 下次约 \(next.formatted(date: .omitted, time: .shortened))",
                        "Every \(interval) min · next around \(next.formatted(date: .omitted, time: .shortened))")
        }
        return text("自动体检每 \(interval) 分钟 · 等待下一次调度",
                    "Every \(interval) min · waiting for the next run")
    }

    private func homeRelativeTime(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return text("刚刚", "just now") }
        if seconds < 3_600 { return text("\(Int(seconds / 60)) 分钟前", "\(Int(seconds / 60)) min ago") }
        if seconds < 86_400 { return text("\(Int(seconds / 3_600)) 小时前", "\(Int(seconds / 3_600)) hr ago") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func homeAssessmentTitle(_ level: EgressAssessmentLevel) -> String {
        switch level {
        case .clear: return text("未发现明显不一致", "No obvious inconsistency")
        case .attention: return text("有项目需要检查", "Needs attention")
        case .insufficient: return text("结果不足，暂时无法判断", "Insufficient evidence")
        }
    }

    private func homeAssessmentSymbol(_ level: EgressAssessmentLevel) -> String {
        switch level {
        case .clear: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.shield.fill"
        case .insufficient: return "questionmark.circle.fill"
        }
    }

    private func homeAssessmentColor(_ level: EgressAssessmentLevel) -> Color {
        switch level {
        case .clear: return .secondary
        case .attention: return .orange
        case .insufficient: return .secondary
        }
    }

    private func homeIPv6Title(_ state: IPv6ExposureState?) -> String {
        switch state {
        case .disabled: return text("未启用", "Not enabled")
        case .noClaudePath: return text("未观察到直连路径", "No direct path observed")
        case .tunneled: return text("经 TUN，出口一致", "Tunneled, exits match")
        case .tunnelUnconfirmed: return text("经 TUN，出口未确认", "Tunneled, unconfirmed")
        case .tunnelExitMismatch: return text("系统与代理出口不一致", "Exit mismatch")
        case .directExposure: return text("发现物理网络直连", "Physical path detected")
        case .unknown: return text("路径无法确认", "Path uncertain")
        case nil: return text("尚未取得结果", "No evidence")
        }
    }

    private func homeIPv6Symbol(_ state: IPv6ExposureState?) -> String {
        switch state {
        case .disabled, .tunneled: return "checkmark.shield.fill"
        case .noClaudePath: return "info.circle"
        case .tunnelUnconfirmed, .unknown, nil: return "questionmark.circle.fill"
        case .tunnelExitMismatch, .directExposure: return "exclamationmark.shield.fill"
        }
    }

    private func homeIPv6Color(_ state: IPv6ExposureState?) -> Color {
        switch state {
        case .disabled, .tunneled: return .secondary
        case .noClaudePath: return .secondary
        case .tunnelUnconfirmed, .tunnelExitMismatch, .directExposure, .unknown, nil: return .orange
        }
    }

    var homePrimaryTitle: String {
        if store.monitoring { return L("action.stopMonitor") }
        if store.snapshot?.ready == true && canStartMonitoring { return L("action.startMonitor") }
        return text("立即体检", "Check now")
    }

    var homePrimarySymbol: String {
        if store.monitoring { return "stop.fill" }
        if store.snapshot?.ready == true && canStartMonitoring { return "shield.fill" }
        return "waveform.path.ecg.rectangle"
    }

    func homePrimaryAction() {
        if store.monitoring {
            store.stop()
        } else if store.snapshot?.ready == true && canStartMonitoring {
            Task { await store.start() }
        } else {
            page = .inspection
        }
    }

    var headline: String {
        store.policy.phase == .incident ? L("overview.incident") : store.monitoring ? L("overview.armed") : L("overview.unmonitored")
    }

    var canStartMonitoring: Bool {
        !store.checking && !store.monitoring && store.settings.hasSelection
            && (store.settings.target(for: .ipv4) != nil || store.settings.target(for: .ipv6) != nil)
    }

    var showsInlineCheckAction: Bool {
        !store.monitoring && !(store.snapshot?.ready == true && canStartMonitoring)
    }

    func homeSummaryRow(id: String, title: String, symbol: String) -> some View {
        let check = store.snapshot?.checks.first { $0.id == id }
        let color: Color = check?.level == .passed ? .primary : check?.level == .failed ? .orange : .secondary
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title).routekeeperFont(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(check?.detail ?? L("target.notChecked"))
                .routekeeperFont(.callout, design: .monospaced).foregroundStyle(color)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(check?.detail ?? L("target.notChecked"))")
    }

    private func homeGatewayTitle(
        _ status: GatewayVerificationStatus,
        mode: GatewayProtectionMode
    ) -> String {
        if mode == .off {
            return text("未启用", "Off")
        }
        switch status {
        case .unverified: return text("尚未验证", "Not verified")
        case .needsNodeFailureTest: return text("待测节点断开", "Node-failure test pending")
        case .needsClientExitTest: return text("待测代理退出", "Client-exit test pending")
        case .needsRecovery: return text("待恢复代理并复测", "Restore proxy and finish")
        case .verified: return text("当前网关已验证", "Current gateway verified")
        case .failed: return text("验证未通过", "Verification failed")
        case .expired: return text("证据已过期", "Evidence expired")
        }
    }

    private func homeGatewaySymbol(_ status: GatewayVerificationStatus) -> String {
        switch status {
        case .verified: return "checkmark.shield.fill"
        case .failed, .expired: return "exclamationmark.shield.fill"
        case .needsNodeFailureTest, .needsClientExitTest, .needsRecovery: return "shield.lefthalf.filled"
        case .unverified: return "shield"
        }
    }

    private func homeGatewayColor(_ status: GatewayVerificationStatus) -> Color {
        switch status {
        case .verified: return appAccent
        case .failed, .expired: return .orange
        case .unverified, .needsNodeFailureTest, .needsClientExitTest, .needsRecovery: return .secondary
        }
    }

    private func homeGatewayModeTitle(_ mode: GatewayProtectionMode) -> String {
        switch mode {
        case .off: return text("未选择保护方式", "No protection mode selected")
        case .splitTraffic: return text("分流保护", "Split routing")
        case .claudeOnly: return text("仅限制 Claude", "Claude only")
        }
    }

    var eventsPage: some View {
        GuardCard(title: L("card.events"), subtitle: L("events.sub")) {
            if store.events.isEmpty {
                Text(L("events.empty")).foregroundStyle(.secondary).padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.events) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(event.time.formatted(date: .omitted, time: .standard))
                                .routekeeperFont(.caption, design: .monospaced).foregroundStyle(.secondary)
                            .frame(width: 70 * textScale, alignment: .leading)
                            if event.isAttention {
                                Label(text("需注意", "Attention"), systemImage: "exclamationmark.triangle.fill")
                                    .routekeeperFont(.caption, weight: .semibold).foregroundStyle(.orange)
                            }
                            Text(event.message).routekeeperFont(.callout).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 5)
                        if event.id != store.events.last?.id { Divider() }
                    }
                }
            }
        }
    }

    var cleanupPage: some View {
        VStack(spacing: 16) {
            cleanupSummaryCard

            if store.cleanupPlan == nil {
                cleanupScopePreviewCard
            } else {
                cleanupSelectionCard
                cleanupLocalDataCard
            }
            cleanupPolicyCard
        }
        .alert(
            text("把本地信息加入清理？", "Include local data in cleanup?"),
            isPresented: $confirmLocalDataInCleanup
        ) {
            Button(text("取消", "Cancel"), role: .cancel) {
                store.cleanupIncludesLocalData = false
            }
            Button(text("加入清理", "Include"), role: .destructive) {
                store.cleanupIncludesLocalData = true
            }
        } message: {
            Text(text(
                "本地信息包括 Routekeeper 设置、运行记录、报告、登录凭证、沙箱副本和系统过滤配置。它与普通缓存不同，无法从废纸篓恢复。",
                "Local data includes Routekeeper settings, run history, reports, the saved credential, sandbox copies and system-filter configuration. Unlike regular caches, it cannot be restored from Trash."
            ))
        }
        .onChange(of: store.cleanupPlanRevision) {
            guard let targets = store.cleanupPlan?.targets else { return }
            let groups = CleanupScope.allCases.compactMap { scope -> (String, Int64)? in
                let bytes = targets
                    .filter { $0.scope == scope && $0.exists && $0.fileCount > 0 && $0.isSelectable }
                    .reduce(Int64(0)) { $0 + $1.sizeBytes }
                return bytes > 0 ? (scope.rawValue, bytes) : nil
            }
            expandedCleanupGroups = groups.max(by: { $0.1 < $1.1 }).map { [$0.0] } ?? []
        }
    }

    private var cleanupSummaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(appAccent.opacity(0.09))
                    Image(systemName: cleanupSummarySymbol)
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(appAccent)
                }
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cleanupSummaryTitle)
                        .routekeeperFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                    if store.cleanupPlan == nil {
                        Text(store.cleanupBusy
                             ? text("正在统计可清理空间", "Calculating cleanable space")
                             : text("扫描后显示可清理空间", "Cleanable space appears after scanning"))
                            .routekeeperFont(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(cleanupAvailableSize)
                                .routekeeperFont(.largeTitle, weight: .semibold)
                                .fontDesign(.rounded)
                                .monospacedDigit()
                            Text(text("可清理", "cleanable"))
                                .routekeeperFont(.title3, weight: .medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if store.cleanupPlan != nil {
                        HStack(spacing: 12) {
                            Label(cleanupSelectedSummary, systemImage: "checkmark.circle")
                            if (store.cleanupPlan?.blockedCount ?? 0) > 0 {
                                Label(
                                    text(
                                        "\(store.cleanupPlan?.blockedCount ?? 0) 项受保护",
                                        "\(store.cleanupPlan?.blockedCount ?? 0) protected"
                                    ),
                                    systemImage: "lock.fill"
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    if store.cleanupBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    }
                    if store.cleanupPlan != nil {
                        Button(text("重新扫描", "Scan again")) {
                            store.refreshCleanup()
                        }
                        .buttonStyle(.borderless)
                        .routekeeperFont(.callout)
                        .disabled(store.cleanupBusy)
                    }
                    Button {
                        if store.cleanupPlan == nil {
                            store.refreshCleanup()
                        } else {
                            store.runCleanup()
                        }
                    } label: {
                        Label(cleanupPrimaryTitle, systemImage: cleanupPrimarySymbol)
                    }
                    .routekeeperProminentButton()
                    .tint(store.cleanupIncludesLocalData ? .red : appAccent)
                    .disabled(!cleanupPrimaryEnabled)
                    .accessibilityIdentifier(
                        store.cleanupPlan == nil ? "cleanup-open" : "cleanup-confirm-run"
                    )
                }
            }

            if store.cleanupPlan != nil {
                AppHairline()
                HStack(spacing: 12) {
                    Button(text("全选可清理", "Select cleanable")) {
                        store.selectAllCleanupTargets()
                    }
                    .buttonStyle(.borderless)
                    .routekeeperFont(.caption)
                    Button(text("清除", "Clear")) {
                        store.cleanupSelection.removeAll()
                        store.cleanupIncludesLocalData = false
                    }
                    .buttonStyle(.borderless)
                    .routekeeperFont(.caption)
                    Spacer()
                }
            }

            if !store.cleanupResult.isEmpty {
                Label(store.cleanupResult, systemImage: "checkmark.circle")
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .cardSurface(corner: 22)
    }

    private var cleanupScopePreviewCard: some View {
        GuardCard(
            title: text("扫描范围", "Scan scope")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    text("Claude Desktop 与 Claude Code 的可再生成缓存、临时文件和运行日志",
                         "Regenerable caches, temporary files and runtime logs from Claude Desktop and Claude Code"),
                    systemImage: "macwindow"
                )
                Label(
                    text("Claude Science 与 Routekeeper 沙箱中的缓存、日志和临时副本",
                         "Caches, logs and temporary copies from Claude Science and Routekeeper sandboxes"),
                    systemImage: "shippingbox"
                )
                Label(
                    text("带 Routekeeper 归属标记的会话和持久登录 profile 临时数据",
                         "Session and persistent-profile temporary data carrying a Routekeeper ownership marker"),
                    systemImage: "checkmark.seal"
                )
            }
            .routekeeperFont(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cleanupPolicyCard: some View {
        Label(
            text(
                "普通清理只处理白名单内的可再生成缓存、临时文件和日志；不会处理对话、项目、Cookie、账户或设备标识。",
                "Regular cleanup only handles allowlisted regenerable caches, temporary files and logs. Conversations, projects, cookies, accounts and device identifiers are excluded."
            ),
            systemImage: "checkmark.shield"
        )
        .routekeeperFont(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    private var cleanupSelectionCard: some View {
        GuardCard(
            title: text("清理范围", "Cleanup scope"),
            subtitle: text("按来源分组；安全缓存默认选中，可展开逐项调整。",
                           "Grouped by source; safe caches are selected by default and can be adjusted individually.")
        ) {
            if store.cleanupCandidates.isEmpty {
                Label(
                    text("没有发现可清理的缓存或日志", "No cleanable caches or logs found"),
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(cleanupGroupScopes, id: \.rawValue) { scope in
                    cleanupGroupView(scope)
                }

                if !(store.cleanupPlan?.warnings.isEmpty ?? true) {
                    Label(
                        text(
                            "部分目录因归属标记、符号链接或进程状态被保护，未参与清理。",
                            "Some directories were protected because of ownership, symbolic links or process state."
                        ),
                        systemImage: "info.circle"
                    )
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(store.cleanupBusy)
    }

    private var cleanupLocalDataCard: some View {
        GuardCard(
            title: text("Routekeeper 本地信息", "Routekeeper local data"),
            subtitle: text("默认不选择。", "Off by default.")
        ) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(store.cleanupIncludesLocalData ? Color.orange : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        (store.cleanupIncludesLocalData ? Color.orange : Color.secondary).opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(text("清除设置、记录、凭证与沙箱副本",
                              "Clear settings, history, credentials and sandbox copies"))
                        .routekeeperFont(.callout, weight: .medium)
                    Text(text(
                        "不可恢复，也不会进入废纸篓。",
                        "This cannot be undone or restored from Trash."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: Binding(
                    get: { store.cleanupIncludesLocalData },
                    set: { selected in
                        if selected {
                            confirmLocalDataInCleanup = true
                        } else {
                            store.cleanupIncludesLocalData = false
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(text("清空 Routekeeper 本地信息", "Clear Routekeeper local data"))
            }
        }
        .disabled(store.cleanupBusy)
    }

    private func cleanupGroupView(_ scope: CleanupScope) -> some View {
        let targets = cleanupTargets(for: scope)
        let selectable = targets.filter(\.isSelectable)
        let selectedCount = selectable.filter { store.cleanupSelection.contains($0.id) }.count
        let selectedBytes = selectable
            .filter { store.cleanupSelection.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.sizeBytes }
        let totalBytes = targets.reduce(Int64(0)) { $0 + $1.sizeBytes }

        return DisclosureGroup(isExpanded: cleanupGroupExpandedBinding(scope.rawValue)) {
            VStack(spacing: 0) {
                HStack {
                    Toggle(
                        text("全选本组", "Select group"),
                        isOn: cleanupGroupSelectionBinding(targets)
                    )
                    .toggleStyle(.checkbox)
                    .routekeeperFont(.caption, weight: .medium)
                    .disabled(selectable.isEmpty)
                    Spacer()
                    Text(text(
                        "\(selectedCount)/\(selectable.count) 项已选",
                        "\(selectedCount)/\(selectable.count) selected"
                    ))
                    .routekeeperFont(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 7)

                ForEach(targets) { target in
                    cleanupTargetRow(target)
                    if target.id != targets.last?.id { Divider() }
                }
            }
            .padding(.leading, 4)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: cleanupScopeSymbol(scope))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        appAccent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(cleanupScopeTitle(scope))
                        .routekeeperFont(.callout, weight: .semibold)
                    Text(text(
                        "\(selectable.count) 项可清理",
                        "\(selectable.count) cleanable"
                    ))
                    .routekeeperFont(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(text(
                        "共 \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))",
                        "\(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) total"
                    ))
                    .routekeeperFont(.caption, monospacedDigit: true)
                    Text(selectedBytes > 0
                         ? text(
                            "已选 \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))",
                            "\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)) selected"
                         )
                         : text("未选择", "Nothing selected"))
                        .routekeeperFont(.caption2, monospacedDigit: true)
                        .foregroundStyle(selectedBytes > 0 ? appAccent : Color.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func cleanupGroupExpandedBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expandedCleanupGroups.contains(key) },
            set: { expanded in
                if expanded {
                    expandedCleanupGroups.insert(key)
                } else {
                    expandedCleanupGroups.remove(key)
                }
            }
        )
    }

    private func cleanupGroupSelectionBinding(_ targets: [CleanupTarget]) -> Binding<Bool> {
        let selectableIDs = Set(targets.filter(\.isSelectable).map(\.id))
        return Binding(
            get: {
                !selectableIDs.isEmpty
                    && selectableIDs.allSatisfy { store.cleanupSelection.contains($0) }
            },
            set: { selected in
                var next = store.cleanupSelection
                if selected {
                    next.formUnion(selectableIDs)
                } else {
                    next.subtract(selectableIDs)
                }
                store.cleanupSelection = next
            }
        )
    }

    private var cleanupOperationsBusy: Bool {
        store.checking || store.capture.busy || store.sandbox.busy
            || store.networkFilter.busy || store.gatewayVerification.busy
            || store.egressAudit.busy
    }

    private var cleanupCanRun: Bool {
        guard !store.cleanupBusy else { return false }
        guard !store.selectedCleanupTargets.isEmpty || store.cleanupIncludesLocalData else {
            return false
        }
        if store.cleanupIncludesLocalData, cleanupOperationsBusy { return false }
        return true
    }

    private var cleanupSummaryTitle: String {
        if store.cleanupPlan == nil {
            return text("清理缓存", "Cache cleanup")
        }
        if (store.cleanupPlan?.selectableCount ?? 0) == 0 {
            return text("本次没有发现可清理缓存", "No cleanable caches found")
        }
        return text("发现可清理缓存", "Cleanable caches found")
    }

    private var cleanupSummarySymbol: String {
        if store.cleanupBusy { return "arrow.triangle.2.circlepath" }
        if store.cleanupPlan == nil { return "magnifyingglass" }
        return (store.cleanupPlan?.selectableCount ?? 0) == 0 ? "checkmark.circle" : "sparkles"
    }

    private var cleanupAvailableSize: String {
        guard let plan = store.cleanupPlan else { return "" }
        return ByteCountFormatter.string(fromByteCount: plan.selectableBytes, countStyle: .file)
    }

    private var cleanupSelectedSummary: String {
        let count = store.selectedCleanupTargets.count
        let size = ByteCountFormatter.string(
            fromByteCount: store.selectedCleanupBytes,
            countStyle: .file
        )
        guard store.cleanupPlan != nil else { return "" }
        if store.cleanupIncludesLocalData {
            return count == 0
                ? text("另含 Routekeeper 本地信息", "Routekeeper local data included")
                : text("已选 \(count) 项 · \(size)，另含本地信息",
                       "\(count) items · \(size), plus local data")
        }
        return count == 0
            ? text("尚未选择清理项", "Nothing selected")
            : text("已选 \(count) 项 · \(size)", "\(count) selected · \(size)")
    }

    private var cleanupPrimaryTitle: String {
        if store.cleanupPlan == nil {
            return store.cleanupBusy
                ? text("正在扫描", "Scanning")
                : text("扫描缓存", "Scan caches")
        }
        return cleanupActionTitle
    }

    private var cleanupPrimarySymbol: String {
        if store.cleanupPlan == nil { return "magnifyingglass" }
        return store.cleanupIncludesLocalData ? "exclamationmark.arrow.triangle.2.circlepath" : "trash"
    }

    private var cleanupPrimaryEnabled: Bool {
        store.cleanupPlan == nil ? !store.cleanupBusy : cleanupCanRun
    }

    private var cleanupActionTitle: String {
        store.cleanupIncludesLocalData
            ? text("清理并重置本地信息", "Clean and reset local data")
            : text("移到废纸篓", "Move to Trash")
    }

    private var cleanupGroupScopes: [CleanupScope] {
        CleanupScope.allCases.filter { scope in
            store.cleanupCandidates.contains { $0.scope == scope }
        }
    }

    private func cleanupTargets(for scope: CleanupScope) -> [CleanupTarget] {
        store.cleanupCandidates.filter { $0.scope == scope }
    }

    private func cleanupScopeTitle(_ scope: CleanupScope) -> String {
        switch scope {
        case .hostDesktop: return text("宿主 Claude Desktop", "Host Claude Desktop")
        case .hostCode: return text("宿主 Claude Code", "Host Claude Code")
        case .hostScience: return text("宿主 Claude Science", "Host Claude Science")
        case .currentSession: return text("当前 Routekeeper 沙箱", "Current Routekeeper sandbox")
        case .pastSession: return text("历史 Routekeeper 沙箱", "Past Routekeeper sandboxes")
        case .persistentProfile: return text("持久登录 sandbox profile", "Persistent sign-in sandbox profile")
        }
    }

    private func cleanupScopeSymbol(_ scope: CleanupScope) -> String {
        switch scope {
        case .hostDesktop: return "macwindow"
        case .hostCode: return "terminal"
        case .hostScience: return "atom"
        case .currentSession: return "shippingbox.fill"
        case .pastSession: return "archivebox"
        case .persistentProfile: return "person.crop.circle.badge.checkmark"
        }
    }

    @ViewBuilder
    private func cleanupTargetRow(_ target: CleanupTarget) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(get: {
                store.cleanupSelection.contains(target.id) && target.isSelectable
            }, set: {
                if $0 && target.isSelectable {
                    store.cleanupSelection.insert(target.id)
                } else {
                    store.cleanupSelection.remove(target.id)
                }
            }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!target.isSelectable)
            .accessibilityLabel(target.label(english: L10n.resolvedEnglish))

            VStack(alignment: .leading, spacing: 4) {
                Text(target.label(english: L10n.resolvedEnglish))
                    .routekeeperFont(.callout, weight: .medium)
                Text(target.kind(english: L10n.resolvedEnglish))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                Text(abbreviateHome(target.path))
                    .routekeeperFont(.caption2, design: .monospaced)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(target.path)
                if let reason = target.blockedReason {
                    Label(cleanupBlockedReason(reason), systemImage: "lock.fill")
                        .routekeeperFont(.caption, weight: .medium)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: target.sizeBytes, countStyle: .file))
                    .routekeeperFont(.callout, monospacedDigit: true)
                Text(target.blockedReason == nil
                     ? (store.cleanupSelection.contains(target.id)
                        ? text("已选择", "Selected")
                        : text("可清理", "Cleanable"))
                     : text("受保护", "Protected"))
                    .routekeeperFont(.caption2, weight: .medium)
                    .foregroundStyle(
                        target.blockedReason != nil
                            ? Color.orange
                            : store.cleanupSelection.contains(target.id) ? appAccent : Color.secondary
                    )
            }
            .frame(width: 96 * textScale, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .opacity(target.isSelectable ? 1 : 0.72)
    }

    private func cleanupBlockedReason(_ reason: CleanupBlockReason) -> String {
        switch reason {
        case .symbolicLink:
            return text("目标是指向其他位置的符号链接，已锁定。", "Target is a symbolic link and is locked.")
        case .processRunning:
            return text("对应 Claude 进程仍在运行，退出后重新检测。", "The matching Claude process is running; quit it and rescan.")
        case .sessionRunning:
            return text("该沙箱会话仍在运行，结束后再清理。", "This sandbox session is running; clean after it ends.")
        case .profileInUse:
            return text("持久登录 profile 正被运行中的沙箱使用。", "The persistent sign-in profile is in use by a running sandbox.")
        case .processInspectionUnavailable:
            return text("无法核验进程状态，已按失败关闭策略锁定。", "Process state cannot be inspected, so the target is locked fail-closed.")
        }
    }

    func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct GlassCircleButton: View {
    let systemImage: String
    var accentStyle: Bool
    var size: CGFloat
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            if accentStyle {
                Button(action: action) {
                    glassLabel
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(action: action) {
                    glassLabel
                }
                .buttonStyle(.glass)
            }
        } else {
            Button(action: action) {
                ZStack {
                    if accentStyle {
                        Circle().fill(LinearGradient(colors: [appAccent, appAccent.opacity(0.82)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(accentStyle ? Color.white : appAccent)
                }
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(accentStyle ? 0.25 : 0.55), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.16), radius: 9, x: 0, y: 4)
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    private var glassLabel: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.36, weight: .semibold))
            .frame(width: size, height: size)
            .contentShape(Circle())
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

struct GuardCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String = "",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .routekeeperFont(.headline)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .routekeeperFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appSurface(.primary)
        .accessibilityElement(children: .contain)
    }
}

struct CheckRow: View {
    let row: CheckItem
    @AppStorage(AppTextScale.storageKey) private var textScaleRaw = AppTextScale.standard.rawValue
    var color: Color { row.level == .passed ? .secondary : row.level == .warning ? .secondary : .orange }
    var symbol: String { row.level == .passed ? "checkmark.circle" : row.level == .warning ? "info.circle" : row.level == .unknown ? "questionmark.circle.fill" : "exclamationmark.circle.fill" }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 18).padding(.top, 2)
            Text(row.title)
                .routekeeperFont(.callout, weight: .medium)
                .frame(width: 120 * textScale, alignment: .leading)
            Text(row.detail).routekeeperFont(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(row.title), \(L10n.resolvedEnglish ? checkLevelEnglish(row.level) : checkLevelChinese(row.level)), \(row.detail)"
            )
    }

    private func checkLevelChinese(_ level: CheckLevel) -> String {
        switch level {
        case .passed: return "通过"
        case .warning: return "提示"
        case .unknown: return "未知"
        case .failed: return "未通过"
        }
    }

    private func checkLevelEnglish(_ level: CheckLevel) -> String {
        switch level {
        case .passed: return "passed"
        case .warning: return "warning"
        case .unknown: return "unknown"
        case .failed: return "failed"
        }
    }

    private var textScale: CGFloat {
        (AppTextScale(rawValue: textScaleRaw) ?? .standard).multiplier
    }
}

private struct CardBackground: ViewModifier {
    var corner: CGFloat
    func body(content: Content) -> some View {
        content.appSurface(.primary, corner: min(corner, 14))
    }
}

extension View {
    func cardSurface(corner: CGFloat = 16) -> some View { modifier(CardBackground(corner: corner)) }
}

private struct SidebarTableAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SidebarTableAppearanceView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? SidebarTableAppearanceView)?.configureTable()
    }
}

private final class SidebarTableAppearanceView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTable()
    }

    func configureTable() {
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let table = self.sidebarTable(in: window) else { return }
            table.identifier = NSUserInterfaceItemIdentifier("routekeeper-sidebar-list")
            table.selectionHighlightStyle = .none
        }
    }

    private func sidebarTable(in window: NSWindow) -> NSTableView? {
        guard let contentView = window.contentView else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("routekeeper-sidebar-list")
        return descendantTables(in: contentView)
            .first(where: { $0.identifier == identifier })
            ?? descendantTables(in: contentView).first
    }

    private func descendantTables(in view: NSView) -> [NSTableView] {
        view.subviews.flatMap { subview in
            (subview as? NSTableView).map { [$0] } ?? descendantTables(in: subview)
        }
    }
}
