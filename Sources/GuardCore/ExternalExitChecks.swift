import Foundation

struct ExternalExitProbe: Sendable {
    var ip: String?
    var failure: String?
}

enum ExternalExitChecks {
    private struct IPInfoResponse: Decodable {
        let ip: String
    }

    private enum ResponseFormat: Sendable {
        case ipInfo
        case claudeTrace

        func parse(_ output: String) -> String? {
            switch self {
            case .ipInfo:
                return ExternalExitChecks.parseIPInfo(output)
            case .claudeTrace:
                return ExternalExitChecks.parseClaudeTrace(output)
            }
        }
    }

    static func parseIPInfo(_ output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let response = try? JSONDecoder().decode(IPInfoResponse.self, from: data) else { return nil }
        return IPAddress.normalized(response.ip)
    }

    static func parseClaudeTrace(_ output: String) -> String? {
        let value = output.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("ip=") }?
            .dropFirst(3)
        return value.flatMap { IPAddress.normalized(String($0)) }
    }

    static func ipInfo(proxy: ProxyEndpoint?) async -> ExternalExitProbe {
        await request(
            url: "https://ipinfo.io/",
            proxy: proxy,
            format: .ipInfo
        )
    }

    static func claudeTrace(proxy: ProxyEndpoint?) async -> ExternalExitProbe {
        await request(
            url: "https://claude.ai/cdn-cgi/trace",
            proxy: proxy,
            format: .claudeTrace
        )
    }

    static func row(
        id: String,
        title: String,
        service: String,
        probe: ExternalExitProbe,
        settings: GuardSettings
    ) -> CheckItem {
        guard let ip = probe.ip else {
            return .init(id, title, "\(service) 没有返回有效 IP；请检查网络或代理后重新检测", .failed)
        }
        guard let target = settings.target(for: IPFamily.of(ip)) else {
            return .init(
                id,
                title,
                "\(service) 返回 \(ip)；该地址族的固定出口尚未设置，暂时无法判断",
                .unknown
            )
        }
        return .init(
            id,
            title,
            ip == target
                ? "\(service) 返回 \(ip)，与固定出口一致"
                : "\(service) 返回 \(ip)，与固定出口 \(target) 不一致",
            ip == target ? .passed : .failed
        )
    }

    private static func request(
        url: String,
        proxy: ProxyEndpoint?,
        format: ResponseFormat
    ) async -> ExternalExitProbe {
        await Task.detached(priority: .utility) {
            var args = [
                "--disable", "--silent", "--fail", "--location", "--max-redirs", "3",
                "--connect-timeout", "3", "--max-time", "8", "--max-filesize", "16384",
                "--proto", "=https", "--proto-redir", "=https",
                "--header", "Cache-Control: no-cache"
            ]
            if let proxy {
                args += ["--proxy", proxy.url]
            } else {
                args += ["--noproxy", "*"]
            }
            args.append(url)
            let result = Command.run("/usr/bin/curl", args, timeout: 10)
            guard result.status == 0 else {
                return .init(ip: nil, failure: "curl 退出码 \(result.status)")
            }
            guard let ip = format.parse(result.output) else {
                return .init(ip: nil, failure: "返回内容中没有有效 IP")
            }
            return .init(ip: ip, failure: nil)
        }.value
    }
}
