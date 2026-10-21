import GuardCore
import SwiftUI

struct InspectionPage: View {
    @Bindable var store: GuardStore
    @Bindable var audit: EgressAuditController
    let onOpenNetworkSettings: () -> Void

    @AppStorage("routekeeper-egress-intelligence-v1") private var includeIntelligence = false
    @State private var showEgressDetails = false
    @State private var groupExpansionOverrides: [InspectionCheckGroupKind: Bool] = [:]

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryPanel
            if store.settings.gatewayProtectionMode != .off {
                GatewayVerificationPage(
                    controller: store.gatewayVerification,
                    mode: store.settings.gatewayProtectionMode,
                    onChangeMode: onOpenNetworkSettings
                )
            }
            if !attentionItems.isEmpty {
                attentionPanel
            }
            resultGroupsPanel
            egressDetailsPanel
            boundaryNote
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: summarySymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(summaryColor)
                    .frame(width: 46, height: 46)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(summaryTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.25)
                    Text(summarySubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if store.checking || audit.busy {
                    ProgressView().controlSize(.small)
                }
            }

            AppHairline()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let snapshot = store.snapshot {
                        Text(text("自检 \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))",
                                  "Self-check \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))"))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L("capsule.noCheck")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let report = audit.report {
                        Text(text("出口 \(report.auditedAt.formatted(date: .omitted, time: .shortened)) · \(audit.lastRunTrigger?.title ?? "体检")",
                                  "Egress \(report.auditedAt.formatted(date: .omitted, time: .shortened)) · \(audit.lastRunTrigger?.title ?? "check")"))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if store.monitoring {
                    Text(text("监控中自动核验", "Monitoring checks automatically"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(action: onOpenNetworkSettings) {
                        Label(text("网络保护", "Network protection"), systemImage: "shield.lefthalf.filled")
                    }
                    .routekeeperSecondaryButton()
                    .accessibilityIdentifier("inspection-open-network-settings")
                    Button {
                        Task { await runFullCheck() }
                    } label: {
                        Label(
                            store.checking || audit.busy
                                ? text("正在体检…", "Checking…")
                                : text("运行完整体检", "Run full check"),
                            systemImage: "waveform.path.ecg.rectangle"
                        )
                    }
                    .routekeeperProminentButton()
                    .controlSize(.large)
                    .disabled(store.checking || audit.busy)
                    .accessibilityIdentifier("inspection-run-full")
                }
                Menu {
                    Button(text("导出脱敏报告…", "Export redacted report…")) {
                        store.exportReport(redacted: true)
                    }
                    Button(text("导出原始报告…", "Export raw report…")) {
                        store.exportReport()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(store.snapshot == nil)
                .help(text("导出报告", "Export report"))
            }
        }
        .padding(22)
        .cardSurface(corner: 22)
    }

    private var attentionPanel: some View {
        GuardCard(
            title: text("需要处理", "Needs attention"),
            subtitle: text("先处理这些问题，再开启或继续监控。", "Resolve these before starting or continuing monitoring.")
        ) {
            VStack(spacing: 0) {
                ForEach(Array(attentionItems.prefix(4))) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.callout.weight(.semibold))
                            Text(row.nextStep).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    if row.id != attentionItems.prefix(4).last?.id {
                        AppHairline()
                    }
                }
            }
            Button {
                onOpenNetworkSettings()
            } label: {
                Label(text("打开网络保护", "Open network protection"), systemImage: "shield.lefthalf.filled")
            }
        }
    }

    private var attentionItems: [CheckItem] {
        allCheckItems.filter(\.needsAttention)
    }

    private var allCheckItems: [CheckItem] {
        (store.snapshot?.checks ?? []) + egressCheckItems
    }

    private var inspectionGroups: [InspectionCheckGroup] {
        InspectionCheckGrouping.groups(from: allCheckItems)
    }

    private var resultGroupsPanel: some View {
        GuardCard(
            title: text("检查结果", "Check results"),
            subtitle: resultGroupsSubtitle
        ) {
            if inspectionGroups.isEmpty {
                Text(L("checks.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(inspectionGroups.enumerated()), id: \.element.id) { index, group in
                        checkGroupRow(group)
                        if index < inspectionGroups.count - 1 {
                            AppHairline()
                        }
                    }
                }
            }
        }
    }

    private func checkGroupRow(_ group: InspectionCheckGroup) -> some View {
        let expanded = groupIsExpanded(group)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    groupExpansionOverrides[group.kind] = !expanded
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: group.kind.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Color.primary.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.kind.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(group.kind.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(groupLevelTitle(group.level))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(groupLevelColor(group.level))
                    Text(text("\(group.passedCount)/\(group.checks.count)", "\(group.passedCount)/\(group.checks.count)"))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inspection-group-\(group.kind.rawValue)")

            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.checks) { row in
                        CheckRow(row: row)
                            .padding(.vertical, 4)
                        if row.id != group.checks.last?.id {
                            AppHairline()
                        }
                    }
                }
                .padding(.leading, 44)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .transition(.opacity)
            }
        }
    }

    private func groupIsExpanded(_ group: InspectionCheckGroup) -> Bool {
        groupExpansionOverrides[group.kind]
            ?? group.checks.contains { $0.level != .passed }
    }

    private func groupLevelTitle(_ level: InspectionCheckGroupLevel) -> String {
        switch level {
        case .notRun: return text("未运行", "Not run")
        case .passed: return text("通过", "Passed")
        case .notice: return text("有提示", "Notice")
        case .unverified: return text("未验证", "Unverified")
        case .needsAttention: return text("需处理", "Needs attention")
        }
    }

    private func groupLevelColor(_ level: InspectionCheckGroupLevel) -> Color {
        switch level {
        case .passed: return appAccent
        case .needsAttention, .notice: return .orange
        case .unverified, .notRun: return .secondary
        }
    }

    private var resultGroupsSubtitle: String {
        guard !inspectionGroups.isEmpty else { return L("checks.empty") }
        let normal = inspectionGroups.filter { $0.level == .passed }.count
        let pending = inspectionGroups.count - normal
        if pending == 0 {
            return text("\(inspectionGroups.count) 个方面均正常", "\(inspectionGroups.count) areas are normal")
        }
        return text("\(inspectionGroups.count) 个方面 · \(normal) 正常 · \(pending) 需确认",
                    "\(inspectionGroups.count) areas · \(normal) normal · \(pending) need review")
    }

    private var egressCheckItems: [CheckItem] {
        guard let report = audit.report else {
            guard store.snapshot != nil else { return [] }
            return [
                CheckItem(
                    "egress-audit",
                    text("出口体检结论", "Egress assessment"),
                    text("尚未运行出口体检；本机自检不能替代外部出口与服务探测。",
                         "The egress check has not run. Local checks cannot replace external exit and service probes."),
                    .unknown
                )
            ]
        }

        var rows: [CheckItem] = []
        let findings = report.assessment.findings.map(\.localizedDescription)
        let assessmentDetail: String
        let assessmentLevel: CheckLevel
        switch report.assessment.level {
        case .clear:
            assessmentLevel = .passed
            assessmentDetail = text(
                "系统与代理出口、服务可达性和本地网络路径未发现明显冲突。",
                "No obvious conflict was found across exits, service reachability or local network paths."
            )
        case .attention:
            assessmentLevel = .warning
            assessmentDetail = findings.isEmpty
                ? text("出口体检发现需要核对的项目。", "The egress check found items to review.")
                : findings.prefix(3).joined(separator: "；")
        case .insufficient:
            assessmentLevel = .unknown
            assessmentDetail = findings.isEmpty
                ? text("部分出口证据不足；缺失结果不会被当作通过。",
                       "Some exit evidence is incomplete; missing results are not treated as a pass.")
                : findings.prefix(3).joined(separator: "；")
        }
        rows.append(CheckItem("egress-audit", text("出口体检结论", "Egress assessment"),
                              assessmentDetail, assessmentLevel))

        if report.services.isEmpty {
            rows.append(CheckItem(
                "egress-service",
                text("Claude 服务可达性", "Claude service reachability"),
                text("本次没有取得服务探测结果。", "No service probe result was available."),
                .unknown
            ))
        } else {
            let reached = report.services.filter(\.reachedTLS).count
            let level: CheckLevel = reached == report.services.count
                ? .passed
                : reached == 0 ? .failed : .warning
            rows.append(CheckItem(
                "egress-service",
                text("Claude 服务可达性", "Claude service reachability"),
                text("\(reached)/\(report.services.count) 条 HTTPS/TLS 探测完成连接。",
                     "\(reached)/\(report.services.count) HTTPS/TLS probes reached the service."),
                level
            ))
        }

        if let ipv6 = report.ipv6 {
            let item: (String, CheckLevel) = ipv6CheckSummary(ipv6)
            rows.append(CheckItem("egress-ipv6", text("IPv6 分流", "IPv6 routing"), item.0, item.1))
        }
        return rows
    }

    private func ipv6CheckSummary(_ report: IPv6EgressReport) -> (String, CheckLevel) {
        switch report.state {
        case .disabled:
            return (text("本机未启用可用 IPv6，本次没有形成 IPv6 分流路径。",
                         "No usable IPv6 is enabled, so no IPv6 split route was formed."), .passed)
        case .noClaudePath:
            return (text("未观察到 Claude 的 IPv6 可达路径。",
                         "No reachable Claude IPv6 path was observed."), .passed)
        case .tunneled:
            return (text("Claude IPv6 路径经过 TUN，系统与代理出口一致。",
                         "Claude IPv6 uses TUN and the system and proxy exits match."), .passed)
        case .tunnelUnconfirmed:
            return (text("Claude IPv6 经过 TUN，但代理路径未返回 IPv6 出口。",
                         "Claude IPv6 uses TUN, but the proxy path returned no IPv6 exit."), .warning)
        case .tunnelExitMismatch:
            return (text("IPv6 虽经过 TUN，但系统与代理公网出口不同。",
                         "IPv6 uses TUN, but the system and proxy public exits differ."), .failed)
        case .directExposure:
            return (text("Claude IPv6 可从物理接口直连，可能绕过仅匹配 IPv4 的规则。",
                         "Claude IPv6 is reachable through a physical interface and may bypass IPv4-only rules."), .failed)
        case .unknown:
            return (text("IPv6 路径或代理归属无法确认。",
                         "The IPv6 path or proxy ownership could not be confirmed."), .unknown)
        }
    }

    private var egressDetailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showEgressDetails.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text("完整出口证据", "Full egress evidence"))
                            .font(.callout.weight(.semibold))
                        Text(text("逐项出口、DNS/UDP、IPv6、服务可达性、时区与本机历史。",
                                  "Exit, DNS/UDP, IPv6, service reachability, time zone and local history evidence."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(showEgressDetails ? text("收起", "Hide") : text("查看", "View"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(appAccent)
                    Image(systemName: showEgressDetails ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .cardSurface(corner: 18)
            .accessibilityIdentifier("inspection-egress-details")

            if showEgressDetails {
                EgressAuditPage(store: store, audit: audit, embedded: true, compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var boundaryNote: some View {
        if let boundary = store.snapshot?.checks.first(where: { $0.id == "boundary" }) {
            Text(boundary.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var summaryTitle: String {
        if store.checking || audit.busy { return text("正在体检", "Checking") }
        guard let snapshot = store.snapshot else { return text("尚未体检", "Not checked yet") }
        if !snapshot.ready || audit.report?.assessment.level == .attention {
            return text("需要检查", "Needs attention")
        }
        if audit.report == nil {
            return text("自检通过，待出口体检", "Self-check passed; egress check pending")
        }
        if audit.report?.assessment.level == .insufficient {
            return text("部分项目未验证", "Some items are unverified")
        }
        return text("网络体检正常", "Network check passed")
    }

    private var summarySubtitle: String {
        if store.checking || audit.busy {
            return text("正在核对出口、DNS、UDP 与 Claude 服务可达性。",
                        "Checking exits, DNS, UDP and Claude service reachability.")
        }
        guard let snapshot = store.snapshot else {
            return text("运行一次完整体检后，这里会给出唯一结论和下一步。",
                        "Run a full check to get one verdict and a next action.")
        }
        if !snapshot.ready {
            return text("自检发现未通过或未知项目；展开下方详情查看检查详情。",
                        "Self-check found failed or unknown items. Expand the details below.")
        }
        if audit.report == nil {
            return text("本机自检已通过；运行完整体检可继续核对出口与服务可达性。",
                        "The local self-check passed. Run a full check to verify exits and service reachability.")
        }
        if audit.report?.assessment.level == .attention {
            return text("出口或服务探测发现需要核对的项目；详情已收起到下方。",
                        "Exit or service checks found items to review. Details are collapsed below.")
        }
        if audit.report?.assessment.level == .insufficient {
            return text("本机路径没有发现明显冲突，但部分出口结果不足，暂时无法判断。",
                        "No obvious local conflict was found, but some exit evidence is incomplete.")
        }
        return text("出口一致，DNS/UDP 与 Claude 服务探测未发现明显冲突。",
                    "Exits match, and DNS/UDP and Claude service checks found no obvious conflict.")
    }

    private var summarySymbol: String {
        if store.checking || audit.busy { return "arrow.triangle.2.circlepath" }
        if store.snapshot == nil { return "waveform.path.ecg.rectangle" }
        if store.snapshot?.ready != true || audit.report?.assessment.level == .attention { return "exclamationmark.shield.fill" }
        if audit.report == nil { return "checkmark.shield" }
        if audit.report?.assessment.level == .insufficient {
            return "questionmark.shield.fill"
        }
        return "checkmark.shield.fill"
    }

    private var summaryColor: Color {
        if store.checking || audit.busy { return .secondary }
        if store.snapshot == nil { return .secondary }
        if store.snapshot?.ready != true || audit.report?.assessment.level == .attention { return .orange }
        if audit.report?.assessment.level == .insufficient { return .secondary }
        return appAccent
    }

    private func runFullCheck() async {
        guard !store.monitoring, !store.checking, !audit.busy else { return }
        await store.check()
        guard let snapshot = await store.snapshotForEgressAudit(maxAge: 45) else { return }
        await audit.run(
            snapshot: snapshot,
            includeIntelligence: includeIntelligence,
            trigger: .manual
        )
    }
}
