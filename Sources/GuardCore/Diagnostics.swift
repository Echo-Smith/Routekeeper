import Foundation
import AppKit

public enum Diagnostics {
    private static func exitIP(proxy: ProxyEndpoint?, ipv6: Bool) async -> String? {
        await Task.detached(priority: .utility) {
            let url = ipv6 ? "https://api6.ipify.org/" : "https://api.ipify.org/"
            let family = proxy == nil ? [ipv6 ? "--ipv6" : "--ipv4"] : []
            var args = ["--disable", "--silent", "--fail", "--connect-timeout", "3", "--max-time", "6",
                        "--max-filesize", "128", "--proto", "=https"] + family
            if let proxy {
                args += ["--proxy", proxy.url]
            } else {
                args += ["--noproxy", "*"]
            }
            args += ["--header", "Cache-Control: no-cache", url]
            let result = Command.run("/usr/bin/curl", args)
            guard result.status == 0 else { return nil }
            guard let value = IPAddress.normalized(result.output), IPFamily.of(value) == (ipv6 ? .ipv6 : .ipv4) else { return nil }
            return value
        }.value
    }
    private struct FamilyEvidence: Sendable {
        var routes: FamilyRoutes
        var direct: String?
        var proxied: String?
        var active: Bool
        var gate: CheckItem
        var probes: [CheckItem]
    }
    private static func familyEvidence(_ family: IPFamily, proxy: ProxyEndpoint?, settings: GuardSettings) async -> FamilyEvidence {
        let routes = await Task.detached { NetworkEvidence.routes(family) }.value
        if routes.absent {
            let gate = NetworkEvidence.familyGate(routes, target: nil, observed: nil, proxied: nil)
            let udp: CheckItem = .init(
                "udp-\(family.rawValue)",
                "UDP · \(family.displayName)",
                settings.udpProbeEnabled
                    ? "本机未启用该地址族，未发送 UDP 探测"
                    : "用户关闭 UDP 探测；未验证",
                .passed
            )
            return .init(routes: routes, direct: nil, proxied: nil, active: false, gate: gate, probes: [udp])
        }
        let expected = settings.target(for: family)
        async let directIP = exitIP(proxy: nil, ipv6: family == .ipv6)
        async let proxyIP: String? = proxy?.isLoopback == true ? exitIP(proxy: proxy, ipv6: family == .ipv6) : nil
        async let udpRow: CheckItem = settings.udpProbeEnabled
            ? DatagramProbes.udp(family: family, expected: expected)
            : .init("udp-\(family.rawValue)", "UDP · \(family.displayName)", "用户关闭 UDP 探测；未验证", .warning)
        let (direct, proxied, probe) = await (directIP, proxyIP, udpRow)
        let active = NetworkEvidence.familyActive(routes, observed: direct, proxied: proxied)
        let udp = active
            ? probe
            : CheckItem("udp-\(family.rawValue)", "UDP · \(family.displayName)",
                        "本次未观察到可用的 \(family.displayName) 出口；UDP 探测不参与判定", .passed)
        // Proxy transport may use the other family. No local family route is a scoped observation, not a global proof.
        let gate = NetworkEvidence.familyGate(routes, target: expected, observed: direct, proxied: proxied)
        return .init(routes: routes, direct: direct, proxied: proxied, active: active, gate: gate, probes: [udp])
    }

    public static func run(settings: GuardSettings) async -> DiagnosticSnapshot {
        let target = settings.target(for: .ipv4) ?? settings.target(for: .ipv6)
        let primaryFamily = target.map(IPFamily.of) ?? .ipv4
        let proxy = ProxyEndpoint.current()
        async let v4 = familyEvidence(.ipv4, proxy: proxy, settings: settings)
        async let v6 = familyEvidence(.ipv6, proxy: proxy, settings: settings)
        async let dns: CheckItem = settings.dnsProbeEnabled ? DatagramProbes.dns() : .init("dns", "DNS", "用户关闭探测；未验证 DNS 路由", .warning)
        async let ipInfo = ExternalExitChecks.ipInfo(proxy: proxy)
        async let claudeTrace = ExternalExitChecks.claudeTrace(proxy: proxy)
        let local = await Task.detached(priority: .utility) {
            () -> (ProxyIdentification, String?, [String], ProcessScan,
                   ClaudeProcessNetworkSummary?, ClaudeCodeEnvironmentSummary?) in
            let adapter = ProxyAdapters.identify(settings.proxyClient)
            let desktop = ClaudeDesktopDiscovery.locate()?.appURL.path
            let code = ApplicationDiscovery.codePaths()
            let scan = LocalProcesses.scan(desktopRoots: desktop.map { [$0] } ?? [])
            let selected = scan.records.filter { settings.includes($0.kind) }
            let network = LocalProcesses.networkSummary(for: selected)
            let environment: ClaudeCodeEnvironmentSummary?
            if settings.protectCode,
               let codeRecord = scan.records.first(where: { $0.kind == .code }) {
                environment = await LocalProcesses.cachedCodeEnvironment(for: codeRecord)
            } else {
                environment = nil
            }
            return (adapter, desktop, code, scan, network, environment)
        }.value
        let (adapter, desktop, code, scan, processNetwork, codeEnvironment) = local
        let (four, six, dnsRow, ipInfoProbe, claudeTraceProbe) = await (v4, v6, dns, ipInfo, claudeTrace)
        let primary = primaryFamily == .ipv4 ? four : six
        let direct = primary.direct; let proxied = primary.proxied
        var rows: [CheckItem] = []
        rows.append(.init("target", "目标出口 IP", target ?? "填写固定出口 IP 后才能开启监控", target == nil ? .failed : .passed))
        rows.append(.init("scope", "保护范围", settings.hasSelection ? [settings.protectDesktop ? "Claude Desktop" : nil, settings.protectCode ? "Claude Code" : nil].compactMap { $0 }.joined(separator: "、") : "至少选择一个应用", settings.hasSelection ? .passed : .failed))
        rows.append(.init("proxy-client", "代理客户端", adapter.running ? "已配置" : "未检测到正在运行的代理，请先启动代理后重新检查", adapter.running ? .passed : .failed))
        rows.append(.init("proxy", "系统 HTTPS 代理", proxy.map { "\($0.host):\($0.port)" } ?? "未启用明确的 HTTPS 代理；PAC 暂不支持", proxy?.isLoopback == true ? .passed : .failed))
        rows.append(.init("interval", "轮询间隔", "每轮结束后等待 \(settings.pollInterval) 秒；查询耗时另计", settings.validInterval ? .passed : .failed))
        let ipv4Target = settings.fixedIPv4TargetIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let ipv6Target = settings.fixedIPv6TargetIP.trimmingCharacters(in: .whitespacesAndNewlines)
        for (family, value) in [(IPFamily.ipv4, ipv4Target), (IPFamily.ipv6, ipv6Target)] where !value.isEmpty {
            if IPAddress.normalized(value) == nil || IPFamily.of(value) != family {
                rows.append(.init("target-\(family.rawValue)", "\(family.displayName) 固定出口", "请填写有效的 \(family.displayName) IP", .failed))
            }
        }
        rows += [four.gate, six.gate, dnsRow] + four.probes + six.probes
        rows.append(.init("tun", "主地址族 TUN 路由", primary.routes.tunnel ?? "未确认同一 utun；路由不能单独证明代理归属", primary.routes.tunnel == nil ? .failed : .passed))
        rows.append(.init("proxy-exit", "代理出口", proxied ?? "查询失败", proxied != nil && proxied == target ? .passed : .failed))
        rows.append(.init("tun-exit", "系统路由出口", direct ?? "查询失败", direct != nil && direct == target ? .passed : .failed))
        rows.append(ExternalExitChecks.row(
            id: "ipinfo-exit",
            title: "ipinfo.io",
            service: "ipinfo.io",
            probe: ipInfoProbe,
            settings: settings
        ))
        rows.append(ExternalExitChecks.row(
            id: "claude-trace-exit",
            title: "经当前路径访问 Claude",
            service: "claude.ai/cdn-cgi/trace",
            probe: claudeTraceProbe,
            settings: settings
        ))
        rows.append(.init("process-access", "进程检查", scan.available ? "仅识别当前用户的明确 Claude 进程" : "无法读取进程列表，保护不可用", scan.available ? .passed : .failed))
        if let processNetwork,
           processNetwork.processCount > 0,
           processNetwork.readable,
           processNetwork.establishedConnections > 0 {
            let detail = "当前 \(processNetwork.processCount) 个 Claude 进程观察到 \(processNetwork.establishedConnections) 条已建立 TCP 连接（本机 \(processNetwork.loopbackConnections)，非回环 \(processNetwork.nonLoopbackConnections)）。非回环连接也可能经过 TUN，仅作实时证据。"
            rows.append(.init(
                "claude-process-network",
                "Claude 进程连接",
                detail,
                .passed
            ))
        }
        if settings.protectDesktop {
            let count = scan.records.filter { $0.kind == .desktop }.count
            rows.append(.init("desktop", "Claude Desktop", desktop.map { "\($0) · \(count) 个进程" } ?? "未发现安装；后续检查会继续识别", desktop == nil ? .warning : .passed))
        }
        if settings.protectCode {
            let count = scan.records.filter { $0.kind == .code }.count
            rows.append(.init("code", "Claude Code", "\(code.count) 个常见安装入口 · \(count) 个明确 CLI 进程", code.isEmpty && count == 0 ? .warning : .passed))
            if let codeEnvironment, codeEnvironment.readable {
                rows.append(codeEnvironmentRow(codeEnvironment))
            }
        }
        rows.append(.init("boundary", "当前保护能力", "此报告只说明本次检测结果，不代表额外网络限制已经开启。额外限制需要单独设置；通过自定义启动器运行的程序可能无法识别。", .warning))
        var snapshot = DiagnosticSnapshot(settings: settings, checks: rows, proxyIP: proxied, tunnelIP: direct,
                     processes: scan.records, desktopPath: desktop, codePaths: code)
        snapshot.familyExits = [.init(family: .ipv4, direct: four.direct, proxied: four.proxied), .init(family: .ipv6, direct: six.direct, proxied: six.proxied)]
        snapshot.enabledFamilies = Set([four, six].filter(\.active).map(\.routes.family))
        snapshot.claudeProcessNetwork = processNetwork
        snapshot.codeEnvironment = codeEnvironment
        return snapshot
    }

    private static func codeEnvironmentRow(
        _ environment: ClaudeCodeEnvironmentSummary
    ) -> CheckItem {
        let proxy = environment.proxyConfigured
            ? environment.proxyHosts.joined(separator: "、")
            : "未设置"
        let noProxy = environment.noProxyConfigured ? "已设置" : "未设置"
        let api = environment.apiBaseConfigured
            ? (environment.apiBaseHost ?? "已设置")
            : "未设置"
        let locale = environment.locale ?? "未设置"
        let timeZone = environment.timeZone ?? "继承系统"
        let detail = "代理变量：\(proxy)；代理绕过：\(noProxy)；自定义 API：\(api)；区域：\(locale)；时区：\(timeZone)。仅显示脱敏后的主机名。"
        return .init(
            "code-environment",
            "Claude Code 终端环境",
            detail,
            environment.apiBaseConfigured ? .warning : .passed
        )
    }
}
