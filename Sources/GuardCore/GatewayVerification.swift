import Foundation

public struct GatewayCheckResult: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var level: CheckLevel
    public var required: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        level: CheckLevel,
        required: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.level = level
        self.required = required
    }
}

public struct GatewayProbeReport: Equatable, Sendable {
    public var checks: [GatewayCheckResult]
    public var passed: Bool

    public init(checks: [GatewayCheckResult]) {
        self.checks = checks
        passed = checks.filter(\.required).allSatisfy { $0.level == .passed }
    }
}

public enum GatewayVerificationStatus: String, Codable, Sendable {
    case unverified
    case needsNodeFailureTest
    case needsClientExitTest
    case needsRecovery
    case verified
    case failed
    case expired
}

public struct GatewayVerificationRecord: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var mode: GatewayProtectionMode
    public var baselineAt: Date?
    public var baselinePassed: Bool
    public var baselineChecks: [GatewayCheckResult]
    public var nodeFailureAt: Date?
    public var nodeFailureCheck: GatewayCheckResult?
    public var clientExitAt: Date?
    public var clientExitCheck: GatewayCheckResult?
    public var recoveredAt: Date?
    public var recoveryChecks: [GatewayCheckResult]
    public var invalidatedAt: Date?
    public var invalidationReason: String?

    public init(sessionID: UUID, mode: GatewayProtectionMode) {
        self.sessionID = sessionID
        self.mode = mode
        baselineAt = nil
        baselinePassed = false
        baselineChecks = []
        nodeFailureAt = nil
        nodeFailureCheck = nil
        clientExitAt = nil
        clientExitCheck = nil
        recoveredAt = nil
        recoveryChecks = []
        invalidatedAt = nil
        invalidationReason = nil
    }

    public func status(
        at date: Date = Date(),
        maxAge: TimeInterval = 15 * 60,
        currentMode: GatewayProtectionMode? = nil
    ) -> GatewayVerificationStatus {
        guard mode != .off, currentMode == nil || currentMode == mode,
              baselineAt != nil else { return .unverified }
        guard baselinePassed else { return .failed }
        if invalidatedAt != nil {
            if let nodeFailureCheck, nodeFailureCheck.level != .passed { return .failed }
            if nodeFailureCheck == nil { return .needsNodeFailureTest }
            if let clientExitCheck, clientExitCheck.level != .passed { return .failed }
            if clientExitCheck == nil { return .needsClientExitTest }
            if recoveredAt == nil { return .needsRecovery }
            return .expired
        }
        guard let nodeFailureCheck else { return .needsNodeFailureTest }
        guard nodeFailureCheck.level == .passed else { return .failed }
        guard let clientExitCheck else { return .needsClientExitTest }
        guard clientExitCheck.level == .passed else { return .failed }
        guard let recoveredAt else { return .needsRecovery }
        let recoveryPassed = recoveryChecks.filter(\.required).allSatisfy { $0.level == .passed }
        guard recoveryPassed else { return .failed }
        let newestEvidence = [baselineAt, nodeFailureAt, clientExitAt, recoveredAt]
            .compactMap { $0 }
            .max() ?? recoveredAt
        guard date.timeIntervalSince(newestEvidence) <= maxAge else { return .expired }
        return .verified
    }

    public var allChecks: [GatewayCheckResult] {
        baselineChecks + [nodeFailureCheck, clientExitCheck].compactMap { $0 } + recoveryChecks
    }
}

public enum GatewayNetworkProbes {
    public static func baseline() async -> GatewayProbeReport {
        let proxy = ProxyEndpoint.current()
        async let systemInfo = ExternalExitChecks.ipInfo(proxy: nil)
        async let systemTrace = ExternalExitChecks.claudeTrace(proxy: nil)
        let (info, trace) = await (systemInfo, systemTrace)
        let explicitTrace: ExternalExitProbe? = if let proxy {
            await ExternalExitChecks.claudeTrace(proxy: proxy)
        } else {
            nil
        }
        async let v4Exit = ipify(family: .ipv4)
        async let v6Exit = ipify(family: .ipv6)
        async let rawDNS = DatagramProbes.dns()
        let (v4, v6, dns) = await (v4Exit, v6Exit, rawDNS)

        var checks: [GatewayCheckResult] = []
        let entryAvailable = proxy != nil || routeToPublicAddressUsesTunnel()
        checks.append(.init(
            id: "gateway-entry",
            title: "代理入口",
            detail: entryAvailable
                ? "检测到系统代理入口或 TUN 路由；这不代表所有应用都会遵守该入口"
                : "没有检测到系统代理入口或 TUN 路由",
            level: entryAvailable ? .passed : .failed
        ))

        let traceIP = trace.ip ?? explicitTrace?.ip
        let directPathWorks = info.ip != nil || trace.ip != nil
        let traceDetail = traceIP == nil
            ? "经当前路径访问 Claude 跟踪地址时没有返回可用出口"
            : directPathWorks
                ? "Claude 服务路径可用，系统普通请求也取得了出口"
                : "Claude 服务路径可用，系统普通请求没有直接取得出口"
        checks.append(.init(
            id: "gateway-claude-path",
            title: "Claude 服务路径",
            detail: traceDetail,
            level: traceIP == nil ? .failed : .passed
        ))

        let exitsAgree = info.ip == nil && trace.ip == nil
            ? explicitTrace?.ip != nil
            : info.ip != nil && trace.ip != nil && info.ip == trace.ip
        checks.append(.init(
            id: "gateway-exit-consistency",
            title: "出口一致性",
            detail: exitsAgree
                ? "系统请求与 Claude 服务路径没有观察到不同的公共出口"
                : "系统请求与 Claude 服务路径没有取得一致出口",
            level: exitsAgree ? .passed : .failed
        ))

        if proxy != nil {
            let explicitMatches = explicitTrace?.ip != nil
                && (trace.ip == nil || explicitTrace?.ip == trace.ip)
            checks.append(.init(
                id: "gateway-system-proxy",
                title: "系统代理路径",
                detail: explicitMatches
                    ? "显式系统代理可以到达 Claude，且没有观察到不同出口"
                    : "显式系统代理没有取得有效的 Claude 出口",
                level: explicitMatches ? .passed : .failed
            ))
        } else {
            checks.append(.init(
                id: "gateway-system-proxy",
                title: "系统代理路径",
                detail: "没有启用的 HTTPS 系统代理；本次以 TUN 路径为准",
                level: .warning,
                required: false
            ))
        }

        checks.append(familyCheck(.ipv4, exit: v4))
        checks.append(familyCheck(.ipv6, exit: v6))

        checks.append(.init(
            id: "gateway-dns",
            title: "DNS 路径",
            detail: dns.level == .passed
                ? "系统 DNS 请求获得有效响应，且没有观察到非 TUN 解析器路径"
                : "系统 DNS 路径没有得到可用于严格结论的证据",
            level: dns.level == .passed ? .passed : .failed
        ))

        let observedFamily = traceIP.map(IPFamily.of) ?? info.ip.map(IPFamily.of) ?? .ipv4
        let observedExit = traceIP ?? info.ip ?? explicitTrace?.ip
        let udp = await DatagramProbes.udp(family: observedFamily, expected: observedExit)
        checks.append(.init(
            id: "gateway-udp",
            title: "UDP / QUIC 参考",
            detail: udp.level == .passed
                ? "STUN 观测到的 UDP 出口与当前主出口一致"
                : "STUN 结果不足，不能据此证明或否定 UDP 绕过；本项不参与严格结论",
            level: udp.level,
            required: false
        ))

        return .init(checks: checks)
    }

    public static func claudeTargetBlocked() async -> GatewayCheckResult {
        let trace = await ExternalExitChecks.claudeTrace(proxy: nil)
        if trace.ip == nil {
            return .init(
                id: "gateway-target-blocked",
                title: "Claude 连接失败",
                detail: "本次没有从 Claude 跟踪地址取得出口。只代表当前时点未连通",
                level: .passed
            )
        }
        return .init(
            id: "gateway-target-blocked",
            title: "Claude 连接失败",
            detail: "Claude 跟踪地址仍然可以访问；失败关闭测试没有通过",
            level: .failed
        )
    }

    private static func routeToPublicAddressUsesTunnel() -> Bool {
        [IPFamily.ipv4, .ipv6].contains { family in
            let routes = NetworkEvidence.routes(family)
            return routes.hasUsableAddress && routes.tunnel != nil
        }
    }

    private static func familyCheck(_ family: IPFamily, exit: String?) -> GatewayCheckResult {
        let routes = NetworkEvidence.routes(family)
        if !routes.hasUsableAddress {
            return .init(
                id: "gateway-\(family.rawValue)",
                title: family.displayName,
                detail: "本机未启用可用的 \(family.displayName) 地址，已跳过该地址族",
                level: .passed
            )
        }
        if exit == nil {
            return .init(
                id: "gateway-\(family.rawValue)",
                title: family.displayName,
                detail: "本机存在 \(family.displayName) 地址，但本次没有取得该地址族出口",
                level: .failed
            )
        }
        return .init(
            id: "gateway-\(family.rawValue)",
            title: family.displayName,
            detail: "已单独取得 \(family.displayName) 出口；出口地址未写入持久化记录",
            level: .passed
        )
    }

    private static func ipify(family: IPFamily) async -> String? {
        await Task.detached(priority: .utility) {
            let flag = family == .ipv4 ? "--ipv4" : "--ipv6"
            let result = Command.run(
                "/usr/bin/curl",
                [
                    "--disable", "--silent", "--fail", flag, "--noproxy", "*",
                    "--connect-timeout", "3", "--max-time", "6",
                    "--max-filesize", "128", "--proto", "=https",
                    "--header", "Cache-Control: no-cache",
                    "https://api.ipify.org/"
                ],
                timeout: 8
            )
            guard result.status == 0,
                  let value = IPAddress.normalized(result.output),
                  IPFamily.of(value) == family else { return nil }
            return value
        }.value
    }
}
