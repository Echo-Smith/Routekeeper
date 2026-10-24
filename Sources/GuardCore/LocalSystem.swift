import Foundation
import AppKit
import SystemConfiguration
import Darwin

public struct CommandResult: Sendable { public var status: Int32; public var output: String }
public enum Command {
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 8) -> CommandResult {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        // The probes never inherit proxy credentials, curl settings, or user shell initialization.
        p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "HOME": NSHomeDirectory()]
        do { try p.run() } catch { return .init(status: -1, output: "无法执行 \(URL(fileURLWithPath: path).lastPathComponent)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if p.isRunning { p.terminate(); Thread.sleep(forTimeInterval: 0.1); if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return .init(status: p.terminationStatus, output: String(decoding: data.prefix(64_000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
public struct ProxyEndpoint: Sendable, Equatable {
    public var host: String; public var port: Int
    public var url: String { "http://\(host.contains(":") ? "[\(host)]" : host):\(port)" }
    public var isLoopback: Bool { ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) }
    public static func current() -> ProxyEndpoint? {
        guard let dict = SCDynamicStoreCopyProxies(nil) as? [String: Any],
              (dict["HTTPSEnable"] as? NSNumber)?.boolValue == true,
              let host = dict["HTTPSProxy"] as? String,
              let port = dict["HTTPSPort"] as? NSNumber, (1...65535).contains(port.intValue) else { return nil }
        return .init(host: host, port: port.intValue)
    }
}
public enum ApplicationDiscovery {
    public static let desktopID = "com.anthropic.claudefordesktop"
    public static let flClashID = "com.follow.clash"
    public static func path(bundleID: String, name: String) -> String? {
        let candidates: [String?] = [NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path,
                          "/Applications/\(name).app", NSHomeDirectory() + "/Applications/\(name).app"]
        return candidates.compactMap { $0 }.first { Bundle(path: $0)?.bundleIdentifier == bundleID }
    }
    public static func codePathsInstalled() -> Bool {
        let home = NSHomeDirectory()
        let roots = [home + "/.local/bin/claude", home + "/.npm-global/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/Caskroom/claude-code", "/usr/local/Caskroom/claude-code"]
        if roots.contains(where: { FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0) }) { return true }
        for editor in [".vscode", ".cursor", ".vscode-insiders"] {
            let dir = home + "/\(editor)/extensions"
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir),
               entries.contains(where: { $0.hasPrefix("anthropic.claude-code-") }) { return true }
        }
        return false
    }
    public static func codePaths() -> [String] {
        let home = NSHomeDirectory()
        var candidates = [home + "/.local/bin/claude", home + "/.npm-global/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        let nvm = home + "/.nvm/versions/node"
        candidates += ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).map { nvm + "/\($0)/bin/claude" }
        for editor in [".vscode", ".cursor", ".vscode-insiders"] {
            let root = home + "/\(editor)/extensions"
            candidates += ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
                .filter { $0.hasPrefix("anthropic.claude-code-") }
                .map { root + "/\($0)/resources/native-binary/claude" }
        }
        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
public struct ProcessScan: Sendable {
    public var records: [ProcessIdentity]
    public var available: Bool
}

public struct ClaudeProcessNetworkSummary: Codable, Equatable, Sendable {
    public var processCount: Int
    public var establishedConnections: Int
    public var loopbackConnections: Int
    public var nonLoopbackConnections: Int
    public var unknownConnections: Int
    public var readable: Bool

    public init(
        processCount: Int,
        establishedConnections: Int,
        loopbackConnections: Int,
        nonLoopbackConnections: Int,
        unknownConnections: Int = 0,
        readable: Bool
    ) {
        self.processCount = processCount
        self.establishedConnections = establishedConnections
        self.loopbackConnections = loopbackConnections
        self.nonLoopbackConnections = nonLoopbackConnections
        self.unknownConnections = unknownConnections
        self.readable = readable
    }
}

public struct ClaudeCodeEnvironmentSummary: Codable, Equatable, Sendable {
    public var readable: Bool
    public var proxyConfigured: Bool
    public var proxyHosts: [String]
    public var noProxyConfigured: Bool
    public var apiBaseConfigured: Bool
    public var apiBaseHost: String?
    public var locale: String?
    public var timeZone: String?

    public init(
        readable: Bool,
        proxyConfigured: Bool = false,
        proxyHosts: [String] = [],
        noProxyConfigured: Bool = false,
        apiBaseConfigured: Bool = false,
        apiBaseHost: String? = nil,
        locale: String? = nil,
        timeZone: String? = nil
    ) {
        self.readable = readable
        self.proxyConfigured = proxyConfigured
        self.proxyHosts = proxyHosts
        self.noProxyConfigured = noProxyConfigured
        self.apiBaseConfigured = apiBaseConfigured
        self.apiBaseHost = apiBaseHost
        self.locale = locale
        self.timeZone = timeZone
    }
}

private actor ClaudeCodeEnvironmentCache {
    private var record: ProcessIdentity?
    private var summary: ClaudeCodeEnvironmentSummary?

    func value(for record: ProcessIdentity) -> ClaudeCodeEnvironmentSummary {
        if self.record == record, let summary {
            return summary
        }
        let value = LocalProcesses.codeEnvironment(for: record)
        self.record = record
        summary = value
        return value
    }
}

public enum LocalProcesses {
    private static let codeEnvironmentCache = ClaudeCodeEnvironmentCache()
    /// Only argv[0..1]; no prompts, environment or persistent logging.
    public static func classificationArguments(_ pid: Int32) -> [String] { arguments(pid) }
    public static func ownExecutablePaths() -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var ids = [Int32](repeating: 0, count: Int(count) + 1024)
        let actual = proc_listallpids(&ids, Int32(ids.count * MemoryLayout<Int32>.size))
        guard actual > 0 else { return [] }
        return ids.prefix(min(Int(actual), ids.count)).compactMap { pid in
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  info.pbi_uid == getuid() else { return nil }
            return executable(pid)
        }
    }
    private static func executable(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
    private static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 4, size < 2_000_000 else { return [] }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return [] }
        let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc < 100_000 else { return [] }
        var offset = 4
        while offset < size && data[offset] != 0 { offset += 1 }
        while offset < size && data[offset] == 0 { offset += 1 }
        var result: [String] = []
        // Only argv[0] and argv[1] are needed. Never persist arguments or environment.
        for _ in 0..<min(Int(argc), 2) {
            let start = offset
            while offset < size && data[offset] != 0 { offset += 1 }
            result.append(String(decoding: data[start..<offset], as: UTF8.self)); offset += 1
            if offset >= size { break }
        }
        return result
    }
    public static func identity(_ pid: Int32, desktopRoots: [String]) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), let path = executable(pid) else { return nil }
        var args = URL(fileURLWithPath: path).lastPathComponent == "node" ? arguments(pid) : []
        if args.count > 1, args[1].hasPrefix("/") { args[1] = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath().path }
        guard let kind = ProcessClassifier.classify(executable: path, arguments: args, desktopRoots: desktopRoots, home: NSHomeDirectory()) else { return nil }
        return .init(pid: pid, uid: info.pbi_uid, startSeconds: info.pbi_start_tvsec,
                     startMicroseconds: info.pbi_start_tvusec, executable: path, kind: kind)
    }
    public static func scan(desktopRoots: [String]) -> ProcessScan {
        var ownInfo = proc_bsdinfo()
        guard proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &ownInfo, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
              executable(getpid()) != nil else { return .init(records: [], available: false) }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return .init(records: [], available: false) }
        var ids = [Int32](repeating: 0, count: Int(count) + 1024)
        let actual = proc_listallpids(&ids, Int32(ids.count * MemoryLayout<Int32>.size))
        guard actual > 0 else { return .init(records: [], available: false) }
        let records = ids.prefix(min(Int(actual), ids.count)).filter { $0 != getpid() }.compactMap { identity($0, desktopRoots: desktopRoots) }
        return .init(records: records, available: true)
    }

    public static func networkSummary(
        for records: [ProcessIdentity]
    ) -> ClaudeProcessNetworkSummary? {
        let processIDs = records.map(\.pid)
        guard !processIDs.isEmpty else { return nil }
        let lsof = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: lsof) else {
            return .init(
                processCount: processIDs.count,
                establishedConnections: 0,
                loopbackConnections: 0,
                nonLoopbackConnections: 0,
                readable: false
            )
        }
        let result = Command.run(lsof, [
            "-nP", "-a",
            "-p", processIDs.map(String.init).joined(separator: ","),
            "-iTCP", "-sTCP:ESTABLISHED", "-FpPn"
        ], timeout: 4)
        // lsof exits 1 when the selected processes have no established TCP socket.
        guard result.status == 0 || result.status == 1 else {
            return .init(
                processCount: processIDs.count,
                establishedConnections: 0,
                loopbackConnections: 0,
                nonLoopbackConnections: 0,
                readable: false
            )
        }
        return parseNetworkConnections(result.output, expectedProcessCount: processIDs.count)
    }

    public static func parseNetworkConnections(
        _ output: String,
        expectedProcessCount: Int = 0
    ) -> ClaudeProcessNetworkSummary {
        var processIDs = Set<Int32>()
        var established = 0
        var loopback = 0
        var nonLoopback = 0
        var unknown = 0

        for line in output.split(whereSeparator: \.isNewline) {
            if line.first == "p" {
                if let pid = Int32(line.dropFirst()) {
                    processIDs.insert(pid)
                }
                continue
            }
            guard line.first == "n",
                  let separator = line.range(of: "->") else { continue }
            established += 1
            let remote = String(line[separator.upperBound...])
            let host = remoteHost(remote)
            if let host {
                if isLoopback(host) {
                    loopback += 1
                } else {
                    nonLoopback += 1
                }
            } else {
                unknown += 1
            }
        }

        return .init(
            processCount: max(expectedProcessCount, processIDs.count),
            establishedConnections: established,
            loopbackConnections: loopback,
            nonLoopbackConnections: nonLoopback,
            unknownConnections: unknown,
            readable: true
        )
    }

    public static func codeEnvironment(
        for record: ProcessIdentity
    ) -> ClaudeCodeEnvironmentSummary {
        let ps = "/bin/ps"
        guard FileManager.default.isExecutableFile(atPath: ps) else {
            return .init(readable: false)
        }
        let result = Command.run(
            ps,
            ["eww", "-p", String(record.pid), "-o", "command="],
            timeout: 3
        )
        guard result.status == 0, !result.output.isEmpty else {
            return .init(readable: false)
        }
        return parseCodeEnvironment(result.output)
    }

    public static func cachedCodeEnvironment(
        for record: ProcessIdentity
    ) async -> ClaudeCodeEnvironmentSummary {
        await codeEnvironmentCache.value(for: record)
    }

    public static func parseCodeEnvironment(_ output: String) -> ClaudeCodeEnvironmentSummary {
        let names = [
            "ANTHROPIC_BASE_URL",
            "HTTPS_PROXY", "https_proxy",
            "HTTP_PROXY", "http_proxy",
            "ALL_PROXY", "all_proxy",
            "NO_PROXY", "no_proxy",
            "LC_ALL", "LANG", "TZ"
        ]
        let alternation = names
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = "(?:^|\\s)(\(alternation))=([^\\s]+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var values: [String: String] = [:]
        regex?.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: output),
                  let valueRange = Range(match.range(at: 2), in: output) else { return }
            values[String(output[nameRange])] = String(output[valueRange])
        }

        let proxyValues = [
            values["HTTPS_PROXY"], values["https_proxy"],
            values["HTTP_PROXY"], values["http_proxy"],
            values["ALL_PROXY"], values["all_proxy"]
        ].compactMap { $0 }
        let proxyHosts = Array(Set(proxyValues.map(maskedEndpoint))).sorted()
        let apiValue = values["ANTHROPIC_BASE_URL"]
        let locale = values["LC_ALL"] ?? values["LANG"]
        return .init(
            readable: true,
            proxyConfigured: !proxyValues.isEmpty,
            proxyHosts: proxyHosts,
            noProxyConfigured: values["NO_PROXY"] != nil || values["no_proxy"] != nil,
            apiBaseConfigured: apiValue != nil,
            apiBaseHost: apiValue.map(maskedEndpoint),
            locale: locale,
            timeZone: values["TZ"]
        )
    }

    private static func remoteHost(_ remote: String) -> String? {
        let value = remote.split(separator: " ").first.map(String.init) ?? remote
        if value.hasPrefix("["),
           let close = value.firstIndex(of: "]") {
            return String(value[value.index(after: value.startIndex)..<close])
        }
        guard let colon = value.lastIndex(of: ":") else { return nil }
        let host = String(value[..<colon])
        return host.isEmpty || host == "*" ? nil : host
    }

    private static func isLoopback(_ host: String) -> Bool {
        let value = host.lowercased()
        return value == "localhost"
            || value == "::1"
            || value == "0:0:0:0:0:0:0:1"
            || value.hasPrefix("127.")
            || value.hasPrefix("::ffff:127.")
    }

    private static func maskedEndpoint(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "已设置" }
        let candidate = text.contains("://") ? text : "http://\(text)"
        guard let components = URLComponents(string: candidate),
              let host = components.host,
              !host.isEmpty else {
            return "已设置"
        }
        return components.port.map { "\(host):\($0)" } ?? host
    }

    public static func requestExit(_ record: ProcessIdentity, settings: GuardSettings, desktopRoots: [String]) -> String {
        guard ProcessClassifier.mayTerminate(record: record, current: identity(record.pid, desktopRoots: desktopRoots), settings: settings, uid: getuid()) else {
            return "PID \(record.pid)：已退出、身份变化或不在所选范围，未发送信号"
        }
        return kill(record.pid, SIGTERM) == 0 ? "PID \(record.pid)：已发送退出请求，等待进程结束" : "PID \(record.pid)：退出请求失败（\(errno)），请手动处理"
    }
}
