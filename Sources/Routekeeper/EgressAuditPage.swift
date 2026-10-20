import SwiftUI
import AppKit
import Charts
import GuardCore

private let egressAccent = appAccent

struct EgressAuditPage: View {
    @Bindable var store: GuardStore
    @Bindable var audit: EgressAuditController
    var embedded = false
    @AppStorage("routekeeper-egress-intelligence-v1") private var includeIntelligence = false
    @State private var confirmClearHistory = false
    @State private var confirmClearReports = false
    @State private var copiedIPv6Guidance = false
    @State private var exportNotice = ""
    @State private var showDetails = false

    private func text(_ zh: String, _ en: String) -> String { L10n.resolvedEnglish ? en : zh }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !embedded {
                actionCard
            }
            if let report = audit.report {
                summaryCard(report)
                comparisonCard
                if embedded {
                    reportActionsCard(report)
                    advancedOptionsCard
                }
                detailsToggle
                if showDetails {
                    detailSections(report)
                }
            } else {
                emptyCard
                if embedded {
                    advancedOptionsCard
                }
            }
        }
        .confirmationDialog(text("清除本机出口历史？", "Clear local exit history?"),
                            isPresented: $confirmClearHistory) {
            Button(text("清除历史", "Clear history"), role: .destructive) { audit.clearHistory() }
        } message: {
            Text(text("只会删除 Routekeeper 保存在本机的出口 IP 历史，不影响 Claude 或网络设置。",
                      "Only Routekeeper's local exit-IP history is removed. Claude and network settings are unchanged."))
        }
        .confirmationDialog(text("清除最近两次体检报告？", "Clear the two most recent egress reports?"),
                            isPresented: $confirmClearReports) {
            Button(text("清除报告", "Clear reports"), role: .destructive) {
                audit.clearStoredResults()
            }
        } message: {
            Text(text("只删除本机保存的完整体检报告，不删除出口历史，也不修改网络设置。",
                      "Only locally stored egress reports are removed. Exit history and network settings are unchanged."))
        }
    }

    private func reportActionsCard(_ report: EgressAuditReport) -> some View {
        GuardCard(
            title: text("报告操作", "Report actions"),
            subtitle: text("导出当前脱敏报告，或清除本机保存的最近两次完整报告。",
                           "Export the current redacted report or clear the two most recent full reports stored on this Mac.")
        ) {
            HStack(spacing: 10) {
                Button {
                    exportRedacted(report)
                } label: {
                    Label(text("导出脱敏报告", "Export redacted report"),
                          systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("egress-export-redacted")

                Button(role: .destructive) {
                    confirmClearReports = true
                } label: {
                    Label(text("清除已保存报告", "Clear stored reports"),
                          systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("egress-clear-reports")

                Spacer(minLength: 0)
            }

            Text(text("脱敏报告会移除公网 IP、MAC 地址等可识别字段；原始报告仍只保存在本机。",
                      "The redacted report removes public IPs, MAC addresses and other identifying fields. Raw reports stay on this Mac."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            feedbackMessages
        }
    }

    private var advancedOptionsCard: some View {
        GuardCard(
            title: text("高级选项", "Advanced options"),
            subtitle: text("隐私相关设置独立于报告操作；自动体检始终不会查询第三方 IP 信息。",
                           "Privacy-sensitive settings are separate from report actions. Automatic checks never query third-party intelligence.")
        ) {
            Toggle(text("查询第三方 IP 信息", "Query third-party IP intelligence"),
                   isOn: $includeIntelligence)
                .toggleStyle(.switch)
                .accessibilityIdentifier("egress-advanced-options")
            Text(text("默认关闭。开启并手动运行体检后，出口 IP 会发送给 ipwho.is / ipapi.is；自动体检不会发送。",
                      "Off by default. When enabled and a manual check runs, the exit IP is sent to ipwho.is / ipapi.is. Automatic checks never send it."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var feedbackMessages: some View {
        if !audit.notice.isEmpty {
            Text(audit.notice).font(.callout).foregroundStyle(.orange)
        }
        if !exportNotice.isEmpty {
            Label(exportNotice, systemImage: exportNotice.contains(text("失败", "failed"))
                  ? "exclamationmark.circle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(exportNotice.contains(text("失败", "failed")) ? Color.orange : egressAccent)
        }
    }

    private var detailsToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showDetails.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(text("检查详情与历史记录", "Detailed evidence and history"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(text("展开查看各项检测结果、IP 信息和历史变化。",
                              "Explore network evidence, context and history without interrupting the assessment above."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(showDetails ? text("收起", "Hide") : text("查看", "View"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(appAccent)
                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(16)
        .cardSurface(corner: 18)
    }

    @ViewBuilder
    private func detailSections(_ report: EgressAuditReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            detailGroupHeader(
                title: text("网络检测结果", "Network evidence"),
                subtitle: text("出口一致性、IPv6 分流、DNS/UDP 泄漏与 Claude 服务可达性。",
                               "Exit consistency, IPv6 routing, DNS/UDP leaks and Claude service reachability."),
                symbol: "network"
            )
            exitCard(report)
            ipv6Card(report.ipv6)
            LeakEvidenceCard(report: report.leaks)
            serviceCard(report)
        }

        VStack(alignment: .leading, spacing: 12) {
            detailGroupHeader(
                title: text("上下文与历史", "Context and history"),
                subtitle: text("第三方 IP 信息、时区、使用提醒与本机出口变化记录。",
                               "Third-party intelligence, time zone, guidance and local exit history."),
                symbol: "clock.arrow.circlepath"
            )
            .padding(.top, 4)
            intelligenceCard(report)
            timeZoneCard(report)
            guidanceCard
            historyCard
            caveatCard
        }
    }

    private func detailGroupHeader(title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var actionCard: some View {
        GuardCard(title: text("Claude 出口体检", "Claude egress check"),
                  subtitle: text("检查出口一致性、服务可达性和可选的 IP 网络属性；不读取账号内容。",
                                 "Checks exit consistency, service reachability and optional IP attributes without reading account content.")) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        guard let snapshot = await store.snapshotForEgressAudit() else { return }
                        await audit.run(
                            snapshot: snapshot, includeIntelligence: includeIntelligence,
                            trigger: .manual
                        )
                    }
                } label: {
                    Label(audit.busy ? text("体检中…", "Checking…") : text("运行出口体检", "Run egress check"),
                          systemImage: "waveform.path.ecg.rectangle")
                }
                .routekeeperProminentButton()
                .disabled(audit.busy || store.checking)
                .accessibilityIdentifier("egress-run")
                if audit.busy || store.checking { ProgressView().controlSize(.small) }
                if let report = audit.report {
                    Button {
                        exportRedacted(report)
                    } label: {
                        Label(text("导出脱敏报告…", "Export redacted report…"),
                              systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("egress-export-redacted")
                }
                Spacer()
                if let report = audit.report {
                    Text((audit.lastRunTrigger?.title ?? text("体检", "Checked"))
                         + " · " + report.auditedAt.formatted(date: .abbreviated, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(text("查询第三方 IP 信息（会向外部服务发送出口 IP）",
                        "Query third-party IP intelligence (sends exit IP externally)"),
                   isOn: $includeIntelligence)
                .toggleStyle(.switch)
            Text(text("自动体检会在 App 启动后、网络变化后以及每 \(store.automaticEgressAuditIntervalMinutes) 分钟运行；自动体检始终不查询第三方 IP 信息。手动运行只使用 45 秒内的自检快照，过期会先自动复核。",
                      "Automatic checks run after launch, after network changes and every \(store.automaticEgressAuditIntervalMinutes) minutes. Automatic checks never query third-party intelligence. Manual checks use a snapshot no older than 45 seconds and refresh it first when needed."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !audit.notice.isEmpty {
                Text(audit.notice).font(.callout).foregroundStyle(.orange)
            }
            if !exportNotice.isEmpty {
                Label(exportNotice, systemImage: exportNotice.contains(text("失败", "failed"))
                      ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(exportNotice.contains(text("失败", "failed")) ? Color.orange : egressAccent)
            }
            Text(text("第三方 IP 信息默认关闭。只有打开上方开关并运行体检后，出口 IP 才会发送给 ipwho.is / ipapi.is。Claude 服务的 TLS 可达性探测始终由本机发起。",
                      "Third-party IP intelligence is off by default. The exit IP is sent to ipwho.is / ipapi.is only after enabling the switch and running a check. Claude TLS reachability probes always originate locally."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if audit.report != nil || audit.previousReport != nil {
                HStack {
                    Text(text("最近两次完整报告只保存在本机，可随时清除。",
                              "The two most recent full reports stay on this Mac and can be cleared at any time."))
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button(text("清除已保存报告", "Clear stored reports")) {
                        confirmClearReports = true
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var emptyCard: some View {
        GuardCard(title: text("尚未体检", "No egress check yet"),
                  subtitle: text("结果只描述本次网络观察，不读取 Claude 登录信息。",
                                 "Results describe this network observation only and do not read Claude sign-in data.")) {
            Label(text("运行后将显示 IPv4/IPv6、系统路径/代理路径、Claude 服务 TLS 连通性，以及可选的 ASN/国家/城市信息。",
                       "The result shows IPv4/IPv6, system and proxy paths, Claude TLS reachability, and optional ASN/country/city data."),
                  systemImage: "network")
                .foregroundStyle(.secondary)
        }
    }

    private func summaryCard(_ report: EgressAuditReport) -> some View {
        GuardCard(title: text("体检结论", "Assessment"),
                  subtitle: text("这是 Routekeeper 基于本次观测给出的有限提示，不是 Anthropic 官方风控或封号判断。",
                                 "A limited Routekeeper observation, not an Anthropic risk-control or account-action decision.")) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: assessmentSymbol(report.assessment.level))
                    .font(.title2)
                    .foregroundStyle(assessmentColor(report.assessment.level))
                VStack(alignment: .leading, spacing: 5) {
                    Text(assessmentTitle(report.assessment.level)).font(.headline)
                    Text(assessmentSubtitle(report.assessment.level))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if let drift = audit.drift {
                Label(text("出口已变化：上次 \(drift.previousIP)，本次 \(drift.currentIP)",
                           "Exit changed: \(drift.previousIP) → \(drift.currentIP)"),
                      systemImage: "arrow.triangle.swap")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }
            if !report.assessment.findings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.assessment.findings, id: \.self) { finding in
                        Label(findingText(finding), systemImage: finding == .thirdPartyDisabled ? "info.circle" : "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(finding == .thirdPartyDisabled ? Color.secondary : Color.orange)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var comparisonCard: some View {
        if let comparison = audit.comparison {
            GuardCard(
                title: text("与上次体检相比", "Compared with previous check"),
                subtitle: text("同一次安装内比较最近两次完整报告；所有数据只保存在本机。",
                               "Compares the two most recent full reports on this Mac. All data stays local.")
            ) {
                HStack {
                    Text(text("上次  ", "Previous  ")
                         + comparison.previousAuditedAt.formatted(date: .abbreviated, time: .shortened)
                         + " · " + assessmentTitle(comparison.previousLevel))
                    Spacer()
                    Text(text("本次  ", "Current   ")
                         + comparison.currentAuditedAt.formatted(date: .abbreviated, time: .shortened)
                         + " · " + assessmentTitle(comparison.currentLevel))
                }
                .font(.caption).foregroundStyle(.secondary)

                if !comparison.hasChanges {
                    Label(text("未发现可见变化", "No visible change"),
                          systemImage: "equal.circle.fill")
                        .foregroundStyle(egressAccent)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if comparison.previousPrimaryExit != comparison.currentPrimaryExit {
                            changeRow(
                                text("主出口", "Primary exit"),
                                from: comparison.previousPrimaryExit ?? text("未取得", "not observed"),
                                to: comparison.currentPrimaryExit ?? text("未取得", "not observed"),
                                warning: true
                            )
                        }
                        if comparison.previousCountryCode != comparison.currentCountryCode {
                            changeRow(
                                text("国家/地区", "Country/region"),
                                from: comparison.previousCountryCode ?? "—",
                                to: comparison.currentCountryCode ?? "—",
                                warning: true
                            )
                        }
                        if comparison.previousASN != comparison.currentASN {
                            changeRow(
                                text("ASN", "ASN"),
                                from: comparison.previousASN ?? "—",
                                to: comparison.currentASN ?? "—",
                                warning: true
                            )
                        }
                        if comparison.previousTimeZoneState != comparison.currentTimeZoneState {
                            changeRow(
                                text("出口时区", "Exit time zone"),
                                from: comparison.previousTimeZoneState.map(timeZoneShortTitle) ?? "—",
                                to: comparison.currentTimeZoneState.map(timeZoneShortTitle) ?? "—",
                                warning: comparison.currentTimeZoneState == .mismatch
                            )
                        }
                        if comparison.previousIPv6State != comparison.currentIPv6State {
                            changeRow(
                                text("IPv6 分流", "IPv6 routing"),
                                from: comparison.previousIPv6State?.rawValue ?? "—",
                                to: comparison.currentIPv6State?.rawValue ?? "—",
                                warning: true
                            )
                        }
                        ForEach(comparison.serviceReachabilityChanges) { change in
                            changeRow(
                                "\(change.target) · \(change.route.rawValue)",
                                from: change.previousReachedTLS ? text("TLS 可达", "TLS reached") : text("未连接", "not reached"),
                                to: change.currentReachedTLS ? text("TLS 可达", "TLS reached") : text("未连接", "not reached"),
                                warning: !change.currentReachedTLS
                            )
                        }
                        ForEach(comparison.addedFindings, id: \.self) { finding in
                            Label(text("新增：", "New: ") + findingText(finding),
                                  systemImage: "exclamationmark.circle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        ForEach(comparison.resolvedFindings, id: \.self) { finding in
                            Label(text("已消失：", "Resolved: ") + findingText(finding),
                                  systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(egressAccent)
                        }
                    }
                }
            }
        }
    }

    private func changeRow(_ title: String, from: String, to: String,
                           warning: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption.weight(.medium))
            Text(from).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Text(to).font(.system(.caption, design: .monospaced))
                .foregroundStyle(warning ? Color.orange : egressAccent)
            Spacer(minLength: 0)
        }
    }

    private func exitCard(_ report: EgressAuditReport) -> some View {
        GuardCard(title: text("出口一致性", "Exit consistency"),
                  subtitle: text("同一地址族的系统路径与显式代理路径应一致；只有一侧结果时不判为通过。",
                                 "System and explicit-proxy paths for the same family should match. One-sided evidence is not a pass.")) {
            VStack(spacing: 0) {
                ForEach(report.families) { family in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: family.family == .ipv4 ? "4.circle.fill" : "6.circle.fill")
                            .foregroundStyle(family.targetMismatch ? Color.orange : stateColor(family.state))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(family.family.displayName).font(.callout.weight(.semibold))
                                Text(family.targetMismatch ? text("与固定目标不一致", "target mismatch") : stateTitle(family.state))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(family.targetMismatch ? Color.orange : stateColor(family.state))
                            }
                            Text(text("系统路径  ", "System   ") + (family.directIP ?? text("未取得", "not observed")))
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(text("代理路径  ", "Proxy    ") + (family.proxiedIP ?? text("未配置/未取得", "not configured/observed")))
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            if let target = family.targetIP {
                                Text(text("固定目标  ", "Target   ") + target + (family.targetMismatch ? text(" · 不一致", " · mismatch") : ""))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(family.targetMismatch ? Color.orange : Color.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    if family.id != report.families.last?.id { Divider() }
                }
            }
            if let primary = report.primaryIP {
                Divider().padding(.vertical, 3)
                Text(text("当前主出口：", "Primary exit: ") + primary)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
            }
        }
    }

    private func serviceCard(_ report: EgressAuditReport) -> some View {
        GuardCard(title: text("Claude 服务可达性", "Claude service reachability"),
                  subtitle: text("以 HTTPS/TLS 是否建立为主；403、404 或 301 仍表示服务已到达。",
                                 "TLS establishment is the primary signal. 403, 404 and 301 still mean the service was reached.")) {
            VStack(spacing: 0) {
                ForEach(EgressAudit.serviceTargets, id: \.self) { target in
                    HStack(alignment: .top, spacing: 12) {
                        Text(target)
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .frame(width: 190, alignment: .leading)
                        serviceValue(probe(target: target, route: .system, in: report), title: text("系统", "System"))
                        if report.proxyConfigured {
                            serviceValue(probe(target: target, route: .proxy, in: report), title: text("代理", "Proxy"))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    if target != EgressAudit.serviceTargets.last { Divider() }
                }
            }
            Text(text("探测不包含登录操作，不代表账号当前可登录或订阅有效。HTTP 状态由服务端策略决定。",
                      "The probe does not sign in and does not prove that the account can log in or that a subscription is active. HTTP status is controlled by the server."))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func ipv6Card(_ report: IPv6EgressReport?) -> some View {
        GuardCard(title: text("IPv6 分流风险", "IPv6 split-routing risk"),
                  subtitle: text("检查 Claude 的 AAAA 记录是否从物理网络直连，以及 IPv6 是否真正经过同一代理/TUN。",
                                 "Checks whether Claude AAAA records connect through the physical network and whether IPv6 truly uses the same proxy/TUN path.")) {
            if let report {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: ipv6Symbol(report.state))
                        .font(.title3)
                        .foregroundStyle(ipv6Color(report.state))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ipv6Title(report.state)).font(.callout.weight(.semibold))
                        Text(ipv6Subtitle(report.state))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                if report.state != .disabled {
                    VStack(alignment: .leading, spacing: 4) {
                        if let local = report.localAddress {
                            Text(text("本机公网 IPv6  ", "Local public IPv6  ") + local)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        Text(text("系统路径出口  ", "System exit       ") + (report.systemPublicExit ?? text("未取得", "not observed")))
                            .font(.system(.caption, design: .monospaced))
                        Text(text("代理路径出口  ", "Proxy exit        ") + (report.proxyPublicExit ?? text("未取得", "not observed")))
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))

                    VStack(spacing: 0) {
                        ForEach(report.probes) { probe in
                            HStack(alignment: .top, spacing: 10) {
                                Text(probe.target)
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                                    .frame(width: 170, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    if probe.resolvedAddresses.isEmpty {
                                        Text(text("无 AAAA 记录", "No AAAA record"))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(probe.reachedTLS
                                             ? (probe.httpStatus.map { "HTTP \($0)" } ?? text("TLS 已连接", "TLS connected"))
                                             : (probe.failure ?? text("未连接", "not connected")))
                                            .foregroundStyle(probe.reachedTLS
                                                             ? (probe.reachedDirectly ? Color.orange : egressAccent)
                                                             : Color.secondary)
                                        Text(text("路由：", "Route: ") + (probe.routeInterface ?? text("未知", "unknown"))
                                             + (probe.remoteAddress.map { " · \($0)" } ?? ""))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.system(.caption, design: .monospaced))
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 7)
                            if probe.id != report.probes.last?.id { Divider() }
                        }
                    }
                }

                if [.directExposure, .tunnelUnconfirmed, .tunnelExitMismatch, .unknown].contains(report.state) {
                    Text(text("建议：不需要 IPv6 时，在代理客户端的 Claude 规则使用 ForceIPv4，或设置 ipv6: false；必须使用 IPv6 时，确保 AAAA 流量进入同一 TUN，且系统与代理 IPv6 出口一致。Routekeeper 不会自动修改代理配置。",
                              "Recommendation: when IPv6 is unnecessary, use ForceIPv4 for Claude rules or set ipv6: false in the proxy client. If IPv6 is required, ensure AAAA traffic enters the same TUN and system/proxy IPv6 exits match. Routekeeper does not modify proxy configuration."))
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        copyIPv6Guidance()
                    } label: {
                        Label(copiedIPv6Guidance
                              ? text("已复制排查建议", "Guidance copied")
                              : text("复制排查建议", "Copy guidance"),
                              systemImage: copiedIPv6Guidance ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityIdentifier("ipv6-copy-guidance")
                }
            } else {
                Text(text("本次报告没有 IPv6 分流数据，请重新运行体检。",
                          "This report has no IPv6 split-routing data. Rerun the check."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func intelligenceCard(_ report: EgressAuditReport) -> some View {
        GuardCard(title: text("IP 信息与风险提示", "IP network attributes and risk evidence"),
                  subtitle: text("第三方 IP 信息可能延迟、缺失或误判，不能替代 Claude 官方结论。",
                                 "Third-party intelligence can be delayed, incomplete or wrong and cannot replace an official Claude decision.")) {
            if includeIntelligence && report.intelligenceStatus == .disabled {
                Text(text("开关已打开；请重新运行体检以获取情报。",
                          "The switch is on. Rerun the egress check to fetch intelligence."))
                    .font(.callout).foregroundStyle(.orange)
            }
            switch report.intelligenceStatus {
            case .disabled:
                Text(text("未启用第三方查询。本次仅完成本机出口一致性、Claude TLS 可达性和本地历史检查。",
                          "Third-party lookup is disabled. Only local exit consistency, Claude TLS reachability and local history were checked."))
                    .font(.callout).foregroundStyle(.secondary)
            case .unavailable:
                Label(text("情报服务未返回可用数据。未取得风险证据不等于低风险。",
                           "No usable intelligence was returned. Missing risk evidence does not mean low risk."),
                      systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
            case .partial, .available:
                if report.intelligence.isEmpty {
                    Text(text("本次未取得 IP 情报。", "No IP intelligence was available."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.intelligence) { value in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(value.ip).font(.system(.callout, design: .monospaced).weight(.semibold))
                                if value.ip == report.primaryIP {
                                    Text(text("主出口", "Primary")).font(.caption.weight(.medium))
                                        .foregroundStyle(egressAccent)
                                }
                                Spacer()
                                Text(value.sources.joined(separator: " + "))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(intelligenceSummary(value))
                                .font(.callout).foregroundStyle(.secondary)
                            if value.hasRiskMetadata {
                                let flags = value.riskFlags
                                Text(flags.isEmpty
                                     ? text("情报源未标记 VPN/代理/Tor/滥用等属性。",
                                            "The source did not flag VPN/proxy/Tor/abuse attributes.")
                                     : text("情报标记：", "Intelligence flags: ") + flags.map(riskTitle).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(flags.isEmpty ? Color.secondary : Color.orange)
                            } else {
                                Text(text("该情报源未返回 VPN/代理/Tor/滥用等风险字段；不能据此推断安全。",
                                          "This source returned no VPN/proxy/Tor/abuse fields. This is not evidence of safety."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func timeZoneCard(_ report: EgressAuditReport) -> some View {
        GuardCard(
            title: text("系统时区与出口时区", "System and exit time zones"),
            subtitle: text("用于发现本机时间与代理出口地区明显不一致；只有启用第三方 IP 信息并取得主出口时区时才作判断。",
                           "Highlights a clear difference between this Mac and the proxy exit region. A verdict requires third-party intelligence with a primary-exit time zone.")
        ) {
            if let check = report.timeZone {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: timeZoneSymbol(check.state))
                        .font(.title3)
                        .foregroundStyle(timeZoneColor(check.state))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(timeZoneTitle(check.state)).font(.callout.weight(.semibold))
                        Text(timeZoneSubtitle(check))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("本机  ", "This Mac  ") + check.systemIdentifier
                         + " · " + timeZoneOffset(check.systemOffsetSeconds))
                    Text(text("出口  ", "Exit      ")
                         + (check.exitIdentifier ?? text("未取得", "not observed"))
                         + (check.exitOffsetSeconds.map { " · " + timeZoneOffset($0) } ?? ""))
                }
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                if check.state == .mismatch {
                    Text(text("建议：长期使用该出口时，将 macOS 时区调整为出口地区，或保持固定地区节点；不要在会话中频繁跨时区切换。",
                              "Recommendation: when using this exit long term, align the macOS time zone with the exit region or keep a fixed-region node. Avoid frequent cross-time-zone changes during a session."))
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(text("本次报告没有时区数据，请重新运行体检。",
                          "This report has no time-zone data. Rerun the check."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var guidanceCard: some View {
        GuardCard(title: text("使用提醒", "What to watch"),
                  subtitle: text("以下是根据网络检测结果给出的运维建议，不是规避账号风控的保证。",
                                 "Operational guidance based on network evidence, not a guarantee for account risk controls.")) {
            VStack(alignment: .leading, spacing: 12) {
                guidanceRow(
                    text("同一会话内尽量保持出口 IP、国家和 ASN 稳定；频繁切换地区或节点会制造额外异常信号。",
                         "Keep IP, country and ASN stable during a session. Frequent region or node changes create extra anomalies."),
                    symbol: "pin"
                )
                guidanceRow(
                    text("不需要 IPv6 时，优先让 Claude/Code 规则只解析 IPv4；IPv6 的 AAAA 路径更容易绕过只匹配 A 记录或域名的分流规则。",
                         "If IPv6 is unnecessary, prefer IPv4-only resolution for Claude/Code. AAAA paths can bypass rules that only match A records or domains."),
                    symbol: "arrow.left.arrow.right"
                )
                guidanceRow(
                    text("如情报标记数据中心、VPN、Tor 或滥用历史，优先确认节点来源；这些标记仍是第三方判断。",
                         "If intelligence flags datacenter, VPN, Tor or abuse history, verify the node source. These remain third-party judgments."),
                    symbol: "exclamationmark.shield"
                )
                guidanceRow(
                    text("DNS 与 UDP 最好和 TCP 主出口走同一节点；代理客户端的 DNS、TUN UDP 和 Fake-IP 设置需要分别核对。",
                         "Keep DNS and UDP on the same node as the primary TCP exit. Verify DNS, TUN UDP and Fake-IP settings separately in the proxy client."),
                    symbol: "point.3.connected.trianglepath.dotted"
                )
            }
            .font(.callout)
        }
    }

    private func guidanceRow(_ content: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 20)
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var historyCard: some View {
        GuardCard(title: text("本机出口历史", "Local exit history"),
                  subtitle: text("最多保留 20 条；同一 IP 在 30 分钟内重复体检会合并。",
                                 "Up to 20 entries; repeated checks of the same IP within 30 minutes are merged.")) {
            if audit.history.isEmpty {
                Text(text("暂无记录。完成一次能取得公网出口的体检后会记录 IP。",
                          "No entries yet. A successful exit observation will be recorded locally."))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(text("出口历史只保存在本机，不自动上传；其中含敏感 IP 信息。",
                              "Exit history stays on this Mac and is not uploaded automatically. It contains sensitive IP data."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(text("清除历史", "Clear history"), role: .destructive) { confirmClearHistory = true }
                }
                if audit.history.count >= 2 {
                    historyChart
                }
                VStack(spacing: 0) {
                    ForEach(audit.history.prefix(8)) { entry in
                        HStack(spacing: 12) {
                            Text(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: 128, alignment: .leading)
                            Text(entry.ip).font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text([entry.countryCode, entry.city, entry.asn].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        if entry.id != audit.history.prefix(8).last?.id { Divider() }
                    }
                }
                if audit.history.count > 8 {
                    Text(text("另有 \(audit.history.count - 8) 条较早记录", "\(audit.history.count - 8) older entries"))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var historySeries: [String] {
        var seen: [String] = []
        for entry in audit.history.reversed() where !seen.contains(entry.ip) {
            seen.append(entry.ip)
        }
        return seen
    }

    private var historyPoints: [ExitHistoryPoint] {
        let labels = historySeries
        let indexes = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        return audit.history.reversed().compactMap { entry in
            guard let index = indexes[entry.ip] else { return nil }
            return ExitHistoryPoint(
                id: entry.id,
                capturedAt: entry.capturedAt,
                index: index,
                label: text("出口 ", "Exit ") + alphabeticLabel(index)
            )
        }
    }

    private var historyChart: some View {
        let labels = historySeries.enumerated().map { text("出口 ", "Exit ") + alphabeticLabel($0.offset) }
        let colors: [Color] = [
            egressAccent,
            Color(red: 0.90, green: 0.48, blue: 0.16),
            Color(red: 0.17, green: 0.45, blue: 0.75),
            Color(red: 0.72, green: 0.35, blue: 0.28),
            Color(red: 0.43, green: 0.57, blue: 0.22),
            Color(red: 0.67, green: 0.43, blue: 0.18)
        ]
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(text("出口变化时间线", "Exit timeline")).font(.caption.weight(.semibold))
                Spacer()
                Text(text("\(labels.count) 个不同出口 · \(audit.history.count) 次记录",
                          "\(labels.count) exits · \(audit.history.count) observations"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Chart(historyPoints) { point in
                LineMark(
                    x: .value(text("时间", "Time"), point.capturedAt),
                    y: .value(text("出口", "Exit"), point.index)
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(by: .value(text("出口序列", "Exit series"), point.label))
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value(text("时间", "Time"), point.capturedAt),
                    y: .value(text("出口", "Exit"), point.index)
                )
                .symbolSize(26)
                .foregroundStyle(by: .value(text("出口序列", "Exit series"), point.label))
            }
            .chartYScale(domain: -0.5...(Double(max(1, labels.count)) - 0.5))
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .chartForegroundStyleScale(
                domain: labels,
                range: labels.indices.map { colors[$0 % colors.count] }
            )
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                }
            }
            .frame(height: 155)
            Text(text("图表只显示替代标签，真实 IP 仍仅保存在本机下方记录中。",
                      "The chart uses replacement labels only. Real IPs remain solely in the local records below."))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    private var caveatCard: some View {
        Text(text("边界：Routekeeper 不读取 Claude Cookie、认证 Token 或对话内容，也不复刻浏览器 Canvas/WebGL 指纹。出口体检与 Claude 服务可达性探测不能证明账号没有被限制，也不能预测封号；网络波动、Cloudflare 验证和第三方 IP 信息缺失都可能造成误判。",
                  "Boundary: Routekeeper does not read Claude cookies, auth tokens or conversations, and does not replicate browser Canvas/WebGL fingerprints. This check cannot prove an account is unrestricted or predict account actions. Network failures, Cloudflare challenges and missing third-party intelligence can all cause false conclusions."))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func serviceValue(_ probe: EgressServiceProbe?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            if let probe {
                if probe.reachedTLS {
                    Text((probe.httpStatus.map { "HTTP \($0)" } ?? text("TLS 已连接", "TLS connected"))
                         + (probe.tlsMilliseconds.map { " · TLS \($0) ms" } ?? ""))
                        .foregroundStyle(egressAccent)
                } else {
                    Text(probe.failure ?? text("未连接", "Not connected"))
                        .foregroundStyle(.orange)
                }
            } else {
                Text(text("未测试", "Not tested")).foregroundStyle(.secondary)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func probe(target: String, route: EgressRouteKind, in report: EgressAuditReport) -> EgressServiceProbe? {
        report.services.first { $0.target == target && $0.route == route }
    }

    private func intelligenceSummary(_ value: IPIntelligence) -> String {
        let location = [value.country, value.region, value.city].compactMap { $0 }.filter { !$0.isEmpty }
        let network = [value.asn, value.organization ?? value.isp].compactMap { $0 }.filter { !$0.isEmpty }
        let timezone = value.timezone.map { [text("时区：", "Timezone: ") + $0] } ?? []
        return (location + network + timezone).joined(separator: " · ")
    }

    private func ipv6Title(_ state: IPv6ExposureState) -> String {
        switch state {
        case .disabled: return text("未启用公网 IPv6", "Public IPv6 is not enabled")
        case .noClaudePath: return text("未观察到 Claude IPv6 直连", "No Claude IPv6 path observed")
        case .tunneled: return text("IPv6 经 TUN，系统与代理出口一致", "IPv6 is tunneled with matching exits")
        case .tunnelUnconfirmed: return text("IPv6 经 TUN，代理出口未确认", "IPv6 is tunneled, but proxy exit is unconfirmed")
        case .tunnelExitMismatch: return text("IPv6 系统与代理出口不一致", "IPv6 system and proxy exits differ")
        case .directExposure: return text("发现 IPv6 物理网络直连", "Physical IPv6 path detected")
        case .unknown: return text("IPv6 路径无法确认", "IPv6 path is uncertain")
        }
    }

    private func ipv6Subtitle(_ state: IPv6ExposureState) -> String {
        switch state {
        case .disabled:
            return text("本机没有可用的公网 IPv6 地址；Claude 的 AAAA 不会形成可用的旁路。",
                        "This Mac has no usable public IPv6 address, so Claude AAAA records cannot form a usable bypass.")
        case .noClaudePath:
            return text("本机启用了 IPv6，但本次没有取得可连接的 Claude IPv6 路径。没有观察到泄漏不等于分流配置一定正确。",
                        "IPv6 is enabled, but no reachable Claude IPv6 path was observed. No observed leak does not prove split routing is correct.")
        case .tunneled:
            return text("Claude IPv6 TLS 经 utun，且系统与代理 IPv6 公网出口一致。",
                        "Claude IPv6 TLS traverses utun, and system and proxy IPv6 public exits match.")
        case .tunnelUnconfirmed:
            return text("Claude IPv6 TLS 经 utun，但代理路径没有返回 IPv6 出口，无法证明同一节点。",
                        "Claude IPv6 TLS traverses utun, but the proxy path returned no IPv6 exit, so the same node cannot be proven.")
        case .tunnelExitMismatch:
            return text("Claude IPv6 经 utun，但系统路径与代理路径得到不同公网 IPv6 出口。",
                        "Claude IPv6 traverses utun, but system and proxy paths expose different public IPv6 exits.")
        case .directExposure:
            return text("至少一个 Claude IPv6 TLS 请求从非 utun 接口成功直连。这可能绕过 IPv4 代理规则。",
                        "At least one Claude IPv6 TLS request succeeded through a non-utun interface. This can bypass IPv4 proxy rules.")
        case .unknown:
            return text("取得 AAAA 或 TLS 结果，但无法确认路由接口与代理归属。",
                        "AAAA or TLS evidence exists, but the route interface and proxy ownership cannot be confirmed.")
        }
    }

    private func ipv6Color(_ state: IPv6ExposureState) -> Color {
        switch state {
        case .disabled, .tunneled: return egressAccent
        case .noClaudePath: return .secondary
        case .tunnelUnconfirmed, .tunnelExitMismatch, .directExposure, .unknown: return .orange
        }
    }

    private func ipv6Symbol(_ state: IPv6ExposureState) -> String {
        switch state {
        case .disabled, .tunneled: return "checkmark.shield.fill"
        case .noClaudePath: return "info.circle"
        case .tunnelUnconfirmed, .unknown: return "questionmark.circle.fill"
        case .tunnelExitMismatch, .directExposure: return "exclamationmark.shield.fill"
        }
    }

    private func copyIPv6Guidance() {
        let value = text(
            "Routekeeper IPv6 排查建议\n1. 不需要 IPv6 时，在代理客户端将 Claude 规则设为 ForceIPv4，或设置 ipv6: false。\n2. 必须使用 IPv6 时，确认 Claude 的 AAAA 流量进入同一 TUN。\n3. 比较系统 IPv6 出口与代理 IPv6 出口，二者应一致。\n4. 修改后退出 Claude，重新运行 Routekeeper 出口体检。\n\n注意：这是网络排查建议，不代表 Anthropic 官方风控结论。",
            "Routekeeper IPv6 guidance\n1. If IPv6 is unnecessary, set ForceIPv4 for Claude rules or set ipv6: false in the proxy client.\n2. If IPv6 is required, ensure Claude AAAA traffic enters the same TUN.\n3. Compare system and proxy IPv6 exits; they should match.\n4. Quit Claude after changes and rerun the Routekeeper egress check.\n\nNote: operational guidance only, not an Anthropic risk-control decision."
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedIPv6Guidance = true
    }

    private func exportRedacted(_ report: EgressAuditReport) {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "Routekeeper-egress-redacted-\(formatter.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "unknown"
            let data = try EgressReportExport.redactedData(
                report: report, history: audit.history, appVersion: version
            )
            try data.write(to: url, options: .atomic)
            exportNotice = text(
                "脱敏报告已导出：IP 已替换为固定标签，不包含本地路径或账号数据。",
                "Redacted report exported. IPs use stable labels; local paths and account data are excluded."
            )
        } catch {
            exportNotice = text("脱敏报告导出失败：", "Redacted report export failed: ")
                + error.localizedDescription
        }
    }

    private func alphabeticLabel(_ index: Int) -> String {
        guard index >= 0, index < 26, let scalar = UnicodeScalar(65 + index) else {
            return "\(index + 1)"
        }
        return String(Character(scalar))
    }

    private func timeZoneTitle(_ state: EgressTimeZoneState) -> String {
        switch state {
        case .disabled: return text("未启用出口时区检查", "Exit time-zone check is disabled")
        case .unverified: return text("出口时区未取得，不能判断", "Exit time zone unavailable; no verdict")
        case .consistent: return text("系统与出口时区偏移一致", "System and exit offsets match")
        case .mismatch: return text("系统与出口时区不一致", "System and exit time zones differ")
        }
    }

    private func timeZoneShortTitle(_ state: EgressTimeZoneState) -> String {
        switch state {
        case .disabled: return text("未启用", "disabled")
        case .unverified: return text("未取得", "unverified")
        case .consistent: return text("一致", "consistent")
        case .mismatch: return text("不一致", "mismatch")
        }
    }

    private func timeZoneSubtitle(_ check: EgressTimeZoneCheck) -> String {
        switch check.state {
        case .disabled:
            return text("第三方 IP 信息默认关闭。打开体检页上方的情报开关并重新体检后，才能读取主出口时区。",
                        "Third-party intelligence is off by default. Enable it above and rerun the check to read the primary exit time zone.")
        case .unverified:
            return text("情报已请求，但主出口没有返回可识别的时区；缺失结果不能当作一致。",
                        "Intelligence was requested, but the primary exit returned no recognizable time zone. Missing evidence is not a match.")
        case .consistent:
            return text("标识名称可以不同，只要当前 UTC 偏移一致就不提示时区差异。",
                        "Identifiers may differ; no warning is raised when the current UTC offsets match.")
        case .mismatch:
            let hours = check.offsetDifferenceHours ?? 0
            let value = hours.rounded() == hours ? "\(Int(hours))" : String(format: "%.1f", hours)
            return text("当前相差 \(value) 小时。这个结果不是封号判断，但长期跨时区使用会制造额外一致性信号。",
                        "The current offsets differ by \(value) hours. This is not an account-action decision, but persistent cross-zone use creates an extra consistency signal.")
        }
    }

    private func timeZoneColor(_ state: EgressTimeZoneState) -> Color {
        switch state {
        case .consistent: return egressAccent
        case .mismatch, .unverified: return .orange
        case .disabled: return .secondary
        }
    }

    private func timeZoneSymbol(_ state: EgressTimeZoneState) -> String {
        switch state {
        case .consistent: return "checkmark.circle.fill"
        case .mismatch: return "exclamationmark.triangle.fill"
        case .unverified: return "questionmark.circle.fill"
        case .disabled: return "info.circle"
        }
    }

    private func timeZoneOffset(_ seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        return String(format: "UTC%@%02d:%02d", sign, absolute / 3_600, absolute % 3_600 / 60)
    }

    private func stateTitle(_ state: EgressFamilyState) -> String {
        switch state {
        case .consistent: return text("一致", "consistent")
        case .incomplete: return text("检测结果不完整", "incomplete")
        case .mismatch: return text("不一致", "mismatch")
        case .notObserved: return text("未观察到出口", "not observed")
        }
    }

    private func stateColor(_ state: EgressFamilyState) -> Color {
        switch state {
        case .consistent: return egressAccent
        case .incomplete, .mismatch: return .orange
        case .notObserved: return .secondary
        }
    }

    private func assessmentTitle(_ level: EgressAssessmentLevel) -> String {
        switch level {
        case .clear: return text("本次未发现明显不一致", "No obvious inconsistency found")
        case .attention: return text("有项目需要检查", "Items need attention")
        case .insufficient: return text("结果不足，暂时无法判断，不能判断", "Insufficient evidence")
        }
    }

    private func assessmentSubtitle(_ level: EgressAssessmentLevel) -> String {
        switch level {
        case .clear:
            return text("出口与本机服务探测没有显示明显冲突；这不等于 Claude 官方认可该网络或账号。",
                        "Exit and service probes show no obvious conflict. This does not mean Claude officially accepts the network or account.")
        case .attention:
            return text("请先核对出口一致性、节点稳定性和 Claude 服务可达性，再决定是否继续使用当前网络。",
                        "Review exit consistency, node stability and Claude service reachability before continuing with this network.")
        case .insufficient:
            return text("未能取得代理和系统连接的完整出口 IP，请稍后重新检查。",
                        "There is not enough two-sided exit evidence. Missing results are not a pass.")
        }
    }

    private func assessmentSymbol(_ level: EgressAssessmentLevel) -> String {
        switch level {
        case .clear: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.shield.fill"
        case .insufficient: return "questionmark.circle.fill"
        }
    }

    private func assessmentColor(_ level: EgressAssessmentLevel) -> Color {
        switch level {
        case .clear: return egressAccent
        case .attention: return .orange
        case .insufficient: return .secondary
        }
    }

    private func findingText(_ finding: EgressFinding) -> String {
        switch finding {
        case .exitMismatch:
            return text("同一地址族的系统出口与代理出口不同，或与固定目标不一致。",
                        "System and proxy exits differ, or an exit does not match the fixed target.")
        case .incompleteExitEvidence:
            return text("只有一个路径取得出口，无法证明两路一致。",
                        "Only one path produced an exit; consistency cannot be proven.")
        case .noObservedExit:
            return text("本次没有观察到公网出口。", "No public exit was observed.")
        case .serviceUnreachable:
            return text("至少一个 Claude 服务未完成 TLS 连接。",
                        "At least one Claude service did not establish TLS.")
        case .countryMismatch:
            return text("不同出口 IP 的国家/地区情报不一致。",
                        "Countries or regions differ across observed exit IPs.")
        case .asnMismatch:
            return text("不同出口 IP 的 ASN 不一致，可能经过不同网络。",
                        "Observed exit IPs use different ASNs and may traverse different networks.")
        case .datacenterNetwork:
            return text("情报将主出口标记为数据中心/机房网络。这可能触发额外验证，但不是封号结论。",
                        "The primary exit is flagged as datacenter/hosting. This may trigger extra verification, not an account-action decision.")
        case .proxySignal:
            return text("情报将主出口标记为代理网络。", "The primary exit is flagged as a proxy network.")
        case .vpnSignal:
            return text("情报将主出口标记为 VPN 网络。", "The primary exit is flagged as a VPN network.")
        case .torSignal:
            return text("情报将主出口标记为 Tor 网络。", "The primary exit is flagged as Tor.")
        case .abuseSignal:
            return text("情报源记录了该主出口的滥用历史。", "The intelligence source reports abuse history for the primary exit.")
        case .crawlerSignal:
            return text("情报将主出口标记为爬虫/自动化流量。", "The primary exit is flagged as crawler/automation traffic.")
        case .mobileNetwork:
            return text("主出口被识别为移动网络；这本身不是错误。", "The primary exit is identified as mobile; this alone is not an error.")
        case .bogonAddress:
            return text("主出口被标记为保留或无效公网地址。", "The primary exit is flagged as bogon or non-public.")
        case .riskIntelligenceUnavailable:
            return text("风险情报未完整返回；缺失不等于安全。",
                        "Risk intelligence was incomplete. Missing evidence is not safety.")
        case .thirdPartyDisabled:
            return text("第三方风险情报未启用；没有查询 VPN、Tor 或滥用标记。",
                        "Third-party risk intelligence is disabled; VPN, Tor and abuse flags were not queried.")
        case .ipv6DirectExposure:
            return text("Claude IPv6 可从物理网络接口直连，可能绕过只匹配 IPv4 的代理规则。",
                        "Claude IPv6 is reachable through a physical interface and may bypass IPv4-only proxy rules.")
        case .ipv6TunnelExitMismatch:
            return text("IPv6 虽经 TUN，但系统路径与代理路径的公网出口不同。",
                        "IPv6 traverses TUN, but system and proxy paths expose different public exits.")
        case .ipv6ProxyUnconfirmed:
            return text("IPv6 经 TUN，但代理路径未返回 IPv6 出口，无法证明同一节点。",
                        "IPv6 traverses TUN, but the proxy path returned no IPv6 exit, so the same node is unconfirmed.")
        case .ipv6PathUnknown:
            return text("IPv6 路径或代理归属无法确认。", "The IPv6 path or proxy ownership is uncertain.")
        case .dnsPathLeakSuspected:
            return text("系统 DNS 路由可能未经过预期 TUN/代理路径。",
                        "System DNS routing may not use the expected TUN/proxy path.")
        case .dnsPathUnverified:
            return text("DNS 路由或响应未取得完整证据；不能当作无泄漏。",
                        "DNS route or response evidence is incomplete and cannot be treated as leak-free.")
        case .udpExitMismatch:
            return text("STUN/UDP 观测到与 TCP 主出口不同的地址族出口，可能存在 UDP 旁路。",
                        "STUN/UDP exposed a different exit from the primary TCP exit, suggesting a possible UDP bypass.")
        case .udpExitUnverified:
            return text("UDP 出口未取得完整证据；超时或不支持不等于安全。",
                        "UDP exit evidence is incomplete. Timeout or lack of support is not safety.")
        case .dualStackFallbackSuspected:
            return text("连续双栈连接出现地址族切换、首连失败或明显变慢，可能存在 IPv6 回退。",
                        "Consecutive dual-stack connections switched families, failed first or slowed significantly, suggesting possible IPv6 fallback.")
        case .timeZoneMismatch:
            return text("本机系统时区与主出口时区偏移不同。建议核对时区设置，避免长期跨时区使用同一账号。",
                        "The system and primary-exit UTC offsets differ. Review the time-zone setting and avoid long-term cross-zone use of the same account.")
        case .timeZoneUnverified:
            return text("未取得可识别的出口时区；不能将缺失结果当作一致。",
                        "No recognizable exit time zone was obtained. Missing evidence is not a match.")
        }
    }

    private func riskTitle(_ flag: EgressRiskFlag) -> String {
        switch flag {
        case .datacenter: return text("数据中心", "datacenter")
        case .proxy: return text("代理", "proxy")
        case .vpn: return text("VPN", "VPN")
        case .tor: return text("Tor", "Tor")
        case .abuser: return text("滥用记录", "abuse history")
        case .crawler: return text("爬虫", "crawler")
        case .mobile: return text("移动网络", "mobile")
        case .bogon: return text("非公网地址", "bogon")
        }
    }
}

private struct LeakEvidenceCard: View {
    let report: LeakEgressReport?

    private func text(_ zh: String, _ en: String) -> String { L10n.resolvedEnglish ? en : zh }

    var body: some View {
        GuardCard(
            title: text("DNS、UDP 与双栈路径", "DNS, UDP and dual-stack path"),
            subtitle: text("检查系统 DNS 路由、STUN/UDP 出口是否与 TCP 出口一致，以及连续两次双栈连接的地址族和耗时。",
                           "Checks system DNS routes, whether STUN/UDP exits match TCP, and the family/timing of two consecutive dual-stack connections.")
        ) {
            if let report {
                evidenceRows(report)
                dualStackSection(report.dualStack)
                boundary
            } else {
                Text(text("本次报告没有 DNS/UDP/双栈数据，请重新运行体检。",
                          "This report has no DNS/UDP/dual-stack data. Rerun the check."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func evidenceRows(_ report: LeakEgressReport) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let dns = report.dns {
                evidenceRow(dns)
            } else {
                Text(text("DNS：未执行", "DNS: not run"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if report.udpChecks.isEmpty {
                Text(text("STUN/UDP：没有启用的地址族可测试", "STUN/UDP: no enabled address family to test"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(report.udpChecks) { check in
                    evidenceRow(check)
                }
            }
        }
    }

    private func evidenceRow(_ evidence: EgressCheckEvidence) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: evidenceSymbol(evidence.level))
                .foregroundStyle(evidenceColor(evidence.level))
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(evidence.title).font(.system(.callout, design: .monospaced).weight(.medium))
                Text(evidence.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func dualStackSection(_ dual: DualStackFallbackReport?) -> some View {
        if let dual {
            Divider().padding(.top, 3)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: dual.fallbackSuspected ? "exclamationmark.triangle.fill" : "arrow.left.arrow.right.circle")
                    .foregroundStyle(dual.fallbackSuspected ? Color.orange : egressAccent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("双栈连接：", "Dual-stack connection: ") + dual.target)
                        .font(.callout.weight(.medium))
                    Text(dualStackSummary(dual))
                        .font(.caption)
                        .foregroundStyle(dual.fallbackSuspected ? Color.orange : Color.secondary)
                    HStack(spacing: 14) {
                        ForEach(dual.attempts) { attempt in
                            Text(attemptSummary(attempt))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(attempt.reachedTLS ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
        }
    }

    private var boundary: some View {
        Text(text("边界：DNS 仅测试当前全局解析器，不覆盖应用 DoH/分域 DNS；STUN 不等于完整 WebRTC；双栈检查是两次连续 HTTPS 尝试，不证明系统 Happy Eyeballs 的具体实现。未知或不完整结果不会当作通过。",
                  "Boundary: DNS tests only current global resolvers, not app DoH/split DNS. STUN is not a full WebRTC test. The dual-stack check uses two consecutive HTTPS attempts and does not prove the system's Happy Eyeballs behavior. Unknown or incomplete results are not a pass."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func dualStackSummary(_ dual: DualStackFallbackReport) -> String {
        if dual.fallbackSuspected {
            return text("检测到地址族切换、首连失败或明显变慢，可能存在 IPv6 → IPv4 回退。",
                        "A family switch, first-attempt failure or large delay was observed; an IPv6-to-IPv4 fallback is possible.")
        }
        return text("两次连接未观察到地址族切换或明显首连变慢。",
                    "No family switch or large first-attempt delay was observed across two connections.")
    }

    private func attemptSummary(_ attempt: DualStackAttempt) -> String {
        let family: String
        switch attempt.family {
        case .ipv4: family = "IPv4"
        case .ipv6: family = "IPv6"
        case nil: family = "—"
        }
        if attempt.reachedTLS {
            let time = attempt.totalMilliseconds.map { "\($0) ms" } ?? "TLS"
            return "#\(attempt.id) \(family) · \(time)"
        }
        return "#\(attempt.id) \(family) · \(attempt.failure ?? text("未连接", "failed"))"
    }

    private func evidenceSymbol(_ level: CheckLevel) -> String {
        switch level {
        case .passed: return "checkmark.circle.fill"
        case .warning, .unknown: return "questionmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private func evidenceColor(_ level: CheckLevel) -> Color {
        level == .passed ? egressAccent : .orange
    }
}

private struct ExitHistoryPoint: Identifiable {
    let id: UUID
    let capturedAt: Date
    let index: Int
    let label: String
}
