import GuardCore
import SwiftUI

enum InspectionContentMode {
    case full
    case statusOnly
    case resultsOnly
}

struct InspectionPage: View {
    @Bindable var store: GuardStore
    @Bindable var audit: EgressAuditController
    let onOpenNetworkSettings: () -> Void
    var contentMode: InspectionContentMode = .full
    var showsToolbar = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @AppStorage("routekeeper-egress-intelligence-v1") private var includeIntelligence = false
    @State private var showInspectionOptions = false
    @State private var showConnectionDiagnostics = false
    @State private var groupExpansionOverrides: [InspectionCheckGroupKind: Bool] = [:]
    @State private var toolbarOwner = UUID()

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if contentMode != .resultsOnly {
                statusCard
            }
            if contentMode != .statusOnly {
                if !passedChecks.isEmpty || presentation.outcome == .passed {
                    passedChecksSection
                }
                usageReminderSection
            }
        }
        .accessibilityIdentifier("inspection-page")
        .sheet(isPresented: $showInspectionOptions) {
            InspectionOptionsSheet(store: store)
        }
        .sheet(isPresented: $showConnectionDiagnostics) {
            InspectionDiagnosticsSheet(store: store)
        }
        .onAppear {
            if showsToolbar {
                RoutekeeperToolbarCoordinator.shared.setInspection(
                    owner: toolbarOwner,
                    label: text("更多操作", "More actions"),
                    entries: overflowActions
                )
            }
        }
        .onChange(of: overflowActionsSignature) { _, _ in
            if showsToolbar {
                RoutekeeperToolbarCoordinator.shared.setInspection(
                    owner: toolbarOwner,
                    label: text("更多操作", "More actions"),
                    entries: overflowActions
                )
            }
        }
        .onDisappear {
            if showsToolbar {
                RoutekeeperToolbarCoordinator.shared.clear(owner: toolbarOwner)
            }
        }
    }

    private var overflowActionsSignature: String {
        "\(store.snapshot != nil)|\(L10n.resolvedEnglish)"
    }

    private var overflowActions: [PageOverflowEntry] {
        [
            .action(PageOverflowAction(
                title: text("高级设置…", "Advanced settings…"),
                systemImage: "slider.horizontal.3"
            ) {
                showInspectionOptions = true
            }),
            .action(PageOverflowAction(
                title: text("连接排查…", "Connection diagnostics…"),
                systemImage: "network"
            ) {
                showConnectionDiagnostics = true
            }),
            .separator,
            .action(PageOverflowAction(
                title: text("导出脱敏报告…", "Export redacted report…"),
                systemImage: "square.and.arrow.up",
                isDisabled: store.snapshot == nil
            ) {
                store.exportReport(redacted: true)
            }),
            .action(PageOverflowAction(
                title: text("导出原始报告…", "Export raw report…"),
                systemImage: "doc.badge.arrow.up",
                isDisabled: store.snapshot == nil
            ) {
                store.exportReport()
            })
        ]
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 46, height: 46)
                    .background(
                        statusColor.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .routekeeperFont(.title2, weight: .semibold)
                        .tracking(-0.3)
                        .accessibilityAddTraits(.isHeader)
                    Text(statusSubtitle)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                HStack(spacing: 8) {
                    helpButton(
                        statusHelpSection,
                        label: text("打开网络体检帮助", "Open network check help")
                    )

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(text("正在体检", "Checking"))
                    }

                    if presentation.primaryAction != nil {
                        primaryActionButton
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }

            AppHairline()
            timestampLine

            if presentation.outcome == .attention || presentation.outcome == .incomplete {
                issuesContent
            }
        }
        .padding(20)
        .appSurface(.primary)
        .accessibilityIdentifier("inspection-status-card")
    }

    private var primaryActionButton: some View {
        Button {
            runPrimaryAction()
        } label: {
            Label(primaryActionTitle, systemImage: primaryActionSymbol)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .routekeeperProminentButton()
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isRunning || store.monitoring || !store.canRunNetworkInspection)
        .help(!store.canRunNetworkInspection
              ? text("结束沙箱会话后可运行网络检查", "End the sandbox session to run network checks")
              : store.monitoring
                ? text("监控中会自动核验", "Checks run automatically while monitoring")
                : primaryActionTitle)
        .accessibilityIdentifier("inspection-primary-action")
    }

    private var timestampLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .routekeeperFont(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(timestampText)
                .routekeeperFont(.caption, monospacedDigit: true)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if store.monitoring {
                Text(text("监控中自动核验", "Checks run automatically while monitoring"))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var issuesContent: some View {
        if case .gateway = presentation.primaryIssue {
            GatewayVerificationPage(
                controller: store.gatewayVerification,
                mode: store.settings.gatewayProtectionMode,
                onChangeMode: onOpenNetworkSettings,
                embedded: true,
                showsHeader: false,
                showsAction: false
            )
        }

        if !unresolvedChecks.isEmpty {
            issueRows
        } else if case .snapshot = presentation.primaryIssue {
            fallbackIssueRow(
                title: text("本机网络配置尚未满足严格结论", "Local network configuration is incomplete"),
                detail: store.snapshot?.failureSummary.isEmpty == false
                    ? store.snapshot?.failureSummary ?? ""
                    : text("请检查固定出口、保护对象、网络路径与 Claude 进程状态后重新体检。",
                           "Check fixed exits, protected apps, network paths and Claude processes, then run the check again."),
                symbol: "exclamationmark.circle.fill",
                color: appStatusWarning
            )
        } else if case .assessment = presentation.primaryIssue {
            fallbackIssueRow(
                title: text("出口检查尚未形成完整结论", "The egress check is incomplete"),
                detail: text("部分出口、DNS、UDP 或服务探测结果不足；缺失证据不会当作通过。",
                             "Some exit, DNS, UDP or service evidence is incomplete. Missing evidence is not treated as a pass."),
                symbol: "questionmark.circle.fill",
                color: audit.report?.assessment.level == .insufficient
                    ? appStatusWarning
                    : appStatusFailure
            )
        }
    }

    private var issueRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(unresolvedChecks.prefix(5))) { check in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: checkSymbol(check.level))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(check.level.routekeeperStatusColor)
                        .frame(width: 20)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.title)
                            .routekeeperFont(.callout, weight: .semibold)
                        Text(check.detail)
                            .routekeeperFont(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(check.nextStep)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)

                if check.id != unresolvedChecks.prefix(5).last?.id {
                    AppHairline()
                }
            }

            if unresolvedChecks.count > 5 {
                Text(text("另有 \(unresolvedChecks.count - 5) 项待确认。",
                          "\(unresolvedChecks.count - 5) more items need review."))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private func fallbackIssueRow(
        title: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).routekeeperFont(.callout, weight: .semibold)
                Text(detail)
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var passedChecksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AppSectionHeading(
                    title: text("已通过检查项", "Passed checks")
                )
                Spacer()
                Text(text("\(passedChecks.count) 项", "\(passedChecks.count) item\(passedChecks.count == 1 ? "" : "s")"))
                    .routekeeperFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            if passedGroups.isEmpty {
                Text(text("本次没有可确认的通过项。", "No checks could be confirmed as passed."))
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(passedGroups.enumerated()), id: \.element.id) { index, group in
                        checkGroupRow(group)
                        if index < passedGroups.count - 1 {
                            AppHairline()
                        }
                    }
                }
            }
        }
        .padding(20)
        .appSurface(.secondary)
        .accessibilityIdentifier("inspection-passed-checks")
    }

    private func checkGroupRow(_ group: InspectionCheckGroup) -> some View {
        let expanded = groupIsExpanded(group)
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    groupExpansionOverrides[group.kind] = !expanded
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: group.kind.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(appStatusSuccess)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.kind.title)
                            .routekeeperFont(.callout, weight: .semibold)
                        Text(group.kind.subtitle)
                            .routekeeperFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(text("\(group.passedCount)/\(group.checks.count)",
                              "\(group.passedCount)/\(group.checks.count)"))
                        .routekeeperFont(.caption, monospacedDigit: true)
                        .foregroundStyle(appStatusSuccess)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .routekeeperFont(.caption, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded
                                ? text("已展开", "Expanded")
                                : text("已收起", "Collapsed"))
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
                .padding(.leading, 32)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .transition(.opacity)
            }
        }
    }

    private var usageReminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AppSectionHeading(
                    title: text("使用提醒", "Before you rely on this")
                )
            }
            reminderRow(
                text(
                    "体检会向 ipify、ipinfo.io、Claude 跟踪地址、STUN 与系统 DNS 发送请求，这些服务会看到当前公网出口；未知或缺失结果不会当作通过。",
                    "Checks contact ipify, ipinfo.io, the Claude trace endpoint, STUN and system DNS. These services can see the current public exit; unknown or missing results are never treated as a pass."
                ),
                symbol: "network"
            )
            reminderRow(
                text(
                    "代理网关的严格结论只覆盖这台 Mac 当前网络会话；切换网络、节点、代理或系统设置后，旧证据会失效。",
                    "A strict gateway result covers only this Mac's current network session. Changing the network, node, proxy or system settings invalidates the evidence."
                ),
                symbol: "clock.arrow.circlepath"
            )
            if let boundary = store.snapshot?.checks.first(where: { $0.id == "boundary" }) {
                reminderRow(boundary.detail, symbol: "hand.raised")
            } else {
                reminderRow(
                    text(
                        "Routekeeper 不读取 Claude 的 Cookie、登录凭证或对话内容，也不保证匿名、绕过账号风控或预测账号限制。",
                        "Routekeeper does not read Claude cookies, sign-in credentials or conversations, and it cannot guarantee anonymity, bypass account risk controls or predict account restrictions."
                    ),
                    symbol: "hand.raised"
                )
            }
        }
        .padding(20)
        .appSurface(.secondary)
        .accessibilityIdentifier("inspection-usage-reminders")
    }

    private func reminderRow(_ content: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 18)
                .accessibilityHidden(true)
            Text(content)
                .routekeeperFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func helpButton(_ section: RoutekeeperHelpSection, label: String) -> some View {
        Button {
            RoutekeeperHelpNavigation.request(section)
            openWindow(id: "routekeeper-help")
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .help(label)
        .accessibilityLabel(label)
    }

    private var presentation: InspectionPresentationState {
        InspectionPresentationResolver.resolve(
            isRunning: isRunning,
            hasSnapshot: store.snapshot != nil,
            snapshotReady: store.snapshot?.ready == true,
            hasAuditReport: audit.report != nil,
            auditLevel: audit.report?.assessment.level,
            gatewayMode: store.settings.gatewayProtectionMode,
            gatewayStatus: gatewayStatus,
            checks: allCheckItems
        )
    }

    private var isRunning: Bool {
        store.checking || audit.busy || store.gatewayVerification.busy
    }

    private var gatewayStatus: GatewayVerificationStatus {
        store.gatewayVerification.status(for: store.settings.gatewayProtectionMode)
    }

    private var allCheckItems: [CheckItem] {
        (store.snapshot?.checks ?? []) + egressCheckItems
    }

    private var unresolvedChecks: [CheckItem] {
        InspectionPresentationResolver.unresolvedChecks(from: allCheckItems)
    }

    private var passedChecks: [CheckItem] {
        InspectionPresentationResolver.passedChecks(from: allCheckItems)
    }

    private var passedGroups: [InspectionCheckGroup] {
        InspectionCheckGrouping.groups(from: passedChecks)
    }

    private var primaryCheck: CheckItem? {
        guard case let .check(id, _) = presentation.primaryIssue else { return nil }
        return allCheckItems.first { $0.id == id }
    }

    private var statusTitle: String {
        switch presentation.outcome {
        case .running:
            return text("正在体检", "Checking")
        case .notRun:
            return text("网络体检", "Network check")
        case .passed:
            return text("网络体检通过", "Network check passed")
        case .attention, .incomplete:
            switch presentation.primaryIssue {
            case let .gateway(status):
                return GatewayVerificationPage.title(for: status)
            case .check:
                if unresolvedChecks.count > 1 {
                    return text(
                        "发现 \(unresolvedChecks.count) 项待处理问题",
                        "\(unresolvedChecks.count) items need attention"
                    )
                }
                return unresolvedGroupKinds.first?.title
                    ?? primaryCheck?.title
                    ?? text("网络体检需要处理", "Network check needs attention")
            case .assessment:
                if audit.report == nil {
                    return text("出口体检尚未完成", "Egress check is incomplete")
                }
                return audit.report?.assessment.level == .insufficient
                    ? text("出口证据不足", "Insufficient egress evidence")
                    : text("出口检查需要确认", "Egress check needs review")
            case .snapshot:
                return text("本机网络配置需处理", "Local network configuration needs attention")
            case nil:
                return text("网络体检需要处理", "Network check needs attention")
            }
        }
    }

    private var statusSubtitle: String {
        switch presentation.outcome {
        case .running:
            return text("正在核对出口、DNS、UDP 与 Claude 服务可达性。",
                        "Checking exits, DNS, UDP and Claude service reachability.")
        case .notRun:
            return text("运行一次完整体检，核对本机网络路径与 Claude 出口。",
                        "Run a full check to verify the local network path and Claude egress.")
        case .passed:
            return text("出口一致，DNS、UDP 与 Claude 服务探测未发现明显冲突。",
                        "Exits match, and DNS, UDP and Claude service checks found no obvious conflict.")
        case .attention, .incomplete:
            switch presentation.primaryIssue {
            case .gateway:
                return text(
                    "详细流程请点击问号查看。",
                    "Open Help for the full verification flow."
                )
            case .check:
                if unresolvedChecks.count > 1 {
                    let separator = L10n.resolvedEnglish ? ", " : "、"
                    let areas = unresolvedGroupKinds.map(\.title).joined(separator: separator)
                    return text(
                        "涉及\(areas)；具体检查结果与下一步见下方。",
                        "Affects \(areas). Review the findings and next steps below."
                    )
                }
                return text(
                    "该区域的检查结果与下一步见下方。",
                    "Review this area's findings and next step below."
                )
            case .assessment:
                if audit.report == nil {
                    return text("本机检查已完成，出口检查尚未运行；当前不能形成完整结论。",
                                "The local check is complete, but the egress check has not run. A full verdict is not available.")
                }
                if audit.report?.assessment.level == .insufficient {
                    return text("部分出口结果不足，缺失或未知证据不会当作通过。",
                                "Some egress evidence is incomplete. Missing or unknown evidence is not treated as a pass.")
                }
                return text("出口或服务探测发现需要核对的项目。",
                            "The egress or service probes found items to review.")
            case .snapshot:
                return text("本机网络配置尚未满足严格结论条件。",
                            "The local network configuration does not yet meet the strict-verdict requirements.")
            case nil:
                return text("请处理后重新体检。", "Resolve the item and check again.")
            }
        }
    }

    private var statusHelpSection: RoutekeeperHelpSection {
        switch presentation.primaryIssue {
        case .gateway:
            return .inspectionGateway
        case .assessment, .snapshot:
            return .inspectionEvidence
        case .check, nil:
            return .inspectionMethods
        }
    }

    private var unresolvedGroupKinds: [InspectionCheckGroupKind] {
        InspectionCheckGrouping.groups(from: unresolvedChecks).map(\.kind)
    }

    private var statusSymbol: String {
        switch presentation.outcome {
        case .running:
            return "arrow.triangle.2.circlepath"
        case .notRun:
            return "waveform.path.ecg.rectangle"
        case .passed:
            return "checkmark.shield.fill"
        case .incomplete:
            return "questionmark.shield.fill"
        case .attention:
            switch presentation.primaryIssue {
            case let .gateway(status):
                switch status {
                case .failed, .expired: return "exclamationmark.shield.fill"
                case .verified: return "checkmark.shield.fill"
                default: return "shield.lefthalf.filled"
                }
            case let .check(_, level):
                return checkSymbol(level)
            case .assessment, .snapshot:
                return "exclamationmark.shield.fill"
            case nil:
                return "exclamationmark.shield.fill"
            }
        }
    }

    private var statusColor: Color {
        switch presentation.outcome {
        case .passed:
            return appStatusSuccess
        case .attention:
            switch presentation.primaryIssue {
            case let .check(_, level):
                return level.routekeeperStatusColor
            case let .gateway(status):
                switch status {
                case .failed, .expired:
                    return appStatusFailure
                case .verified:
                    return appStatusSuccess
                default:
                    return appStatusWarning
                }
            case .assessment:
                return audit.report?.assessment.level == .insufficient
                    ? appStatusWarning
                    : appStatusFailure
            case .snapshot, nil:
                return appStatusWarning
            }
        case .incomplete:
            return appStatusWarning
        case .running, .notRun:
            return .secondary
        }
    }

    private var primaryActionTitle: String {
        switch presentation.primaryAction {
        case .runFullCheck:
            return text("立即体检", "Check now")
        case .rerunFullCheck:
            if audit.report == nil, presentation.outcome == .incomplete {
                return text("继续体检", "Continue check")
            }
            return text("重新体检", "Check again")
        case .gatewayBaseline:
            return gatewayStatus == .unverified
                ? text("检查当前代理路径", "Check current gateway")
                : text("重新检查当前代理路径", "Check gateway again")
        case .gatewayNodeFailureTest:
            return text("开始节点断开复测", "Test node failure")
        case .gatewayClientExitTest:
            return text("开始代理退出复测", "Test client exit")
        case .gatewayRecovery:
            return text("代理已恢复，完成验证", "Proxy restored; finish")
        case nil:
            return text("体检", "Check")
        }
    }

    private var primaryActionSymbol: String {
        switch presentation.primaryAction {
        case .runFullCheck, .rerunFullCheck:
            return "waveform.path.ecg.rectangle"
        case .gatewayBaseline:
            return "point.3.connected.trianglepath.dotted"
        case .gatewayNodeFailureTest:
            return "wifi.exclamationmark"
        case .gatewayClientExitTest:
            return "xmark.icloud"
        case .gatewayRecovery:
            return "checkmark.shield"
        case nil:
            return "waveform.path.ecg.rectangle"
        }
    }

    private var timestampText: String {
        guard let snapshot = store.snapshot else {
            return text("尚未体检", "Not checked yet")
        }
        var value = text(
            "自检 \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))",
            "Self-check \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))"
        )
        if let report = audit.report {
            value += text(
                " · 出口 \(report.auditedAt.formatted(date: .omitted, time: .shortened)) · \(audit.lastRunTrigger?.title ?? "体检")",
                " · Egress \(report.auditedAt.formatted(date: .omitted, time: .shortened)) · \(audit.lastRunTrigger?.title ?? "check")"
            )
        } else {
            value += text(" · 出口尚未检查", " · Egress not checked")
        }
        return value
    }

    private func groupIsExpanded(_ group: InspectionCheckGroup) -> Bool {
        groupExpansionOverrides[group.kind] ?? false
    }

    private func checkSymbol(_ level: CheckLevel) -> String {
        switch level {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .warning: return "info.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var egressCheckItems: [CheckItem] {
        guard let report = audit.report else { return [] }

        var rows: [CheckItem] = []
        let findings = report.assessment.findings.map(\.conciseDescription)
        let assessmentDetail: String
        let assessmentLevel: CheckLevel
        switch report.assessment.level {
        case .clear:
            assessmentLevel = .passed
            assessmentDetail = text("未发现明显冲突。", "No obvious conflict found.")
        case .attention:
            assessmentLevel = .warning
            assessmentDetail = findings.isEmpty
                ? text("有项目需要核对。", "Items need review.")
                : conciseFindings(findings)
        case .insufficient:
            assessmentLevel = .unknown
            assessmentDetail = findings.isEmpty
                ? text("证据不足。", "Insufficient evidence.")
                : conciseFindings(findings)
        }
        rows.append(CheckItem(
            "egress-audit",
            text("出口体检结论", "Egress assessment"),
            assessmentDetail,
            assessmentLevel
        ))

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
                text("经当前路径访问 Claude", "Claude through current path"),
                text("\(reached)/\(report.services.count) 项连接成功。",
                     "\(reached)/\(report.services.count) probes connected."),
                level
            ))
        }

        if let ipv6 = report.ipv6 {
            let item: (String, CheckLevel) = ipv6CheckSummary(ipv6)
            rows.append(CheckItem(
                "egress-ipv6",
                text("IPv6 分流", "IPv6 routing"),
                item.0,
                item.1
            ))
        }
        return rows
    }

    private func conciseFindings(_ findings: [String]) -> String {
        let punctuation = CharacterSet(charactersIn: "。；;，,")
        let normalized = findings.prefix(2).compactMap { finding -> String? in
            let value = finding
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: punctuation)
            return value.isEmpty ? nil : value
        }
        return normalized.isEmpty
            ? text("有项目需要核对。", "Items need review.")
            : normalized.joined(separator: " · ")
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

    private func runPrimaryAction() {
        guard let action = presentation.primaryAction else { return }
        guard store.canRunNetworkInspection else {
            store.notice = text(
                "请先结束当前沙箱会话，再进行网络体检或代理网关验证。",
                "End the active sandbox session before running a network check or gateway verification."
            )
            return
        }
        Task {
            switch action {
            case .runFullCheck, .rerunFullCheck:
                await runFullCheck()
            case .gatewayBaseline:
                await store.gatewayVerification.runBaseline(
                    for: store.settings.gatewayProtectionMode
                )
            case .gatewayNodeFailureTest:
                await store.gatewayVerification.testNodeFailure(
                    for: store.settings.gatewayProtectionMode
                )
            case .gatewayClientExitTest:
                await store.gatewayVerification.testClientExit(
                    for: store.settings.gatewayProtectionMode
                )
            case .gatewayRecovery:
                await store.gatewayVerification.completeRecovery(
                    for: store.settings.gatewayProtectionMode
                )
            }
        }
    }

    private func runFullCheck() async {
        guard store.canRunNetworkInspection,
              !store.monitoring,
              !store.checking,
              !audit.busy else { return }
        await store.check()
        guard let snapshot = await store.snapshotForEgressAudit(maxAge: 45) else { return }
        await audit.run(
            snapshot: snapshot,
            includeIntelligence: includeIntelligence,
            trigger: .manual
        )
    }
}

private struct InspectionOptionsSheet: View {
    @Bindable var store: GuardStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("routekeeper-egress-intelligence-v1") private var includeIntelligence = false
    @AppStorage(AppTextScale.storageKey) private var textScaleRaw = AppTextScale.standard.rawValue
    @State private var confirmClearHistory = false
    @State private var confirmClearReports = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text("高级设置", "Advanced settings"))
                        .routekeeperFont(.title2, weight: .semibold)
                    Text(text(
                        "自动体检、连接、探测与本机数据",
                        "Automatic checks, connection, probes and local data"
                    ))
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(text("完成", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            AppHairline()

            Form {
                Section {
                    Toggle(
                        text(
                            "启动、网络变化后及定时自动体检",
                            "Automatically check after launch, network changes and on a schedule"
                        ),
                        isOn: $store.automaticEgressAuditEnabled
                    )
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("inspection-automatic-egress")

                    Picker(
                        text("自动体检间隔", "Automatic-check interval"),
                        selection: $store.automaticEgressAuditIntervalMinutes
                    ) {
                        Text(text("每 15 分钟", "Every 15 minutes")).tag(15)
                        Text(text("每 30 分钟", "Every 30 minutes")).tag(30)
                        Text(text("每 60 分钟", "Every 60 minutes")).tag(60)
                    }
                    .pickerStyle(.menu)
                    .disabled(!store.automaticEgressAuditEnabled)
                    .accessibilityIdentifier("inspection-automatic-egress-interval")
                } header: {
                    Text(text("自动体检", "Automatic checks"))
                }

                Section {
                    LabeledContent {
                        Picker("", selection: $store.settings.proxyClient) {
                            ForEach(ProxyClient.allCases, id: \.self) { client in
                                Text(client.title).tag(client)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityLabel(text("代理客户端", "Proxy client"))
                        .accessibilityValue(store.settings.proxyClient.title)
                        .accessibilityIdentifier("network-settings-proxy-client")
                    } label: {
                        Text(text("代理客户端", "Proxy client"))
                    }

                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                TextField("", value: $store.settings.pollInterval, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90 * textScale)
                                    .accessibilityLabel(text(
                                        "监控核验间隔（秒）",
                                        "Monitoring interval in seconds"
                                    ))
                                    .accessibilityIdentifier("network-settings-poll-interval")
                                Text(text("秒", "seconds"))
                                    .foregroundStyle(.secondary)
                                Stepper("", value: $store.settings.pollInterval, in: 1...300, step: 1)
                                    .labelsHidden()
                                    .accessibilityLabel(text("监控核验间隔", "Monitoring interval"))
                            }

                            Text(text("有效范围：1–300 秒", "Valid range: 1–300 seconds"))
                                .routekeeperFont(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(text("监控核验间隔", "Monitoring interval"))
                    }

                    if !store.settings.validInterval {
                        Text(text("请输入 1–300 秒。", "Enter a value from 1 to 300."))
                            .routekeeperFont(.caption)
                            .foregroundStyle(appStatusFailure)
                    }
                } header: {
                    Text(text("连接与监控", "Connection and monitoring"))
                } footer: {
                    Text(text(
                        "代理客户端默认自动识别；监控核验间隔仅影响监控开启后的检查频率。",
                        "The proxy client is detected automatically by default. The monitoring interval only affects checks while monitoring is active."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .disabled(settingsLocked)

                Section {
                    Toggle(
                        text(
                            "检测 DNS 解析器路由与响应",
                            "Probe DNS resolver routes and responses"
                        ),
                        isOn: $store.settings.dnsProbeEnabled
                    )
                    .toggleStyle(.switch)
                    .disabled(settingsLocked)
                    .accessibilityIdentifier("inspection-dns-probe")

                    Toggle(
                        text(
                            "用两处 STUN 服务检测 UDP 出口",
                            "Probe UDP egress with two STUN servers"
                        ),
                        isOn: $store.settings.udpProbeEnabled
                    )
                    .toggleStyle(.switch)
                    .disabled(settingsLocked)
                    .accessibilityIdentifier("inspection-udp-probe")
                } header: {
                    Text(text("探测范围", "Probe coverage"))
                } footer: {
                    Text(text(
                        "关闭探测会减少外部请求，但对应证据也会变为未检查；不会因为关闭而视为通过。",
                        "Disabling a probe reduces external requests, but its evidence becomes unverified. Disabled does not mean passed."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Toggle(
                        text(
                            "手动体检时查询第三方 IP 信息",
                            "Query third-party IP intelligence during manual checks"
                        ),
                        isOn: $includeIntelligence
                    )
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("inspection-egress-intelligence")
                } header: {
                    Text(text("隐私", "Privacy"))
                } footer: {
                    Text(text(
                        "默认关闭。开启后，手动体检会把出口 IP 发送给 ipwho.is / ipapi.is；自动体检始终只在本机运行。",
                        "Off by default. When enabled, manual checks send the exit IP to ipwho.is / ipapi.is. Automatic checks always stay local."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    HStack(spacing: 10) {
                        Button(role: .destructive) {
                            confirmClearReports = true
                        } label: {
                            Label(text("清除已保存报告", "Clear stored reports"),
                                  systemImage: "trash")
                        }
                        .routekeeperSecondaryButton()
                        .disabled(store.egressAudit.report == nil
                                  && store.egressAudit.previousReport == nil)

                        Button(role: .destructive) {
                            confirmClearHistory = true
                        } label: {
                            Label(text("清除出口历史", "Clear exit history"),
                                  systemImage: "clock.arrow.circlepath")
                        }
                        .routekeeperSecondaryButton()
                        .disabled(store.egressAudit.history.isEmpty)
                    }
                } header: {
                    Text(text("本机数据", "Local data"))
                } footer: {
                    Text(text(
                        "最近两次报告和最多 20 条出口历史只保存在本机；清除不会修改网络设置。",
                        "The two latest reports and up to 20 exits stay on this Mac. Clearing them does not change network settings."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
        }
        .frame(width: 560, height: 650)
        .accessibilityIdentifier("advanced-settings-sheet")
        .confirmationDialog(
            text("清除本机出口历史？", "Clear local exit history?"),
            isPresented: $confirmClearHistory
        ) {
            Button(text("清除历史", "Clear history"), role: .destructive) {
                store.egressAudit.clearHistory()
            }
        } message: {
            Text(text(
                "只删除本机出口 IP 历史。",
                "Only local exit-IP history is removed."
            ))
        }
        .confirmationDialog(
            text("清除最近两次体检报告？", "Clear the two most recent egress reports?"),
            isPresented: $confirmClearReports
        ) {
            Button(text("清除报告", "Clear reports"), role: .destructive) {
                store.egressAudit.clearStoredResults()
            }
        } message: {
            Text(text(
                "只删除本机保存的完整体检报告。",
                "Only locally stored egress reports are removed."
            ))
        }
    }

    private var settingsLocked: Bool {
        store.monitoring
            || store.checking
            || store.networkFilter.configured
            || store.networkFilter.busy
            || store.sandbox.anyActive
            || store.sandbox.busy
    }

    private var textScale: CGFloat {
        (AppTextScale(rawValue: textScaleRaw) ?? .standard).multiplier
    }
}
