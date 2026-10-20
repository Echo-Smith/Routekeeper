import SwiftUI
import GuardCore

enum GuardPage: String, CaseIterable, Identifiable {
    case home, inspection, protection, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return L10n.resolvedEnglish ? "Home" : "首页"
        case .inspection: return L10n.resolvedEnglish ? "Network check" : "网络体检"
        case .protection: return L10n.resolvedEnglish ? "Protection" : "保护"
        case .settings: return L10n.resolvedEnglish ? "Settings" : "设置"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .inspection: return "waveform.path.ecg.rectangle"
        case .protection: return "shield.lefthalf.filled"
        case .settings: return "gearshape"
        }
    }
}

private enum ProtectionSection: String, CaseIterable, Identifiable {
    case settings, authentication, advancedNetwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return L10n.resolvedEnglish ? "Protection settings" : "保护设置"
        case .authentication: return L10n.resolvedEnglish ? "Claude Code sign-in" : "Claude Code 登录凭证"
        case .advancedNetwork: return L10n.resolvedEnglish ? "Advanced network protection" : "高级网络保护"
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, events, cleanup, disclaimer, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.resolvedEnglish ? "General" : "通用"
        case .events: return L10n.resolvedEnglish ? "Run log" : "运行记录"
        case .cleanup: return L10n.resolvedEnglish ? "Cleanup" : "清理"
        case .disclaimer: return L10n.resolvedEnglish ? "Disclaimer" : "免责声明"
        case .about: return L10n.resolvedEnglish ? "About" : "关于"
        }
    }
}

struct Dashboard: View {
    @Bindable var store: GuardStore
    @State private var page: GuardPage = .home
    @State private var sidebarCollapsed = false
    @State private var showProxyName = false
    @State private var proxyNameRevision = 0
    @State private var protectionSection: ProtectionSection = .settings
    @State private var settingsSection: SettingsSection = .general
    @State private var headerHasScrolledContent = false
    private func text(_ zh: String, _ en: String) -> String { L10n.resolvedEnglish ? en : zh }
    @ScaledMetric(relativeTo: .title2) private var pageHeaderSize: CGFloat = 22
    @ScaledMetric(relativeTo: .headline) private var sidebarNameSize: CGFloat = 15
    @AppStorage(L10n.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("routekeeper.disclaimer-accepted-version") private var disclaimerAcceptedVersion = ""
    @State private var showDisclaimerGate = false
    var needsOnboarding: Bool {
        !store.monitoring && (store.snapshot == nil ||
            (store.settings.target(for: .ipv4) == nil && store.settings.target(for: .ipv6) == nil))
    }
    var statusColor: Color { store.policy.phase == .incident ? .orange : store.policy.phase == .armed ? appAccent : .secondary }
    private var sidebarWidth: CGFloat { sidebarCollapsed ? 76 : 200 }
    private var pageHorizontalPadding: CGFloat {
        page == .settings && settingsSection == .disclaimer ? 18 : 22
    }

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
            if disclaimerAcceptedVersion != DisclaimerPage.currentVersion {
                showDisclaimerGate = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .routekeeperShowChecks)) { _ in
            applyNavigationRequest()
        }
        .sheet(isPresented: $showDisclaimerGate) {
            DisclaimerConsentSheet(
                onAgree: {
                    disclaimerAcceptedVersion = DisclaimerPage.currentVersion
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
        if let requested = AppNavigationRequest.consumePendingPage() {
            selectPage(requested)
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
                    Text("v0.3.10").font(.caption2).foregroundStyle(.tertiary)
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
        case .home, .inspection:
            EmptyView()
        }
    }

    var storeTitle: String {
        switch store.policy.phase {
        case .idle: return store.checking ? L("status.checking") : L("status.idle")
        case .armed: return L("status.armed")
        case .incident: return L("status.incident")
        }
    }

    var pageHeader: some View {
        HStack(spacing: 12) {
            SidebarToggleButton(collapsed: sidebarCollapsed) {
                withAnimation(.easeInOut(duration: 0.18)) { sidebarCollapsed.toggle() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let sectionTitle = currentSectionTitle {
                    Text(page.title)
                        .foregroundStyle(.secondary)
                    Text("/")
                        .foregroundStyle(.tertiary)
                    Text(sectionTitle)
                        .foregroundStyle(.primary)
                } else {
                    Text(page.title)
                }
            }
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
        case .home, .inspection: return nil
        }
    }

    private var navigationIdentity: String {
        switch page {
        case .protection: return "protection-\(protectionSection.rawValue)"
        case .settings: return "settings-\(settingsSection.rawValue)"
        case .home, .inspection: return page.rawValue
        }
    }

    private func selectPage(_ newPage: GuardPage) {
        if newPage == .protection {
            protectionSection = .settings
        } else if newPage == .settings {
            settingsSection = .general
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
        if store.checking { return L("status.checking") }
        if store.policy.phase == .incident { return L("status.incident") }
        if store.monitoring { return L("status.armed") }
        guard let snapshot = store.snapshot else { return L("capsule.noCheck") }
        guard let family = snapshot.proxyIP.map(IPFamily.of),
              let target = store.settings.target(for: family) else { return L("capsule.noTarget") }
        let match = snapshot.proxyIP == snapshot.tunnelIP && snapshot.proxyIP == target
        return "\(L("capsule.last")) \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened)) · \(match ? L("capsule.match") : L("capsule.mismatch"))"
    }

    @ViewBuilder var pageBody: some View {
        switch page {
        case .home: homePage
        case .inspection: InspectionPage(store: store, audit: store.egressAudit) { selectPage(.protection) }
        case .protection: protectionPage
        case .settings: settingsPage
        }
    }

    var homePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            homeStatusCard
            HStack(alignment: .top, spacing: 16) {
                homeProtectionCard
                homeEgressCard
            }
            homeActivityCard
            Text(L("overview.boundary"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

            if needsOnboarding {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        setupStep(1, text("检测网络", "Check network"))
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        setupStep(2, text("确认出口", "Confirm exits"))
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        setupStep(3, text("开启监控", "Start monitoring"))
                    }
                    Text(text("先完成一次网络体检，Routekeeper 会读取一致的 IPv4/IPv6 出口。",
                              "Run one network check first. Routekeeper will read matching IPv4/IPv6 exits."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                AppHairline()
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
                return store.snapshot?.desktopPath != nil
                    || ApplicationDiscovery.path(bundleID: ApplicationDiscovery.desktopID, name: "Claude") != nil
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
                .buttonStyle(.bordered)
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

    private var homeActivityCard: some View {
        GuardCard(
            title: text("最近变化", "Recent activity"),
            subtitle: text("最近的监控、网络变化与检查结果。",
                           "Recent monitoring, network changes and check results.")
        ) {
            if store.events.isEmpty {
                Label(text("暂无运行记录；完成一次自检后会显示在这里。",
                           "No activity yet. A completed check will appear here."),
                      systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.events.prefix(4))) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.isAttention
                                  ? "exclamationmark.circle.fill"
                                  : "circle.fill")
                                .font(.system(size: event.isAttention ? 13 : 6, weight: .medium))
                                .foregroundStyle(event.isAttention ? Color.orange : appAccent)
                                .frame(width: 18, height: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.message)
                                    .font(.callout)
                                    .lineLimit(2)
                                Text(homeRelativeTime(event.time))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        if event.id != store.events.prefix(4).last?.id {
                            AppHairline()
                        }
                    }
                }
            }
            HStack {
                if store.events.count > 4 {
                    Text(text("另有 \(store.events.count - 4) 条记录", "\(store.events.count - 4) more entries"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    settingsSection = .events
                    headerHasScrolledContent = false
                    withAnimation(.easeInOut(duration: 0.16)) {
                        page = .settings
                    }
                } label: {
                    Label(text("查看运行记录", "Open run log"), systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .foregroundStyle(appAccent)
                .accessibilityIdentifier("home-open-run-log")
            }
        }
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

    func setupStep(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.caption2.weight(.semibold))
                .frame(width: 18, height: 18)
                .background(Color.primary.opacity(0.07), in: Circle())
            Text(title).font(.caption.weight(.medium))
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

    var protectionSettingsPage: some View {
        VStack(spacing: 16) {
            GuardCard(title: L("card.protect"), subtitle: L("card.protect.sub")) {
                protectToggle(isOn: $store.settings.protectDesktop, icon: "macwindow", label: L("protect.desktop"), available: store.desktopInstalled, unavailableHint: L("protect.desktop.unavailable"))
                Divider().padding(.vertical, 4)
                protectToggle(isOn: $store.settings.protectCode, icon: "terminal", label: L("protect.code"), available: store.codeInstalled, unavailableHint: L("protect.code.unavailable"))
                Text(L("protect.code.hint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.disabled(store.monitoring || store.checking || store.networkFilter.configured || store.networkFilter.busy)

            GuardCard(title: L("card.target"), subtitle: L("card.target.sub")) {
                fixedExitRow(
                    family: .ipv4,
                    label: L10n.resolvedEnglish ? "IPv4 fixed exit" : "IPv4 固定出口",
                    placeholder: L10n.resolvedEnglish ? "IPv4 exit address" : "IPv4 出口地址"
                )
                Divider().padding(.vertical, 2)
                fixedExitRow(
                    family: .ipv6,
                    label: L10n.resolvedEnglish ? "IPv6 fixed exit" : "IPv6 固定出口",
                    placeholder: L10n.resolvedEnglish ? "IPv6 exit address" : "IPv6 出口地址"
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("target.guide.title")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(L("target.guide.1")).font(.caption).foregroundStyle(.secondary)
                    Text(L("target.guide.2")).font(.caption).foregroundStyle(.secondary)
                    Text(L("target.guide.3")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L("target.hint")).font(.caption2).foregroundStyle(.tertiary)
            }.disabled(store.monitoring || store.checking)

            GuardCard(title: L10n.resolvedEnglish ? "Network checks" : "网络检测", subtitle: L10n.resolvedEnglish ? "Unknown probe results prevent monitoring" : "所选检查项目都通过后，才能开启监控") {
                HStack {
                    Text(text("代理客户端", "Proxy client"))
                    Spacer()
                    Menu {
                        ForEach(ProxyClient.allCases, id: \.self) { client in
                            Button(client.title) {
                                store.settings.proxyClient = client
                                showProxyName = true
                                proxyNameRevision += 1
                            }
                        }
                    } label: {
                        Text(showProxyName
                             ? text("已配置（\(store.settings.proxyClient.title)）", "Configured (\(store.settings.proxyClient.title))")
                             : text("已配置", "Configured"))
                    }
                    .accessibilityIdentifier("proxy-client")
                    .task(id: proxyNameRevision) {
                        guard showProxyName else { return }
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        showProxyName = false
                    }
                }
                HStack {
                    Text(L10n.resolvedEnglish ? "Polling delay (seconds)" : "检查间隔（秒）")
                    TextField("1–300", value: $store.settings.pollInterval, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 90).accessibilityIdentifier("poll-interval")
                    Stepper("", value: $store.settings.pollInterval, in: 1...300, step: 1).labelsHidden()
                }
                if !store.settings.validInterval { Text(L10n.resolvedEnglish ? "Enter a value from 1 to 300." : "请输入 1–300 秒，填写后才能开启监控。").foregroundStyle(.orange) }
                Text(L10n.resolvedEnglish ? "Wait after each completed round; requests take additional time. Network changes trigger immediate invalidation and revalidation." : "每轮检查完成后，等待这段时间再检查。切换网络时会立即重新检查。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.resolvedEnglish ? "Probe DNS resolver routes and responses" : "检测 DNS 解析器路由与有效响应", isOn: $store.settings.dnsProbeEnabled)
                Toggle(L10n.resolvedEnglish ? "Probe UDP egress with two STUN servers" : "用两处 STUN 服务检测 UDP 出口", isOn: $store.settings.udpProbeEnabled)
                Text(L10n.resolvedEnglish ? "Disabled probes remain unverified. STUN is not a full browser WebRTC test. Probe services see your current egress IP." : "关闭的项目会显示未验证。STUN 不等于完整浏览器 WebRTC 测试；探测服务会看到当前出口 IP。")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(store.monitoring || store.checking)

            GuardCard(title: L("card.action"), subtitle: L("card.action.sub")) {
                Picker("检测到异常时", selection: $store.settings.action) {
                    ForEach(IncidentAction.allCases, id: \.self) { action in
                        Text(action == .notify ? L("action.notify") : L("action.terminate")).tag(action)
                    }
                }.pickerStyle(.menu).frame(maxWidth: 430)
                Text(store.settings.action == .terminate ? L("action.terminate.hint") : L("action.notify.hint"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.disabled(store.monitoring || store.checking)
        }
    }

    @ViewBuilder
    var protectionPage: some View {
        switch protectionSection {
        case .settings:
            VStack(spacing: 16) {
                protectionSettingsPage
                navigationToolCard(
                    title: text("Claude Code 登录凭证", "Claude Code sign-in"),
                    subtitle: authenticationSummary,
                    symbol: "person.badge.key",
                    identifier: "tool-card-authentication"
                ) {
                    protectionSection = .authentication
                }
                navigationToolCard(
                    title: L10n.resolvedEnglish ? "Advanced network protection" : "高级网络保护",
                    subtitle: advancedNetworkSummary,
                    symbol: "network.badge.shield.half.filled",
                    identifier: "tool-card-advanced-network"
                ) {
                    protectionSection = .advancedNetwork
                }
            }
        case .authentication:
            AuthenticationPage(controller: store.authentication)
        case .advancedNetwork:
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
                    title: text("免责声明", "Disclaimer"),
                    subtitle: text("查看使用条款与隐私说明", "Terms of use and privacy"),
                    symbol: "doc.text",
                    identifier: "tool-card-disclaimer"
                ) { settingsSection = .disclaimer }
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
                    subtitle: text("清理 Claude 缓存与日志", "Clean Claude caches and logs"),
                    symbol: "trash.circle",
                    identifier: "tool-card-cleanup"
                ) {
                    settingsSection = .cleanup
                }
                navigationToolCard(
                    title: text("关于", "About"),
                    subtitle: text("查看版本信息", "View version information"),
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
        case .disclaimer:
            DisclaimerPage(onQuit: { confirmQuit(store) })
        case .about:
            AboutPage()
        }
    }

    var authenticationSummary: String {
        switch store.authentication.status {
        case .saved: return text("登录凭证已保存", "Authentication saved in Keychain")
        case .missing: return text("尚未配置，可选", "Not configured, optional")
        case .error: return text("需要处理", "Action required")
        }
    }

    var advancedNetworkSummary: String {
        store.networkFilter.configured
            ? text("额外网络限制已开启", "Additional network restriction enabled")
            : text("额外网络限制与连接排查，可选", "Additional restriction and connection check, optional")
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

    @ViewBuilder func fixedExitRow(family: IPFamily, label: String, placeholder: String) -> some View {
        let availabilityKnown = store.activeFamilies != nil
        let available = family == .ipv4 || !availabilityKnown || store.activeFamilies?.contains(family) == true
        HStack(spacing: 10) {
            Label(label, systemImage: family == .ipv4 ? "4.circle" : "6.circle")
                .frame(width: 132, alignment: .leading)
            TextField(placeholder, text: Binding(
                get: { store.settings.fixedExit(for: family) },
                set: { store.settings.setFixedExit($0, for: family) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityIdentifier("fixed-exit-\(family.rawValue)")
            Button {
                Task { await store.adoptObservedExit(family: family) }
            } label: {
                Label(L("action.autoExit"), systemImage: "wand.and.stars")
            }
            .disabled(!available || store.monitoring || store.checking)
            if !available {
                Text(text("未启用，已关闭", "Disabled on this Mac"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!available || store.monitoring || store.checking)
    }

    @ViewBuilder func protectToggle(isOn: Binding<Bool>, icon: String, label: String, available: Bool, unavailableHint: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            if !available {
                Text(unavailableHint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { available && isOn.wrappedValue },
                set: { guard available else { return }; isOn.wrappedValue = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!available)
        }
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
            GuardCard(title: L("card.cleanup"), subtitle: text("先检测，再勾选需要清理的项目。", "Scan, then select what to clean.")) {
                Text(text("仅检查 Claude 的缓存和日志，保留对话、配置与登录信息。清理会移到废纸篓，可从中恢复。建议先退出 Claude。", "Checks only Claude caches and logs, preserving conversations, settings and sign-in data. Selected items move to Trash and can be restored. Quit Claude first."))
                    .font(.callout).foregroundStyle(.secondary)
                Button { store.refreshCleanup() } label: {
                    Label(text("检测可清理项目", "Scan for cleanable items"), systemImage: "magnifyingglass")
                }.routekeeperProminentButton().disabled(store.cleanupBusy).accessibilityIdentifier("cleanup-open")
                if store.cleanupBusy { ProgressView().controlSize(.small) }
                if !store.cleanupResult.isEmpty { Text(store.cleanupResult).font(.callout).textSelection(.enabled) }
            }
            GuardCard(title: L("card.scope"), subtitle: text("仅显示本次检测发现的缓存和日志；勾选后才会清理。", "Only detected caches and logs appear here. Only selected items are cleaned.")) {
                if store.cleanupPlan == nil {
                    Text(text("点击上方检测，查看可清理项目。", "Scan above to see cleanable items.")).foregroundStyle(.secondary)
                } else if store.cleanupCandidates.isEmpty {
                    Label(text("未发现可清理的缓存或日志", "No caches or logs to clean"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    ForEach(store.cleanupCandidates) { target in
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: Binding(get: { store.cleanupSelection.contains(target.id) }, set: {
                                if $0 { store.cleanupSelection.insert(target.id) } else { store.cleanupSelection.remove(target.id) }
                            })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel(target.label)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(target.label).font(.callout.weight(.medium))
                                Text(abbreviateHome(target.path)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                Text(target.kind).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(ByteCountFormatter.string(fromByteCount: target.sizeBytes, countStyle: .file))
                                .font(.callout.monospacedDigit()).frame(width: 90, alignment: .trailing)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        Divider()
                    }
                    HStack {
                        Text(text("已选 \(store.selectedCleanupTargets.count) 项", "\(store.selectedCleanupTargets.count) selected")).font(.callout)
                        Spacer()
                        Button(text("将所选项目移到废纸篓", "Move selected items to Trash")) { store.runCleanup() }
                            .routekeeperProminentButton().tint(.orange)
                            .disabled(store.selectedCleanupTargets.isEmpty || store.cleanupBusy)
                            .accessibilityIdentifier("cleanup-confirm-run")
                    }
                }
            }.disabled(store.cleanupBusy)
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
            Text(text("关闭窗口后，应用会继续在后台运行。点击顶部菜单栏图标可重新打开面板；要完全退出，请在菜单中选择“退出”。",
                      "Closing the window keeps the app running in the menu bar. Open the panel from there, or choose Quit to exit completely."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            Text(text("自动体检会在 App 启动、网络变化及所选间隔到达时运行。为保护隐私，自动体检不会查询第三方 IP 信息；网络变化触发的体检会在自检恢复后执行。",
                      "Automatic checks run after launch, after network changes and at the selected interval. To protect privacy, they never query third-party intelligence. Network-change checks run after self-check recovery."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).tracking(-0.15)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
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
