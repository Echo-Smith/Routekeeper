import GuardCore

extension CheckItem {
    var needsAttention: Bool {
        level == .failed || level == .unknown || (level == .warning && !["boundary", "dns", "udp-ipv4", "udp-ipv6"].contains(id))
    }
    var nextStep: String {
        let en = L10n.resolvedEnglish
        switch id {
        case "target", "alternate-target", "stack-ipv4", "stack-ipv6", "claude-trace-exit":
            return en ? "Next: set the expected fixed exit IP in Network protection, then check again." : "下一步：在“网络保护”中填写对应的固定出口 IP，再重新检查。"
        case "scope", "desktop", "code":
            return en ? "Next: install the selected Claude app, or deselect it in Network protection." : "下一步：安装所选 Claude 应用，或在“网络保护”中取消保护未安装的应用。"
        case "interval":
            return en ? "Next: set the monitoring interval to 1–300 seconds." : "下一步：将监控核验间隔设置为 1–300 秒。"
        case "dns":
            return en ? "Next: check your proxy client's DNS settings and connectivity, then check again. A timeout is not a pass." : "下一步：检查代理客户端的 DNS 配置及联网状态，再重新检查；超时不代表通过。"
        case "udp-ipv4", "udp-ipv6":
            return en ? "Next: check UDP support in your proxy and node, then retry. No response does not prove blocking." : "下一步：检查代理和节点是否支持 UDP，再重新检查；没有响应不能证明已阻断。"
        case "process-access":
            return en ? "Next: ensure Claude is running normally and retry. Process inspection must succeed before monitoring." : "下一步：确认 Claude 正常运行后重试；进程检查成功前无法开启监控。"
        case "egress-audit":
            return en
                ? "Next: run the full check again and review any failed or unknown exit evidence. Missing evidence is not a pass."
                : "下一步：重新运行完整体检，并核对未通过或未知的出口证据；缺失证据不代表通过。"
        case "egress-service":
            return en
                ? "Next: confirm the proxy can reach Claude services, check DNS and node health, then run the full check again."
                : "下一步：确认代理能够连接 Claude 服务，检查 DNS 与节点状态后重新运行完整体检。"
        case "egress-ipv6":
            return en
                ? "Next: check IPv6 routing and the proxy's TUN rules, then run the full check again. Unknown IPv6 paths are not a pass."
                : "下一步：检查 IPv6 路由与代理的 TUN 规则后重新运行完整体检；IPv6 路径未知不代表通过。"
        default:
            return en ? "Next: open your proxy client, verify the selected node and TUN mode, then return here and check again. If the exit changed, confirm it before updating your fixed target." : "下一步：打开代理客户端，检查所选节点和 TUN 模式，再返回重新检查。若出口发生变化，请确认后再修改固定目标。"
        }
    }
}
