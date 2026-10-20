import Foundation

public enum IPv6RouteKind: String, Codable, Sendable {
    case tunnel, physical, other, noRoute, noAddress
}

public struct ClaudeIPv6Probe: Codable, Equatable, Sendable, Identifiable {
    public var target: String
    public var resolvedAddresses: [String]
    public var remoteAddress: String?
    public var routeInterface: String?
    public var routeKind: IPv6RouteKind
    public var reachedTLS: Bool
    public var httpStatus: Int?
    public var tlsMilliseconds: Int?
    public var failure: String?

    public var id: String { target }
    public var reachedDirectly: Bool {
        reachedTLS && (routeKind == .physical || routeKind == .other)
    }
    public var reachedThroughTunnel: Bool { reachedTLS && routeKind == .tunnel }

    public init(target: String, resolvedAddresses: [String], remoteAddress: String?,
                routeInterface: String?, routeKind: IPv6RouteKind, reachedTLS: Bool,
                httpStatus: Int?, tlsMilliseconds: Int?, failure: String?) {
        self.target = target
        self.resolvedAddresses = resolvedAddresses
        self.remoteAddress = remoteAddress
        self.routeInterface = routeInterface
        self.routeKind = routeKind
        self.reachedTLS = reachedTLS
        self.httpStatus = httpStatus
        self.tlsMilliseconds = tlsMilliseconds
        self.failure = failure
    }
}

public enum IPv6ExposureState: String, Codable, Sendable {
    case disabled
    case noClaudePath
    case tunneled
    case tunnelUnconfirmed
    case tunnelExitMismatch
    case directExposure
    case unknown
}

public struct IPv6EgressReport: Codable, Equatable, Sendable {
    public var localAddress: String?
    public var systemPublicExit: String?
    public var proxyPublicExit: String?
    public var probes: [ClaudeIPv6Probe]
    public var state: IPv6ExposureState

    public init(localAddress: String?, systemPublicExit: String?, proxyPublicExit: String?,
                probes: [ClaudeIPv6Probe], state: IPv6ExposureState) {
        self.localAddress = localAddress
        self.systemPublicExit = systemPublicExit
        self.proxyPublicExit = proxyPublicExit
        self.probes = probes
        self.state = state
    }
}

public enum IPv6EgressAudit {
    public static let targets = ["claude.ai", "api.anthropic.com", "console.anthropic.com"]

    public static func exposureState(localAddress: String?, probes: [ClaudeIPv6Probe],
                                     systemPublicExit: String?, proxyPublicExit: String?) -> IPv6ExposureState {
        guard localAddress != nil else { return .disabled }
        let reached = probes.filter(\.reachedTLS)
        guard !reached.isEmpty else { return .noClaudePath }
        if reached.contains(where: \.reachedDirectly) { return .directExposure }
        guard reached.contains(where: \.reachedThroughTunnel) else { return .unknown }
        switch (systemPublicExit, proxyPublicExit) {
        case let (.some(system), .some(proxy)) where system == proxy:
            return .tunneled
        case (.some, .some):
            return .tunnelExitMismatch
        default:
            return .tunnelUnconfirmed
        }
    }

    public static func resolvedAddresses(from output: String) -> [String] {
        Array(Set(output.split(separator: "\n").compactMap {
            guard let value = IPAddress.normalized(String($0)), IPFamily.of(value) == .ipv6 else { return nil }
            return value
        })).sorted()
    }

    public static func routeKind(_ interface: String?) -> IPv6RouteKind {
        guard let interface, !interface.isEmpty else { return .noRoute }
        if interface.range(of: #"^utun[0-9]+$"#, options: .regularExpression) != nil { return .tunnel }
        if interface.range(of: #"^(en|pdp_ip|bridge|awdl|llw)[0-9]+$"#, options: .regularExpression) != nil {
            return .physical
        }
        return .other
    }

    public static func run(snapshot: DiagnosticSnapshot) async -> IPv6EgressReport {
        let local = NetworkEvidence.activeAddresses()
            .map(\.1)
            .first { NetworkEvidence.hasUsableAddress($0, family: .ipv6) }
        let exits = snapshot.familyExits.first { $0.family == .ipv6 }
        guard let local else {
            return .init(localAddress: nil, systemPublicExit: nil, proxyPublicExit: nil,
                         probes: [], state: .disabled)
        }
        var probes: [ClaudeIPv6Probe] = []
        await withTaskGroup(of: ClaudeIPv6Probe.self) { group in
            for target in targets {
                group.addTask { await probe(target: target) }
            }
            for await result in group { probes.append(result) }
        }
        probes.sort {
            (targets.firstIndex(of: $0.target) ?? Int.max) < (targets.firstIndex(of: $1.target) ?? Int.max)
        }
        let state = exposureState(
            localAddress: local,
            probes: probes,
            systemPublicExit: exits?.direct,
            proxyPublicExit: exits?.proxied
        )
        return .init(localAddress: local, systemPublicExit: exits?.direct,
                     proxyPublicExit: exits?.proxied, probes: probes, state: state)
    }

    private static func probe(target: String) async -> ClaudeIPv6Probe {
        await Task.detached(priority: .utility) {
            let resolved = resolveAAAA(target)
            guard !resolved.isEmpty else {
                return .init(target: target, resolvedAddresses: [], remoteAddress: nil,
                             routeInterface: nil, routeKind: .noAddress, reachedTLS: false,
                             httpStatus: nil, tlsMilliseconds: nil, failure: "未取得 AAAA 记录")
            }
            let result = Command.run("/usr/bin/curl", [
                "--disable", "--silent", "--show-error", "--ipv6",
                "--connect-timeout", "4", "--max-time", "10", "--max-filesize", "1048576",
                "--proto", "=https", "--noproxy", "*", "--output", "/dev/null",
                "--write-out", "%{http_code}\t%{time_appconnect}\t%{remote_ip}",
                "https://\(target)/"
            ], timeout: 12)
            let fields = result.output.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let status = fields.indices.contains(0) ? Int(fields[0]) : nil
            let tlsSeconds = fields.indices.contains(1) ? Double(fields[1]) : nil
            let tls = tlsSeconds.flatMap { $0.isFinite && $0 > 0 ? Int(($0 * 1_000).rounded()) : nil }
            let remote = fields.indices.contains(2)
                ? IPAddress.normalized(fields[2]).flatMap { IPFamily.of($0) == .ipv6 ? $0 : nil }
                : nil
            let interface = remote.flatMap { NetworkEvidence.route(to: $0) }
            let kind = routeKind(interface)
            let failure: String?
            if tls != nil {
                failure = nil
            } else if result.status != 0 {
                failure = "IPv6 TLS 未完成（curl \(result.status)）"
            } else {
                failure = "IPv6 TLS 未完成"
            }
            return .init(
                target: target, resolvedAddresses: resolved, remoteAddress: remote,
                routeInterface: interface, routeKind: kind, reachedTLS: tls != nil,
                httpStatus: status.flatMap { (100...599).contains($0) ? $0 : nil },
                tlsMilliseconds: tls, failure: failure
            )
        }.value
    }

    private static func resolveAAAA(_ target: String) -> [String] {
        let result = Command.run("/usr/bin/dig", [
            "+short", "+time=2", "+tries=1", target, "AAAA"
        ], timeout: 3)
        return result.status == 0 ? resolvedAddresses(from: result.output) : []
    }
}
