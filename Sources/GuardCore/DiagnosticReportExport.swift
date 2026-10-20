import Foundation

public enum DiagnosticReportExport {
    public static let schema = "routekeeper.self-check.redacted.v1"

    public static func redactedData(snapshot: DiagnosticSnapshot, appVersion: String,
                                    generatedAt: Date = Date()) throws -> Data {
        let redactor = IPRedactor()
        func optionalIP(_ value: String?) -> Any {
            value.flatMap { redactor.token(for: $0) } ?? NSNull()
        }
        let processCounts = Dictionary(grouping: snapshot.processes, by: \.kind)
            .mapValues(\.count)
            .map { ["kind": $0.key.rawValue, "count": $0.value] }
            .sorted { ($0["kind"] as? String ?? "") < ($1["kind"] as? String ?? "") }

        let object: [String: Any] = [
            "schema": schema,
            "privacy": "IP addresses and local file paths are replaced. PIDs, executable paths and account data are excluded.",
            "generatedAt": iso8601(generatedAt),
            "appVersion": appVersion,
            "checkedAt": iso8601(snapshot.checkedAt),
            "ready": snapshot.ready,
            "failureSummary": redactor.redactText(snapshot.failureSummary),
            "settings": [
                "ipv4Target": optionalIP(snapshot.settings.fixedIPv4TargetIP),
                "ipv6Target": optionalIP(snapshot.settings.fixedIPv6TargetIP),
                "proxyClient": snapshot.settings.proxyClient.rawValue,
                "pollInterval": snapshot.settings.pollInterval,
                "dnsProbeEnabled": snapshot.settings.dnsProbeEnabled,
                "udpProbeEnabled": snapshot.settings.udpProbeEnabled,
                "protectDesktop": snapshot.settings.protectDesktop,
                "protectCode": snapshot.settings.protectCode,
                "action": snapshot.settings.action.rawValue
            ],
            "proxyExit": optionalIP(snapshot.proxyIP),
            "routeExit": optionalIP(snapshot.tunnelIP),
            "families": snapshot.familyExits.map { exit in
                [
                    "family": exit.family.rawValue,
                    "systemExit": optionalIP(exit.direct),
                    "proxyExit": optionalIP(exit.proxied)
                ]
            },
            "enabledFamilies": snapshot.enabledFamilies.map(\.rawValue).sorted(),
            "checks": snapshot.checks.map { row in
                [
                    "id": row.id,
                    "title": redactor.redactText(row.title),
                    "detail": redactor.redactText(row.detail),
                    "level": row.level.rawValue
                ]
            },
            "processCounts": processCounts,
            "installations": [
                "desktopFound": snapshot.desktopPath != nil,
                "codePathCount": snapshot.codePaths.count
            ]
        ]
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func iso8601(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}
