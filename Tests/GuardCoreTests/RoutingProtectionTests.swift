import XCTest
@testable import GuardCore

final class RoutingProtectionTests: XCTestCase {
    func testProxyClientCatalogIncludesRequestedProtocols() {
        XCTAssertTrue(ProxyClient.allCases.contains(.clash))
        XCTAssertTrue(ProxyClient.allCases.contains(.v2ray))
        XCTAssertTrue(ProxyClient.allCases.contains(.shadowsocks))
        XCTAssertEqual(ProxyClient.v2ray.title, "V2Ray")
        XCTAssertEqual(ProxyClient.shadowsocks.title, "Shadowsocks")
    }

    func testAgentPromptUsesTheConfiguredClientAndRequiredSafeguards() {
        let prompt = RoutingProtection.agentPrompt(clientName: "V2Ray")
        XCTAssertTrue(prompt.contains("帮我改 V2Ray 的分流规则"))
        XCTAssertTrue(prompt.contains("https://github.com/pluwen/china-domain-allowlist"))
        XCTAssertTrue(prompt.contains("https://github.com/Loyalsoldier/clash-rules"))
        XCTAssertTrue(prompt.contains("宁可断网，也不要回落直连"))
        XCTAssertTrue(prompt.contains("完整备份一份"))
        XCTAssertTrue(prompt.contains("开启 TUN 模式"))
        XCTAssertTrue(prompt.contains("claude.ai"))
        XCTAssertTrue(prompt.contains("api.anthropic.com"))
        XCTAssertTrue(prompt.contains("看到的进程是 Routekeeper"))
        XCTAssertTrue(prompt.contains("出站网卡"))
        XCTAssertTrue(prompt.contains("不要填写 FlClash 自己创建的 utun"))
        XCTAssertTrue(prompt.contains("要使用的海外节点名称，不要猜"))
        XCTAssertFalse(prompt.contains("帮我改 Clash 的分流规则"))
    }

    func testRestrictionPromptKeepsClaudeFailClosedAndAsksBeforeChangingClients() {
        let prompt = RoutingProtection.restrictionPrompt(clientName: "FlClash")
        XCTAssertTrue(prompt.contains("帮我限制 Claude 的网络连接"))
        XCTAssertTrue(prompt.contains("FlClash 客户端"))
        XCTAssertTrue(prompt.contains("不得包含 DIRECT"))
        XCTAssertTrue(prompt.contains("Claude Code 从终端运行"))
        XCTAssertTrue(prompt.contains("claude.ai"))
        XCTAssertTrue(prompt.contains("api.anthropic.com"))
        XCTAssertTrue(prompt.contains("看到的进程是 Routekeeper"))
        XCTAssertTrue(prompt.contains("出站网卡"))
        XCTAssertTrue(prompt.contains("不要回落直连"))
        XCTAssertTrue(prompt.contains("不要擅自改用其他客户端或节点"))
        XCTAssertTrue(prompt.contains("要使用的海外节点名称，不要猜"))
    }
}
