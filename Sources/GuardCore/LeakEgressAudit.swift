import Foundation

public struct EgressCheckEvidence: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var level: CheckLevel

    public init(_ check: CheckItem) {
        id = check.id
        title = check.title
        detail = check.detail
        level = check.level
    }

    public init(id: String, title: String, detail: String, level: CheckLevel) {
        self.id = id
        self.title = title
        self.detail = detail
        self.level = level
    }
}

public struct DualStackAttempt: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var reachedTLS: Bool
    public var remoteAddress: String?
    public var family: IPFamily?
    public var httpStatus: Int?
    public var connectMilliseconds: Int?
    public var tlsMilliseconds: Int?
    public var totalMilliseconds: Int?
    public var failure: String?

    public init(id: Int, reachedTLS: Bool, remoteAddress: String?, family: IPFamily?,
                httpStatus: Int?, connectMilliseconds: Int?, tlsMilliseconds: Int?,
                totalMilliseconds: Int?, failure: String?) {
        self.id = id
        self.reachedTLS = reachedTLS
        self.remoteAddress = remoteAddress
        self.family = family
        self.httpStatus = httpStatus
        self.connectMilliseconds = connectMilliseconds
        self.tlsMilliseconds = tlsMilliseconds
        self.totalMilliseconds = totalMilliseconds
        self.failure = failure
    }
}

public struct DualStackFallbackReport: Codable, Equatable, Sendable {
    public var target: String
    public var attempts: [DualStackAttempt]
    public var fallbackSuspected: Bool
    public var switchedFamily: Bool
    public var firstAttemptSlow: Bool
    public var firstAttemptFailedThenSucceeded: Bool

    public init(target: String, attempts: [DualStackAttempt], fallbackSuspected: Bool,
                switchedFamily: Bool, firstAttemptSlow: Bool,
                firstAttemptFailedThenSucceeded: Bool) {
        self.target = target
        self.attempts = attempts
        self.fallbackSuspected = fallbackSuspected
        self.switchedFamily = switchedFamily
        self.firstAttemptSlow = firstAttemptSlow
        self.firstAttemptFailedThenSucceeded = firstAttemptFailedThenSucceeded
    }
}

public struct LeakEgressReport: Codable, Equatable, Sendable {
    public var dns: EgressCheckEvidence?
    public var udpIPv4: EgressCheckEvidence?
    public var udpIPv6: EgressCheckEvidence?
    public var dualStack: DualStackFallbackReport?

    public init(dns: EgressCheckEvidence?, udpIPv4: EgressCheckEvidence?,
                udpIPv6: EgressCheckEvidence?, dualStack: DualStackFallbackReport?) {
        self.dns = dns
        self.udpIPv4 = udpIPv4
        self.udpIPv6 = udpIPv6
        self.dualStack = dualStack
    }

    public var udpChecks: [EgressCheckEvidence] {
        [udpIPv4, udpIPv6].compactMap { $0 }
    }
}

public enum LeakEgressAudit {
    public static let dualStackTarget = "api.anthropic.com"

    public static func run(snapshot: DiagnosticSnapshot, ipv6: IPv6EgressReport) async -> LeakEgressReport {
        let ipv4Exit = snapshot.familyExits.first { $0.family == .ipv4 }
            .flatMap { $0.proxied ?? $0.direct }
        let ipv6Exit = ipv6.proxyPublicExit ?? ipv6.systemPublicExit
        let ipv4Enabled = snapshot.enabledFamilies.contains(.ipv4)
        let ipv6Enabled = snapshot.enabledFamilies.contains(.ipv6)

        async let dnsTask = DatagramProbes.dns()
        async let udp4Task = udpEvidence(family: .ipv4, expected: ipv4Exit, enabled: ipv4Enabled)
        async let udp6Task = udpEvidence(family: .ipv6, expected: ipv6Exit, enabled: ipv6Enabled)
        let (dns, udp4, udp6) = await (dnsTask, udp4Task, udp6Task)
        let dual = await dualStackFallback()
        return .init(
            dns: .init(dns),
            udpIPv4: udp4,
            udpIPv6: udp6,
            dualStack: dual
        )
    }

    public static func evaluateFallback(target: String,
                                        attempts: [DualStackAttempt]) -> DualStackFallbackReport {
        let sorted = attempts.sorted { $0.id < $1.id }
        guard sorted.count >= 2 else {
            return .init(target: target, attempts: sorted, fallbackSuspected: false,
                         switchedFamily: false, firstAttemptSlow: false,
                         firstAttemptFailedThenSucceeded: false)
        }
        let first = sorted[0]
        let second = sorted[1]
        let switched = first.reachedTLS && second.reachedTLS
            && first.family != nil && second.family != nil && first.family != second.family
        let failedThenSucceeded = !first.reachedTLS && second.reachedTLS
        let firstTotal = first.totalMilliseconds ?? Int.max
        let secondTotal = second.totalMilliseconds ?? Int.max
        let slow = first.reachedTLS && second.reachedTLS
            && firstTotal - secondTotal >= 800
            && firstTotal > max(1_500, secondTotal * 2)
        return .init(
            target: target,
            attempts: sorted,
            fallbackSuspected: switched || failedThenSucceeded || slow,
            switchedFamily: switched,
            firstAttemptSlow: slow,
            firstAttemptFailedThenSucceeded: failedThenSucceeded
        )
    }

    public static func parseAttempt(_ output: String, exitStatus: Int32, id: Int) -> DualStackAttempt {
        let fields = output.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        func number(_ index: Int) -> Double? {
            guard fields.indices.contains(index), let value = Double(fields[index]), value.isFinite else { return nil }
            return value
        }
        func milliseconds(_ index: Int) -> Int? {
            guard let value = number(index), value > 0 else { return nil }
            return Int((value * 1_000).rounded())
        }
        let normalizedRemote = fields.indices.contains(4) ? IPAddress.normalized(fields[4]) : nil
        let family = normalizedRemote.map(IPFamily.of)
        let status = fields.indices.contains(0) ? Int(fields[0]) : nil
        let tls = milliseconds(2)
        let failure: String?
        if tls != nil {
            failure = nil
        } else if exitStatus != 0 {
            failure = "TLS 未完成（curl \(exitStatus)）"
        } else {
            failure = "TLS 未完成"
        }
        return .init(
            id: id,
            reachedTLS: tls != nil,
            remoteAddress: normalizedRemote,
            family: family,
            httpStatus: status.flatMap { (100...599).contains($0) ? $0 : nil },
            connectMilliseconds: milliseconds(1),
            tlsMilliseconds: tls,
            totalMilliseconds: milliseconds(3),
            failure: failure
        )
    }

    private static func udpEvidence(family: IPFamily, expected: String?,
                                    enabled: Bool) async -> EgressCheckEvidence? {
        guard enabled else { return nil }
        let check = await DatagramProbes.udp(family: family, expected: expected)
        return .init(check)
    }

    private static func dualStackFallback() async -> DualStackFallbackReport {
        var attempts: [DualStackAttempt] = []
        for index in 1...2 {
            attempts.append(await dualStackAttempt(index: index))
        }
        return evaluateFallback(target: dualStackTarget, attempts: attempts)
    }

    private static func dualStackAttempt(index: Int) async -> DualStackAttempt {
        await Task.detached(priority: .utility) {
            let result = Command.run("/usr/bin/curl", [
                "--disable", "--silent", "--show-error", "--connect-timeout", "4", "--max-time", "8",
                "--max-filesize", "1048576", "--proto", "=https", "--noproxy", "*",
                "--header", "Cache-Control: no-cache", "--output", "/dev/null",
                "--write-out", "%{http_code}\t%{time_connect}\t%{time_appconnect}\t%{time_total}\t%{remote_ip}",
                "https://\(dualStackTarget)/"
            ], timeout: 10)
            return parseAttempt(result.output, exitStatus: result.status, id: index)
        }.value
    }
}
