import GuardCore
import SwiftUI

struct InspectionPage: View {
    @Bindable var store: GuardStore
    @Bindable var audit: EgressAuditController
    let onOpenProtection: () -> Void

    @AppStorage("routekeeper-egress-intelligence-v1") private var includeIntelligence = false
    @State private var showChecks = false

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryPanel
            if !attentionItems.isEmpty {
                attentionPanel
            }
            selfCheckDetails
            EgressAuditPage(store: store, audit: audit, embedded: true)
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
                onOpenProtection()
            } label: {
                Label(text("打开保护设置", "Open protection settings"), systemImage: "shield.lefthalf.filled")
            }
        }
    }

    private var selfCheckDetails: some View {
        GuardCard(
            title: text("自检项目", "Self-check items"),
            subtitle: selfCheckSubtitle
        ) {
            DisclosureGroup(isExpanded: $showChecks) {
                if let snapshot = store.snapshot {
                    VStack(spacing: 0) {
                        ForEach(snapshot.checks) { row in
                            CheckRow(row: row).padding(.vertical, 4)
                            if row.id != snapshot.checks.last?.id {
                                AppHairline()
                            }
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Text(L("checks.empty"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            } label: {
                HStack {
                    Text(text("查看全部 \(store.snapshot?.checks.count ?? 0) 项", "View all \(store.snapshot?.checks.count ?? 0) items"))
                        .font(.callout.weight(.medium))
                    Spacer()
                }
            }
        }
    }

    private var attentionItems: [CheckItem] {
        store.snapshot?.checks.filter(\.needsAttention) ?? []
    }

    private var passedCount: Int {
        store.snapshot?.checks.filter { $0.level == .passed }.count ?? 0
    }

    private var selfCheckSubtitle: String {
        guard let snapshot = store.snapshot else { return L("checks.empty") }
        let warningCount = snapshot.checks.filter { $0.level == .warning }.count
        if warningCount > 0 {
            return text("\(passedCount)/\(snapshot.checks.count) 项通过 · \(warningCount) 项提示",
                        "\(passedCount)/\(snapshot.checks.count) passed · \(warningCount) notice")
        }
        return text("\(passedCount)/\(snapshot.checks.count) 项通过",
                    "\(passedCount)/\(snapshot.checks.count) passed")
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
