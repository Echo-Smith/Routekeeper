import SwiftUI
import GuardCore

enum GuardPage: String, CaseIterable, Identifiable {
    case home, inspection, sandbox, protection, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return L10n.resolvedEnglish ? "Home" : "首页"
        case .inspection: return L10n.resolvedEnglish ? "Network check" : "网络体检"
        case .sandbox: return L10n.resolvedEnglish ? "Sandbox" : "沙箱"
        case .protection: return L10n.resolvedEnglish ? "Protection" : "保护"
        case .settings: return L10n.resolvedEnglish ? "Settings" : "设置"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .inspection: return "waveform.path.ecg.rectangle"
        case .sandbox: return "lock.shield"
        case .protection: return "shield.lefthalf.filled"
        case .settings: return "gearshape"
        }
    }
}

enum ProtectionSection: String, CaseIterable, Identifiable {
    case authentication, networkSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .authentication: return L10n.resolvedEnglish ? "Claude Code sign-in" : "Claude Code 登录凭证"
        case .networkSettings: return L10n.resolvedEnglish ? "Network protection" : "网络保护"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, events, cleanup, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.resolvedEnglish ? "General" : "通用"
        case .events: return L10n.resolvedEnglish ? "Run log" : "运行记录"
        case .cleanup: return L10n.resolvedEnglish ? "Cleanup" : "清理"
        case .about: return L10n.resolvedEnglish ? "About" : "关于"
        }
    }
}

struct Dashboard: View {
    @Bindable var store: GuardStore
    @State private var page: GuardPage = .home
    @State private var sidebarCollapsed = false
    @State private var protectionSection: ProtectionSection = .authentication
    @State private var settingsSection: SettingsSection = .general
    @State private var sandboxSection: SandboxSection = .overview
    @State private var headerHasScrolledContent = false
    private func text(_ zh: String, _ en: String) -> String { L10n.resolvedEnglish ? en : zh }
    @ScaledMetric(relativeTo: .title2) private var pageHeaderSize: CGFloat = 22
    @ScaledMetric(relativeTo: .headline) private var sidebarNameSize: CGFloat = 15
    @AppStorage(L10n.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
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
    private var sidebarWidth: CGFloat { sidebarCollapsed ? 76 : 200 }
    private var pageHorizontalPadding: CGFloat { 22 }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ZStack(alignment: .top) {
                ScrollView {
                    pageBody
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.top, 76)
                        .padding(.bottom, 26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            ScrollOffsetObserver { offset in
                                setHeaderScrolled(offset > 12)
                            }
                            .frame(height: 0)
                        }
                }
                .id(navigationIdentity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                pageHeader
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.72))
                .frame(width: 1)
                .offset(x: sidebarWidth - 1)
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .top)
        .tint(appAccent)
        .id(store.languageRevision)
        .background(WindowDragHelper())
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
        let requestedSection = AppNavigationRequest.consumePendingProtectionSection()
        let requestedSettings = AppNavigationRequest.consumePendingSettingsSection()
        if let requested = AppNavigationRequest.consumePendingPage() {
            selectPage(requested)
        }
        if let requestedSection {
            protectionSection = requestedSection
        }
        if let requestedSettings {
            settingsSection = requestedSettings
        }
    }

    var sidebar: some View {
        VStack(spacing: 4) {
            AppBadge(collapsed: sidebarCollapsed, symbol: store.symbol, tint: statusColor)
                .padding(.bottom, sidebarCollapsed ? 14 : 10)
            if !sidebarCollapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("app.name")).font(.system(size: sidebarNameSize, weight: .semibold))
                    Text(storeTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            VStack(spacing: 4) {
                ForEach(GuardPage.allCases.filter { $0 != .settings }) { item in
                    SidebarButton(page: item, selected: item == page, collapsed: sidebarCollapsed) {
                        selectPage(item)
                    }
                    if item == page && !sidebarCollapsed {
                        sidebarSubmenu(for: item)
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                if page == .settings && !sidebarCollapsed {
                    sidebarSubmenu(for: .settings)
                        .padding(.bottom, 2)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                SidebarButton(page: .settings, selected: page == .settings, collapsed: sidebarCollapsed) {
                    selectPage(.settings)
                }
                if !sidebarCollapsed {
                    Text("v0.3.12").font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: sidebarWidth)
        .padding(.top, 48)
        .padding(.bottom, 14)
        .background(Color(nsColor: .controlBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: sidebarCollapsed)
    }

    @ViewBuilder
    private func sidebarSubmenu(for page: GuardPage) -> some View {
        switch page {
        case .protection:
            VStack(spacing: 2) {
                ForEach(ProtectionSection.allCases) { section in
                    SidebarSubButton(
                        title: section.title,
                        selected: protectionSection == section
                    ) {
                        headerHasScrolledContent = false
                        withAnimation(.easeInOut(duration: 0.16)) {
                            protectionSection = section
                        }
                    }
                    .accessibilityIdentifier("protection-section-\(section.rawValue)")
                }
            }
            .padding(.leading, 18)
        case .settings:
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarSubButton(
                        title: section.title,
                        selected: settingsSection == section
                    ) {
                        headerHasScrolledContent = false
                        withAnimation(.easeInOut(duration: 0.16)) {
                            settingsSection = section
                        }
                    }
                    .accessibilityIdentifier("settings-section-\(section.rawValue)")
                }
            }
            .padding(.leading, 18)
        case .home, .inspection, .sandbox:
            EmptyView()
        }
    }

    var storeTitle: String {
        if store.checking { return L("status.checking") }
        return store.title
    }

    var pageHeader: some View {
        HStack(spacing: 12) {
            SidebarToggleButton(collapsed: sidebarCollapsed) {
                withAnimation(.easeInOut(duration: 0.18)) { sidebarCollapsed.toggle() }
            }
            PageHeaderBreadcrumb(
                pageTitle: page.title,
                sectionTitle: currentSectionTitle,
                onOpenRoot: { selectPage(page) }
            )
            .font(.system(size: pageHeaderSize, weight: .semibold))
            .tracking(-0.45)
            .lineLimit(1)
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(capsuleText).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .routekeeperGlassCapsule()
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background {
            if headerHasScrolledContent {
                Rectangle().fill(.bar)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if headerHasScrolledContent {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.48))
                    .frame(height: 0.5)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: headerHasScrolledContent)
    }

    private var currentSectionTitle: String? {
        switch page {
        case .protection: return protectionSection.title
        case .settings: return settingsSection.title
        case .sandbox: return sandboxSection.title
        case .home, .inspection: return nil
        }
    }

    private var navigationIdentity: String {
        switch page {
        case .protection: return "protection-\(protectionSection.rawValue)"
        case .settings: return "settings-\(settingsSection.rawValue)"
        case .sandbox: return "sandbox-\(sandboxSection.rawValue)"
        case .home, .inspection: return page.rawValue
        }
    }

    private func selectPage(_ newPage: GuardPage) {
        if newPage == .protection {
            protectionSection = .authentication
        } else if newPage == .settings {
            settingsSection = .general
        } else if newPage == .sandbox {
            sandboxSection = .overview
        }
        headerHasScrolledContent = false
        withAnimation(.easeInOut(duration: 0.16)) {
            page = newPage
        }
    }

    private func setHeaderScrolled(_ scrolled: Bool) {
        guard scrolled != headerHasScrolledContent else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            headerHasScrolledContent = scrolled
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
                        selectPage(.protection)
                        protectionSection = .networkSettings
                    }
                )
            }
        case .sandbox:
            SandboxPage(store: store, mode: .management, section: $sandboxSection)
        case .protection: protectionPage
        case .settings: settingsPage
        }
    }

    var homePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.settings.experimentalSandboxEnabled {
                homeSandboxCard
                HStack(alignment: .top, spacing: 16) {
                    homeProtectionCard
                    if store.settings.gatewayProtectionMode != .off {
                        homeGatewayCard
                    } else {
                        homeEgressCard
                    }
                }
            } else {
                homeStatusCard
                if store.settings.gatewayProtectionMode != .off {
                    homeGatewayCard
                }
                HStack(alignment: .top, spacing: 16) {
                    homeProtectionCard
                    homeEgressCard
                }
            }
        }
    }

    private var homeSandboxCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: store.sandbox.statusSymbol)
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(statusColor)
                    .frame(width: 56, height: 56)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.sandbox.statusTitle)
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.3)
                    Text(store.sandbox.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(text("实验性", "Experimental"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            HStack(spacing: 20) {
                Label(
                    store.sandbox.networkEnabled ? text("中继网络已开启", "Relay network on") : text("网络已关闭", "Network off"),
                    systemImage: store.sandbox.networkEnabled ? "network" : "wifi.slash"
                )
                .foregroundStyle(store.sandbox.networkEnabled ? appAccent : Color.orange)
                Label(
                    store.sandbox.claudeRunning ? text("Claude 正在运行", "Claude running") : text("Claude 未运行", "Claude not running"),
                    systemImage: "terminal"
                )
                .foregroundStyle(.secondary)
            }
            .font(.callout.weight(.medium))

            HStack {
                Text(text("普通网络监控已暂停", "Ordinary monitoring is paused"))
                    .font(.caption)
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
        .padding(22)
        .cardSurface(corner: 22)
    }

    private var homeStatusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: store.symbol)
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(statusColor)
                    .frame(width: 56, height: 56)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.system(size: 21, weight: .semibold)).tracking(-0.3)
                    Text(store.notice.isEmpty ? L("overview.unmonitored.sub") : store.notice)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if let snapshot = store.snapshot {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(homePassedChecks)/\(snapshot.checks.count)")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(homeCheckSummary)
                            .font(.caption2)
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
                        Text(store.policy.reason).font(.callout).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            AppHairline()

            HStack(spacing: 12) {
                if let snapshot = store.snapshot {
                    Text(text("最近体检 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))",
                              "Last checked \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L("capsule.noCheck")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !store.monitoring {
                    Button(text("重新检测", "Check again")) { page = .inspection }
                        .buttonStyle(.plain).foregroundStyle(appAccent)
                }
                Button(action: homePrimaryAction) {
                    Label(homePrimaryTitle, systemImage: homePrimarySymbol)
                }
                .routekeeperProminentButton()
                .controlSize(.large)
                .disabled(store.checking)
                .accessibilityIdentifier(store.monitoring ? "stop-monitor" : "home-primary")
            }
        }
        .padding(22)
        .cardSurface(corner: 22)
    }

    private var homeGatewayCard: some View {
        let mode = store.settings.gatewayProtectionMode
        let status = store.gatewayVerification.status(for: mode)
        return GuardCard(
            title: text("代理网关", "Proxy gateway"),
            subtitle: text(
                "检查代理可用、节点断开失败关闭，以及代理退出后不会回落直连。",
                "Check proxy reachability, fail-closed behavior with the node unavailable, and no direct fallback after the client exits."
            )
        ) {
            HStack(spacing: 12) {
                Image(systemName: homeGatewaySymbol(status))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(homeGatewayColor(status))
                    .frame(width: 38, height: 38)
                    .background(
                        homeGatewayColor(status).opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(homeGatewayTitle(status, mode: mode))
                        .font(.callout.weight(.semibold))
                    Text(homeGatewayModeTitle(mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(text("打开检查", "Open check")) {
                    selectPage(.inspection)
                }
                .routekeeperSecondaryButton()
                .accessibilityIdentifier("home-gateway-open-check")
            }
        }
    }

    private var homeProtectionCard: some View {
        GuardCard(
            title: text("Claude 保护范围", "Claude protection"),
            subtitle: text("应用是否纳入监控，以及发现异常后的处理方式。",
                           "Which Claude apps are monitored and what happens after an incident.")
        ) {
            homeProtectionRow(kind: .desktop)
            AppHairline()
            homeProtectionRow(kind: .code)
            AppHairline()
            HStack(spacing: 10) {
                Label(text("发现异常时", "On incident"), systemImage: "bell.badge")
                    .font(.callout)
                Spacer()
                Text(store.settings.action == .notify
                     ? text("仅提醒", "Notify only")
                     : text("请求退出所选进程", "Request selected exits"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(store.settings.action == .notify ? Color.secondary : Color.orange)
            }
            AppHairline()
            HStack(spacing: 10) {
                Image(systemName: store.events.contains(where: \.isAttention)
                      ? "exclamationmark.triangle.fill"
                      : "checkmark.circle")
                    .foregroundStyle(store.events.contains(where: \.isAttention) ? Color.orange : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text("最近异常", "Latest incident"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(homeLatestAttentionText)
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let incident = store.events.first(where: \.isAttention) {
                    Text(homeRelativeTime(incident.time))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack {
                Spacer()
                Button {
                    selectPage(.protection)
                    protectionSection = .networkSettings
                } label: {
                    Label(text("管理保护范围", "Manage protection"), systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .foregroundStyle(appAccent)
                .accessibilityIdentifier("home-manage-protection")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
                return (text("\(running) 个进程", "\(running) running"), appAccent)
            }
            return (text("已启用 · 等待启动", "On · waiting to launch"), .secondary)
        }()

        HStack(spacing: 12) {
            Image(systemName: kind == .desktop ? "macwindow" : "terminal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .desktop ? "Claude Desktop" : "Claude Code")
                    .font(.callout.weight(.medium))
                Text(enabled
                     ? text("已纳入异常检测", "Included in incident checks")
                     : text("不会处理该应用的异常", "Excluded from incident handling"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.color)
        }
        .padding(.vertical, 5)
    }

    private var homeEgressCard: some View {
        GuardCard(
            title: text("最近出口体检", "Latest egress check"),
            subtitle: text("出口一致性、IPv6、服务可达性与自动体检节奏。",
                           "Exit consistency, IPv6, service reachability and automatic-check timing.")
        ) {
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
                    color: report.services.allSatisfy(\.reachedTLS) ? appAccent : .orange
                )
                if let drift = store.egressAudit.drift {
                    Label(text("出口已从 \(drift.previousIP) 变化为 \(drift.currentIP)",
                               "Exit changed from \(drift.previousIP) to \(drift.currentIP)"),
                          systemImage: "arrow.triangle.swap")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(homeNextAuditText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(text("最近 \(report.auditedAt.formatted(date: .abbreviated, time: .shortened))",
                              "Last \(report.auditedAt.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button(text("查看检查详情", "View evidence")) { selectPage(.inspection) }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(appAccent)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text("还没有出口体检结果", "No egress report yet"))
                            .font(.callout.weight(.semibold))
                        Text(text("完成体检后可在这里查看出口一致性、IPv6 路径与服务可达性。",
                                  "Run a check to see exit consistency, IPv6 routing and service reachability here."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(homeNextAuditText)
                    .font(.caption2)
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
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced
                      ? .system(.callout, design: .monospaced)
                      : .callout)
                .foregroundStyle(color)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
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
        case .clear: return appAccent
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
        case .disabled, .tunneled: return appAccent
        case .noClaudePath: return .secondary
        case .tunnelUnconfirmed, .tunnelExitMismatch, .directExposure, .unknown, nil: return .orange
        }
    }

    var homePrimaryTitle: String {
        if store.monitoring { return L("action.stopMonitor") }
        if store.snapshot?.ready == true && canStartMonitoring { return L("action.startMonitor") }
        return text("完成体检", "Run network check")
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

    func homeSummaryRow(id: String, title: String, symbol: String) -> some View {
        let check = store.snapshot?.checks.first { $0.id == id }
        let color: Color = check?.level == .passed ? appAccent : check?.level == .failed ? .orange : .secondary
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(check?.detail ?? L("target.notChecked"))
                .font(.system(.callout, design: .monospaced)).foregroundStyle(color)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var protectionPage: some View {
        switch protectionSection {
        case .authentication:
            AuthenticationPage(
                controller: store.authentication,
                launchAction: { store.launchFromAuthentication() }
            )
        case .networkSettings:
            NetworkProtectionPage(store: store)
        }
    }

    @ViewBuilder
    var settingsPage: some View {
        switch settingsSection {
        case .general:
            VStack(spacing: 16) {
                appSettingsPage
                navigationToolCard(
                    title: L("page.events"),
                    subtitle: text("\(store.events.count) 条本机记录", "\(store.events.count) local events"),
                    symbol: "clock.arrow.circlepath",
                    identifier: "tool-card-events"
                ) {
                    settingsSection = .events
                }
                navigationToolCard(
                    title: L("page.cleanup"),
                    subtitle: text("清理缓存与日志，或重置 Routekeeper 本地信息",
                                   "Clean caches and logs, or reset Routekeeper local data"),
                    symbol: "trash.circle",
                    identifier: "tool-card-cleanup"
                ) {
                    settingsSection = .cleanup
                }
                navigationToolCard(
                    title: text("关于", "About"),
                    subtitle: text("版本、用途边界与免责声明", "Version, purpose and disclaimer"),
                    symbol: "info.circle",
                    identifier: "tool-card-about"
                ) {
                    settingsSection = .about
                }
            }
        case .events:
            eventsPage
        case .cleanup:
            cleanupPage
        case .about:
            AboutPage(onQuit: { confirmQuit(store) })
        }
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

    func navigationToolCard(
        title: String,
        subtitle: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(text("打开", "Open"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(appAccent)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSurface(corner: 18)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("\(title)，\(subtitle)")
    }

    var eventsPage: some View {
        GuardCard(title: L("card.events"), subtitle: L("events.sub")) {
            if store.events.isEmpty {
                Text(L("events.empty")).foregroundStyle(.secondary).padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.events) { event in
                        HStack(alignment: .top, spacing: 14) {
                            Text(event.time.formatted(date: .omitted, time: .standard))
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                            if event.isAttention {
                                Label(text("需注意", "Attention"), systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            }
                            Text(event.message).font(.callout).textSelection(.enabled)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if store.cleanupPlan == nil {
                        Text(store.cleanupBusy
                             ? text("正在统计可清理空间", "Calculating cleanable space")
                             : text("扫描后显示可清理空间", "Cleanable space appears after scanning"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(cleanupAvailableSize)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(text("可清理", "cleanable"))
                                .font(.title3.weight(.medium))
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
                        .font(.caption)
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
                        .font(.callout)
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
                    .font(.caption)
                    Button(text("清除", "Clear")) {
                        store.cleanupSelection.removeAll()
                        store.cleanupIncludesLocalData = false
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    Spacer()
                }
            }

            if !store.cleanupResult.isEmpty {
                Label(store.cleanupResult, systemImage: "checkmark.circle")
                    .font(.callout)
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
            .font(.callout)
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
        .font(.caption)
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
                    .font(.caption)
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
                        .font(.callout.weight(.medium))
                    Text(text(
                        "不可恢复，也不会进入废纸篓。",
                        "This cannot be undone or restored from Trash."
                    ))
                    .font(.caption)
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
                    .font(.caption.weight(.medium))
                    .disabled(selectable.isEmpty)
                    Spacer()
                    Text(text(
                        "\(selectedCount)/\(selectable.count) 项已选",
                        "\(selectedCount)/\(selectable.count) selected"
                    ))
                    .font(.caption2)
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
                        .font(.callout.weight(.semibold))
                    Text(text(
                        "\(selectable.count) 项可清理",
                        "\(selectable.count) cleanable"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(text(
                        "共 \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))",
                        "\(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) total"
                    ))
                    .font(.caption.monospacedDigit())
                    Text(selectedBytes > 0
                         ? text(
                            "已选 \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))",
                            "\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)) selected"
                         )
                         : text("未选择", "Nothing selected"))
                        .font(.caption2.monospacedDigit())
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
                    .font(.callout.weight(.medium))
                Text(target.kind(english: L10n.resolvedEnglish))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(abbreviateHome(target.path))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(target.path)
                if let reason = target.blockedReason {
                    Label(cleanupBlockedReason(reason), systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: target.sizeBytes, countStyle: .file))
                    .font(.callout.monospacedDigit())
                Text(target.blockedReason == nil
                     ? (store.cleanupSelection.contains(target.id)
                        ? text("已选择", "Selected")
                        : text("可清理", "Cleanable"))
                     : text("受保护", "Protected"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(
                        target.blockedReason != nil
                            ? Color.orange
                            : store.cleanupSelection.contains(target.id) ? appAccent : Color.secondary
                    )
            }
            .frame(width: 96, alignment: .trailing)
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

    var appSettingsPage: some View {
        GuardCard(title: L("card.general"), subtitle: L("card.general.sub")) {
            Picker(L("general.language"), selection: Binding(
                get: { L10n.language },
                set: { newValue in
                    L10n.language = newValue
                    UserDefaults.standard.set([newValue == .en ? "en" : "zh-Hans"], forKey: "AppleLanguages")
                    store.languageRevision += 1
                    store.notifyLanguageChanged()
                }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in Text(lang.title).tag(lang) }
            }.pickerStyle(.menu).frame(maxWidth: 260)
            Text(L("general.langNote")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(L("general.appearance"), selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }.pickerStyle(.menu).frame(maxWidth: 260)
            Divider().padding(.vertical, 4)
            if store.settings.experimentalSandboxEnabled {
                Label(
                    text("沙箱运行中，无法进行设置。请先结束并关闭沙箱。",
                         "Sandbox is active. End and close it before changing settings."),
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Toggle(text("自动出口体检", "Automatic egress checks"),
                       isOn: $store.automaticEgressAuditEnabled)
                    .toggleStyle(.switch)
                Picker(text("自动体检间隔", "Automatic-check interval"),
                       selection: $store.automaticEgressAuditIntervalMinutes) {
                    Text(text("每 15 分钟", "Every 15 minutes")).tag(15)
                    Text(text("每 30 分钟", "Every 30 minutes")).tag(30)
                    Text(text("每 60 分钟", "Every 60 minutes")).tag(60)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
                .disabled(!store.automaticEgressAuditEnabled)
            }
        }
    }

    func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct AppBadge: View {
    let collapsed: Bool
    let symbol: String
    let tint: Color

    @ViewBuilder
    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .light))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.clear)
                        .glassEffect(
                            .regular.tint(tint.opacity(0.10)),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.09))
                }
            }
            .frame(maxWidth: .infinity)
    }
}

private struct SidebarButton: View {
    let page: GuardPage
    let selected: Bool
    let collapsed: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                if !collapsed {
                    Text(page.title).font(.callout.weight(selected ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : 10)
            .frame(height: 34)
            .routekeeperSidebarSelection(selected: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? appAccent : Color.primary)
        .accessibilityIdentifier("nav-\(page.rawValue)")
        .help(page.title)
        .accessibilityLabel(page.title)
    }
}

private struct SidebarSubButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .routekeeperSidebarSelection(selected: selected, cornerRadius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? appAccent : Color.primary.opacity(0.78))
        .accessibilityLabel(title)
    }
}

private struct SidebarToggleButton: View {
    let collapsed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            toggleLabel
        }
        .buttonStyle(HeaderIconButtonStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .help(collapsed
              ? (L10n.resolvedEnglish ? "Show sidebar" : "显示侧栏")
              : (L10n.resolvedEnglish ? "Hide sidebar" : "隐藏侧栏"))
        .accessibilityLabel(collapsed
                            ? (L10n.resolvedEnglish ? "Show sidebar" : "显示侧栏")
                            : (L10n.resolvedEnglish ? "Hide sidebar" : "隐藏侧栏"))
        .accessibilityIdentifier("sidebar-toggle")
    }

    private var toggleLabel: some View {
        Image(systemName: "sidebar.left")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }
}

private struct PageHeaderBreadcrumb: View {
    let pageTitle: String
    let sectionTitle: String?
    let onOpenRoot: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let sectionTitle {
                Button(action: onOpenRoot) {
                    Text(pageTitle)
                        .foregroundStyle(Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.resolvedEnglish ? "Back to \(pageTitle)" : "返回\(pageTitle)")
                .accessibilityLabel(L10n.resolvedEnglish ? "Back to \(pageTitle)" : "返回\(pageTitle)")
                .accessibilityIdentifier("page-header-root")
                Text("/")
                    .foregroundStyle(.tertiary)
                Text(sectionTitle)
                    .foregroundStyle(.primary)
            } else {
                Text(pageTitle)
            }
        }
    }
}

private struct HeaderIconButtonStyle: ButtonStyle {
    let hovering: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .background {
                if hovering || configuration.isPressed {
                    if #available(macOS 26.0, *) {
                        shape
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: shape)
                    } else {
                        shape.fill(Color.primary.opacity(0.06))
                    }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).tracking(-0.15)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 3)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardSurface(corner: 18)
    }
}

struct CheckRow: View {
    let row: CheckItem
    var color: Color { row.level == .passed ? appAccent : row.level == .warning ? .secondary : .orange }
    var symbol: String { row.level == .passed ? "checkmark.circle.fill" : row.level == .warning ? "info.circle" : row.level == .unknown ? "questionmark.circle.fill" : "exclamationmark.circle.fill" }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 18).padding(.top, 2)
            Text(row.title).font(.callout.weight(.medium)).frame(width: 120, alignment: .leading)
            Text(row.detail).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(row.title)，\(row.level == .passed ? "通过" : row.level == .warning ? "提示" : row.level == .unknown ? "未知" : "未通过")，\(row.detail)")
    }
}

private struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var corner: CGFloat
    func body(content: Content) -> some View {
        content
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(
                color: colorScheme == .light ? .black.opacity(0.045) : .clear,
                radius: 14, x: 0, y: 6
            )
    }
}

extension View {
    func cardSurface(corner: CGFloat = 16) -> some View { modifier(CardBackground(corner: corner)) }
}

private struct ScrollOffsetObserver: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollObserverView {
        let view = ScrollObserverView()
        view.onOffsetChange = onChange
        return view
    }

    func updateNSView(_ view: ScrollObserverView, context: Context) {
        view.onOffsetChange = onChange
        view.attachIfNeeded()
    }
}

private final class ScrollObserverView: NSView {
    var onOffsetChange: ((CGFloat) -> Void)?
    private weak var observedClipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        guard let scrollView = enclosingScrollView else {
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
            return
        }

        let clipView = scrollView.contentView
        guard observedClipView !== clipView else {
            reportOffset()
            return
        }

        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.reportOffset()
        }
        reportOffset()
    }

    private func reportOffset() {
        guard let clipView = observedClipView else { return }
        onOffsetChange?(max(0, clipView.bounds.minY))
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }
}

private struct WindowDragHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in view.window?.isMovableByWindowBackground = true }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        view.window?.isMovableByWindowBackground = true
    }
}
