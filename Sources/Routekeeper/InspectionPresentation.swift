import GuardCore

enum InspectionOutcome: Equatable {
    case notRun
    case running
    case attention
    case incomplete
    case passed
}

enum InspectionIssueReference: Equatable {
    case gateway(GatewayVerificationStatus)
    case check(id: String, level: CheckLevel)
    case assessment
    case snapshot
}

enum InspectionPrimaryAction: Equatable {
    case runFullCheck
    case rerunFullCheck
    case gatewayBaseline
    case gatewayNodeFailureTest
    case gatewayClientExitTest
    case gatewayRecovery
}

struct InspectionPresentationState: Equatable {
    let outcome: InspectionOutcome
    let primaryIssue: InspectionIssueReference?
    let primaryAction: InspectionPrimaryAction?
}

enum InspectionPresentationResolver {
    static func resolve(
        isRunning: Bool,
        hasSnapshot: Bool,
        snapshotReady: Bool,
        hasAuditReport: Bool,
        auditLevel: EgressAssessmentLevel?,
        gatewayMode: GatewayProtectionMode,
        gatewayStatus: GatewayVerificationStatus,
        checks: [CheckItem]
    ) -> InspectionPresentationState {
        if isRunning {
            return InspectionPresentationState(
                outcome: .running,
                primaryIssue: nil,
                primaryAction: nil
            )
        }
        guard hasSnapshot else {
            return InspectionPresentationState(
                outcome: .notRun,
                primaryIssue: nil,
                primaryAction: .runFullCheck
            )
        }

        if gatewayMode != .off, gatewayStatus != .verified {
            return InspectionPresentationState(
                outcome: .attention,
                primaryIssue: .gateway(gatewayStatus),
                primaryAction: gatewayAction(for: gatewayStatus)
            )
        }

        for level in [CheckLevel.failed] {
            if let check = checks.first(where: { $0.level == level && $0.needsAttention }) {
                return InspectionPresentationState(
                    outcome: .attention,
                    primaryIssue: .check(id: check.id, level: level),
                    primaryAction: .rerunFullCheck
                )
            }
        }

        if auditLevel == .insufficient {
            return InspectionPresentationState(
                outcome: .incomplete,
                primaryIssue: .assessment,
                primaryAction: .rerunFullCheck
            )
        }

        for level in [CheckLevel.unknown, .warning] {
            if let check = checks.first(where: { $0.level == level && $0.needsAttention }) {
                return InspectionPresentationState(
                    outcome: .attention,
                    primaryIssue: .check(id: check.id, level: level),
                    primaryAction: .rerunFullCheck
                )
            }
        }

        if !snapshotReady {
            return InspectionPresentationState(
                outcome: .attention,
                primaryIssue: .snapshot,
                primaryAction: .rerunFullCheck
            )
        }
        guard hasAuditReport else {
            return InspectionPresentationState(
                outcome: .incomplete,
                primaryIssue: .assessment,
                primaryAction: .rerunFullCheck
            )
        }
        if auditLevel == .attention {
            return InspectionPresentationState(
                outcome: .attention,
                primaryIssue: .assessment,
                primaryAction: .rerunFullCheck
            )
        }
        return InspectionPresentationState(
            outcome: .passed,
            primaryIssue: nil,
            primaryAction: .rerunFullCheck
        )
    }

    static func passedChecks(from checks: [CheckItem]) -> [CheckItem] {
        checks.filter { $0.id != "boundary" && $0.level == .passed }
    }

    static func unresolvedChecks(from checks: [CheckItem]) -> [CheckItem] {
        checks.filter { $0.id != "boundary" && $0.level != .passed }
    }

    private static func gatewayAction(
        for status: GatewayVerificationStatus
    ) -> InspectionPrimaryAction {
        switch status {
        case .unverified, .failed, .expired:
            return .gatewayBaseline
        case .needsNodeFailureTest:
            return .gatewayNodeFailureTest
        case .needsClientExitTest:
            return .gatewayClientExitTest
        case .needsRecovery:
            return .gatewayRecovery
        case .verified:
            return .rerunFullCheck
        }
    }
}
