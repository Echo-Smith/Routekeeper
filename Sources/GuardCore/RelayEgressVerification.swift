import Foundation

public enum RelayEgressLevel: String, Codable, Equatable, Sendable {
    case verified
    case warning
}

public enum RelayEgressBasis: String, Codable, Equatable, Sendable {
    case exact
    case relayIPv4Anchor
}

public struct RelayEgressReport: Equatable, Sendable {
    public var checkedAt: Date
    public var level: RelayEgressLevel
    public var basis: RelayEgressBasis?
    public var claudeExitIP: String?
    public var relayIPv4ExitIP: String?
    public var expectedExits: IsolationExpectedExits
    public var apiReachable: Bool
    public var detail: String

    public var isVerified: Bool { level == .verified }

    public init(
        checkedAt: Date,
        level: RelayEgressLevel,
        basis: RelayEgressBasis?,
        claudeExitIP: String?,
        relayIPv4ExitIP: String?,
        expectedExits: IsolationExpectedExits,
        apiReachable: Bool,
        detail: String
    ) {
        self.checkedAt = checkedAt
        self.level = level
        self.basis = basis
        self.claudeExitIP = claudeExitIP
        self.relayIPv4ExitIP = relayIPv4ExitIP
        self.expectedExits = expectedExits
        self.apiReachable = apiReachable
        self.detail = detail
    }
}

public enum RelayEgressVerification {
    public static let claudeTraceURL = "https://claude.ai/cdn-cgi/trace"
    public static let relayIPv4ExitURL = "https://api.ipify.org"
    public static let anthropicAPIURL = "https://api.anthropic.com/"

    public static func check(
        proxyURL: String,
        expectedExits: IsolationExpectedExits
    ) async -> RelayEgressReport {
        let normalizedProxy = remoteResolvingProxyURL(proxyURL)
        async let claudeExit = probeClaudeExit(proxyURL: normalizedProxy)
        async let relayIPv4Exit = probeIPv4Exit(proxyURL: normalizedProxy)
        async let apiReachable = probeAPI(proxyURL: normalizedProxy)
        let values = await (claudeExit, relayIPv4Exit, apiReachable)
        return evaluate(
            claudeExitIP: values.0,
            relayIPv4ExitIP: values.1,
            apiReachable: values.2,
            expectedExits: expectedExits
        )
    }

    public static func evaluate(
        checkedAt: Date = Date(),
        claudeExitIP: String?,
        relayIPv4ExitIP: String?,
        apiReachable: Bool,
        expectedExits: IsolationExpectedExits
    ) -> RelayEgressReport {
        let claude = claudeExitIP.flatMap(IPAddress.normalized)
        let relayIPv4 = relayIPv4ExitIP.flatMap(IPAddress.normalized)

        guard let claude else {
            return report(
                checkedAt: checkedAt,
                level: .warning,
                basis: nil,
                claudeExitIP: nil,
                relayIPv4ExitIP: relayIPv4,
                expectedExits: expectedExits,
                apiReachable: apiReachable,
                detail: L10n.resolvedEnglish
                    ? "No Claude exit was obtained through the Routekeeper relay. Direct fallback, a rejected proxy request, or an unavailable network cannot be ruled out."
                    : "未能经 Routekeeper 中继取得 Claude 出口，无法排除直连、代理拒绝或网络不可用。"
            )
        }

        guard expectedExits.hasAny else {
            return report(
                checkedAt: checkedAt,
                level: .warning,
                basis: nil,
                claudeExitIP: claude,
                relayIPv4ExitIP: relayIPv4,
                expectedExits: expectedExits,
                apiReachable: apiReachable,
                detail: L10n.resolvedEnglish
                    ? "Claude was reached through the relay at \(claude), but no fixed exit is saved, so the route cannot be matched to an expected node."
                    : "已经中继访问 Claude，看到的出口是 \(claude)；但尚未保存固定出口，无法判断是否落在预期节点。"
            )
        }

        let basis: RelayEgressBasis
        if expectedExits.contains(claude) {
            basis = .exact
        } else if IPFamily.of(claude) == .ipv6,
                  let relayIPv4,
                  let expectedIPv4 = expectedExits.ipv4,
                  relayIPv4 == expectedIPv4 {
            basis = .relayIPv4Anchor
        } else {
            return report(
                checkedAt: checkedAt,
                level: .warning,
                basis: nil,
                claudeExitIP: claude,
                relayIPv4ExitIP: relayIPv4,
                expectedExits: expectedExits,
                apiReachable: apiReachable,
                detail: L10n.resolvedEnglish
                    ? "Claude was reached through the relay at \(claude), which does not match the saved fixed exit \(expectedDescription(expectedExits))."
                    : "经中继看到的 Claude 出口是 \(claude)，与保存的固定出口 \(expectedDescription(expectedExits)) 不一致。"
            )
        }

        guard apiReachable else {
            let pathDetail = basis == .relayIPv4Anchor
                ? (L10n.resolvedEnglish
                    ? "Claude returned a dynamic IPv6 address; the same relay's stable IPv4 exit \(relayIPv4 ?? "unknown") matches the fixed exit."
                    : "Claude 返回了动态 IPv6 地址；同一中继的稳定 IPv4 出口 \(relayIPv4 ?? "未知") 与固定出口一致。")
                : (L10n.resolvedEnglish
                    ? "The Claude exit \(claude) matches the fixed exit."
                    : "经中继看到的 Claude 出口 \(claude) 与固定出口一致。")
            return report(
                checkedAt: checkedAt,
                level: .warning,
                basis: basis,
                claudeExitIP: claude,
                relayIPv4ExitIP: relayIPv4,
                expectedExits: expectedExits,
                apiReachable: false,
                detail: L10n.resolvedEnglish
                    ? "\(pathDetail) The Anthropic API did not return a TLS response through the same relay; Claude Code connectivity may still be unavailable."
                    : "\(pathDetail) 但经同一中继访问 api.anthropic.com 未取得 TLS 响应；Claude Code 路径仍可能不可用。"
            )
        }

        let verifiedDetail: String
        switch basis {
        case .exact:
            verifiedDetail = L10n.resolvedEnglish
                ? "Claude was reached through the Routekeeper relay at \(claude), matching the fixed exit."
                : "已经 Routekeeper 中继访问 Claude，出口 \(claude) 与固定出口一致。"
        case .relayIPv4Anchor:
            verifiedDetail = L10n.resolvedEnglish
                ? "Claude returned a dynamic IPv6 address; the same relay's stable IPv4 exit \(relayIPv4 ?? "unknown") matches the fixed exit."
                : "Claude 返回了动态 IPv6 地址；同一中继的稳定 IPv4 出口 \(relayIPv4 ?? "未知") 与固定出口一致。"
        }
        return report(
            checkedAt: checkedAt,
            level: .verified,
            basis: basis,
            claudeExitIP: claude,
            relayIPv4ExitIP: relayIPv4,
            expectedExits: expectedExits,
            apiReachable: true,
            detail: verifiedDetail
        )
    }

    public static func remoteResolvingProxyURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("socks5://") {
            return "socks5h://" + trimmed.dropFirst("socks5://".count)
        }
        return trimmed
    }

    public static func apiIsReachable(output: String, exitStatus: Int32) -> Bool {
        guard exitStatus == 0 else { return false }
        let fields = output.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 2,
              let status = Int(fields[0]),
              (100...599).contains(status),
              let tls = Double(fields[1]),
              tls.isFinite,
              tls > 0 else {
            return false
        }
        return true
    }

    private static func probeClaudeExit(proxyURL: String) async -> String? {
        await Task.detached(priority: .utility) {
            let result = Command.run(
                "/usr/bin/curl",
                probeArguments(proxyURL: proxyURL, url: claudeTraceURL),
                timeout: 12
            )
            guard result.status == 0 else { return nil }
            return ExternalExitChecks.parseClaudeTrace(result.output)
        }.value
    }

    private static func probeIPv4Exit(proxyURL: String) async -> String? {
        await Task.detached(priority: .utility) {
            var arguments = probeArguments(proxyURL: proxyURL, url: relayIPv4ExitURL)
            arguments.insert("--ipv4", at: arguments.count - 1)
            let result = Command.run("/usr/bin/curl", arguments, timeout: 12)
            guard result.status == 0 else { return nil }
            return IPAddress.normalized(result.output)
        }.value
    }

    private static func probeAPI(proxyURL: String) async -> Bool {
        await Task.detached(priority: .utility) {
            var arguments = probeArguments(proxyURL: proxyURL, url: anthropicAPIURL)
            arguments.insert(contentsOf: [
                "--output", "/dev/null",
                "--write-out", "%{http_code}\t%{time_appconnect}"
            ], at: arguments.count - 1)
            let result = Command.run("/usr/bin/curl", arguments, timeout: 12)
            return apiIsReachable(output: result.output, exitStatus: result.status)
        }.value
    }

    private static func probeArguments(proxyURL: String, url: String) -> [String] {
        [
            "--disable", "--silent", "--show-error", "--location", "--max-redirs", "2",
            "--connect-timeout", "4", "--max-time", "10", "--max-filesize", "16384",
            "--proto", "=https", "--proto-redir", "=https",
            "--proxy", proxyURL,
            "--header", "Cache-Control: no-cache",
            url
        ]
    }

    private static func report(
        checkedAt: Date,
        level: RelayEgressLevel,
        basis: RelayEgressBasis?,
        claudeExitIP: String?,
        relayIPv4ExitIP: String?,
        expectedExits: IsolationExpectedExits,
        apiReachable: Bool,
        detail: String
    ) -> RelayEgressReport {
        .init(
            checkedAt: checkedAt,
            level: level,
            basis: basis,
            claudeExitIP: claudeExitIP,
            relayIPv4ExitIP: relayIPv4ExitIP,
            expectedExits: expectedExits,
            apiReachable: apiReachable,
            detail: detail
        )
    }

    private static func expectedDescription(_ exits: IsolationExpectedExits) -> String {
        [exits.ipv4, exits.ipv6].compactMap { $0 }.joined(separator: " / ")
    }
}
