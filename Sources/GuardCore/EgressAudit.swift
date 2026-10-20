import Foundation

public enum EgressRouteKind: String, Codable, CaseIterable, Sendable {
    case system, proxy
}

public enum EgressFamilyState: String, Codable, Sendable {
    case notObserved, incomplete, consistent, mismatch
}

public struct EgressFamilyObservation: Codable, Equatable, Sendable, Identifiable {
    public var family: IPFamily
    public var directIP: String?
    public var proxiedIP: String?
    public var targetIP: String?

    public var id: String { family.rawValue }
    public var state: EgressFamilyState {
        EgressAudit.familyState(direct: directIP, proxied: proxiedIP)
    }
    public var targetMismatch: Bool {
        guard let targetIP else { return false }
        return [directIP, proxiedIP].compactMap { $0 }.contains { $0 != targetIP }
    }

    public init(family: IPFamily, directIP: String?, proxiedIP: String?, targetIP: String?) {
        self.family = family
        self.directIP = directIP
        self.proxiedIP = proxiedIP
        self.targetIP = targetIP
    }
}

public struct EgressServiceProbe: Codable, Equatable, Sendable, Identifiable {
    public var target: String
    public var route: EgressRouteKind
    public var reachedTLS: Bool
    public var httpStatus: Int?
    public var remoteIP: String?
    public var connectMilliseconds: Int?
    public var tlsMilliseconds: Int?
    public var totalMilliseconds: Int?
    public var failure: String?

    public var id: String { "\(target)-\(route.rawValue)" }

    public init(target: String, route: EgressRouteKind, reachedTLS: Bool, httpStatus: Int?,
                remoteIP: String?, connectMilliseconds: Int?, tlsMilliseconds: Int?,
                totalMilliseconds: Int?, failure: String?) {
        self.target = target
        self.route = route
        self.reachedTLS = reachedTLS
        self.httpStatus = httpStatus
        self.remoteIP = remoteIP
        self.connectMilliseconds = connectMilliseconds
        self.tlsMilliseconds = tlsMilliseconds
        self.totalMilliseconds = totalMilliseconds
        self.failure = failure
    }
}

public enum EgressIntelligenceStatus: String, Codable, Sendable {
    case disabled, unavailable, partial, available
}

public enum EgressRiskFlag: String, Codable, CaseIterable, Sendable {
    case datacenter, proxy, vpn, tor, abuser, crawler, mobile, bogon
}

public struct IPIntelligence: Codable, Equatable, Sendable, Identifiable {
    public var ip: String
    public var sources: [String]
    public var countryCode: String?
    public var country: String?
    public var region: String?
    public var city: String?
    public var timezone: String?
    public var asn: String?
    public var organization: String?
    public var isp: String?
    public var isDatacenter: Bool?
    public var isProxy: Bool?
    public var isVPN: Bool?
    public var isTor: Bool?
    public var isAbuser: Bool?
    public var isCrawler: Bool?
    public var isMobile: Bool?
    public var isBogon: Bool?

    public var id: String { ip }

    public var riskFlags: [EgressRiskFlag] {
        var values: [EgressRiskFlag] = []
        if isDatacenter == true { values.append(.datacenter) }
        if isProxy == true { values.append(.proxy) }
        if isVPN == true { values.append(.vpn) }
        if isTor == true { values.append(.tor) }
        if isAbuser == true { values.append(.abuser) }
        if isCrawler == true { values.append(.crawler) }
        if isMobile == true { values.append(.mobile) }
        if isBogon == true { values.append(.bogon) }
        return values
    }

    public var hasRiskMetadata: Bool {
        [isDatacenter, isProxy, isVPN, isTor, isAbuser, isCrawler, isMobile, isBogon]
            .contains { $0 != nil }
    }

    public init(ip: String, sources: [String], countryCode: String? = nil, country: String? = nil,
                region: String? = nil, city: String? = nil, timezone: String? = nil,
                asn: String? = nil, organization: String? = nil, isp: String? = nil,
                isDatacenter: Bool? = nil, isProxy: Bool? = nil, isVPN: Bool? = nil,
                isTor: Bool? = nil, isAbuser: Bool? = nil, isCrawler: Bool? = nil,
                isMobile: Bool? = nil, isBogon: Bool? = nil) {
        self.ip = ip
        self.sources = sources
        self.countryCode = countryCode
        self.country = country
        self.region = region
        self.city = city
        self.timezone = timezone
        self.asn = asn
        self.organization = organization
        self.isp = isp
        self.isDatacenter = isDatacenter
        self.isProxy = isProxy
        self.isVPN = isVPN
        self.isTor = isTor
        self.isAbuser = isAbuser
        self.isCrawler = isCrawler
        self.isMobile = isMobile
        self.isBogon = isBogon
    }
}

public enum EgressFinding: String, Codable, Hashable, Sendable {
    case exitMismatch
    case incompleteExitEvidence
    case noObservedExit
    case serviceUnreachable
    case countryMismatch
    case asnMismatch
    case datacenterNetwork
    case proxySignal
    case vpnSignal
    case torSignal
    case abuseSignal
    case crawlerSignal
    case mobileNetwork
    case bogonAddress
    case riskIntelligenceUnavailable
    case thirdPartyDisabled
    case ipv6DirectExposure
    case ipv6TunnelExitMismatch
    case ipv6ProxyUnconfirmed
    case ipv6PathUnknown
    case dnsPathLeakSuspected
    case dnsPathUnverified
    case udpExitMismatch
    case udpExitUnverified
    case dualStackFallbackSuspected
    case timeZoneMismatch
    case timeZoneUnverified
}

public enum EgressAssessmentLevel: String, Codable, Sendable {
    case clear, attention, insufficient
}

public struct EgressAssessment: Codable, Equatable, Sendable {
    public var level: EgressAssessmentLevel
    public var findings: [EgressFinding]

    public init(level: EgressAssessmentLevel, findings: [EgressFinding]) {
        self.level = level
        self.findings = findings
    }
}

public struct EgressAuditReport: Codable, Equatable, Sendable {
    public var auditedAt: Date
    public var snapshotTime: Date
    public var proxyConfigured: Bool
    public var primaryIP: String?
    public var families: [EgressFamilyObservation]
    public var services: [EgressServiceProbe]
    public var intelligence: [IPIntelligence]
    public var intelligenceStatus: EgressIntelligenceStatus
    public var assessment: EgressAssessment
    public var ipv6: IPv6EgressReport?
    public var leaks: LeakEgressReport?
    public var timeZone: EgressTimeZoneCheck?

    public init(auditedAt: Date = Date(), snapshotTime: Date, proxyConfigured: Bool,
                primaryIP: String?, families: [EgressFamilyObservation],
                services: [EgressServiceProbe], intelligence: [IPIntelligence],
                intelligenceStatus: EgressIntelligenceStatus, assessment: EgressAssessment,
                ipv6: IPv6EgressReport? = nil, leaks: LeakEgressReport? = nil,
                timeZone: EgressTimeZoneCheck? = nil) {
        self.auditedAt = auditedAt
        self.snapshotTime = snapshotTime
        self.proxyConfigured = proxyConfigured
        self.primaryIP = primaryIP
        self.families = families
        self.services = services
        self.intelligence = intelligence
        self.intelligenceStatus = intelligenceStatus
        self.assessment = assessment
        self.ipv6 = ipv6
        self.leaks = leaks
        self.timeZone = timeZone
    }
}

public struct EgressHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var capturedAt: Date
    public var ip: String
    public var asn: String?
    public var countryCode: String?
    public var city: String?
    public var sources: [String]

    public init(id: UUID = UUID(), capturedAt: Date = Date(), ip: String, asn: String?,
                countryCode: String?, city: String?, sources: [String]) {
        self.id = id
        self.capturedAt = capturedAt
        self.ip = ip
        self.asn = asn
        self.countryCode = countryCode
        self.city = city
        self.sources = sources
    }
}

public struct EgressDrift: Equatable, Sendable {
    public var previousIP: String
    public var currentIP: String
    public var previousTime: Date

    public init(previousIP: String, currentIP: String, previousTime: Date) {
        self.previousIP = previousIP
        self.currentIP = currentIP
        self.previousTime = previousTime
    }
}

public enum EgressHistory {
    public static func append(_ entry: EgressHistoryEntry, to entries: [EgressHistoryEntry],
                              maxCount: Int = 20, dedupeWindow: TimeInterval = 1_800) -> [EgressHistoryEntry] {
        var updated = entries
        if let first = updated.first,
           first.ip == entry.ip,
           abs(entry.capturedAt.timeIntervalSince(first.capturedAt)) <= dedupeWindow {
            updated[0] = entry
        } else {
            updated.insert(entry, at: 0)
        }
        if maxCount >= 0, updated.count > maxCount {
            updated.removeLast(updated.count - maxCount)
        }
        return updated
    }

    public static func drift(currentIP: String, in entries: [EgressHistoryEntry]) -> EgressDrift? {
        guard let previous = entries.first, previous.ip != currentIP else { return nil }
        return .init(previousIP: previous.ip, currentIP: currentIP, previousTime: previous.capturedAt)
    }
}

public enum EgressAudit {
    public static let serviceTargets = ["claude.ai", "api.anthropic.com", "console.anthropic.com"]

    public static func familyState(direct: String?, proxied: String?) -> EgressFamilyState {
        switch (direct, proxied) {
        case (nil, nil): return .notObserved
        case (.some, nil), (nil, .some): return .incomplete
        case let (.some(left), .some(right)): return left == right ? .consistent : .mismatch
        }
    }

    public static func parseCurlProbe(_ output: String, exitStatus: Int32, target: String,
                                      route: EgressRouteKind) -> EgressServiceProbe {
        let fields = output.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        func number(_ index: Int) -> Double? {
            guard fields.indices.contains(index) else { return nil }
            let value = Double(fields[index])
            return value?.isFinite == true ? value : nil
        }
        func milliseconds(_ index: Int) -> Int? {
            guard let value = number(index), value > 0 else { return nil }
            return Int((value * 1_000).rounded())
        }
        let status = fields.indices.contains(0) ? Int(fields[0]) : nil
        let remote = fields.indices.contains(4) && !fields[4].isEmpty ? fields[4] : nil
        let tls = milliseconds(2)
        let reached = tls != nil
        let http = status.flatMap { (100...599).contains($0) ? $0 : nil }
        let failure: String?
        if reached {
            failure = nil
        } else if exitStatus != 0 {
            failure = "TLS 未完成（curl \(exitStatus)）"
        } else {
            failure = "TLS 未完成"
        }
        return .init(target: target, route: route, reachedTLS: reached, httpStatus: http,
                     remoteIP: remote, connectMilliseconds: milliseconds(1),
                     tlsMilliseconds: tls, totalMilliseconds: milliseconds(3), failure: failure)
    }

    public static func parseIPWho(_ data: Data) -> IPIntelligence? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["success"] as? Bool != false,
              let ip = object["ip"] as? String else { return nil }
        let connection = object["connection"] as? [String: Any] ?? [:]
        let timezone = object["timezone"] as? [String: Any] ?? [:]
        let asnNumber = connection["asn"] as? NSNumber
        let asn = asnNumber.map { "AS\($0.intValue)" }
        return .init(ip: ip, sources: ["ipwho.is"],
                     countryCode: object["country_code"] as? String,
                     country: object["country"] as? String,
                     region: object["region"] as? String,
                     city: object["city"] as? String,
                     timezone: timezone["id"] as? String,
                     asn: asn,
                     organization: connection["org"] as? String,
                     isp: connection["isp"] as? String)
    }

    public static func parseIPAPI(_ data: Data) -> IPIntelligence? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] == nil,
              let ip = object["ip"] as? String else { return nil }
        let asnObject = object["asn"] as? [String: Any] ?? [:]
        let company = object["company"] as? [String: Any] ?? [:]
        let location = object["location"] as? [String: Any] ?? [:]
        let asnValue = asnObject["asn"]
        let asn: String?
        if let value = asnValue as? NSNumber {
            asn = "AS\(value.intValue)"
        } else if let value = asnValue as? String {
            asn = value.hasPrefix("AS") ? value : "AS\(value)"
        } else {
            asn = nil
        }
        func bool(_ key: String) -> Bool? { object[key] as? Bool }
        return .init(ip: ip, sources: ["ipapi.is"],
                     countryCode: location["country_code"] as? String,
                     country: location["country"] as? String,
                     region: location["state"] as? String,
                     city: location["city"] as? String,
                     timezone: location["timezone"] as? String,
                     asn: asn,
                     organization: asnObject["org"] as? String ?? company["name"] as? String,
                     isp: company["name"] as? String,
                     isDatacenter: bool("is_datacenter"),
                     isProxy: bool("is_proxy"),
                     isVPN: bool("is_vpn"),
                     isTor: bool("is_tor"),
                     isAbuser: bool("is_abuser"),
                     isCrawler: bool("is_crawler"),
                     isMobile: bool("is_mobile"),
                     isBogon: bool("is_bogon"))
    }

    public static func merge(_ base: IPIntelligence, with risk: IPIntelligence) -> IPIntelligence {
        var merged = base
        merged.sources = Array(Set(base.sources + risk.sources)).sorted()
        merged.countryCode = merged.countryCode ?? risk.countryCode
        merged.country = merged.country ?? risk.country
        merged.region = merged.region ?? risk.region
        merged.city = merged.city ?? risk.city
        merged.timezone = merged.timezone ?? risk.timezone
        merged.asn = merged.asn ?? risk.asn
        merged.organization = merged.organization ?? risk.organization
        merged.isp = merged.isp ?? risk.isp
        merged.isDatacenter = risk.isDatacenter
        merged.isProxy = risk.isProxy
        merged.isVPN = risk.isVPN
        merged.isTor = risk.isTor
        merged.isAbuser = risk.isAbuser
        merged.isCrawler = risk.isCrawler
        merged.isMobile = risk.isMobile
        merged.isBogon = risk.isBogon
        return merged
    }

    public static func intelligenceFindings(_ values: [IPIntelligence]) -> [EgressFinding] {
        let countries = Set(values.compactMap(\.countryCode).filter { !$0.isEmpty })
        let asns = Set(values.compactMap(\.asn).filter { !$0.isEmpty })
        var findings: [EgressFinding] = []
        if countries.count > 1 { findings.append(.countryMismatch) }
        if asns.count > 1 { findings.append(.asnMismatch) }
        return findings
    }

    public static func intelligenceStatus(requestedIPs: [String], intelligence: [IPIntelligence],
                                         primaryIP: String?, enabled: Bool) -> EgressIntelligenceStatus {
        guard enabled else { return .disabled }
        guard !intelligence.isEmpty else { return .unavailable }
        if intelligence.count < requestedIPs.count
            || primaryIP == nil
            || intelligence.first(where: { $0.ip == primaryIP })?.hasRiskMetadata != true {
            return .partial
        }
        return .available
    }

    public static func assess(families: [EgressFamilyObservation], services: [EgressServiceProbe],
                              intelligence: [IPIntelligence],
                              intelligenceStatus: EgressIntelligenceStatus,
                              ipv6: IPv6EgressReport? = nil,
                              leaks: LeakEgressReport? = nil,
                              timeZone: EgressTimeZoneCheck? = nil) -> EgressAssessment {
        var findings: [EgressFinding] = []
        if families.allSatisfy({ $0.state == .notObserved }) { findings.append(.noObservedExit) }
        if families.contains(where: { $0.state == .mismatch || $0.targetMismatch }) {
            findings.append(.exitMismatch)
        }
        if families.contains(where: { $0.state == .incomplete }) {
            findings.append(.incompleteExitEvidence)
        }
        if !services.isEmpty && services.contains(where: { !$0.reachedTLS }) {
            findings.append(.serviceUnreachable)
        }
        for family in families {
            guard let direct = family.directIP, let proxied = family.proxiedIP, direct != proxied else { continue }
            let pair = [direct, proxied].compactMap { ip in intelligence.first { $0.ip == ip } }
            findings += intelligenceFindings(pair)
        }
        let primary = intelligence.first
        if primary?.isDatacenter == true { findings.append(.datacenterNetwork) }
        if primary?.isProxy == true { findings.append(.proxySignal) }
        if primary?.isVPN == true { findings.append(.vpnSignal) }
        if primary?.isTor == true { findings.append(.torSignal) }
        if primary?.isAbuser == true { findings.append(.abuseSignal) }
        if primary?.isCrawler == true { findings.append(.crawlerSignal) }
        if primary?.isMobile == true { findings.append(.mobileNetwork) }
        if primary?.isBogon == true { findings.append(.bogonAddress) }
        switch intelligenceStatus {
        case .disabled:
            findings.append(.thirdPartyDisabled)
        case .partial, .unavailable:
            findings.append(.riskIntelligenceUnavailable)
        case .available:
            break
        }
        switch ipv6?.state {
        case .directExposure:
            findings.append(.ipv6DirectExposure)
        case .tunnelExitMismatch:
            findings.append(.ipv6TunnelExitMismatch)
        case .tunnelUnconfirmed:
            findings.append(.ipv6ProxyUnconfirmed)
        case .unknown:
            findings.append(.ipv6PathUnknown)
        case .disabled, .noClaudePath, .tunneled, .none:
            break
        }
        if let dns = leaks?.dns {
            if dns.level == .failed {
                findings.append(.dnsPathLeakSuspected)
            } else if dns.level == .unknown || dns.level == .warning {
                findings.append(.dnsPathUnverified)
            }
        }
        if let udp = leaks?.udpChecks {
            if udp.contains(where: { $0.level == .failed }) {
                findings.append(.udpExitMismatch)
            } else if udp.contains(where: { $0.level == .unknown || $0.level == .warning }) {
                findings.append(.udpExitUnverified)
            }
        }
        if leaks?.dualStack?.fallbackSuspected == true {
            findings.append(.dualStackFallbackSuspected)
        }
        switch timeZone?.state {
        case .mismatch:
            findings.append(.timeZoneMismatch)
        case .unverified:
            findings.append(.timeZoneUnverified)
        case .disabled, .consistent, .none:
            break
        }
        let attention: Set<EgressFinding> = [
            .exitMismatch, .serviceUnreachable, .countryMismatch, .asnMismatch,
            .datacenterNetwork, .proxySignal, .vpnSignal, .torSignal,
            .abuseSignal, .crawlerSignal, .bogonAddress,
            .ipv6DirectExposure, .ipv6TunnelExitMismatch,
            .dnsPathLeakSuspected, .udpExitMismatch, .dualStackFallbackSuspected,
            .timeZoneMismatch
        ]
        let level: EgressAssessmentLevel
        if !attention.isDisjoint(with: findings) {
            level = .attention
        } else if findings.contains(.noObservedExit) || findings.contains(.incompleteExitEvidence)
                    || findings.contains(.riskIntelligenceUnavailable)
                    || findings.contains(.ipv6ProxyUnconfirmed)
                    || findings.contains(.ipv6PathUnknown)
                    || findings.contains(.dnsPathUnverified)
                    || findings.contains(.udpExitUnverified)
                    || findings.contains(.timeZoneUnverified) {
            level = .insufficient
        } else {
            level = .clear
        }
        return .init(level: level, findings: Array(Set(findings)).sorted { $0.rawValue < $1.rawValue })
    }

    public static func run(snapshot: DiagnosticSnapshot, includeIntelligence: Bool) async -> EgressAuditReport {
        let proxy = ProxyEndpoint.current()
        async let ipv6Audit = IPv6EgressAudit.run(snapshot: snapshot)
        let families = IPFamily.allCases.map { family -> EgressFamilyObservation in
            let exits = snapshot.familyExits.first { $0.family == family }
            return .init(family: family, directIP: exits?.direct, proxiedIP: exits?.proxied,
                         targetIP: snapshot.settings.target(for: family))
        }
        let observedIPs = Array(Set(families.flatMap { [$0.directIP, $0.proxiedIP].compactMap { $0 } }))
        let primaryIP = snapshot.proxyIP ?? snapshot.tunnelIP ?? families.lazy.compactMap(\.proxiedIP).first
            ?? families.lazy.compactMap(\.directIP).first

        var probes: [EgressServiceProbe] = []
        await withTaskGroup(of: EgressServiceProbe.self) { group in
            for target in serviceTargets {
                group.addTask { await probe(target: target, route: .system, proxy: nil) }
                if let proxy {
                    group.addTask { await probe(target: target, route: .proxy, proxy: proxy) }
                }
            }
            for await result in group { probes.append(result) }
        }
        probes.sort {
            let first = serviceTargets.firstIndex(of: $0.target) ?? Int.max
            let second = serviceTargets.firstIndex(of: $1.target) ?? Int.max
            return first == second ? $0.route.rawValue < $1.route.rawValue : first < second
        }

        var intelligence: [IPIntelligence] = []
        var intelligenceStatus: EgressIntelligenceStatus = .disabled
        if includeIntelligence {
            let requestedIPs = Array(observedIPs.prefix(4))
            for ip in requestedIPs {
                if let value = await fetchIPWho(ip: ip) { intelligence.append(value) }
            }
            if let primaryIP {
                let primaryRisk = await fetchIPAPI(ip: primaryIP)
                if let risk = primaryRisk {
                    if let index = intelligence.firstIndex(where: { $0.ip == primaryIP }) {
                        intelligence[index] = merge(intelligence[index], with: risk)
                    } else {
                        intelligence.append(risk)
                    }
                }
            }
            intelligenceStatus = EgressAudit.intelligenceStatus(
                requestedIPs: requestedIPs, intelligence: intelligence,
                primaryIP: primaryIP, enabled: true
            )
            intelligence.sort {
                if $0.ip == primaryIP { return $1.ip != primaryIP }
                if $1.ip == primaryIP { return false }
                return $0.ip < $1.ip
            }
        }
        let ipv6 = await ipv6Audit
        async let leakAudit = LeakEgressAudit.run(snapshot: snapshot, ipv6: ipv6)
        let leaks = await leakAudit
        let timeZone = EgressTimeZoneAudit.evaluate(
            primaryIP: primaryIP,
            intelligence: intelligence,
            intelligenceEnabled: includeIntelligence
        )
        let finalAssessment = assess(
            families: families, services: probes, intelligence: intelligence,
            intelligenceStatus: intelligenceStatus, ipv6: ipv6, leaks: leaks,
            timeZone: timeZone
        )
        return .init(snapshotTime: snapshot.checkedAt, proxyConfigured: proxy != nil,
                     primaryIP: primaryIP, families: families, services: probes,
                     intelligence: intelligence, intelligenceStatus: intelligenceStatus,
                     assessment: finalAssessment, ipv6: ipv6, leaks: leaks,
                     timeZone: timeZone)
    }

    private static func probe(target: String, route: EgressRouteKind, proxy: ProxyEndpoint?) async -> EgressServiceProbe {
        await Task.detached(priority: .utility) {
            var args = ["--disable", "--silent", "--show-error", "--connect-timeout", "4", "--max-time", "10",
                        "--max-filesize", "1048576", "--proto", "=https", "--output", "/dev/null",
                        "--write-out", "%{http_code}\t%{time_connect}\t%{time_appconnect}\t%{time_total}\t%{remote_ip}"]
            if let proxy {
                args += ["--proxy", proxy.url]
            } else {
                args += ["--noproxy", "*"]
            }
            args.append("https://\(target)/")
            let result = Command.run("/usr/bin/curl", args, timeout: 12)
            return parseCurlProbe(result.output, exitStatus: result.status, target: target, route: route)
        }.value
    }

    private static func fetchData(_ url: String) async -> Data? {
        await Task.detached(priority: .utility) {
            let result = Command.run("/usr/bin/curl", [
                "--disable", "--silent", "--show-error", "--fail", "--connect-timeout", "4",
                "--max-time", "8", "--max-filesize", "262144", "--proto", "=https",
                "--noproxy", "*", "--header", "Accept: application/json", url
            ], timeout: 10)
            return result.status == 0 ? Data(result.output.utf8) : nil
        }.value
    }

    private static func fetchIPWho(ip: String) async -> IPIntelligence? {
        guard let encoded = ip.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let data = await fetchData("https://ipwho.is/\(encoded)") else { return nil }
        return parseIPWho(data)
    }

    private static func fetchIPAPI(ip: String) async -> IPIntelligence? {
        guard let encoded = ip.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let data = await fetchData("https://ipapi.is/json/?q=\(encoded)") else { return nil }
        return parseIPAPI(data)
    }
}
