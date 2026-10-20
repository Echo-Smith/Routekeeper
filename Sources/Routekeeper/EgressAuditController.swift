import Foundation
import Observation
import GuardCore

enum EgressAuditTrigger: String, Codable, Sendable {
    case manual
    case scheduled
    case networkChange

    var title: String {
        switch self {
        case .manual: return L10n.resolvedEnglish ? "Manual" : "手动"
        case .scheduled: return L10n.resolvedEnglish ? "Scheduled" : "定时"
        case .networkChange: return L10n.resolvedEnglish ? "Network change" : "网络变化"
        }
    }
}

@MainActor @Observable
final class EgressAuditController {
    var report: EgressAuditReport?
    var previousReport: EgressAuditReport?
    var history: [EgressHistoryEntry]
    var drift: EgressDrift?
    var lastRunTrigger: EgressAuditTrigger?
    var busy = false
    var notice = ""

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let historyKey = "routekeeper-egress-history-v1"
    @ObservationIgnored private let reportKey = "routekeeper-egress-report-v1"
    @ObservationIgnored private let previousReportKey = "routekeeper-egress-previous-report-v1"
    @ObservationIgnored private let triggerKey = "routekeeper-egress-trigger-v1"
    @ObservationIgnored private let runAudit: @Sendable (DiagnosticSnapshot, Bool) async -> EgressAuditReport

    init(defaults: UserDefaults = .standard,
         runAudit: @escaping @Sendable (DiagnosticSnapshot, Bool) async -> EgressAuditReport = {
             await EgressAudit.run(snapshot: $0, includeIntelligence: $1)
         }) {
        self.defaults = defaults
        self.runAudit = runAudit
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        history = defaults.data(forKey: historyKey)
            .flatMap { try? decoder.decode([EgressHistoryEntry].self, from: $0) } ?? []
        report = defaults.data(forKey: reportKey)
            .flatMap { try? decoder.decode(EgressAuditReport.self, from: $0) }
        previousReport = defaults.data(forKey: previousReportKey)
            .flatMap { try? decoder.decode(EgressAuditReport.self, from: $0) }
        lastRunTrigger = defaults.string(forKey: triggerKey)
            .flatMap(EgressAuditTrigger.init(rawValue:))
    }

    var comparison: EgressReportComparison? {
        guard let report, let previousReport else { return nil }
        return EgressReportComparison(previous: previousReport, current: report)
    }

    @discardableResult
    func run(snapshot: DiagnosticSnapshot, includeIntelligence: Bool,
             trigger: EgressAuditTrigger = .manual) async -> EgressAuditReport? {
        guard !busy else { return nil }
        busy = true
        notice = ""
        let result = await runAudit(snapshot, includeIntelligence)
        guard !Task.isCancelled else {
            busy = false
            return nil
        }
        previousReport = report
        report = result
        lastRunTrigger = trigger
        if let ip = result.primaryIP {
            let intelligence = result.intelligence.first { $0.ip == ip }
            let entry = EgressHistoryEntry(
                ip: ip,
                asn: intelligence?.asn,
                countryCode: intelligence?.countryCode,
                city: intelligence?.city,
                sources: intelligence?.sources ?? []
            )
            drift = EgressHistory.drift(currentIP: ip, in: history)
            history = EgressHistory.append(entry, to: history)
            persistHistory()
        } else {
            notice = L10n.resolvedEnglish
                ? "No public exit was observed. This is not a pass."
                : "本次未观察到公网出口，这不代表通过。"
        }
        persistReports()
        busy = false
        return result
    }

    func clearHistory() {
        history = []
        drift = nil
        defaults.removeObject(forKey: historyKey)
    }

    func clearStoredResults() {
        report = nil
        previousReport = nil
        lastRunTrigger = nil
        defaults.removeObject(forKey: reportKey)
        defaults.removeObject(forKey: previousReportKey)
        defaults.removeObject(forKey: triggerKey)
        notice = L10n.resolvedEnglish
            ? "Stored egress reports were removed. History was not changed."
            : "已清除本机保存的出口体检报告；出口历史未改变。"
    }

    private func persistHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func persistReports() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let report, let data = try? encoder.encode(report) {
            defaults.set(data, forKey: reportKey)
        }
        if let previousReport, let data = try? encoder.encode(previousReport) {
            defaults.set(data, forKey: previousReportKey)
        } else {
            defaults.removeObject(forKey: previousReportKey)
        }
        if let lastRunTrigger {
            defaults.set(lastRunTrigger.rawValue, forKey: triggerKey)
        }
    }
}
