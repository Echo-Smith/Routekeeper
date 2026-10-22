import SwiftUI
import GuardCore

enum DisclaimerDocument {
    static let currentVersion = "2026-10-21.4"
}

struct DisclaimerConsentSheet: View {
    let onAgree: () -> Void
    let onQuit: () -> Void

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Label(text("免责声明", "Disclaimer"), systemImage: "doc.text")
                    .routekeeperFont(.title2, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(text("请阅读并同意以下条款后继续使用。",
                          "Read and accept these terms before continuing."))
                    .routekeeperFont(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DisclaimerScopeNotice()
                    AppHairline()
                    JustifiedText(text(
                        "在使用 Routekeeper（以下简称“本软件”）前，请仔细阅读并充分理解本声明的全部内容。点击“同意”即表示你已阅读、理解并接受以下全部条款；如不同意，请点击“退出”并停止使用本软件。",
                        "Before using Routekeeper (the “Software”), read and understand this notice. Clicking Agree confirms that you accept all terms below. If you do not agree, click Quit and stop using the Software."
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    DisclaimerBody()
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Button(text("退出", "Quit"), role: .destructive, action: onQuit)
                Spacer()
                Button(text("同意并继续", "Agree and continue"), action: onAgree)
                    .routekeeperProminentButton()
            }
        }
        .padding(24)
        .frame(minWidth: 720, idealWidth: 840, maxWidth: 960, minHeight: 600, idealHeight: 700, maxHeight: 800)
        .accessibilityIdentifier("disclaimer-consent")
    }
}

struct DisclaimerBody: View {
    private struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    private var sections: [Section] {
        if L10n.resolvedEnglish {
            return [
                .init(
                    title: "1. Software nature",
                    body: "Routekeeper is a local network inspection and monitoring aid. It is not an antivirus product, firewall, guarantee of network anonymity, or an official Anthropic or Claude product. In Claude Desktop, Chat is an in-app web workspace and Code uses Claude Code; the sandbox treats the official app and its helper processes as one application boundary. The sandbox enforces a traffic path but does not virtualize host network metadata: a sandboxed process may still read interface names, addresses, routes and resolver configuration even though direct LAN and public traffic is denied. Probe results may be incomplete and must be interpreted together with your own network environment."
                ),
                .init(
                    title: "2. Usage restrictions",
                    body: "The Software is provided only for learning, technical research and other non-commercial purposes. Do not use it for any commercial purpose, including paid distribution, bundling for sale, inclusion in a commercial service, or business activity conducted in the Software’s name. Commercial activity is unrelated to the Software and its developer. Do not use the Software for activity that violates applicable laws or regulations, including circumventing lawful network access restrictions, distributing unlawful material, attacking networks, or infringing the rights of others."
                ),
                .init(
                    title: "3. User responsibility",
                    body: "You are responsible for the software, configurations, proxy clients, scripts and network settings you choose to use, and for confirming that they comply with local law and the terms of any third-party service. Before making changes, review them and keep any backups you need."
                ),
                .init(
                    title: "4. No warranty",
                    body: "To the maximum extent permitted by law, the Software is provided “as is” and “as available”. The developer makes no express or implied warranty of accuracy, completeness, availability, fitness for a particular purpose, or non-infringement. A check cannot guarantee that traffic is protected, that an account is safe, or that no data will be exposed."
                ),
                .init(
                    title: "5. Third-party content",
                    body: "The Software may interoperate with Claude, proxy clients, DNS, STUN and optional IP information services. The developer does not control and is not responsible for their content, availability, accuracy, policies or changes. Their terms and privacy practices continue to apply."
                ),
                .init(
                    title: "6. Limitation of liability",
                    body: "To the maximum extent permitted by law, the developer is not liable for indirect, incidental, special, consequential or punitive loss arising from use of or inability to use the Software, including loss of data, account access, network connectivity, profits or business opportunities. Mandatory rights that cannot be excluded by law remain unaffected."
                ),
                .init(
                    title: "7. Data collection and privacy",
                    body: "Reports and history are stored locally. Inspection uses network requests to services such as ipify, ipinfo.io, STUN and DNS providers and claude.ai; those services can see your public egress IP. Optional third-party IP intelligence lookups remain off unless you enable them. The Software does not automatically upload saved reports. Claude Code sign-in tokens are stored in the macOS Keychain and are not included in reports. If persistent Claude Desktop sign-in is enabled, cookies and local Claude data are retained in a Routekeeper-owned application-support profile until you clear that profile or reset local information."
                ),
                .init(
                    title: "8. Changes to this notice",
                    body: "This notice may be updated when features, data flows or legal requirements change. A revised notice is shown before the affected version requires new acceptance."
                ),
                .init(
                    title: "9. Acceptance",
                    body: "By clicking Agree, you confirm that you have read, understood and accepted this notice. If you do not agree, click Quit and do not use the Software."
                )
            ]
        }

        return [
            .init(
                title: "一、软件性质",
                body: "Routekeeper 是一款运行在本机的网络检查与监控辅助工具，不是杀毒软件、防火墙、网络匿名保证，也不是 Anthropic 或 Claude 的官方产品。Claude Desktop 的 Chat 模式是应用内网页工作区，Code 模式使用 Claude Code；沙箱把官方应用及其 helper 进程视为同一个应用边界。沙箱强制的是流量路径，不虚拟化主机网络元数据：受限进程仍可能读取网卡名称、地址、路由和 DNS 解析器配置，但局域网与公网直连会被拒绝。检测结果可能不完整，需要结合实际网络环境理解。"
            ),
            .init(
                title: "二、使用限制",
                body: "本软件仅供学习交流、技术研究等非商业用途。严禁将本软件用于任何商业目的，包括但不限于付费分发、捆绑销售、作为商业服务的组成部分或以本软件名义开展经营活动；任何商业行为均与本软件及其开发者无关。\n\n严禁将本软件用于违反你所在国家或地区法律法规的活动，包括但不限于绕过依法设置的网络访问限制、传播违法信息、实施网络攻击或侵犯他人合法权益。"
            ),
            .init(
                title: "三、用户责任",
                body: "你应自行选择并核验所使用的软件、配置、代理客户端、脚本与网络设置，并确保其符合当地法律及第三方服务条款。进行配置变更前，请先了解影响并自行做好必要备份。"
            ),
            .init(
                title: "四、无担保声明",
                body: "在适用法律允许的最大范围内，本软件按“现状”和“现有”提供。开发者不对准确性、完整性、可用性、特定用途适用性或无侵权作出明示或默示保证。任何一次检测都不能保证网络流量已受保护、账号一定安全或数据不会暴露。"
            ),
            .init(
                title: "五、第三方内容",
                body: "本软件可能与 Claude、代理客户端、DNS、STUN 及可选的 IP 信息服务配合使用。开发者不控制这些第三方服务的内容、可用性、准确性、政策或变更，也不对其承担责任。第三方的服务条款和隐私政策仍然适用。"
            ),
            .init(
                title: "六、责任限制",
                body: "在适用法律允许的最大范围内，对于因使用或无法使用本软件而产生的间接、附带、特殊、后果性或惩罚性损失，包括数据、账号访问、网络连接、利润或商业机会损失，开发者不承担责任。依法不能排除的权利不受本段影响。"
            ),
            .init(
                title: "七、数据搜集与隐私",
                body: "报告和历史记录保存在本机。检查过程会请求 ipify、ipinfo.io、STUN、DNS 服务及 claude.ai，这些服务能够看到当前的公网出口 IP。可选的第三方 IP 情报查询默认关闭，只有你主动开启后才会使用。本软件不会自动上传已保存的报告。Claude Code 登录凭证保存在 macOS 系统钥匙串中，不会写入检测报告。若你启用 Claude Desktop 持久登录，Cookie 和本地 Claude 数据会保存在 Routekeeper 专属的应用支持目录中，直到你主动清除该配置或清空本地信息。"
            ),
            .init(
                title: "八、声明变更",
                body: "本软件的功能、数据流或法律要求发生变化时，本声明可能更新。更新后的声明会在需要重新同意前向你展示。"
            ),
            .init(
                title: "九、接受协议",
                body: "点击“同意”即表示你已阅读、理解并接受本声明。如不同意，请点击“退出”并停止使用本软件。"
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.title)
                        .routekeeperFont(.headline)
                        .accessibilityAddTraits(.isHeader)
                    JustifiedText(section.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DisclaimerScopeNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                L10n.resolvedEnglish ? "Purpose and limits" : "用途与边界",
                systemImage: "person.badge.shield.checkmark"
            )
            .routekeeperFont(.headline)
            .accessibilityAddTraits(.isHeader)
            JustifiedText(
                L10n.resolvedEnglish
                    ? "Routekeeper helps users manage a Claude identity they lawfully hold, verify this Mac’s network egress, and inspect the Claude client environment. It must not be used to violate Anthropic’s Terms of Service or applicable law. Local settings do not change Anthropic’s server-side records and do not guarantee anonymity, account availability, or server-side regional status."
                    : "Routekeeper用于帮助用户管理本人合法持有的Claude身份，并核验本机网络出口与Claude客户端环境。禁止用于违反Anthropic服务条款或适用法律的行为。本地设置不会更改Anthropic服务端记录，不保证匿名、账号可用性或服务端地区状态。"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JustifiedText: NSViewRepresentable {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    private var font: NSFont {
        NSFont.preferredFont(forTextStyle: .callout)
    }

    private var attributedContent: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .natural
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        return NSAttributedString(
            string: content,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(wrappingLabelWithString: "")
        textField.isEditable = false
        textField.isSelectable = true
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        textField.focusRingType = .none
        textField.cell?.wraps = true
        textField.cell?.usesSingleLineMode = false
        textField.cell?.isScrollable = false
        textField.cell?.truncatesLastVisibleLine = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.attributedStringValue = attributedContent
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextField,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }
        nsView.preferredMaxLayoutWidth = width
        let bounds = attributedContent.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: width, height: ceil(bounds.height) + 2)
    }
}
