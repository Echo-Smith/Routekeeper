import GuardCore
import SwiftUI

enum RoutekeeperHelpCategory: String, CaseIterable, Identifiable {
    case gettingStarted
    case essentials
    case sandbox
    case tools
    case reference

    var id: String { rawValue }

    var title: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .gettingStarted: return en ? "Get started" : "快速上手"
        case .essentials: return en ? "Main features" : "主要功能"
        case .sandbox: return en ? "Experimental sandbox" : "实验性沙箱"
        case .tools: return en ? "Tools" : "工具"
        case .reference: return en ? "Settings and help" : "设置与排查"
        }
    }
}

enum RoutekeeperHelpSection: String, CaseIterable, Identifiable {
    case quickStart
    case overview
    case networkProtection
    case inspectionMethods
    case inspectionGateway
    case sandboxOverview
    case sandboxTargets
    case sandboxWeb
    case sandboxPaths
    case sandboxNetwork
    case sandboxSessions
    case sandboxStatus
    case authentication
    case activity
    case cleanup
    case inspectionEvidence
    case protectionScore
    case inspectionPrivacy
    case settings
    case troubleshooting

    var id: String { rawValue }

    var category: RoutekeeperHelpCategory {
        switch self {
        case .quickStart:
            return .gettingStarted
        case .overview, .networkProtection, .inspectionMethods, .inspectionGateway:
            return .essentials
        case .sandboxOverview, .sandboxTargets, .sandboxWeb, .sandboxPaths, .sandboxNetwork,
             .sandboxSessions, .sandboxStatus:
            return .sandbox
        case .authentication, .activity, .cleanup:
            return .tools
        case .inspectionEvidence, .protectionScore, .inspectionPrivacy, .settings, .troubleshooting:
            return .reference
        }
    }

    var title: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .quickStart:
            return en ? "Quick start" : "快速上手"
        case .overview:
            return en ? "Overview" : "概览"
        case .networkProtection:
            return en ? "Network protection" : "网络保护"
        case .inspectionMethods:
            return en ? "How checks run" : "检查方法"
        case .inspectionGateway:
            return en ? "Gateway verification" : "代理网关验证"
        case .sandboxOverview:
            return en ? "Isolation model" : "隔离模型与限制"
        case .sandboxTargets:
            return en ? "Three cards and independent runtimes" : "三张卡片与独立运行"
        case .sandboxWeb:
            return en ? "Chrome isolation" : "Chrome 隔离浏览"
        case .sandboxPaths:
            return en ? "Folders and workspaces" : "目录与工作副本"
        case .sandboxNetwork:
            return en ? "Proxy and network boundary" : "代理与网络边界"
        case .sandboxSessions:
            return en ? "Launching sessions" : "启动、暂停与结束"
        case .sandboxStatus:
            return en ? "Status and troubleshooting" : "状态与故障排查"
        case .authentication:
            return en ? "Claude sign-in" : "Claude 登录"
        case .activity:
            return en ? "Activity" : "运行记录"
        case .cleanup:
            return en ? "Cleanup" : "清理"
        case .inspectionEvidence:
            return en ? "Reading the evidence" : "检查结果说明"
        case .protectionScore:
            return en ? "Protection completeness" : "保护完整度"
        case .inspectionPrivacy:
            return en ? "Privacy and limits" : "隐私与限制"
        case .settings:
            return en ? "Settings" : "设置"
        case .troubleshooting:
            return en ? "Troubleshooting" : "常见问题"
        }
    }

    var subtitle: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .quickStart:
            return en ? "A short first-run path" : "首次使用的最短路径"
        case .overview:
            return en ? "Status, next action and monitoring" : "状态、下一步与监控"
        case .networkProtection:
            return en ? "Scope, mode and fixed exits" : "保护范围、方式与固定出口"
        case .inspectionMethods:
            return en ? "Local checks and external probes" : "本机自检与外部探测"
        case .inspectionGateway:
            return en ? "Baseline, node failure, client exit and recovery" : "基线、节点断开、客户端退出与恢复"
        case .sandboxOverview:
            return en ? "What is isolated and what is not" : "隔离什么，不隔离什么"
        case .sandboxTargets:
            return en ? "Shared environment in the menu, separate states" : "共享环境在菜单中，运行状态彼此独立"
        case .sandboxWeb:
            return en ? "Dedicated Chrome profile and native sandbox" : "独立 Chrome 配置与原生沙箱"
        case .sandboxPaths:
            return en ? "Project copies and separate exchange folders" : "项目副本与分开的交换目录"
        case .sandboxNetwork:
            return en ? "Local relay, fail-closed traffic and limits" : "本机中继、失败断网与限制"
        case .sandboxSessions:
            return en ? "Prepare and launch each target independently" : "分别准备并启动每个目标"
        case .sandboxStatus:
            return en ? "Action colors and blocked states" : "动作颜色与不可用状态"
        case .authentication:
            return en ? "Claude Code and Claude sign-in" : "Claude Code 与 Claude 登录"
        case .activity:
            return en ? "Recent local events" : "最近的本地事件"
        case .cleanup:
            return en ? "Caches, history and local data" : "缓存、历史与本地数据"
        case .inspectionEvidence:
            return en ? "Passed, unconfirmed and insufficient evidence" : "通过、待确认与证据不足"
        case .protectionScore:
            return en ? "What the score means and does not mean" : "分数代表什么，不代表什么"
        case .inspectionPrivacy:
            return en ? "What is sent and what is never read" : "会发送什么，不读取什么"
        case .settings:
            return en ? "Language, appearance and text size" : "语言、外观与文字大小"
        case .troubleshooting:
            return en ? "Common blockers and fixes" : "常见阻塞与处理方法"
        }
    }

    var symbol: String {
        switch self {
        case .quickStart: return "sparkles"
        case .overview: return "rectangle.grid.2x2"
        case .networkProtection: return "shield.lefthalf.filled"
        case .inspectionMethods: return "waveform.path.ecg.rectangle"
        case .inspectionGateway: return "shield.lefthalf.filled"
        case .sandboxOverview: return "lock.shield"
        case .sandboxTargets: return "square.split.2x1"
        case .sandboxWeb: return "globe"
        case .sandboxPaths: return "folder.badge.gearshape"
        case .sandboxNetwork: return "network"
        case .sandboxSessions: return "play.rectangle"
        case .sandboxStatus: return "checklist"
        case .authentication: return "key"
        case .activity: return "clock.arrow.circlepath"
        case .cleanup: return "trash"
        case .inspectionEvidence: return "doc.text.magnifyingglass"
        case .protectionScore: return "gauge.medium"
        case .inspectionPrivacy: return "hand.raised"
        case .settings: return "gearshape"
        case .troubleshooting: return "questionmark.circle"
        }
    }
}

extension Notification.Name {
    static let routekeeperHelpSection = Notification.Name("RoutekeeperHelpSection")
}

@MainActor
enum RoutekeeperHelpNavigation {
    private static var pendingSection: RoutekeeperHelpSection?

    static func request(_ section: RoutekeeperHelpSection) {
        pendingSection = section
        NotificationCenter.default.post(
            name: .routekeeperHelpSection,
            object: section.rawValue
        )
    }

    static func consumePendingSection() -> RoutekeeperHelpSection? {
        defer { pendingSection = nil }
        return pendingSection
    }
}

struct RoutekeeperHelpView: View {
    @State private var selection: RoutekeeperHelpSection = .quickStart

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(RoutekeeperHelpCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(RoutekeeperHelpSection.allCases.filter { $0.category == category }) { section in
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: section.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .center)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title)
                                        .routekeeperFont(.callout, weight: .medium)
                                    Text(section.subtitle)
                                        .routekeeperFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                            .tag(section)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(section.title)
                            .accessibilityValue(section.subtitle)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 310)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    helpHeader
                    AppHairline()
                    switch selection {
                    case .quickStart:
                        quickStartContent
                    case .overview:
                        overviewContent
                    case .networkProtection:
                        networkProtectionContent
                    case .inspectionMethods:
                        methodsContent
                    case .inspectionGateway:
                        gatewayContent
                    case .inspectionEvidence:
                        evidenceContent
                    case .protectionScore:
                        protectionScoreContent
                    case .inspectionPrivacy:
                        privacyContent
                    case .sandboxOverview:
                        sandboxOverviewContent
                    case .sandboxTargets:
                        sandboxTargetsContent
                    case .sandboxWeb:
                        sandboxWebContent
                    case .sandboxPaths:
                        sandboxPathsContent
                    case .sandboxNetwork:
                        sandboxNetworkContent
                    case .sandboxSessions:
                        sandboxSessionsContent
                    case .sandboxStatus:
                        sandboxStatusContent
                    case .authentication:
                        authenticationContent
                    case .activity:
                        activityContent
                    case .cleanup:
                        cleanupContent
                    case .settings:
                        settingsContent
                    case .troubleshooting:
                        troubleshootingContent
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle(text("Routekeeper 帮助", "Routekeeper Help"))
        .frame(minWidth: 760, minHeight: 560)
        .onAppear(perform: applyPendingSection)
        .onReceive(NotificationCenter.default.publisher(for: .routekeeperHelpSection)) { _ in
            applyPendingSection()
        }
        .accessibilityIdentifier("routekeeper-help-content")
    }

    private var helpHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: selection.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.title)
                    .routekeeperFont(.title2, weight: .semibold)
                    .tracking(-0.25)
                    .accessibilityAddTraits(.isHeader)
                Text(selection.subtitle)
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickStartContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "推荐从概览开始。先完成一次网络体检，再按结果配置保护范围、固定出口和保护方式。登录、实验性沙箱与清理都可以按需使用，不需要在首次启动时全部配置。",
                    "Start in Overview. Run one network check, then use the result to configure protection scope, fixed exits and protection mode. Sign-in, the experimental sandbox and cleanup are optional and do not need to be configured on first launch."
                )
            )
            helpSteps([
                text(
                    "打开“概览”，点击“立即体检”，等待本机检查与出口检查完成。",
                    "Open Overview and choose Check now. Wait for both the local check and egress check to finish."
                ),
                text(
                    "如有未通过项，按卡片中的下一步处理；固定出口和保护范围在“网络保护”中设置。",
                    "Resolve any failed item using its next step. Fixed exits and protection scope are configured in Network protection."
                ),
                text(
                    "需要严格代理保护时，选择保护方式，并按“配置此模式”生成代理客户端提示词。",
                    "For strict proxy protection, choose a protection mode and use Configure this mode to generate proxy-client instructions."
                ),
                text(
                    "需要验证代理失败关闭时，依次完成基线、节点断开、代理退出和恢复检查。",
                    "To verify fail-closed behavior, complete the baseline, node-failure, client-exit and recovery checks in order."
                ),
                text(
                    "体检通过后，回到“概览”开启监控。需要隔离运行 Claude 时，再配置“实验性沙箱”；未安装 Claude 客户端时，先使用沙箱卡片中的官方安装入口。",
                    "After the check passes, return to Overview and start monitoring. Configure the experimental sandbox only when isolated Claude sessions are needed; if a Claude client is not installed, use the official install entry in its sandbox card."
                )
            ])
            helpCallout(
                text(
                    "Claude Code 登录凭证只影响 Claude Code 隔离会话；Claude 登录由独立数据管理。两者都不会写入项目、运行记录或体检报告。",
                    "The Claude Code credential affects isolated Claude Code sessions only. Claude sign-in uses a separate profile. Neither is written to projects, activity or check reports."
                ),
                symbol: "key"
            )
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "概览汇总当前体检结论、固定出口、代理出口和 TUN 路由，并根据当前状态只显示一个主要操作。",
                    "Overview summarizes the current verdict, fixed exit, proxy exit and TUN route, then shows one primary action for the current state."
                )
            )
            helpFeatureRow(
                title: text("状态与主要操作", "Status and primary action"),
                detail: text(
                    "“立即体检”“查看并处理”或“开启监控”会随当前状态变化。",
                    "Check now, Review and resolve, or Start monitoring changes with the current state."
                ),
                symbol: "bolt.shield"
            )
            helpFeatureRow(
                title: text("保护范围", "Protection scope"),
                detail: text(
                    "查看 Claude、Claude Code 的监控状态，并跳转到保护范围与异常动作设置。",
                    "Review monitoring for Claude and Claude Code, and open protection scope and incident handling."
                ),
                symbol: "shield.lefthalf.filled"
            )
            helpFeatureRow(
                title: text("代理网关", "Proxy gateway"),
                detail: text(
                    "显示当前保护方式与验证状态；选择“打开检查”进入完整检查流程。",
                    "Shows the selected mode and verification state. Choose Open check to enter the full flow."
                ),
                symbol: "network"
            )
            helpFeatureRow(
                title: text("保护完整度", "Protection completeness"),
                detail: text(
                    "分值表示当前配置与证据的完整程度，不是账号风险分，也不会限制 Claude、Claude Code 或实验性沙箱的使用。",
                    "The score describes how complete the current configuration and evidence are. It is not an account-risk score and never limits Claude, Claude Code or the experimental sandbox."
                ),
                symbol: "gauge.medium"
            )
            helpCallout(
                text(
                    "概览不替代详细证据。未通过、未知和证据不足的项目仍以网络保护中的检查结果为准。",
                    "Overview is not a substitute for detailed evidence. Failed, unknown and insufficient items remain authoritative on the Network protection page."
                ),
                symbol: "doc.text.magnifyingglass"
            )
        }
    }

    private var networkProtectionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "“网络保护”把体检结论、保护设置和完整检查结果放在同一页。页面顶部显示当前结论，中部编辑保护范围、保护方式、固定出口与异常动作，底部保留完整证据。",
                    "Network protection combines the verdict, protection settings and full evidence on one page. The verdict appears first, protection scope, mode, fixed exits and incident handling follow, and complete evidence remains below."
                )
            )
            helpSteps([
                text(
                    "在“保护范围”中启用需要监控的 Claude 或 Claude Code。",
                    "Enable Claude or Claude Code in Protection scope."
                ),
                text(
                    "使用“自动获取出口”或手动填写 IPv4、IPv6 固定出口。",
                    "Use Detect exit or enter an IPv4 or IPv6 fixed exit manually."
                ),
                text(
                    "选择保护方式；变更后旧代理网关证据会失效，需要重新检查。",
                    "Choose a protection mode. Changing it invalidates prior gateway evidence, so run the check again."
                ),
                text(
                    "右上角“更多”提供高级设置、连接排查和报告导出；问号按钮打开对应帮助。",
                    "The top-right More menu provides advanced settings, connection diagnostics and report export. The question-mark button opens contextual help."
                )
            ])
            helpCallout(
                text(
                    "监控、体检、系统过滤或实验性沙箱启用时，部分设置会变为只读。先停止相关操作，再修改配置。",
                    "Some settings become read-only while monitoring, checking, system filtering or the experimental sandbox is active. Stop the relevant operation before editing."
                ),
                symbol: "lock.shield"
            )
            helpCallout(
                text(
                    "当前正式构建使用 ad-hoc 签名，macOS Network Extension 系统过滤无法启用。功能代码仍然保留，但界面不显示入口。请在代理客户端中按进程或 Claude 域名配置分流，或选择“仅限制 Claude”。",
                    "The current release is ad-hoc signed, so the macOS Network Extension system filter cannot be enabled. The feature remains in the codebase but has no UI entry. Use process- or Claude-domain rules in the proxy client, or select Claude only."
                ),
                symbol: "signature"
            )
            helpCallout(
                text(
                    "Routekeeper 经本机中继访问代理时，当前代理看到的进程是 Routekeeper，不是 Chrome 或 Claude。只写 Chrome 进程规则并不足够；应为 claude.ai、api.anthropic.com 和实际使用的 Anthropic/Claude 域名设置代理组规则。TUN 的虚拟网卡是流量入口，“出站网卡”应保持自动或物理网卡，不要填写代理自己创建的 utun。",
                    "When Routekeeper reaches a proxy through its local relay, the current proxy sees Routekeeper rather than Chrome or Claude. A Chrome process rule is not sufficient. Add proxy-group rules for claude.ai, api.anthropic.com and the Anthropic/Claude domains actually in use. The TUN virtual interface is an ingress path; Outbound interface should remain automatic or use a physical interface, never the proxy's own utun."
                ),
                symbol: "network"
            )
        }
    }

    private var authenticationContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "“登录凭证”管理 Claude Code 的钥匙串凭证，以及 Claude 在隔离会话中的独立登录数据。两类登录互不共享。",
                    "Claude sign-in manages the Claude Code Keychain credential and Claude sign-in data for isolated sessions. The two sign-ins are never shared."
                )
            )
            helpSteps([
                text(
                    "首次配置 Claude Code 时，打开终端并按提示完成官方 setup-token 流程。",
                    "For the first Claude Code setup, open Terminal and complete the official setup-token flow."
                ),
                text(
                    "把生成的登录凭证粘贴到本页并保存到 macOS 钥匙串。",
                    "Paste the generated token into this page and save it to macOS Keychain."
                ),
                text(
                    "只有 Claude Code 提示凭证失效时才重新获取；已保存凭证可直接复用。",
                    "Acquire a new credential only after Claude Code reports that the current one expired. A saved credential can be reused."
                ),
                text(
                    "Claude 的“保留登录状态”使用独立登录数据；可在同一页清除。",
                    "Keep Claude sign-in uses a separate profile. You can clear that data from the same page."
                )
            ])
            helpCallout(
                text(
                    "Claude Code 凭证只用于 Routekeeper 启动的 Claude Code，不用于其他网站或系统账户，也不会写入项目、日志、交换目录或体检报告。不要把登录凭证粘贴到对话、代码或普通文本文件。",
                    "The Claude Code credential is used only by Claude Code launched through Routekeeper, never for other websites or system accounts, and is never written to projects, logs, exchange folders or check reports. Do not paste a token into chats, code or ordinary text files."
                ),
                symbol: "key.horizontal"
            )
        }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "运行记录显示最近的本机事件，并用“需注意”标记失败、风险或需要人工处理的操作。",
                    "Activity shows recent local events and marks failures, risks and actions requiring attention with Attention."
                )
            )
            helpFeatureRow(
                title: text("只保留最近事件", "Recent events only"),
                detail: text(
                    "应用只在内存中保留最近 60 条记录，不保存命令参数。",
                    "The app keeps the latest 60 entries in memory and does not save command arguments."
                ),
                symbol: "clock.arrow.circlepath"
            )
            helpFeatureRow(
                title: text("用于定位问题", "Use it to diagnose"),
                detail: text(
                    "当体检、代理网关或实验性沙箱失败时，先查看同一时间的运行记录，再返回对应页面重试。",
                    "When a check, gateway verification or sandbox session fails, review Activity at the same time, then retry from the relevant page."
                ),
                symbol: "list.bullet.rectangle"
            )
            helpCallout(
                text(
                    "运行记录不是完整审计日志，也不会替代体检证据。",
                    "Activity is not a complete audit log and does not replace check evidence."
                ),
                symbol: "info.circle"
            )
        }
    }

    private var cleanupContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "清理先扫描，再由你确认范围。普通缓存、历史沙箱和 Routekeeper 本地信息分开选择，避免把安全缓存清理与不可恢复的数据重置混在一起。",
                    "Cleanup scans first and asks you to confirm scope. Regular caches, past sandboxes and Routekeeper local data are selected separately so routine cleanup is not confused with irreversible reset."
                )
            )
            helpSteps([
                text(
                    "点击“扫描缓存”，按来源查看可清理项目；安全缓存默认选中，历史沙箱默认关闭。",
                    "Choose Scan caches and review items by source. Safe caches are selected by default; past sandboxes are off by default."
                ),
                text(
                    "普通缓存会移到废纸篓，可从废纸篓恢复。",
                    "Regular caches move to Trash and can be restored from Trash."
                ),
                text(
                    "“Routekeeper 本地信息”需要单独确认，清除后不可恢复，也不会进入废纸篓。",
                    "Routekeeper local data requires separate confirmation. It cannot be undone or restored from Trash."
                ),
                text(
                    "带锁项目通常由进程占用、符号链接或归属标记触发保护；退出相关 Claude 应用或结束沙箱后再扫描。",
                    "Locked items are usually protected because of a running process, symbolic link or ownership marker. Quit the relevant Claude app or end the sandbox, then scan again."
                )
            ])
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "设置页管理语言、外观和文字大小，并提供用途、隐私与免责声明。",
                    "Settings manages language, appearance and text size, and provides the purpose, privacy and disclaimer notice."
                )
            )
            helpFeatureRow(
                title: text("语言、外观与文字大小", "Language, appearance and text size"),
                detail: text(
                    "这些选项会立即影响当前窗口。",
                    "These options apply to the current window immediately."
                ),
                symbol: "textformat.size"
            )
            helpFeatureRow(
                title: text("法律与隐私", "Legal & privacy"),
                detail: text(
                    "打开“用途、隐私与免责声明”可查看用途边界、数据处理方式与责任说明。",
                    "Open Purpose, privacy and disclaimer to review scope, data handling and responsibility terms."
                ),
                symbol: "doc.text"
            )
            helpCallout(
                text(
                    "系统菜单中的文字可能不会随应用内设置即时刷新；重新打开菜单或应用后会使用当前设置。",
                    "Text in system menus may not refresh immediately with in-app settings. Reopen the menu or app to use the current setting."
                ),
                symbol: "menubar.rectangle"
            )
        }
    }

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpFAQRow(
                title: text("主要按钮不可用", "The primary action is unavailable"),
                detail: text(
                    "体检、代理网关验证或沙箱操作可能仍在运行。等待当前任务结束，再查看同一张卡片中的阻塞项。",
                    "A check, gateway verification or sandbox action may still be running. Wait for it to finish, then review blockers on the same card."
                )
            )
            helpFAQRow(
                title: text("体检通过但无法开启监控", "The check passed, but monitoring will not start"),
                detail: text(
                    "确认保护范围至少包含一个已安装应用，固定出口有效；已选择保护方式时，还要完成代理网关验证。",
                    "Confirm that protection scope contains at least one installed app and that the fixed exit is valid. If a protection mode is selected, complete gateway verification too."
                )
            )
            helpFAQRow(
                title: text("代理网关证据反复失效", "Gateway evidence keeps expiring"),
                detail: text(
                    "切换网络、节点、代理客户端或系统代理后会重新验证。固定当前网络路径后，从头完成基线、断开、退出和恢复流程。",
                    "Changing the network, node, proxy client or system proxy requires re-verification. Stabilize the current path, then repeat baseline, failure, exit and recovery checks."
                )
            )
            helpFAQRow(
                title: text("Claude Code 提示凭证失效", "Claude Code reports an expired credential"),
                detail: text(
                    "回到“登录凭证”，重新运行官方 setup-token 流程并保存新的登录凭证。旧凭证不会自动恢复。",
                    "Return to Claude sign-in, run the official setup-token flow again and save the new token. An expired token is not restored automatically."
                )
            )
            helpFAQRow(
                title: text("实验性沙箱无法启动会话", "The experimental sandbox cannot start a session"),
                detail: text(
                    "先查看共享准备和目标卡片：目录不能重叠，系统代理必须是本机回环入口，固定出口与登录状态必须就绪。",
                    "Review shared readiness and the target card: folders cannot overlap, the system proxy must expose a loopback endpoint, and fixed exit plus sign-in must be ready."
                )
            )
            helpFAQRow(
                title: text("打开或操作其他 App 时要求 macOS 授权", "macOS asks for authorization when opening or operating another app"),
                detail: text(
                    "在“隐私与安全性 > 自动化”中允许 Routekeeper 控制“终端”。沙箱页会打开这个设置并自动重新检查授权状态。",
                    "Under Automation, allow Routekeeper to control Terminal. The sandbox page opens this exact setting and checks it again automatically; closing the window is not a restart."
                )
            )
            helpFAQRow(
                title: text("设置变为只读", "Settings are read-only"),
                detail: text(
                    "停止监控或体检，结束并关闭实验性沙箱，或等待系统网络过滤完成配置后再修改。",
                    "Stop monitoring or checking, end and turn off the experimental sandbox, or wait for system network filtering to finish configuring."
                )
            )
            helpFAQRow(
                title: text("清理项目带有锁标记", "A cleanup item is locked"),
                detail: text(
                    "退出对应的 Claude 应用、结束沙箱会话或避开符号链接后再重新扫描。Routekeeper 会按失败关闭策略保留这些项目。",
                    "Quit the relevant Claude app, end the sandbox session or avoid symbolic links, then scan again. Routekeeper keeps these items under a fail-closed policy."
                )
            )
            helpCallout(
                text(
                    "如果同一问题重复出现，先查看“运行记录”中同一时间的事件，再使用页面内的问号帮助定位对应流程。",
                    "If the same issue repeats, review Activity around the same time, then use the in-page question-mark help for that workflow."
                ),
                symbol: "lifepreserver"
            )
        }
    }

    private var methodsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "一次完整体检由两部分组成：本机自检核对保护对象、固定出口、地址族、DNS、UDP、TUN、Claude 进程及其实时连接与终端环境；出口检查再观察系统路径、代理路径、外部服务看到的出口，以及经当前路径访问 Claude 时的结果。",
                    "A full check has two parts. The local check verifies protected apps, fixed exits, address families, DNS, UDP, TUN, Claude processes, their live TCP connections and terminal environment. The egress check observes the system path, proxy path, external exits and the result of reaching Claude through the current path."
                )
            )
            helpSteps([
                text("点击“立即体检”运行本机自检，再运行出口检查。", "Choose Check now to run the local check, then the egress check."),
                text("所有未通过、未知和证据不足的项目都会留在结论卡中，不会被隐藏或算作通过。", "Failed, unknown and insufficient results remain in the verdict card and are never counted as passed."),
                text("通过的项目合并到“已通过检查项”；完整原始证据不重复占用主页面。", "Passed items are combined under Passed checks. Raw evidence is not duplicated on the main page."),
                text("“经当前路径访问 Claude”是 Routekeeper 主动请求 Claude 跟踪地址得到的出口，不等同于 Claude 进程自身的连接。实时进程连接只在能够读取时作为独立证据展示。",
                     "Reaching Claude through the current path is an active Routekeeper request to the Claude trace endpoint. It is not the Claude process's own connection. Live process connections appear as separate evidence only when they can be read."),
                text("选择右上角“高级设置…”可调整自动体检、代理客户端、监控核验间隔、DNS/STUN 探测、第三方 IP 查询和本机数据。",
                     "Use Advanced settings in the top-right menu to manage automatic checks, the proxy client, monitoring interval, DNS/STUN probes, third-party IP lookup and local data.")
            ])
            helpCallout(
                text(
                    "网络保护页面直接管理保护对象、保护方式、固定出口与异常动作；模式相关的代理规则可从“配置此模式…”生成可复制提示词。代理客户端、监控核验间隔、观测开关和体检记录在右上角“高级设置…”中管理，连接排查在“更多 → 连接排查…”中打开。",
                    "The Network protection page directly manages protected apps, protection mode, fixed exits and incident action. Mode-specific proxy rules are available through Configure this mode. The proxy client, monitoring interval, observation switches and check records live under Advanced settings in the top-right menu, while connection diagnostics opens from More > Connection diagnostics."
                ),
                symbol: "slider.horizontal.3"
            )
        }
    }

    private var gatewayContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "代理网关验证不是一次连通性测试。Routekeeper 依次确认当前路径、节点断开和代理客户端退出时的行为，最后恢复原状态并复测，避免把可回落的代理误判为严格保护。",
                    "Gateway verification is more than one connectivity test. Routekeeper checks the current path, node failure and client exit, then restores the original state and verifies it again."
                )
            )
            helpSteps([
                text("基线：检查系统代理或 TUN、Claude 路径、系统与代理出口一致性、DNS 与 UDP 参考证据。", "Baseline: check the system proxy or TUN, Claude path, system and proxy exit consistency, DNS and UDP reference evidence."),
                text("节点断开：只停用所选海外节点，保持代理客户端运行；Claude 应无法连接。", "Node failure: disable only the selected overseas node while keeping the proxy client running. Claude should become unreachable."),
                text("代理退出：恢复节点后完全退出代理客户端；Claude 仍应无法连接，否则存在回落直连风险。", "Client exit: restore the node, then quit the proxy client. Claude should remain unreachable; otherwise direct fallback is possible."),
                text("恢复：重新启动代理并恢复原节点，再运行最终复测。只有完整证据在有效期内才显示已验证。", "Recovery: restart the proxy, restore the original node and run the final check. Verification is complete only while all evidence is fresh.")
            ])
            helpCallout(
                text(
                    "网络、节点、代理客户端或系统设置发生变化后，旧证据会立即失效。",
                    "Changing the network, node, proxy client or system settings invalidates old evidence."
                ),
                symbol: "clock.arrow.circlepath"
            )
        }
    }

    private var evidenceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            evidenceRow(
                title: text("通过", "Passed"),
                detail: text("检查取得了当前结论所需的证据，并满足条件。", "The check obtained the evidence required for the current conclusion and met its condition."),
                symbol: "checkmark.circle.fill",
                color: appStatusSuccess
            )
            evidenceRow(
                title: text("未通过", "Failed"),
                detail: text("检查取得了证据，但结果不满足保护条件。需要按解决步骤处理后重新检查。", "Evidence was obtained but did not meet the protection condition. Follow the solution and check again."),
                symbol: "xmark.circle.fill",
                color: appStatusFailure
            )
            evidenceRow(
                title: text("待确认或未知", "Unconfirmed or unknown"),
                detail: text("没有取得足够证据，或结果无法可靠判断。未知不会当作通过。", "There was not enough evidence for a reliable conclusion. Unknown is never treated as passed."),
                symbol: "questionmark.circle.fill",
                color: appStatusWarning
            )
            evidenceRow(
                title: text("证据不足", "Insufficient evidence"),
                detail: text("出口或服务探测缺少必要结果，整次体检保持未完成状态。", "The egress or service probe is missing required results, so the full check remains incomplete."),
                symbol: "ellipsis.circle.fill",
                color: appStatusWarning
            )
            helpParagraph(
                text(
                    "“已通过检查项”只收录状态为“通过”的项目。提示、未知、失败和不足都不会混入通过列表。",
                    "Passed checks contains only items whose status is passed. Warnings, unknown, failures and insufficient results are excluded."
                )
            )
        }
    }

    private var protectionScoreContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "保护完整度只回答一个问题：在当前这台 Mac、当前网络和当前体检时间内，我们掌握了多少可解释的保护证据。它不是 Claude 账号风险分，不是 Anthropic 的服务端判定，也不是使用 Claude 或 Claude Code 的资格门槛。分数较低只会给出改进建议，不会阻止登录、启动或使用这些产品。",
                    "Protection completeness answers one question: how much explainable protection evidence do we have for this Mac, network and check window? It is not a Claude account-risk score, an Anthropic server-side decision or a permission gate for Claude or Claude Code. A lower score only produces suggestions and never blocks sign-in, launch or use."
                )
            )
            helpFeatureRow(
                title: text("五个计分区域", "Five scoring areas"),
                detail: text(
                    "保护设置 12 分、本机路径 25 分、外部出口与服务 25 分、Claude 环境 26 分、代理失败关闭 12 分。未选择保护方式时，失败关闭区域不参与计分，其余区域按适用权重归一化到 100 分。",
                    "Protection setup is 12, local path 25, external exits and services 25, Claude environment 26 and gateway fail-closed verification 12. When no protection mode is selected, fail-closed verification is not applicable and the remaining weights are normalized to 100."
                ),
                symbol: "chart.bar.doc.horizontal"
            )
            helpFeatureRow(
                title: text("证据质量有上限", "Evidence quality sets a cap"),
                detail: text(
                    "观察到真实 Claude 进程连接最高可到 100；只有同时刻主动探测和交叉验证最高 92；仅有本机推断最高 78。选择保护方式但验证未完成时最高 84，验证失败或过期时最高 74。证据不足时显示“暂不可评分”，不会硬算成低分。",
                    "A live Claude process connection allows up to 100. Concurrent active probes with cross-checking cap the score at 92. Local inference alone caps it at 78. With a protection mode selected, incomplete gateway verification caps the score at 84, while failed or expired evidence caps it at 74. Insufficient evidence shows Not enough evidence instead of forcing a low score."
                ),
                symbol: "checkmark.shield"
            )
            helpFeatureRow(
                title: text("分档", "Bands"),
                detail: text(
                    "90–100 为完整，75–89 为良好，55–74 为有限，0–54 为需处理。分档帮助快速阅读，不替代具体检查结果。",
                    "90–100 is Strong, 75–89 Good, 55–74 Limited and 0–54 Needs attention. Bands help with quick reading and do not replace the detailed checks."
                ),
                symbol: "gauge.medium"
            )
            helpCallout(
                text(
                    "未启用、不适用和证据不足是三种不同状态：未启用实验性沙箱不会扣分，未选择代理保护方式时失败关闭区域不参与计分，缺少出口报告则暂不可评分。网络、代理、休眠唤醒或设置变化后，旧分数会变为“待复核”。",
                    "Disabled, not applicable and insufficient evidence are different states. Leaving the experimental sandbox off causes no deduction. With no protection mode, fail-closed verification does not participate. Without an egress report, no score is produced. After a network, proxy, wake or settings change, an old score becomes Review needed."
                ),
                symbol: "clock.arrow.circlepath"
            )
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "体检会向 ipify、ipinfo.io、Claude 跟踪地址、STUN 与系统 DNS 发送请求，这些服务会看到当前公网出口。DNS 与 STUN 探测、第三方 IP 查询都在右上角“高级设置…”中管理。第三方查询默认关闭；只有手动体检并主动开启后，出口 IP 才会发送给 ipwho.is 或 ipapi.is。",
                    "Checks contact ipify, ipinfo.io, the Claude trace endpoint, STUN and system DNS. Those services can see the current public exit. DNS and STUN probes plus third-party lookup are managed under Advanced settings in the top-right menu. Third-party lookup is off by default and sends the exit IP to ipwho.is or ipapi.is only after you enable it and run a manual check."
                )
            )
            helpParagraph(
                text(
                    "最近两次报告和最多 20 条出口历史保存在本机，可在“高级设置 → 本机数据”中清除；不会自动上传。",
                    "The two latest reports and up to 20 exits stay on this Mac and can be cleared under Advanced settings > Local data. They are never uploaded automatically."
                )
            )
            helpParagraph(
                text(
                    "实时进程证据只读取当前用户明确 Claude 进程的 TCP 连接数量，以及代理、代理绕过、自定义 API、区域和时区环境变量的存在状态与脱敏主机名。原始环境变量、命令行参数和令牌不会写入报告。",
                    "Live process evidence reads only the TCP connection counts of explicit Claude processes owned by the current user, plus whether proxy, proxy-bypass, custom API, locale and timezone variables are set and their masked hostnames. Raw environment variables, command-line arguments and tokens are never written to reports."
                )
            )
            helpCallout(
                text(
                    "Routekeeper 不读取 Claude 的 Cookie、登录凭证或对话内容，也不保证匿名、绕过账号风控或预测账号限制。",
                    "Routekeeper does not read Claude cookies, sign-in credentials or conversations, and cannot guarantee anonymity, bypass account risk controls or predict account restrictions."
                ),
                symbol: "hand.raised"
            )
        }
    }

    private var sandboxOverviewContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "实验性沙箱会复用普通网络保护中的固定出口、代理客户端识别和代理网关证据，但两者不是同一个开关的两种强度。普通保护不接管 Claude 的启动方式；沙箱在启动会话时增加执行边界。网关或出口检查未确认时会提示警告，由用户决定是否继续；Seatbelt 文件边界、本地中继可达、直连阻断和失败关闭仍然是硬门禁。",
                    "The experimental sandbox reuses fixed exits, proxy-client detection and gateway evidence from regular network protection, but the two are not two strengths of the same switch. Regular protection does not take over how Claude starts; the sandbox adds an execution boundary when a session starts. Unconfirmed gateway or exit evidence is shown as a warning and the user decides whether to continue. Seatbelt file boundaries, local-relay reachability, direct-connection blocking and fail-closed networking remain hard requirements."
                )
            )
            helpCallout(
                text(
                    "沙箱首次在“终端”中创建会话时，macOS 可能在“隐私与安全性 > 自动化”中要求允许 Routekeeper。请按系统提示完成授权，沙箱页会自动重新检查，授权卡片随后消失。",
                    "The first time the sandbox opens Terminal, macOS may ask you to allow Routekeeper under Privacy & Security > Automation. Follow the system prompt, then use the macOS authorization card on the Sandbox page to open that setting and check again."
                ),
                symbol: "hand.raised.fill"
            )
            helpSteps([
                text(
                    "系统弹出授权提示时，按提示允许 Routekeeper；不要通过关闭提示来跳过授权。",
                    "When macOS displays an authorization prompt, allow Routekeeper instead of dismissing it to bypass authorization."
                ),
                text(
                    "需要手动检查时，在沙箱页打开“自动化”设置，确认 Routekeeper 可以控制“终端”。",
                    "To check manually, open Automation settings from the Sandbox page and confirm that Routekeeper is allowed to control Terminal. The timing at which macOS applies a permission can vary by version."
                ),
                text(
                    "授权后返回 Routekeeper；沙箱页会在授权卡片仍显示时自动重新检查。",
                    "Return to Routekeeper after granting access; the Sandbox page keeps checking while the authorization card is visible."
                )
            ])
            helpParagraph(
                text(
                    "强制边界来自 macOS Sandbox（通常称 Seatbelt）。Routekeeper 通过系统 sandbox-exec 为每次会话加载临时规则，限制文件、网络与子进程访问。它不是 App Sandbox：App Sandbox 约束应用自身的签名权限，而这里需要约束由 Routekeeper 启动的外部 Claude 进程。",
                    "The enforcement boundary comes from macOS Sandbox, commonly known as Seatbelt. Routekeeper uses the system sandbox-exec command to load temporary rules for each session, restricting file, network and child-process access. This is not App Sandbox: App Sandbox constrains an app's own signed permissions, while Routekeeper needs to constrain external Claude processes that it launches."
                )
            )
            helpParagraph(
                text(
                    "sandbox-exec 已被 Apple 标记为弃用，因此实验性沙箱仍可能受到系统版本变化影响。规则加载或启动前检查失败时，Routekeeper 会停止启动，不会回退到无限制运行。",
                    "Apple has marked sandbox-exec as deprecated, so the experimental sandbox may still be affected by changes between system versions. If rule loading or preflight fails, Routekeeper stops the launch instead of falling back to unrestricted operation."
                )
            )
            VStack(spacing: 10) {
                helpFeatureRow(
                    title: text("普通网络保护", "Regular network protection"),
                    detail: text(
                        "在真实主机环境中观察 Claude 进程和网络路径；发现异常时，按“异常动作”提醒或结束受保护进程。",
                        "Observes Claude processes and network paths in the real host environment, then uses Incident action to notify or terminate a protected process when something is wrong."
                    ),
                    symbol: "shield.lefthalf.filled"
                )
                helpFeatureRow(
                    title: text("实验性沙箱", "Experimental sandbox"),
                    detail: text(
                        "为每个目标复制项目到独立工作副本，使用独立 HOME、临时目录和本机中继，限制文件访问并拒绝公网、局域网直连。",
                        "Copies the project into a separate workspace for each target, uses an isolated HOME and temporary directory plus a local relay, restricts file access and denies direct public or LAN connections."
                    ),
                    symbol: "lock.shield"
                )
            }
            helpParagraph(
                text(
                    "Claude Code、Claude 和 Chrome 共享项目来源、交换根目录、时区、语言地区、出口默认值和本机上游代理设置，但三者各自启动并维护独立状态与工作数据。共享环境不等于共享权限：Routekeeper 不会自动把工作副本覆盖回原项目，也不会把 Claude Code 凭证交给 Claude，或把宿主 Chrome 的登录数据交给独立 Chrome 配置。",
                    "Claude Code, Claude and Chrome share the project source, exchange root, timezone, language region, exit defaults and local upstream proxy settings, while each keeps its own launch state and working data. A shared environment does not mean shared permissions: Routekeeper never copies a workspace back over the original project automatically, never gives Claude Code credentials to Claude, and never gives host Chrome sign-in data to the dedicated Chrome profile."
                )
            )
            helpCallout(
                text(
                    "这是进程隔离，不是虚拟机。Claude 不能直接访问公网或局域网，也不能打开默认浏览器，但仍可能读取主机网卡名称、地址、路由和 DNS 配置。 Chrome 使用独立的官方 Chrome 配置和中继，但 Chrome 仍运行在自己的原生沙箱中，不获得实验性沙箱的完整文件边界；Routekeeper 不内置浏览器，也不接受来源不明的 Chromium。",
                    "This is process isolation, not a virtual machine. Claude cannot reach the public internet or LAN directly and cannot open the default browser, but it may still read host interface names, addresses, routes and DNS configuration. Chrome uses a dedicated official Chrome profile and relay, but Chrome still runs in its own native sandbox and does not receive the experimental sandbox's full filesystem boundary. Routekeeper neither bundles a browser nor accepts an unverified Chromium build."
                ),
                symbol: "exclamationmark.shield"
            )
            helpParagraph(
                text(
                    "网络体检和代理网关验证会为普通监控提供前置判断，也会为沙箱提供出口警告。沙箱不会仅因这些检查未完成而拒绝创建会话；它仍会独立验证中继、文件边界和断网保护。沙箱开关已开启但没有任何活动会话时，仍可运行主机检查；只有会话进入准备、检查、运行或暂停状态后，主机网络检查才暂时不可用。",
                    "Network checks and gateway verification inform ordinary monitoring and provide exit warnings for the sandbox. The sandbox does not refuse to create a session solely because those checks are incomplete; it still verifies the relay, filesystem boundary and fail-closed networking independently. Host checks remain available when sandbox mode is on but no session is active, and pause only while a session is preparing, checking, running or network-paused."
                )
            )
        }
    }

    private var sandboxTargetsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "沙箱页面把 Claude Code、Claude 和 Chrome 放在同一条横向卡片轨道中。窗口较窄时使用触控板或滚动条左右滑动，不会把第三张卡换到下一行。Claude Code 和 Claude 可在卡片右上角启用或关闭；Chrome 始终使用独立配置单独打开。",
                    "The sandbox page places Claude Code, Claude and Chrome in one horizontal card track. On narrower windows, swipe or use the scrollbar to move sideways; the third card never wraps onto a new row. Claude Code and Claude can be enabled or disabled from each card's top-right switch, while Chrome opens independently in its own Chrome profile."
                )
            )
            helpCallout(
                text(
                    "项目、交换目录、时区、语言地区、出口默认值和上游代理位于标题栏右上角菜单的“共享环境、时区与地区…”。主页面不再重复放置共享设置卡；修改后会同步到三个 Claude 环境。",
                    "Project, exchange folder, timezone, language region, exit defaults and upstream proxy live under Shared environment, timezone and region in the top-right title-bar menu. The main page no longer repeats a shared-settings card, and changes are applied to all three Claude environments."
                ),
                symbol: "slider.horizontal.3"
            )
            helpParagraph(
                text(
                    "三张卡片使用相同的结构：顶部是名称与状态，中部是各自的环境详情和次要操作，底部固定显示当前状态与唯一主操作。主操作始终位于卡片右下角；重新检测、选择命令、获取客户端和管理登录等次要操作使用统一的灰色样式，不会与主操作争夺注意力。",
                    "All three cards use the same structure: name and status at the top, environment details and secondary actions in the middle, and current state plus one primary action at the bottom. The primary action always sits at the bottom-right; secondary actions such as Detect again, Choose command, Get app and Manage sign-in use the same neutral style so they do not compete with it."
                )
            )
            helpParagraph(
                text(
                    "项目工作副本位于用户主目录的 `~/Routekeeper/Workspaces/项目名/会话名/workspace`，同一目录下的 `session.json` 记录来源、目标和时间。创建会话后可以随时选择“在 Finder 中显示”，不需要等待会话结束。沙箱的独立 HOME、临时文件、日志和控制文件仍保存在 Routekeeper 的应用支持目录中。",
                    "Project workspaces live under `~/Routekeeper/Workspaces/project/session/workspace` in your home folder, and `session.json` records the source, target and times. After a session is created, choose Show in Finder at any time; you do not need to wait for the session to end. The sandbox HOME, temporary files, logs and control files remain in Routekeeper's application-support directory."
                )
            )
            helpSteps([
                text(
                    "Claude Code 卡会复用现有 claude 命令；不在默认位置时使用“选择命令…”指定。登录凭证是可选配置，不影响创建隔离会话。",
                    "The Claude Code card reuses an existing claude command and offers Choose command when it is outside the default location. Sign-in is optional and does not block creation of an isolated session."
                ),
                text(
                    "Claude 卡会验证官方签名与客户端版本；右下角主操作依次可能是获取官方客户端、创建隔离会话或启动 Claude。",
                    "The Claude card verifies the official signature and app version. Its bottom-right primary action progresses through Get official app, Create isolated session and Launch Claude as appropriate."
                ),
                text(
                    "Chrome 卡会验证官方 Chrome 和独立配置；右下角主操作是打开 Chrome，运行后则变为关闭 Chrome 或恢复网络。",
                    "The Chrome card verifies official Chrome and the dedicated profile. Its bottom-right primary action opens Chrome; once running, it changes to Close browser or Restore network as needed."
                ),
                text(
                    "同一个项目会分别复制到 Claude Code 和 Claude 的会话目录；Chrome 不获得项目文件夹写入权限。各环境的修改不会互相覆盖，审阅时需要分别处理。",
                    "The same project is copied separately into the Claude Code and Claude session folders; Chrome receives no project-folder write access. Changes never overwrite each other and must be reviewed per environment."
                )
            ])
            helpCallout(
                text(
                    "未安装任何 Claude 客户端不会阻止普通网络保护。关闭 Claude Code 或 Claude 前必须先结束该卡片的会话；关闭实验性沙箱则要求所有已启用目标和 Chrome 都没有活动运行。",
                    "Missing Claude clients do not block regular network protection. End a card's session before disabling Claude Code or Claude. Turning off the experimental sandbox requires every enabled target and Chrome to be inactive."
                ),
                symbol: "power"
            )
        }
    }

    private var sandboxWebContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "Chrome 是一个可选的伴随浏览器，不是第三个 Claude 进程保护对象。Routekeeper 只启动已验证签名的 Google Chrome，并让它使用独立配置、Cookie、缓存、下载目录与本机代理；不会读取或导入宿主 Chrome 的登录状态、密码、历史记录和扩展。",
                    "Chrome is an optional companion browser, not a third protected Claude process. Routekeeper launches only a verified Google Chrome bundle and gives it a dedicated profile, cookies, cache, download directory and local proxy. It never reads or imports sign-in state, passwords, history or extensions from the host Chrome profile."
                )
            )
            helpSteps([
                text(
                    "在标题栏右上角菜单的“共享环境、时区与地区…”中设置时区和语言地区。Routekeeper 会把它们传入独立 Chrome 的启动环境、网页请求语言和三个 Claude 环境，不修改 macOS 系统设置。",
                    "Set timezone and language region under Shared environment, timezone and region in the top-right title-bar menu. Routekeeper passes them to the dedicated Chrome launch environment, web request language and all three Claude environments without changing macOS settings."
                ),
                text(
                    "网络通过本机 Routekeeper 中继和当前上游代理转发。路由不会被外部进程重写；当前代理看到的是 Routekeeper 中继，而不是 Chrome，因此 Claude 域名规则比 Chrome 进程规则更重要。",
                    "Network traffic goes through the local Routekeeper relay and the current upstream proxy. Routing is not rewritten by an external process, and the current proxy sees the Routekeeper relay instead of Chrome, so Claude domain rules matter more than a Chrome process rule."
                ),
                text(
                    "打开前，Routekeeper 会用同一中继访问 Claude，并核对实际出口。未设置固定出口、没有取得结果或出口不一致时会明确警告；检查不是打开 Chrome 的前置条件，你确认风险后仍可继续。暂停中继后，Chrome 会立即失去网络，但浏览器窗口仍可保留。",
                    "Before opening, Routekeeper checks the actual exit through the same relay by reaching Claude. A missing fixed exit, missing result or mismatch produces a clear warning. The check is not a prerequisite for opening the browser, and you may continue after confirming the risk. Pausing the relay immediately removes browser networking while the window can remain open."
                ),
                text(
                    "Chrome 中的 Claude 登录保存在独立配置中。可从页面右上角菜单关闭 Chrome 网络或清除该配置；宿主 Chrome 不受影响。",
                    "Claude sign-in in Chrome is stored in the dedicated profile. Use the page's top-right menu to pause Chrome networking or clear the profile without affecting host Chrome."
                )
            ])
            helpCallout(
                text(
                    "Chrome 必须保留自己的原生沙箱。macOS 不支持安全地嵌套 sandbox-exec，因此 Routekeeper 不会用外层 sandbox-exec 包裹 Chrome，也不会使用 --no-sandbox。它提供的是独立浏览器配置、语言、时区和受控网络路径，不是虚拟机级隔离。",
                    "Chrome must keep its own native sandbox. macOS does not support safely nesting sandbox-exec, so Routekeeper neither wraps Chrome with an outer sandbox-exec nor uses --no-sandbox. The result is an isolated browser profile with language, timezone and a controlled network path, not virtual-machine isolation."
                ),
                symbol: "exclamationmark.shield"
            )
            helpCallout(
                text(
                    "在当前代理中启用 TUN 时，虚拟网卡是系统流量的入口；代理的“出站网卡”是它连接上游节点时使用的接口。后者通常应保持自动，只有存在多个物理出口时才指定实际网卡。把出站网卡设为代理自己创建的 utun 可能导致回环，不能用来修复 Claude 直连。",
                    "When TUN is enabled in the current proxy, the virtual interface is the ingress for system traffic. The proxy's Outbound interface is used to reach its upstream node. It should normally remain automatic and should use a physical interface only when multiple physical paths exist. Setting it to the proxy's own utun can create a loop and does not fix direct routing for Claude."
                ),
                symbol: "network"
            )
        }
    }

    private var sandboxPathsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "项目文件夹是读取来源，沙箱会把它复制到 `~/Routekeeper/Workspaces` 下、以项目名和会话名组织的用户可见工作副本。交换根目录是文件交付的上级目录，系统会在其中为 Claude Code 和 Claude 分别创建交换子目录，避免并发会话写入同一位置。 Chrome 使用独立的 Chrome 下载目录，不直接写入项目。",
                    "The project folder is the source. The sandbox copies it into a user-visible workspace under `~/Routekeeper/Workspaces`, organized by project and session. The exchange root is the parent for handoff files; Routekeeper creates separate exchange folders for Claude Code and Claude so concurrent sessions do not write to the same location. Chrome uses its own Chrome download directory and never writes directly into the project."
                )
            )
            helpSteps([
                text("项目文件夹与交换根目录不能相同，也不能互相包含。", "The project folder and exchange root cannot be identical or contain each other."),
                text("系统会在交换根目录下建立“Claude Code”和“Claude”子目录。", "Routekeeper creates Claude Code and Claude subfolders under the exchange root."),
                text("工作副本容器带有 Routekeeper 归属标记；清理页只处理可确认归属的副本，且不会默认勾选用户工作副本。", "Each workspace container has a Routekeeper ownership marker. Cleanup only handles verified copies and never selects user workspaces by default."),
                text("共享环境的时区、语言地区和出口默认值会用于这三个环境；目录路径仍各自独立。", "Shared timezone, language region and exit defaults apply to all three environments, while their paths remain independent."),
                text("会话结束后，工作副本仍保留供审阅；清理会话或 Chrome 配置 只会删除 Routekeeper 自己管理的数据。", "After a session ends, its workspace remains for review. Cleanup or clearing the Chrome profile removes only data managed by Routekeeper.")
            ])
        }
    }

    private var sandboxNetworkContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "每个沙箱会话都通过自己的本机 Routekeeper 中继访问上游代理。上游只接受 127.0.0.1、::1 或 localhost；代理不可用时会话直接失败，不会回退为公网直连。",
                    "Each sandbox session reaches its upstream proxy through its own local Routekeeper relay. The upstream must be 127.0.0.1, ::1 or localhost. If the proxy is unavailable, the session fails instead of falling back to direct internet access."
                )
            )
            helpParagraph(
                text(
                    "代理配置一致性用于比较系统代理与共享上游设置。系统代理不是本机端口时，沙箱不会直接使用它。代理与边界入口位于页面右上角菜单，不再重复占用主页面。",
                    "Proxy configuration consistency compares the system proxy with the shared upstream. A non-loopback system proxy is never used directly. Proxy and boundary details live in the top-right page menu instead of duplicating content on the main page."
                )
            )
            helpCallout(
                text(
                    "网络变化、系统休眠或代理中断会关闭受影响会话的网络，并按该会话自己的证据重新验证。另一个会话的状态不会被伪造成相同的通过或失败。",
                    "Network changes, sleep or proxy interruption close networking for the affected session and revalidate its own evidence. The other session's state is never falsely copied."
                ),
                symbol: "network.slash"
            )
        }
    }

    private var sandboxSessionsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "Claude Code、Claude 和 Chrome 的准备、启动、暂停网络与结束操作彼此独立。工具栏菜单只显示当前可用的会话操作；每张卡片右下角只显示该环境当前真正需要的下一步。",
                    "Preparation, launch, network pause and shutdown are independent for Claude Code, Claude and Chrome. The toolbar menu shows only currently available session actions, while each card's bottom-right action shows only the next step needed for that environment."
                )
            )
            helpSteps([
                text("先在右上角“共享环境、时区与地区…”完成共享配置，再补齐卡片内的客户端、登录凭证和 Chrome 准备项。", "Complete shared configuration under Shared environment, timezone and region in the top-right menu, then resolve client, sign-in and Chrome prerequisites inside each card."),
                text("使用卡片右下角主操作创建隔离会话或打开 Chrome；三个环境可以分别进行。代理网关或出口核对未确认时会显示警告，但不会阻止启动。", "Use the bottom-right primary action to create an isolated session or open Chrome. All three can proceed independently. Unconfirmed gateway or exit verification shows a warning but does not block launch."),
                text("会话运行后可以单独关闭或恢复网络，也可以单独结束并审阅工作副本；Chrome 可以关闭或清除独立配置。", "After a session starts, pause or restore its network and review or end its workspace independently. Chrome can close or clear its dedicated profile."),
                text("关闭实验性沙箱使用顶部状态卡右侧的操作，并需要确认；存在活动会话或正在运行的 Chrome 时不可关闭。", "Turning off the experimental sandbox uses the action beside the status card at the top of the page and requires confirmation. It is unavailable while a session or Chrome is running.")
            ])
        }
    }

    private var sandboxStatusContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpParagraph(
                text(
                    "主操作颜色表达正在执行的动作，不代表账号或 Claude 服务端状态。三张卡都遵守同一套规则，主按钮始终位于右下角。",
                    "Primary-action colors describe the action you are about to perform, not the account or Claude server state. All three cards follow the same rules, and the primary button always sits at the bottom-right."
                )
            )
            evidenceRow(
                title: text("蓝色", "Blue"),
                detail: text("普通主操作，例如创建隔离会话、启动 Claude、打开 Chrome。", "Normal primary actions such as creating an isolated session, launching Claude or opening Chrome."),
                symbol: "arrow.right.circle.fill",
                color: appAccent
            )
            evidenceRow(
                title: text("橙色", "Orange"),
                detail: text("需要处理后再继续，例如恢复网络、修正配置、重试或查看网关警告。", "Actions that need attention first, such as restoring networking, fixing configuration, retrying or reviewing a gateway warning."),
                symbol: "exclamationmark.circle.fill",
                color: appStatusWarning
            )
            evidenceRow(
                title: text("红色", "Red"),
                detail: text("关闭沙箱、关闭浏览器、拒绝操作，以及其他需要明确警示的破坏性动作。", "Turn off the sandbox, close the browser, reject an operation and other destructive actions that need a clear warning."),
                symbol: "xmark.circle.fill",
                color: appStatusFailure
            )
            evidenceRow(
                title: text("绿色", "Green"),
                detail: text("只表示状态已经通过或运行正常，不作为主按钮颜色。", "Used for passed or healthy state, never as the normal primary-button color."),
                symbol: "checkmark.circle.fill",
                color: appStatusSuccess
            )
            evidenceRow(
                title: text("灰色", "Gray"),
                detail: text("重新检测、选择命令、管理登录、查看帮助等不会改变主要流程的次要操作。", "Secondary actions that do not change the main flow, such as Detect again, Choose command, Manage sign-in or help."),
                symbol: "circle.fill",
                color: Color(nsColor: .secondaryLabelColor)
            )
            helpParagraph(
                text(
                    "如果按钮不可用，先查看同一张卡片中标注为橙色的阻塞项。共享环境、固定出口或代理问题会同时影响三个 Claude 环境；客户端安装、登录凭证和 Chrome 配置问题只影响对应环境。",
                    "If an action is unavailable, first review the orange blocking item in the same card. Shared environment, fixed exit or proxy problems affect all three Claude environments; client installation, sign-in and Chrome profile issues affect only their environment."
                )
            )
        }
    }

    private func helpParagraph(_ value: String) -> some View {
        Text(value)
            .routekeeperFont(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func helpFeatureRow(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .routekeeperFont(.callout, weight: .semibold)
                Text(detail)
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.inset, corner: 11)
        .accessibilityElement(children: .combine)
    }

    private func helpFAQRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .routekeeperFont(.callout, weight: .semibold)
                Text(detail)
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func helpSteps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .routekeeperFont(.caption, weight: .bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06), in: Circle())
                    Text(step)
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                .padding(.vertical, 10)
                if index < steps.count - 1 {
                    AppHairline().padding(.leading, 36)
                }
            }
        }
    }

    private func evidenceRow(
        title: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).routekeeperFont(.callout, weight: .semibold)
                Text(detail)
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.inset, corner: 11)
    }

    private func helpCallout(_ value: String, symbol: String) -> some View {
        Label(value, systemImage: symbol)
            .routekeeperFont(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface(.inset, corner: 11)
    }

    private func applyPendingSection() {
        if let section = RoutekeeperHelpNavigation.consumePendingSection() {
            selection = section
        }
    }
}
