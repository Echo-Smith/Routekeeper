import Foundation

public enum RoutingProtection {
    public static func agentPrompt(clientName: String) -> String {
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = trimmed.isEmpty ? "当前代理客户端" : trimmed
        return """
        帮我改 \(client) 的分流规则。目标：国内域名和国内 IP 直连，其余所有流量走我指定的海外节点；节点断了的时候宁可断网，也不要回落直连。

        1. 先找到我正在用的 \(client) 客户端和当前生效的配置文件，完整备份一份，告诉我备份在哪。
        2. 保留我原有的节点订阅和局域网直连规则，不认识的节点不要删也不要换。
        3. 加入国内域名和国内 IP 段的规则集（国内域名来源：https://github.com/pluwen/china-domain-allowlist；国内 IP 段来源：https://github.com/Loyalsoldier/clash-rules 里的 cncidr 规则集），命中的走直连。请使用适合当前客户端和内核的规则格式。
        4. 规则最后的兜底指向我指定的海外节点，不要留默认直连；海外节点所在的代理组里不要放 DIRECT。若当前客户端没有代理组，请先说明如何实现等效的断线不回落直连，再实施。
        5. 检查规则顺序和 DNS 设置，别让国外域名被国内 DNS 解析后走了直连。
        6. 开启 TUN 模式，确认虚拟网卡实际运行，终端里的命令行程序也走代理。
        7. 改完帮我验证：国内网站走直连；claude.ai 走海外节点；在终端里查一下出口 IP，确认在海外；再把海外节点断掉，确认 claude.ai 打不开、国内网站照常能访问。验证结束后恢复节点，并说明每项结果。
        8. 最后告诉我怎么一键恢复到改之前的配置。

        请先核对实际客户端、版本和内核能力。如果当前客户端不支持规则集、DNS 分流、代理组或 TUN，请说明限制和可行方案并先问我，不要假设功能存在，也不要擅自更换客户端或节点。
        缺什么信息先问我，包括要使用的海外节点名称，不要猜。
        """
    }

    public static func restrictionPrompt(clientName: String) -> String {
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = trimmed.isEmpty ? "当前代理客户端" : trimmed
        return """
        帮我限制 Claude 的网络连接，让 Claude Desktop 和 Claude Code 只能通过当前代理使用我指定的海外节点；节点不可用时宁可连接失败，也不要回落直连。

        1. 先找到我正在用的 \(client) 客户端、当前版本、实际内核和当前生效的配置文件，完整备份一份，并告诉我备份在哪。
        2. 保留我原有的节点订阅和局域网规则，不认识的节点不要删也不要换。
        3. 优先使用客户端支持的进程或应用分流能力，把 Claude Desktop 和 Claude Code 固定到只包含指定海外节点的代理组；该代理组和最终兜底都不得包含 DIRECT。
        4. 如果当前客户端不能按进程或应用设置规则，请先说明限制和可行方案并询问我，不要假设功能存在，也不要擅自改用其他客户端或节点。
        5. 检查 DNS 和 TUN 设置。Claude Code 从终端运行，必须确认终端里的 Claude Code 进程实际走代理，不能只限制图形界面应用。
        6. 改完后验证：正常状态下 Claude 走海外节点；断开该海外节点后 Claude 无法联网且不会回落直连；其他应用按原有规则正常工作。验证结束后恢复节点，并说明每项结果。
        7. 最后告诉我如何一键恢复到改之前的配置。

        请先核对实际客户端、版本和内核能力。缺什么信息先问我，包括要使用的海外节点名称，不要猜。
        """
    }
}
