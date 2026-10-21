import Foundation

/// Host-side network policy for the Claude Science web UI. The daemon itself
/// remains inside Seatbelt; these rules keep its window from becoming an
/// unrestricted browser.
public enum ScienceWebBoundary {
    private static let loginExpression = try! NSRegularExpression(
        pattern: #"https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]+/\?nonce=[A-Fa-f0-9]+"#
    )
    private static let nonceExpression = try! NSRegularExpression(
        pattern: #"(?i)([?&]nonce=)[A-Fa-f0-9]+"#
    )
    private static let cookieExpression = try! NSRegularExpression(
        pattern: #"(?i)(operon_csrf=)[A-Fa-f0-9]+"#
    )

    public static func loginURL(in output: String) -> URL? {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = loginExpression.firstMatch(in: output, range: range),
              let urlRange = Range(match.range, in: output) else {
            return nil
        }
        return URL(string: String(output[urlRange]))
    }

    public static func redactSecrets(in output: String) -> String {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let redactedNonce = nonceExpression.stringByReplacingMatches(
            in: output,
            range: range,
            withTemplate: "$1<redacted>"
        )
        let redactedRange = NSRange(
            redactedNonce.startIndex..<redactedNonce.endIndex,
            in: redactedNonce
        )
        return cookieExpression.stringByReplacingMatches(
            in: redactedNonce,
            range: redactedRange,
            withTemplate: "$1<redacted>"
        )
    }

    /// Content blockers run in WebKit's network process, outside Routekeeper's
    /// own process sandbox. Block all public HTTP/WebSocket loads first, then
    /// exempt only the daemon's exact loopback ports.
    public static func contentRuleListJSON(ports: Set<Int>) -> String? {
        let validPorts = ports.filter { (1...65535).contains($0) }.sorted()
        guard !validPorts.isEmpty else { return nil }
        var rules: [[String: Any]] = [
            [
                "trigger": ["url-filter": #"^https?://"#],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": #"^wss?://"#],
                "action": ["type": "block"]
            ]
        ]
        for port in validPorts {
            for (scheme, host) in [
                ("http", "localhost"),
                ("http", #"127\.0\.0\.1"#),
                ("http", #"\[::1\]"#),
                ("ws", "localhost"),
                ("ws", #"127\.0\.0\.1"#),
                ("ws", #"\[::1\]"#)
            ] {
                rules.append([
                    "trigger": [
                        "url-filter": "^\(scheme)://\(host):\(port)/"
                    ],
                    "action": ["type": "ignore-previous-rules"]
                ])
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    public static func isAllowedNavigation(_ url: URL, ports: Set<Int>) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1"].contains(host),
              let port = url.port else {
            return false
        }
        return ports.contains(port)
    }

    /// Parse the same `lsof -Fpcn` format used by the listener audit. Only
    /// loopback listeners owned by the recorded daemon process are returned.
    public static func loopbackListenerPorts(
        in lsofOutput: String,
        ownedPIDs: Set<Int32>
    ) -> Set<Int> {
        var currentPID: Int32?
        var ports = Set<Int>()
        for line in lsofOutput.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            if field == "p" {
                currentPID = Int32(value)
                continue
            }
            guard field == "n", let currentPID, ownedPIDs.contains(currentPID) else {
                continue
            }
            let endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard endpoint.hasPrefix("127.0.0.1:")
                    || endpoint.hasPrefix("[::1]:")
                    || endpoint.hasPrefix("localhost:"),
                  let colon = endpoint.lastIndex(of: ":"),
                  let port = Int(endpoint[endpoint.index(after: colon)...]),
                  (1...65535).contains(port) else {
                continue
            }
            ports.insert(port)
        }
        return ports
    }

    public static func safeDownloadName(_ suggested: String) -> String {
        let base = URL(fileURLWithPath: suggested).lastPathComponent
        let filtered = base.unicodeScalars.map { scalar -> Character in
            if scalar.value < 32 || scalar.value == 127 || scalar == "/" || scalar == "\\" {
                return "_"
            }
            return Character(String(scalar))
        }
        let name = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { return "Science Download" }
        return String(name.prefix(180))
    }
}
