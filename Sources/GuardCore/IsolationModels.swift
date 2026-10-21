import Foundation
import Darwin

public enum IsolationPhase: String, Codable, Equatable, Sendable {
    case disabled
    case ready
    case preparing
    case checking
    case running
    case networkPaused
    case failed
    case ended

    public var canChangeConfiguration: Bool {
        self == .disabled || self == .ready || self == .failed || self == .ended
    }

    public var isActive: Bool {
        self == .preparing || self == .checking || self == .running || self == .networkPaused
    }
}

public enum IsolationUpstreamProtocol: String, Codable, CaseIterable, Sendable {
    case httpConnect
    case socks5

    public var title: String {
        switch self {
        case .httpConnect: return "HTTP CONNECT"
        case .socks5: return "SOCKS5"
        }
    }
}

public struct IsolationUpstream: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var protocolType: IsolationUpstreamProtocol
    public var username: String
    public var password: String

    public init(
        host: String = "127.0.0.1",
        port: Int = 7890,
        protocolType: IsolationUpstreamProtocol = .httpConnect,
        username: String = "",
        password: String = ""
    ) {
        self.host = host
        self.port = port
        self.protocolType = protocolType
        self.username = username
        self.password = password
    }

    public var isValid: Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["127.0.0.1", "::1", "localhost"].contains(normalizedHost)
            && (1...65535).contains(port)
            && !host.contains("/")
            && !host.contains("@")
    }
}

public struct IsolationConfiguration: Codable, Equatable, Sendable {
    public var projectPath: String
    public var exchangePath: String
    public var timezoneIdentifier: String
    public var upstream: IsolationUpstream

    public init(
        projectPath: String = "",
        exchangePath: String = "",
        timezoneIdentifier: String = TimeZone.current.identifier,
        upstream: IsolationUpstream = IsolationUpstream()
    ) {
        self.projectPath = projectPath
        self.exchangePath = exchangePath
        self.timezoneIdentifier = timezoneIdentifier
        self.upstream = upstream
    }

    public var hasRequiredPaths: Bool {
        !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !exchangePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasValidTimezone: Bool {
        TimeZone(identifier: timezoneIdentifier) != nil
    }
}

public struct IsolationSessionLayout: Equatable, Sendable {
    public var root: URL
    public var home: URL
    public var temporary: URL
    public var workspace: URL
    public var control: URL
    public var logs: URL
    public var profile: URL

    public init(root: URL) {
        self.root = root
        home = self.root.appendingPathComponent("home", isDirectory: true)
        temporary = self.root.appendingPathComponent("tmp", isDirectory: true)
        workspace = self.root.appendingPathComponent("workspace", isDirectory: true)
        control = self.root.appendingPathComponent("control", isDirectory: true)
        logs = self.root.appendingPathComponent("logs", isDirectory: true)
        profile = self.root.appendingPathComponent("control/session.sb", isDirectory: false)
    }

    public var writablePaths: [URL] {
        [home, temporary, workspace, logs]
    }
}

public struct IsolationResolvedPaths: Equatable, Sendable {
    public var originalProject: URL
    public var exchange: URL
    public var layout: IsolationSessionLayout

    public init(originalProject: URL, exchange: URL, layout: IsolationSessionLayout) {
        self.originalProject = originalProject
        self.exchange = exchange
        self.layout = layout
    }
}

public enum IsolationValidationError: Error, LocalizedError, Equatable, Sendable {
    case missingProject
    case missingExchange
    case notDirectory(String)
    case unsafePath(String)
    case pathsOverlap
    case sessionRootOutsideApplicationSupport
    case invalidTimezone
    case invalidUpstream

    public var errorDescription: String? {
        switch self {
        case .missingProject:
            return "请选择要隔离的项目文件夹。"
        case .missingExchange:
            return "请选择用于临时交换文件的文件夹。"
        case .notDirectory(let path):
            return "所选路径不是可访问的文件夹：\(path)"
        case .unsafePath(let path):
            return "不能把这个文件夹用作沙箱项目或交换目录：\(path)"
        case .pathsOverlap:
            return "项目文件夹与交换文件夹不能相同，也不能互相包含。"
        case .sessionRootOutsideApplicationSupport:
            return "沙箱会话目录不在 Routekeeper 的应用支持目录中，已拒绝启动。"
        case .invalidTimezone:
            return "所选时区无效。"
        case .invalidUpstream:
            return "本地代理地址无效。第一版只接受本机 127.0.0.1、::1 或 localhost。"
        }
    }
}

public enum IsolationPathValidator {
    public static func validate(
        _ configuration: IsolationConfiguration,
        sessionRoot: URL,
        home: URL,
        fileManager: FileManager = .default
    ) throws -> IsolationResolvedPaths {
        let projectText = configuration.projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let exchangeText = configuration.exchangePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectText.isEmpty else { throw IsolationValidationError.missingProject }
        guard !exchangeText.isEmpty else { throw IsolationValidationError.missingExchange }
        guard configuration.hasValidTimezone else { throw IsolationValidationError.invalidTimezone }
        guard configuration.upstream.isValid else { throw IsolationValidationError.invalidUpstream }

        let project = canonicalURL(URL(fileURLWithPath: projectText, isDirectory: true))
        let exchange = canonicalURL(URL(fileURLWithPath: exchangeText, isDirectory: true))
        let root = canonicalURL(sessionRoot)
        let realHome = canonicalURL(home)
        let applicationSupport = realHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let realApplicationSupport = canonicalURL(applicationSupport)

        guard isDirectory(project, fileManager: fileManager) else {
            throw IsolationValidationError.notDirectory(project.path)
        }
        guard isDirectory(exchange, fileManager: fileManager) else {
            throw IsolationValidationError.notDirectory(exchange.path)
        }
        for path in [project, exchange] {
            guard path.path != "/", path.path != realHome.path else {
                throw IsolationValidationError.unsafePath(path.path)
            }
        }
        guard !contains(project, exchange), !contains(exchange, project) else {
            throw IsolationValidationError.pathsOverlap
        }
        guard !contains(root, project), !contains(project, root),
              !contains(root, exchange), !contains(exchange, root) else {
            throw IsolationValidationError.unsafePath(root.path)
        }
        guard contains(realApplicationSupport, root) else {
            throw IsolationValidationError.sessionRootOutsideApplicationSupport
        }

        let layout = IsolationSessionLayout(root: root)
        return IsolationResolvedPaths(originalProject: project, exchange: exchange, layout: layout)
    }

    public static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func canonicalURL(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) {
            let component = existing.lastPathComponent
            guard !component.isEmpty, existing.path != "/" else { break }
            suffix.insert(component, at: 0)
            existing.deleteLastPathComponent()
        }
        let resolved = existing.path.withCString { realpath($0, nil) }
        var result = resolved.map { URL(fileURLWithPath: String(cString: $0), isDirectory: true) }
            ?? existing
        if let resolved { free(resolved) }
        for component in suffix {
            result.appendPathComponent(component)
        }
        return result
    }
}

public enum IsolationSandboxProfile {
    public static func make(
        paths: IsolationResolvedPaths,
        executableURL: URL,
        relayPort: Int
    ) -> String {
        precondition((1...65535).contains(relayPort))
        let executable = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        var readableRoots = [
            "/System", "/usr", "/bin", "/sbin", "/Library/Apple",
            "/private/etc", "/private/var/db/dyld", "/private/var/select"
        ]
        if executable.path.hasPrefix("/opt/homebrew/") { readableRoots.append("/opt/homebrew") }
        if executable.path.hasPrefix("/usr/local/") { readableRoots.append("/usr/local") }
        if executable.path.hasPrefix("/Applications/") { readableRoots.append("/Applications") }
        if executable.path.hasPrefix(paths.layout.home.path + "/") {
            readableRoots.append(executable.deletingLastPathComponent().path)
        }

        var lines = [
            "(version 1)",
            "(deny default)",
            #"(import "system.sb")"#,
            "(deny network*)",
            "(allow process*)",
            "(allow signal (target same-sandbox))",
            "(allow sysctl-read)",
            "(allow ipc-posix-shm)",
            "(allow file-read-metadata)"
        ]
        lines.append("(deny mach-lookup)")
        lines += readableRoots.map { "(allow file-read* (subpath \(literal($0))))" }
        let readableUserPaths = [
            paths.layout.home,
            paths.layout.temporary,
            paths.layout.workspace,
            paths.exchange,
            executable.deletingLastPathComponent()
        ]
        lines += readableUserPaths.map { "(allow file-read* (subpath \(literal($0.path))))" }
        lines.append("(allow file-map-executable (subpath \(literal(executable.deletingLastPathComponent().path))))")

        let writablePaths = paths.layout.writablePaths + [paths.exchange]
        lines += writablePaths.map { "(allow file-write* (subpath \(literal($0.path))))" }
        lines += [
            #"(allow file-read* file-write* (literal "/dev/null"))"#,
            #"(allow file-read* file-write* (literal "/dev/tty"))"#,
            #"(allow network-outbound (remote ip "localhost:PORT"))"#.replacingOccurrences(of: "PORT", with: String(relayPort))
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public struct IsolationCheck: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var passed: Bool

    public init(id: String, title: String, detail: String, passed: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.passed = passed
    }
}

public struct RelayTarget: Equatable, Sendable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public init?(authority: String) {
        let value = authority.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        let portText: String
        if value.hasPrefix("["),
           let closing = value.firstIndex(of: "]"),
           value.index(after: closing) < value.endIndex,
           value[value.index(after: closing)] == ":" {
            host = String(value[value.index(after: value.startIndex)..<closing])
            portText = String(value[value.index(closing, offsetBy: 2)...])
        } else if let colon = value.lastIndex(of: ":"), !value[..<colon].contains(":") {
            host = String(value[..<colon])
            portText = String(value[value.index(after: colon)...])
        } else {
            return nil
        }
        guard !host.isEmpty, let port = Int(portText), (1...65535).contains(port) else {
            return nil
        }
        self.host = host
        self.port = port
    }

    public var blocksDirectLocalAccess: Bool {
        let value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if value == "localhost" || value.hasSuffix(".localhost") || value.hasSuffix(".local") {
            return true
        }
        guard let ip = IPAddress.normalized(host) else { return false }
        if IPFamily.of(ip) == .ipv6 {
            return ip == "::1" || ip == "::" || ip.hasPrefix("fc") || ip.hasPrefix("fd")
                || ip.hasPrefix("fe8") || ip.hasPrefix("fe9") || ip.hasPrefix("fea") || ip.hasPrefix("feb")
        }
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return true }
        return parts[0] == 10 || parts[0] == 127 || parts[0] == 0
            || (parts[0] == 169 && parts[1] == 254)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 100 && (64...127).contains(parts[1]))
    }
}
