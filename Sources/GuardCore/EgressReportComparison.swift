import Foundation

public struct EgressServiceReachabilityChange: Codable, Equatable, Sendable, Identifiable {
    public var target: String
    public var route: EgressRouteKind
    public var previousReachedTLS: Bool
    public var currentReachedTLS: Bool

    public var id: String { "\(target)-\(route.rawValue)" }

    public init(target: String, route: EgressRouteKind, previousReachedTLS: Bool,
                currentReachedTLS: Bool) {
        self.target = target
        self.route = route
        self.previousReachedTLS = previousReachedTLS
        self.currentReachedTLS = currentReachedTLS
    }
}

public struct EgressReportComparison: Codable, Equatable, Sendable {
    public var previousAuditedAt: Date
    public var currentAuditedAt: Date
    public var previousLevel: EgressAssessmentLevel
    public var currentLevel: EgressAssessmentLevel
    public var addedFindings: [EgressFinding]
    public var resolvedFindings: [EgressFinding]
    public var previousPrimaryExit: String?
    public var currentPrimaryExit: String?
    public var previousCountryCode: String?
    public var currentCountryCode: String?
    public var previousASN: String?
    public var currentASN: String?
    public var previousTimeZoneState: EgressTimeZoneState?
    public var currentTimeZoneState: EgressTimeZoneState?
    public var previousIPv6State: IPv6ExposureState?
    public var currentIPv6State: IPv6ExposureState?
    public var serviceReachabilityChanges: [EgressServiceReachabilityChange]

    public var hasChanges: Bool {
        previousLevel != currentLevel
            || !addedFindings.isEmpty
            || !resolvedFindings.isEmpty
            || previousPrimaryExit != currentPrimaryExit
            || previousCountryCode != currentCountryCode
            || previousASN != currentASN
            || previousTimeZoneState != currentTimeZoneState
            || previousIPv6State != currentIPv6State
            || !serviceReachabilityChanges.isEmpty
    }

    public init(previous: EgressAuditReport, current: EgressAuditReport) {
        previousAuditedAt = previous.auditedAt
        currentAuditedAt = current.auditedAt
        previousLevel = previous.assessment.level
        currentLevel = current.assessment.level

        let oldFindings = Set(previous.assessment.findings)
        let newFindings = Set(current.assessment.findings)
        addedFindings = Array(newFindings.subtracting(oldFindings)).sorted { $0.rawValue < $1.rawValue }
        resolvedFindings = Array(oldFindings.subtracting(newFindings)).sorted { $0.rawValue < $1.rawValue }
        previousPrimaryExit = previous.primaryIP
        currentPrimaryExit = current.primaryIP

        let oldIntelligence = Self.primaryIntelligence(previous)
        let newIntelligence = Self.primaryIntelligence(current)
        previousCountryCode = oldIntelligence?.countryCode
        currentCountryCode = newIntelligence?.countryCode
        previousASN = oldIntelligence?.asn
        currentASN = newIntelligence?.asn
        previousTimeZoneState = previous.timeZone?.state
        currentTimeZoneState = current.timeZone?.state
        previousIPv6State = previous.ipv6?.state
        currentIPv6State = current.ipv6?.state

        let previousServices = Dictionary(
            uniqueKeysWithValues: previous.services.map { ($0.id, $0) }
        )
        serviceReachabilityChanges = current.services.compactMap { value in
            guard let old = previousServices[value.id],
                  old.reachedTLS != value.reachedTLS else { return nil }
            return .init(
                target: value.target, route: value.route,
                previousReachedTLS: old.reachedTLS, currentReachedTLS: value.reachedTLS
            )
        }.sorted {
            $0.target == $1.target
                ? $0.route.rawValue < $1.route.rawValue
                : $0.target < $1.target
        }
    }

    private static func primaryIntelligence(_ report: EgressAuditReport) -> IPIntelligence? {
        if let primaryIP = report.primaryIP {
            return report.intelligence.first { $0.ip == primaryIP }
        }
        return report.intelligence.first
    }
}
