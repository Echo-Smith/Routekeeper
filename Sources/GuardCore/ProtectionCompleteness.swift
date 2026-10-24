import Foundation

public enum ProtectionCompletenessState: String, Codable, Sendable {
    case notRun
    case incomplete
    case needsReview
    case scored
}

public enum ProtectionCompletenessBand: String, Codable, Sendable {
    case strong
    case good
    case limited
    case needsAttention
}

public enum ProtectionEvidenceQuality: String, Codable, Sendable {
    case direct
    case crossChecked
    case inferred
    case insufficient
}

public enum ProtectionCompletenessArea: String, CaseIterable, Codable, Sendable {
    case protectionSetup
    case localPath
    case egressConsistency
    case claudeEnvironment
    case gatewayFailClosed
}

public struct ProtectionCompletenessAssessment: Equatable, Sendable {
    public var state: ProtectionCompletenessState
    public var score: Int?
    public var band: ProtectionCompletenessBand?
    public var evidenceQuality: ProtectionEvidenceQuality
    public var attentionAreas: [ProtectionCompletenessArea]
    public var referenceDate: Date?

    public init(
        state: ProtectionCompletenessState,
        score: Int? = nil,
        band: ProtectionCompletenessBand? = nil,
        evidenceQuality: ProtectionEvidenceQuality,
        attentionAreas: [ProtectionCompletenessArea] = [],
        referenceDate: Date? = nil
    ) {
        self.state = state
        self.score = score
        self.band = band
        self.evidenceQuality = evidenceQuality
        self.attentionAreas = attentionAreas
        self.referenceDate = referenceDate
    }
}

public enum ProtectionCompleteness {
    public static let snapshotFreshness: TimeInterval = 15 * 60
    public static let egressFreshness: TimeInterval = 30 * 60

    private struct Component {
        var weight: Double
        var ratio: Double
    }

    private struct Category {
        var area: ProtectionCompletenessArea
        var score: Double
    }

    public static func evaluate(
        snapshot: DiagnosticSnapshot?,
        egress: EgressAuditReport?,
        gatewayMode: GatewayProtectionMode,
        gatewayStatus: GatewayVerificationStatus,
        hasInvalidatedEvidence: Bool = false,
        now: Date = Date()
    ) -> ProtectionCompletenessAssessment {
        guard let snapshot else {
            return .init(
                state: hasInvalidatedEvidence ? .needsReview : .notRun,
                evidenceQuality: .insufficient
            )
        }

        let snapshotAge = now.timeIntervalSince(snapshot.checkedAt)
        guard snapshotAge >= -60, snapshotAge <= snapshotFreshness else {
            return .init(
                state: .needsReview,
                evidenceQuality: .insufficient,
                referenceDate: snapshot.checkedAt
            )
        }

        guard let egress else {
            return .init(
                state: .incomplete,
                evidenceQuality: .insufficient,
                referenceDate: snapshot.checkedAt
            )
        }

        let egressAge = now.timeIntervalSince(egress.auditedAt)
        let snapshotMismatch = abs(egress.snapshotTime.timeIntervalSince(snapshot.checkedAt)) > 2
        guard egressAge >= -60,
              egressAge <= egressFreshness,
              !snapshotMismatch else {
            return .init(
                state: .needsReview,
                evidenceQuality: .insufficient,
                referenceDate: egress.auditedAt
            )
        }

        let observedFamilies = egress.families.filter { $0.state != .notObserved }
        guard egress.assessment.level != .insufficient,
              !observedFamilies.isEmpty,
              !egress.services.isEmpty else {
            return .init(
                state: .incomplete,
                evidenceQuality: .insufficient,
                referenceDate: egress.auditedAt
            )
        }

        var categories = [
            protectionSetup(snapshot),
            localPath(snapshot, egress: egress),
            egressConsistency(egress),
            claudeEnvironment(snapshot, egress: egress)
        ]
        if gatewayMode != .off {
            categories.append(.init(
                area: .gatewayFailClosed,
                score: gatewayRatio(gatewayStatus)
            ))
        }

        let totalWeight = categories.reduce(0) { $0 + categoryWeight($1.area) }
        let weightedScore = categories.reduce(0) {
            $0 + categoryWeight($1.area) * $1.score
        }
        let evidenceQuality = evidenceQuality(snapshot: snapshot, egress: egress)
        let rawScore = totalWeight > 0 ? weightedScore / totalWeight * 100 : 0
        let evidenceCappedScore = min(evidenceCap(evidenceQuality), Int(rawScore.rounded()))
        let score = min(evidenceCappedScore, gatewayScoreCap(gatewayMode, gatewayStatus))
        let band = band(for: score)
        let attentionAreas = categories
            .filter { $0.score < 0.72 }
            .map(\.area)

        return .init(
            state: .scored,
            score: score,
            band: band,
            evidenceQuality: evidenceQuality,
            attentionAreas: attentionAreas,
            referenceDate: egress.auditedAt
        )
    }

    private static func categoryWeight(_ area: ProtectionCompletenessArea) -> Double {
        switch area {
        case .protectionSetup: return 12
        case .localPath: return 25
        case .egressConsistency: return 25
        case .claudeEnvironment: return 26
        case .gatewayFailClosed: return 12
        }
    }

    private static func protectionSetup(_ snapshot: DiagnosticSnapshot) -> Category {
        let targetCoverage: Double
        if snapshot.enabledFamilies.isEmpty {
            targetCoverage = IPFamily.allCases.contains {
                snapshot.settings.target(for: $0) != nil
            } ? 1 : 0
        } else {
            let configured = snapshot.enabledFamilies.filter {
                snapshot.settings.target(for: $0) != nil
            }.count
            targetCoverage = Double(configured) / Double(snapshot.enabledFamilies.count)
        }
        let components = [
            Component(weight: 0.4, ratio: snapshot.settings.hasSelection ? 1 : 0),
            Component(weight: 0.3, ratio: snapshot.settings.validInterval ? 1 : 0),
            Component(weight: 0.3, ratio: targetCoverage)
        ]
        return .init(area: .protectionSetup, score: weightedRatio(components))
    }

    private static func localPath(
        _ snapshot: DiagnosticSnapshot,
        egress: EgressAuditReport
    ) -> Category {
        let enabledFamilies = snapshot.enabledFamilies
        let udpRatios: [Double]
        if enabledFamilies.isEmpty {
            udpRatios = [1]
        } else {
            udpRatios = IPFamily.allCases.filter(enabledFamilies.contains).map { family in
                ratio(for: snapshot.checks.first { $0.id == "udp-\(family.rawValue)" }?.level)
            }
        }
        let components = [
            Component(weight: 0.10, ratio: ratio(for: check("proxy-client", in: snapshot)?.level)),
            Component(weight: 0.20, ratio: ratio(for: check("proxy", in: snapshot)?.level)),
            Component(weight: 0.20, ratio: ratio(for: check("tun", in: snapshot)?.level)),
            Component(weight: 0.15, ratio: ratio(for: check("dns", in: snapshot)?.level)),
            Component(weight: 0.25, ratio: familyConsistency(egress)),
            Component(weight: 0.10, ratio: average(udpRatios))
        ]
        return .init(area: .localPath, score: weightedRatio(components))
    }

    private static func egressConsistency(_ egress: EgressAuditReport) -> Category {
        let serviceRatio = egress.services.isEmpty
            ? 0
            : Double(egress.services.filter(\.reachedTLS).count) / Double(egress.services.count)
        let components = [
            Component(weight: 0.30, ratio: assessmentRatio(egress.assessment)),
            Component(weight: 0.35, ratio: serviceRatio),
            Component(weight: 0.20, ratio: familyConsistency(egress)),
            Component(weight: 0.15, ratio: findingRatio(egress.assessment))
        ]
        return .init(area: .egressConsistency, score: weightedRatio(components))
    }

    private static func claudeEnvironment(
        _ snapshot: DiagnosticSnapshot,
        egress: EgressAuditReport
    ) -> Category {
        var components = [
            Component(weight: 0.15, ratio: ratio(for: check("process-access", in: snapshot)?.level)),
            Component(weight: 0.20, ratio: ratio(for: check("claude-trace-exit", in: snapshot)?.level))
        ]

        let selectedIDs: [String] = [
            snapshot.settings.protectDesktop ? "desktop" : nil,
            snapshot.settings.protectCode ? "code" : nil
        ].compactMap { $0 }
        if !selectedIDs.isEmpty {
            components.append(.init(
                weight: 0.15,
                ratio: average(selectedIDs.map {
                    ratio(for: check($0, in: snapshot)?.level)
                })
            ))
        }
        if let environment = snapshot.codeEnvironment {
            components.append(.init(
                weight: 0.15,
                ratio: environment.readable && environment.apiBaseHost == nil
                    && !environment.apiBaseConfigured ? 1 : environment.readable ? 0.55 : 0
            ))
        }
        if let network = snapshot.claudeProcessNetwork, network.processCount > 0 {
            let networkRatio: Double
            if !network.readable {
                networkRatio = 0
            } else if network.establishedConnections > 0 {
                networkRatio = 1
            } else {
                networkRatio = 0.55
            }
            components.append(.init(weight: 0.35, ratio: networkRatio))
        }

        let processEvidence = snapshot.claudeProcessNetwork?.establishedConnections ?? 0
        if processEvidence == 0 {
            let activeServiceEvidence = egress.services.filter(\.reachedTLS).count
            if activeServiceEvidence > 0 {
                components.append(.init(weight: 0.04, ratio: 0.85))
            }
        }
        return .init(area: .claudeEnvironment, score: weightedRatio(components))
    }

    private static func evidenceQuality(
        snapshot: DiagnosticSnapshot,
        egress: EgressAuditReport
    ) -> ProtectionEvidenceQuality {
        if let network = snapshot.claudeProcessNetwork,
           network.readable,
           network.establishedConnections > 0 {
            return .direct
        }
        if check("claude-trace-exit", in: snapshot)?.level == .passed,
           egress.services.filter(\.reachedTLS).count >= 2 {
            return .crossChecked
        }
        return .inferred
    }

    private static func evidenceCap(_ quality: ProtectionEvidenceQuality) -> Int {
        switch quality {
        case .direct: return 100
        case .crossChecked: return 92
        case .inferred: return 78
        case .insufficient: return 0
        }
    }

    private static func band(for score: Int) -> ProtectionCompletenessBand {
        if score >= 90 { return .strong }
        if score >= 75 { return .good }
        if score >= 55 { return .limited }
        return .needsAttention
    }

    private static func gatewayRatio(_ status: GatewayVerificationStatus) -> Double {
        switch status {
        case .verified: return 1
        case .needsRecovery: return 0.55
        case .needsClientExitTest: return 0.42
        case .needsNodeFailureTest: return 0.28
        case .unverified: return 0.12
        case .expired: return 0.08
        case .failed: return 0
        }
    }

    private static func gatewayScoreCap(
        _ mode: GatewayProtectionMode,
        _ status: GatewayVerificationStatus
    ) -> Int {
        guard mode != .off else { return 100 }
        switch status {
        case .verified: return 100
        case .needsRecovery, .needsClientExitTest, .needsNodeFailureTest, .unverified:
            return 84
        case .failed, .expired:
            return 74
        }
    }

    private static func assessmentRatio(_ assessment: EgressAssessment) -> Double {
        switch assessment.level {
        case .clear: return 1
        case .attention: return 0
        case .insufficient: return 0.35
        }
    }

    private static func findingRatio(_ assessment: EgressAssessment) -> Double {
        let unconfirmed: Set<EgressFinding> = [
            .riskIntelligenceUnavailable,
            .ipv6ProxyUnconfirmed, .ipv6PathUnknown,
            .dnsPathUnverified, .udpExitUnverified, .timeZoneUnverified
        ]
        if !unconfirmed.isDisjoint(with: assessment.findings) {
            return 0.45
        }
        return assessment.level == .clear ? 1 : 0
    }

    private static func familyConsistency(_ report: EgressAuditReport) -> Double {
        let observed = report.families.filter { $0.state != .notObserved }
        guard !observed.isEmpty else { return 0 }
        let consistent = observed.filter {
            $0.state == .consistent && !$0.targetMismatch
        }.count
        return Double(consistent) / Double(observed.count)
    }

    private static func check(_ id: String, in snapshot: DiagnosticSnapshot) -> CheckItem? {
        snapshot.checks.first { $0.id == id }
    }

    private static func ratio(for level: CheckLevel?) -> Double {
        guard let level else { return 0 }
        switch level {
        case .passed: return 1
        case .warning: return 0.55
        case .unknown: return 0.2
        case .failed: return 0
        }
    }

    private static func weightedRatio(_ components: [Component]) -> Double {
        let total = components.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        return components.reduce(0) { $0 + $1.weight * $1.ratio } / total
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
