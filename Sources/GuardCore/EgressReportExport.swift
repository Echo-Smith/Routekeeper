import Foundation

public enum EgressTimeZoneState: String, Codable, Sendable {
    case disabled
    case unverified
    case consistent
    case mismatch
}

public struct EgressTimeZoneCheck: Codable, Equatable, Sendable {
    public var state: EgressTimeZoneState
    public var systemIdentifier: String
    public var systemOffsetSeconds: Int
    public var exitIdentifier: String?
    public var exitOffsetSeconds: Int?

    public init(state: EgressTimeZoneState, systemIdentifier: String,
                systemOffsetSeconds: Int, exitIdentifier: String?,
                exitOffsetSeconds: Int?) {
        self.state = state
        self.systemIdentifier = systemIdentifier
        self.systemOffsetSeconds = systemOffsetSeconds
        self.exitIdentifier = exitIdentifier
        self.exitOffsetSeconds = exitOffsetSeconds
    }

    public var offsetDifferenceHours: Double? {
        guard let exitOffsetSeconds else { return nil }
        return Double(abs(systemOffsetSeconds - exitOffsetSeconds)) / 3_600
    }
}

public enum EgressTimeZoneAudit {
    public static func evaluate(primaryIP: String?, intelligence: [IPIntelligence],
                                intelligenceEnabled: Bool, now: Date = Date(),
                                systemTimeZone: TimeZone = .current) -> EgressTimeZoneCheck {
        let systemOffset = systemTimeZone.secondsFromGMT(for: now)
        guard intelligenceEnabled else {
            return .init(state: .disabled, systemIdentifier: systemTimeZone.identifier,
                         systemOffsetSeconds: systemOffset, exitIdentifier: nil,
                         exitOffsetSeconds: nil)
        }
        let value: IPIntelligence?
        if let primaryIP {
            value = intelligence.first { $0.ip == primaryIP }
        } else {
            value = intelligence.first
        }
        guard let identifier = value?.timezone,
              let exitTimeZone = TimeZone(identifier: identifier) else {
            return .init(state: .unverified, systemIdentifier: systemTimeZone.identifier,
                         systemOffsetSeconds: systemOffset, exitIdentifier: value?.timezone,
                         exitOffsetSeconds: nil)
        }
        let exitOffset = exitTimeZone.secondsFromGMT(for: now)
        return .init(
            state: systemOffset == exitOffset ? .consistent : .mismatch,
            systemIdentifier: systemTimeZone.identifier,
            systemOffsetSeconds: systemOffset,
            exitIdentifier: exitTimeZone.identifier,
            exitOffsetSeconds: exitOffset
        )
    }
}

public enum EgressReportExport {
    public static let schema = "routekeeper.egress.redacted.v1"

    public static func redactedData(report: EgressAuditReport, history: [EgressHistoryEntry],
                                    appVersion: String,
                                    generatedAt: Date = Date()) throws -> Data {
        let object = redactedObject(
            report: report, history: history, appVersion: appVersion,
            generatedAt: generatedAt
        )
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    public static func redactedObject(report: EgressAuditReport, history: [EgressHistoryEntry],
                                      appVersion: String,
                                      generatedAt: Date = Date()) -> [String: Any] {
        let redactor = IPRedactor()
        func optionalIP(_ value: String?) -> Any {
            value.flatMap { redactor.token(for: $0) } ?? NSNull()
        }

        let families: [[String: Any]] = report.families.map { family in
            [
                "family": family.family.rawValue,
                "state": family.state.rawValue,
                "targetMismatch": family.targetMismatch,
                "systemExit": optionalIP(family.directIP),
                "proxyExit": optionalIP(family.proxiedIP),
                "targetExit": optionalIP(family.targetIP)
            ]
        }
        let services: [[String: Any]] = report.services.map { probe in
            [
                "target": probe.target,
                "route": probe.route.rawValue,
                "reachedTLS": probe.reachedTLS,
                "httpStatus": probe.httpStatus ?? NSNull(),
                "remoteIP": optionalIP(probe.remoteIP),
                "connectMilliseconds": probe.connectMilliseconds ?? NSNull(),
                "tlsMilliseconds": probe.tlsMilliseconds ?? NSNull(),
                "totalMilliseconds": probe.totalMilliseconds ?? NSNull(),
                "failure": probe.failure.map(redactor.redactText) ?? NSNull()
            ]
        }
        let intelligence: [[String: Any]] = report.intelligence.map { value in
            [
                "exit": redactor.token(for: value.ip) ?? NSNull(),
                "isPrimary": value.ip == report.primaryIP,
                "sources": value.sources,
                "countryCode": value.countryCode ?? NSNull(),
                "asn": value.asn ?? NSNull(),
                "timezone": value.timezone ?? NSNull(),
                "riskFlags": value.riskFlags.map(\.rawValue)
            ]
        }
        let historyValues: [[String: Any]] = history.map { entry in
            [
                "capturedAt": iso8601(entry.capturedAt),
                "exit": redactor.token(for: entry.ip) ?? NSNull(),
                "countryCode": entry.countryCode ?? NSNull(),
                "asn": entry.asn ?? NSNull(),
                "sources": entry.sources
            ]
        }

        var object: [String: Any] = [
            "schema": schema,
            "privacy": "IP addresses use stable replacement labels. Local paths and account data are excluded. Country, ASN, timezone and risk flags remain for diagnosis.",
            "generatedAt": iso8601(generatedAt),
            "appVersion": appVersion,
            "auditedAt": iso8601(report.auditedAt),
            "snapshotTime": iso8601(report.snapshotTime),
            "proxyConfigured": report.proxyConfigured,
            "primaryExit": optionalIP(report.primaryIP),
            "assessment": [
                "level": report.assessment.level.rawValue,
                "findings": report.assessment.findings.map(\.rawValue)
            ],
            "families": families,
            "services": services,
            "intelligenceStatus": report.intelligenceStatus.rawValue,
            "intelligence": intelligence,
            "history": historyValues
        ]

        if let ipv6 = report.ipv6 {
            object["ipv6"] = [
                "state": ipv6.state.rawValue,
                "localAddress": optionalIP(ipv6.localAddress),
                "systemExit": optionalIP(ipv6.systemPublicExit),
                "proxyExit": optionalIP(ipv6.proxyPublicExit),
                "probes": ipv6.probes.map { probe in
                    [
                        "target": probe.target,
                        "resolvedAddresses": probe.resolvedAddresses.compactMap { redactor.token(for: $0) },
                        "remoteAddress": optionalIP(probe.remoteAddress),
                        "routeInterface": probe.routeInterface ?? NSNull(),
                        "routeKind": probe.routeKind.rawValue,
                        "reachedTLS": probe.reachedTLS,
                        "httpStatus": probe.httpStatus ?? NSNull(),
                        "tlsMilliseconds": probe.tlsMilliseconds ?? NSNull(),
                        "failure": probe.failure.map(redactor.redactText) ?? NSNull()
                    ]
                }
            ]
        } else {
            object["ipv6"] = NSNull()
        }

        if let leaks = report.leaks {
            var leakObject: [String: Any] = [:]
            if let dns = leaks.dns { leakObject["dns"] = evidence(dns, redactor: redactor) }
            if let udp4 = leaks.udpIPv4 { leakObject["udpIPv4"] = evidence(udp4, redactor: redactor) }
            if let udp6 = leaks.udpIPv6 { leakObject["udpIPv6"] = evidence(udp6, redactor: redactor) }
            if let dual = leaks.dualStack {
                leakObject["dualStack"] = [
                    "target": dual.target,
                    "fallbackSuspected": dual.fallbackSuspected,
                    "switchedFamily": dual.switchedFamily,
                    "firstAttemptSlow": dual.firstAttemptSlow,
                    "firstAttemptFailedThenSucceeded": dual.firstAttemptFailedThenSucceeded,
                    "attempts": dual.attempts.map { attempt in
                        [
                            "id": attempt.id,
                            "reachedTLS": attempt.reachedTLS,
                            "remoteAddress": optionalIP(attempt.remoteAddress),
                            "family": attempt.family?.rawValue ?? NSNull(),
                            "httpStatus": attempt.httpStatus ?? NSNull(),
                            "connectMilliseconds": attempt.connectMilliseconds ?? NSNull(),
                            "tlsMilliseconds": attempt.tlsMilliseconds ?? NSNull(),
                            "totalMilliseconds": attempt.totalMilliseconds ?? NSNull(),
                            "failure": attempt.failure.map(redactor.redactText) ?? NSNull()
                        ]
                    }
                ]
            }
            object["leaks"] = leakObject
        } else {
            object["leaks"] = NSNull()
        }

        if let timeZone = report.timeZone {
            object["timeZone"] = [
                "state": timeZone.state.rawValue,
                "systemIdentifier": timeZone.systemIdentifier,
                "systemOffsetSeconds": timeZone.systemOffsetSeconds,
                "exitIdentifier": timeZone.exitIdentifier ?? (NSNull() as Any),
                "exitOffsetSeconds": timeZone.exitOffsetSeconds ?? (NSNull() as Any)
            ]
        } else {
            object["timeZone"] = NSNull()
        }
        return object
    }

    private static func evidence(_ value: EgressCheckEvidence,
                                 redactor: IPRedactor) -> [String: Any] {
        [
            "id": value.id,
            "title": value.title,
            "detail": redactor.redactText(value.detail),
            "level": value.level.rawValue
        ]
    }

    private static func iso8601(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}

final class IPRedactor {
    private var labels: [String: String] = [:]
    private var ipv4Count = 0
    private var ipv6Count = 0

    private static let ipv4Regex = try! NSRegularExpression(
        pattern: #"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])"#
    )
    private static let ipv6Regex = try! NSRegularExpression(
        pattern: #"(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}(?![0-9A-Fa-f:])"#
    )

    func token(for value: String) -> String? {
        guard let normalized = IPAddress.normalized(value) else { return nil }
        if let existing = labels[normalized] { return existing }
        let label: String
        if IPFamily.of(normalized) == .ipv4 {
            ipv4Count += 1
            label = String(format: "IPv4-%02d", ipv4Count)
        } else {
            ipv6Count += 1
            label = String(format: "IPv6-%02d", ipv6Count)
        }
        labels[normalized] = label
        return label
    }

    func redactText(_ value: String) -> String {
        let withoutIPv4 = replaceIPs(in: value, regex: Self.ipv4Regex)
        let withoutIPs = replaceIPs(in: withoutIPv4, regex: Self.ipv6Regex)
        return withoutIPs.replacingOccurrences(
            of: #"(?:~|/(?:Applications|Users|opt|usr|private|var|tmp|Volumes))/[^\s；;，,]+"#,
            with: "<本地路径>",
            options: .regularExpression
        )
    }

    private func replaceIPs(in value: String, regex: NSRegularExpression) -> String {
        let mutable = NSMutableString(string: value)
        let range = NSRange(location: 0, length: mutable.length)
        let matches = regex.matches(in: value, range: range)
        for match in matches.reversed() {
            let candidate = mutable.substring(with: match.range)
            guard let replacement = token(for: candidate) else { continue }
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return mutable as String
    }
}
