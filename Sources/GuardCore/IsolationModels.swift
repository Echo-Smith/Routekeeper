import Foundation
import Darwin
import CryptoKit
import SystemConfiguration

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

public enum IsolationApplicationTarget: String, Codable, CaseIterable, Hashable, Sendable {
    case claudeCode
    case claudeDesktop

    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        }
    }

    public var exchangeDirectoryName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
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

    public func matches(_ proxy: SystemProxyDescriptor?) -> Bool {
        guard let proxy else { return false }
        return IsolationUpstream.normalizedHost(host) == IsolationUpstream.normalizedHost(proxy.host)
            && port == proxy.port
            && protocolType == proxy.protocolType
    }

    public static func normalizedHost(_ value: String) -> String {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return host == "localhost" ? "127.0.0.1" : host
    }
}

public struct SystemProxyDescriptor: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var protocolType: IsolationUpstreamProtocol

    public init(host: String, port: Int, protocolType: IsolationUpstreamProtocol) {
        self.host = host
        self.port = port
        self.protocolType = protocolType
    }

    public var isLoopback: Bool {
        ["127.0.0.1", "::1", "localhost"].contains(host.lowercased())
    }

    public static func current() -> SystemProxyDescriptor? {
        guard let values = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return nil }
        return descriptor(from: values)
    }

    static func descriptor(from values: [String: Any]) -> SystemProxyDescriptor? {
        let candidates: [(String, String, String, IsolationUpstreamProtocol)] = [
            ("HTTPSEnable", "HTTPSProxy", "HTTPSPort", .httpConnect),
            ("HTTPEnable", "HTTPProxy", "HTTPPort", .httpConnect),
            ("SOCKSEnable", "SOCKSProxy", "SOCKSPort", .socks5)
        ]
        for (enabledKey, hostKey, portKey, protocolType) in candidates {
            guard (values[enabledKey] as? NSNumber)?.boolValue == true,
                  let host = values[hostKey] as? String,
                  !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let port = values[portKey] as? NSNumber,
                  (1...65535).contains(port.intValue) else { continue }
            return .init(host: host, port: port.intValue, protocolType: protocolType)
        }
        return nil
    }
}

/// A non-persistent comparison point for deciding whether a network event
/// actually changed the route Claude depends on.
public struct NetworkFingerprint: Equatable, Sendable {
    public var proxyHost: String?
    public var proxyPort: Int?
    public var proxyProtocol: IsolationUpstreamProtocol?
    public var authMarker: String
    public var upstreamReachable: Bool
    public var exitAnchor: String?

    public init(
        proxy: SystemProxyDescriptor?,
        upstream: IsolationUpstream,
        upstreamReachable: Bool,
        exitAnchor: String?
    ) {
        let effectiveProxy = proxy ?? SystemProxyDescriptor(
            host: upstream.host,
            port: upstream.port,
            protocolType: upstream.protocolType
        )
        proxyHost = IsolationUpstream.normalizedHost(effectiveProxy.host)
        proxyPort = effectiveProxy.port
        proxyProtocol = effectiveProxy.protocolType
        authMarker = Self.authenticationMarker(
            username: upstream.username,
            password: upstream.password
        )
        self.upstreamReachable = upstreamReachable
        self.exitAnchor = exitAnchor.flatMap(IPAddress.normalized)
    }

    public var hasLiveRoute: Bool {
        upstreamReachable && exitAnchor != nil
    }

    /// The proxy and credential identity, excluding the probe-only exit address.
    public func materialConfigurationMatches(_ other: NetworkFingerprint) -> Bool {
        proxyHost == other.proxyHost
            && proxyPort == other.proxyPort
            && proxyProtocol == other.proxyProtocol
            && authMarker == other.authMarker
    }

    public var summary: String {
        guard let proxyHost, let proxyPort, let proxyProtocol else { return "网络配置未知" }
        return "\(proxyProtocol.title) · \(proxyHost):\(proxyPort)"
    }

    public static func authenticationMarker(username: String, password: String) -> String {
        guard !username.isEmpty || !password.isEmpty else { return "anonymous" }
        let material = Data("\(username)\u{0}\(password)".utf8)
        let digest = SHA256.hash(data: material)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

public struct IsolationExpectedExits: Equatable, Sendable {
    public var ipv4: String?
    public var ipv6: String?

    public init(ipv4: String? = nil, ipv6: String? = nil) {
        self.ipv4 = ipv4.flatMap(IPAddress.normalized)
        self.ipv6 = ipv6.flatMap(IPAddress.normalized)
    }

    public var hasAny: Bool { ipv4 != nil || ipv6 != nil }

    public func contains(_ value: String) -> Bool {
        guard let normalized = IPAddress.normalized(value) else { return false }
        return normalized == ipv4 || normalized == ipv6
    }
}

public enum IsolationSessionEnvironment {
    public static func localeIdentifier(for timezoneIdentifier: String) -> String {
        posixLocale(for: defaultLanguageIdentifier(for: timezoneIdentifier))
    }

    public static func defaultLanguageIdentifier(for timezoneIdentifier: String) -> String {
        switch timezoneIdentifier {
        case "Asia/Shanghai", "Asia/Chongqing", "Asia/Harbin":
            return "zh-Hans"
        case "Asia/Hong_Kong":
            return "zh-Hant-HK"
        case "Asia/Taipei":
            return "zh-Hant"
        case "Asia/Tokyo":
            return "ja-JP"
        case "Asia/Seoul":
            return "ko-KR"
        case "Europe/London":
            return "en-GB"
        case "Europe/Paris":
            return "fr-FR"
        case "Europe/Berlin":
            return "de-DE"
        case "Australia/Sydney":
            return "en-AU"
        default:
            return "en-US"
        }
    }

    public static func normalizedLanguageIdentifier(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty, normalized.count <= 35 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard normalized.unicodeScalars.allSatisfy(allowed.contains),
              let primary = normalized.split(separator: "-").first,
              (2...3).contains(primary.count) else {
            return nil
        }
        let components = normalized.split(separator: "-")
        let canonical = components.enumerated().map { index, component -> String in
            let value = String(component)
            if index == 0 { return value.lowercased() }
            if value.count == 4, value.allSatisfy(\.isLetter) {
                return value.prefix(1).uppercased() + value.dropFirst().lowercased()
            }
            if (value.count == 2 || value.count == 3),
               value.allSatisfy(\.isNumber) || value.allSatisfy(\.isLetter) {
                return value.uppercased()
            }
            return value.lowercased()
        }.joined(separator: "-")
        return canonical
    }

    public static func posixLocale(for languageIdentifier: String) -> String {
        let language = normalizedLanguageIdentifier(languageIdentifier) ?? "en-US"
        if language == "zh-Hans" { return "zh_CN.UTF-8" }
        if language == "zh-Hant-HK" { return "zh_HK.UTF-8" }
        if language == "zh-Hant" { return "zh_TW.UTF-8" }
        let components = language.split(separator: "-").map(String.init)
        let primary = components[0].lowercased()
        let explicitRegion = components.dropFirst().first {
            ($0.count == 2 && $0.allSatisfy(\.isLetter))
                || ($0.count == 3 && $0.allSatisfy(\.isNumber))
        }
        let region = explicitRegion?.uppercased()
            ?? defaultRegion(for: primary, components: components)
        return "\(primary)_\(region).UTF-8"
    }

    public static func appleLanguage(for languageIdentifier: String) -> String {
        normalizedLanguageIdentifier(languageIdentifier) ?? "en-US"
    }

    public static func acceptLanguage(for languageIdentifier: String) -> String {
        let language = appleLanguage(for: languageIdentifier)
        let primary = language.split(separator: "-").first.map(String.init) ?? language
        return primary == language ? language : "\(language),\(primary)"
    }

    public static func languageIdentifier(forLocale locale: String) -> String {
        String(locale.split(separator: "_").first ?? "en")
    }

    private static func defaultRegion(for primary: String, components: [String]) -> String {
        switch primary {
        case "zh":
            return components.contains("Hant") ? "TW" : "CN"
        case "en": return "US"
        case "ja": return "JP"
        case "ko": return "KR"
        case "fr": return "FR"
        case "de": return "DE"
        case "es": return "ES"
        case "pt": return "PT"
        case "it": return "IT"
        case "nl": return "NL"
        case "sv": return "SE"
        case "da": return "DK"
        case "fi": return "FI"
        case "nb": return "NO"
        case "pl": return "PL"
        case "ru": return "RU"
        case "uk": return "UA"
        case "tr": return "TR"
        case "ar": return "SA"
        case "he": return "IL"
        case "hi": return "IN"
        case "th": return "TH"
        case "vi": return "VN"
        case "id": return "ID"
        case "ms": return "MY"
        case "cs": return "CZ"
        case "el": return "GR"
        case "hu": return "HU"
        case "ro": return "RO"
        default: return "US"
        }
    }

    public static func appleLanguageIdentifier(forLocale locale: String) -> String {
        let normalized = locale.replacingOccurrences(of: ".UTF-8", with: "")
        switch normalized {
        case "zh_CN":
            return "zh-Hans"
        case "zh_HK":
            return "zh-Hant-HK"
        case "zh_TW":
            return "zh-Hant"
        default:
            return normalized.replacingOccurrences(of: "_", with: "-")
        }
    }
}

public struct IsolationConfiguration: Codable, Equatable, Sendable {
    public var projectPath: String
    public var exchangePath: String
    public var timezoneIdentifier: String
    public var languageIdentifier: String
    public var upstream: IsolationUpstream
    public var target: IsolationApplicationTarget
    public var persistClaudeLogin: Bool

    public init(
        projectPath: String = "",
        exchangePath: String = "",
        timezoneIdentifier: String = TimeZone.current.identifier,
        languageIdentifier: String? = nil,
        upstream: IsolationUpstream = IsolationUpstream(),
        target: IsolationApplicationTarget = .claudeCode,
        persistClaudeLogin: Bool = false
    ) {
        self.projectPath = projectPath
        self.exchangePath = exchangePath
        self.timezoneIdentifier = timezoneIdentifier
        self.languageIdentifier = languageIdentifier
            ?? IsolationSessionEnvironment.defaultLanguageIdentifier(for: timezoneIdentifier)
        self.upstream = upstream
        self.target = target
        self.persistClaudeLogin = persistClaudeLogin
    }

    enum CodingKeys: String, CodingKey {
        case projectPath, exchangePath, timezoneIdentifier, languageIdentifier,
             upstream, target, persistClaudeLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        exchangePath = try container.decodeIfPresent(String.self, forKey: .exchangePath) ?? ""
        let timezone = try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier)
            ?? TimeZone.current.identifier
        timezoneIdentifier = timezone
        languageIdentifier = try container.decodeIfPresent(String.self, forKey: .languageIdentifier)
            ?? IsolationSessionEnvironment.defaultLanguageIdentifier(for: timezone)
        upstream = try container.decodeIfPresent(IsolationUpstream.self, forKey: .upstream)
            ?? IsolationUpstream()
        target = try container.decodeIfPresent(IsolationApplicationTarget.self, forKey: .target)
            ?? .claudeCode
        persistClaudeLogin = try container.decodeIfPresent(Bool.self, forKey: .persistClaudeLogin)
            ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectPath, forKey: .projectPath)
        try container.encode(exchangePath, forKey: .exchangePath)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encode(languageIdentifier, forKey: .languageIdentifier)
        try container.encode(upstream, forKey: .upstream)
        try container.encode(target, forKey: .target)
        try container.encode(persistClaudeLogin, forKey: .persistClaudeLogin)
    }

    public var hasRequiredPaths: Bool {
        let hasExchange = !exchangePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasProject = !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasExchange && (target == .claudeDesktop || hasProject)
    }

    public var hasValidTimezone: Bool {
        TimeZone(identifier: timezoneIdentifier) != nil
    }

    public var hasValidLanguage: Bool {
        IsolationSessionEnvironment.normalizedLanguageIdentifier(languageIdentifier) != nil
    }
}

public struct SandboxSharedConfiguration: Codable, Equatable, Sendable {
    public var projectPath: String
    public var exchangePath: String
    public var timezoneIdentifier: String
    public var languageIdentifier: String
    public var upstream: IsolationUpstream
    public var enabledTargets: Set<IsolationApplicationTarget>
    public var persistClaudeLogin: Bool

    public init(
        projectPath: String = "",
        exchangePath: String = "",
        timezoneIdentifier: String = TimeZone.current.identifier,
        languageIdentifier: String? = nil,
        upstream: IsolationUpstream = IsolationUpstream(),
        enabledTargets: Set<IsolationApplicationTarget> = [.claudeCode, .claudeDesktop],
        persistClaudeLogin: Bool = false
    ) {
        self.projectPath = projectPath
        self.exchangePath = exchangePath
        self.timezoneIdentifier = timezoneIdentifier
        self.languageIdentifier = languageIdentifier
            ?? IsolationSessionEnvironment.defaultLanguageIdentifier(for: timezoneIdentifier)
        self.upstream = upstream
        self.enabledTargets = enabledTargets
        self.persistClaudeLogin = persistClaudeLogin
    }

    public init(legacy: IsolationConfiguration) {
        projectPath = legacy.projectPath
        exchangePath = legacy.exchangePath
        timezoneIdentifier = legacy.timezoneIdentifier
        languageIdentifier = legacy.languageIdentifier
        upstream = legacy.upstream
        enabledTargets = [legacy.target]
        persistClaudeLogin = legacy.persistClaudeLogin
    }

    enum CodingKeys: String, CodingKey {
        case projectPath, exchangePath, timezoneIdentifier, languageIdentifier,
             upstream, enabledTargets, persistClaudeLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        exchangePath = try container.decodeIfPresent(String.self, forKey: .exchangePath) ?? ""
        let timezone = try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier)
            ?? TimeZone.current.identifier
        timezoneIdentifier = timezone
        languageIdentifier = try container.decodeIfPresent(String.self, forKey: .languageIdentifier)
            ?? IsolationSessionEnvironment.defaultLanguageIdentifier(for: timezone)
        upstream = try container.decodeIfPresent(IsolationUpstream.self, forKey: .upstream)
            ?? IsolationUpstream()
        enabledTargets = try container.decodeIfPresent(
            Set<IsolationApplicationTarget>.self,
            forKey: .enabledTargets
        ) ?? [.claudeCode, .claudeDesktop]
        persistClaudeLogin = try container.decodeIfPresent(Bool.self, forKey: .persistClaudeLogin)
            ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectPath, forKey: .projectPath)
        try container.encode(exchangePath, forKey: .exchangePath)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encode(languageIdentifier, forKey: .languageIdentifier)
        try container.encode(upstream, forKey: .upstream)
        try container.encode(enabledTargets, forKey: .enabledTargets)
        try container.encode(persistClaudeLogin, forKey: .persistClaudeLogin)
    }

    public func isEnabled(_ target: IsolationApplicationTarget) -> Bool {
        enabledTargets.contains(target)
    }

    public var hasValidTimezone: Bool {
        TimeZone(identifier: timezoneIdentifier) != nil
    }

    public var hasValidLanguage: Bool {
        IsolationSessionEnvironment.normalizedLanguageIdentifier(languageIdentifier) != nil
    }

    public func targetExchangePath(for target: IsolationApplicationTarget) -> String {
        let trimmed = exchangePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .appendingPathComponent(target.exchangeDirectoryName, isDirectory: true)
            .path
    }

    public func configuration(for target: IsolationApplicationTarget) -> IsolationConfiguration {
        IsolationConfiguration(
            projectPath: projectPath,
            exchangePath: targetExchangePath(for: target),
            timezoneIdentifier: timezoneIdentifier,
            languageIdentifier: languageIdentifier,
            upstream: upstream,
            target: target,
            persistClaudeLogin: persistClaudeLogin
        )
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
    public var originalProject: URL?
    public var exchange: URL
    public var layout: IsolationSessionLayout
    public var identityHome: URL?

    public init(
        originalProject: URL?,
        exchange: URL,
        layout: IsolationSessionLayout,
        identityHome: URL? = nil
    ) {
        self.originalProject = originalProject
        self.exchange = exchange
        self.layout = layout
        self.identityHome = identityHome
    }

    public var runtimeHome: URL {
        identityHome ?? layout.home
    }

    public var sandboxWritablePaths: [URL] {
        layout.writablePaths + (identityHome.map { [$0] } ?? [])
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
    case invalidLanguage
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
        case .invalidLanguage:
            return "所选会话语言格式无效，请使用 en-US、zh-Hans、ja-JP 这类语言标识。"
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
        guard configuration.target == .claudeDesktop || !projectText.isEmpty else {
            throw IsolationValidationError.missingProject
        }
        guard !exchangeText.isEmpty else { throw IsolationValidationError.missingExchange }
        guard configuration.hasValidTimezone else { throw IsolationValidationError.invalidTimezone }
        guard configuration.hasValidLanguage else { throw IsolationValidationError.invalidLanguage }
        guard configuration.upstream.isValid else { throw IsolationValidationError.invalidUpstream }

        let project = projectText.isEmpty
            ? nil
            : canonicalURL(URL(fileURLWithPath: projectText, isDirectory: true))
        let exchange = canonicalURL(URL(fileURLWithPath: exchangeText, isDirectory: true))
        let root = canonicalURL(sessionRoot)
        let realHome = canonicalURL(home)
        let applicationSupport = realHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let realApplicationSupport = canonicalURL(applicationSupport)

        if let project, !isDirectory(project, fileManager: fileManager) {
            throw IsolationValidationError.notDirectory(project.path)
        }
        guard isDirectory(exchange, fileManager: fileManager) else {
            throw IsolationValidationError.notDirectory(exchange.path)
        }
        for path in [project, exchange].compactMap({ $0 }) {
            guard path.path != "/", path.path != realHome.path else {
                throw IsolationValidationError.unsafePath(path.path)
            }
        }
        if let project {
            guard !contains(project, exchange), !contains(exchange, project) else {
                throw IsolationValidationError.pathsOverlap
            }
        }
        for path in [project, exchange].compactMap({ $0 }) {
            guard !contains(root, path), !contains(path, root) else {
                throw IsolationValidationError.unsafePath(root.path)
            }
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
            paths.runtimeHome,
            paths.layout.temporary,
            paths.layout.workspace,
            paths.exchange,
            executable.deletingLastPathComponent()
        ]
        lines += readableUserPaths.map { "(allow file-read* (subpath \(literal($0.path))))" }
        lines.append("(allow file-map-executable (subpath \(literal(executable.deletingLastPathComponent().path))))")

        let writablePaths = paths.sandboxWritablePaths + [paths.exchange]
        lines += writablePaths.map { "(allow file-write* (subpath \(literal($0.path))))" }
        lines += [
            #"(allow file-read* file-write* (literal "/dev/null"))"#,
            #"(allow file-read* file-write* (literal "/dev/tty"))"#,
            #"(allow network-outbound (remote ip "localhost:PORT"))"#.replacingOccurrences(of: "PORT", with: String(relayPort))
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The GUI profile keeps file and outbound-network boundaries, while allowing
    /// the system services a signed Chromium-based desktop app needs to start.
    public static func makeDesktop(
        paths: IsolationResolvedPaths,
        applicationURL: URL,
        relayPort: Int,
        inputMethodApplications: [URL] = []
    ) -> String {
        precondition((1...65535).contains(relayPort))
        let application = applicationURL.standardizedFileURL.resolvingSymlinksInPath()
        var readableRoots = [
            "/System", "/usr", "/bin", "/sbin", "/Library/Apple",
            "/private/etc", "/private/var/db/dyld", "/private/var/select"
        ]
        if application.path.hasPrefix("/Applications/") {
            readableRoots.append("/Applications")
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
            "(allow file-read-metadata)",
            // Desktop families need WindowServer, TCC and helper IPC. Network
            // and filesystem access remain constrained by the rules below.
            "(allow mach-lookup)",
            // Chromium's bootstrap rendezvous server and crashpad helper
            // register per-process dynamic Mach services at startup.
            #"(allow mach-register (global-name-regex #"^Q6L2SF6YDW\.com\.anthropic\.claudefordesktop\.MachPortRendezvousServer\.[0-9]+$"))"#,
            #"(allow mach-register (global-name-prefix "org.chromium.crashpad.child_port_handshake."))"#,
            "(allow iokit-open)"
        ]
        lines += readableRoots.map { "(allow file-read* (subpath \(literal($0))))" }

        let readableUserPaths = [
            paths.runtimeHome,
            paths.layout.temporary,
            paths.layout.workspace,
            paths.exchange,
            application
        ]
        lines += readableUserPaths.map { "(allow file-read* (subpath \(literal($0.path))))" }
        lines.append("(allow file-map-executable (subpath \(literal(application.path))))")
        for inputMethod in inputMethodApplications {
            let bundle = inputMethod.standardizedFileURL.resolvingSymlinksInPath()
            lines.append("(allow file-read* (subpath \(literal(bundle.path))))")
            lines.append("(allow file-map-executable (subpath \(literal(bundle.path))))")
        }

        let writablePaths = paths.sandboxWritablePaths + [paths.exchange]
        lines += writablePaths.map { "(allow file-write* (subpath \(literal($0.path))))" }
        let scienceControlSocket = paths.runtimeHome
            .appendingPathComponent(".claude-science/daemon.sock", isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        lines += [
            #"(allow file-read* file-write* (literal "/dev/null"))"#,
            #"(allow file-read* file-write* (literal "/dev/tty"))"#,
            // The signed Claude daemon creates a private multiplexer directory
            // with this fixed prefix under /private/tmp. Keep every other
            // global temporary path outside the sandbox.
            #"(allow file-read* file-write* (regex #"^/private/tmp/op-mux-[^/]+(/|$)"))"#,
            // The desktop shell and daemon communicate over an OS-assigned
            // loopback port. Outbound traffic remains limited to local IPC and
            // the relay; internet-bound connections cannot use these rules.
            #"(allow network-outbound (remote ip "localhost:*"))"#,
            // Claude Science also exposes a control socket under its isolated
            // data directory. File-write access alone does not grant the
            // separate Seatbelt network-bind/outbound operations.
            "(allow network-bind network-inbound network-outbound (literal \(literal(scienceControlSocket.path))))",
            // Seatbelt requires network-inbound for a TCP listener, but its
            // localhost predicate cannot distinguish a loopback bind from a
            // wildcard bind. Routekeeper audits the live listener addresses.
            #"(allow network-inbound (local ip "localhost:*"))"#,
            #"(allow network-outbound (remote ip "localhost:PORT"))"#.replacingOccurrences(
                of: "PORT",
                with: String(relayPort)
            )
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

public enum InputMethodCompatibility {
    /// Reads only input-source identifiers. The helper never copies dictionaries,
    /// history, or other user data from an input method.
    public static func referencedBundleIdentifiers(in preferences: [String: Any]) -> Set<String> {
        let keys = ["AppleEnabledInputSources", "AppleSelectedInputSources"]
        var result = Set<String>()
        for key in keys {
            let rows = preferences[key] as? [[String: Any]] ?? []
            for row in rows {
                guard let identifier = row["Bundle ID"] as? String,
                      !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                result.insert(identifier)
            }
        }
        return result
    }

    public static func enabledApplications(
        defaults: UserDefaults = UserDefaults(suiteName: "com.apple.HIToolbox") ?? .standard,
        roots: [URL] = [
            URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Input Methods", isDirectory: true)
        ],
        fileManager: FileManager = .default
    ) -> [URL] {
        let identifiers = referencedBundleIdentifiers(in: defaults.dictionaryRepresentation())
        guard !identifiers.isEmpty else { return [] }
        var applications: [URL] = []
        for root in roots {
            let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                let resolvedEntry = entry.standardizedFileURL.resolvingSymlinksInPath()
                guard resolvedEntry.deletingLastPathComponent() == resolvedRoot else {
                    continue
                }
                let info = resolvedEntry.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: info),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data,
                        options: [],
                        format: nil
                      ) as? [String: Any],
                      let identifier = plist["CFBundleIdentifier"] as? String,
                      identifiers.contains(identifier) else {
                    continue
                }
                applications.append(resolvedEntry)
            }
        }
        return applications.sorted { $0.path < $1.path }
    }
}

public struct IsolationCheck: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var passed: Bool
    public var isWarning: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        passed: Bool,
        isWarning: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.passed = passed
        self.isWarning = isWarning
    }

    public var blocksLaunch: Bool {
        !passed && !isWarning
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
