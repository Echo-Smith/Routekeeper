import Foundation
import Darwin

public enum ProtectedKind: String, Codable, Sendable { case desktop, code }
public enum IncidentAction: String, Codable, CaseIterable, Sendable {
    case notify, terminate
    public var title: String { self == .notify ? "仅提醒" : "请求退出所选 Claude 进程" }
}
public enum GatewayProtectionMode: String, Codable, CaseIterable, Sendable {
    case off, splitTraffic, claudeOnly
}
public struct GuardSettings: Codable, Equatable, Sendable {
    public var targetIP = ""
    public var alternateTargetIP = ""
    public var proxyClient: ProxyClient = .automatic
    public var pollInterval: Double = 2
    public var dnsProbeEnabled = true
    public var udpProbeEnabled = true
    public var protectDesktop = false
    public var protectCode = true
    public var action: IncidentAction = .notify
    public var cleanupConsented = false
    public var cleanupConsentedAt: Date?
    public var experimentalSandboxEnabled = false
    public var gatewayProtectionMode: GatewayProtectionMode = .off
    public init() {}
    enum CodingKeys: String, CodingKey {
        case targetIP, alternateTargetIP, proxyClient, pollInterval, dnsProbeEnabled, udpProbeEnabled
        case protectDesktop, protectCode, action, cleanupConsented, cleanupConsentedAt
        case experimentalSandboxEnabled, gatewayProtectionMode
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetIP = try c.decodeIfPresent(String.self, forKey: .targetIP) ?? ""
        alternateTargetIP = try c.decodeIfPresent(String.self, forKey: .alternateTargetIP) ?? ""
        proxyClient = try c.decodeIfPresent(ProxyClient.self, forKey: .proxyClient) ?? .automatic
        pollInterval = try c.decodeIfPresent(Double.self, forKey: .pollInterval) ?? 2
        dnsProbeEnabled = try c.decodeIfPresent(Bool.self, forKey: .dnsProbeEnabled) ?? true
        udpProbeEnabled = try c.decodeIfPresent(Bool.self, forKey: .udpProbeEnabled) ?? true
        protectDesktop = try c.decodeIfPresent(Bool.self, forKey: .protectDesktop) ?? false
        protectCode = try c.decodeIfPresent(Bool.self, forKey: .protectCode) ?? true
        action = try c.decodeIfPresent(IncidentAction.self, forKey: .action) ?? .notify
        cleanupConsented = try c.decodeIfPresent(Bool.self, forKey: .cleanupConsented) ?? false
        cleanupConsentedAt = try c.decodeIfPresent(Date.self, forKey: .cleanupConsentedAt)
        experimentalSandboxEnabled = try c.decodeIfPresent(Bool.self, forKey: .experimentalSandboxEnabled) ?? false
        gatewayProtectionMode = try c.decodeIfPresent(GatewayProtectionMode.self, forKey: .gatewayProtectionMode) ?? .off
    }
    public var validInterval: Bool { pollInterval.isFinite && (1...300).contains(pollInterval) }
    public var fixedIPv4TargetIP: String {
        get { fixedExit(for: .ipv4) }
        set { setFixedExit(newValue, for: .ipv4) }
    }
    public var fixedIPv6TargetIP: String {
        get { fixedExit(for: .ipv6) }
        set { setFixedExit(newValue, for: .ipv6) }
    }
    public func fixedExit(for family: IPFamily) -> String {
        usesPrimaryTargetSlot(for: family) ? targetIP : alternateTargetIP
    }
    public mutating func setFixedExit(_ value: String, for family: IPFamily) {
        if usesPrimaryTargetSlot(for: family) { targetIP = value } else { alternateTargetIP = value }
    }
    public func target(for family: IPFamily) -> String? {
        guard let value = IPAddress.normalized(fixedExit(for: family)), IPFamily.of(value) == family else { return nil }
        return value
    }
    public func includes(_ kind: ProtectedKind) -> Bool { kind == .desktop ? protectDesktop : protectCode }
    public var hasSelection: Bool { protectDesktop || protectCode }

    private func usesPrimaryTargetSlot(for family: IPFamily) -> Bool {
        let primary = targetIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternate = alternateTargetIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized = IPAddress.normalized(primary), IPFamily.of(normalized) == family { return true }
        if let normalized = IPAddress.normalized(alternate), IPFamily.of(normalized) == family { return false }
        if primary.isEmpty && alternate.isEmpty { return family == .ipv4 }
        // Partial text is still assigned to the row being edited; IPv6 values are identified by a colon.
        return family == .ipv6 ? primary.contains(":") : !primary.contains(":")
    }
}
public enum IPAddress {
    public static func normalized(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var v4 = in_addr(); var v6 = in6_addr()
        var result = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if inet_pton(AF_INET, value, &v4) == 1 {
            guard inet_ntop(AF_INET, &v4, &result, socklen_t(result.count)) != nil else { return nil }
        } else if inet_pton(AF_INET6, value, &v6) == 1 {
            guard inet_ntop(AF_INET6, &v6, &result, socklen_t(result.count)) != nil else { return nil }
        } else { return nil }
        return String(cString: result)
    }
}
public enum CheckLevel: String, Codable, Sendable { case passed, warning, failed, unknown }
public struct CheckItem: Identifiable, Codable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var level: CheckLevel
    public init(_ id: String, _ title: String, _ detail: String, _ level: CheckLevel) {
        self.id = id; self.title = title; self.detail = detail; self.level = level
    }
}
public struct ProcessIdentity: Codable, Hashable, Sendable, Identifiable {
    public var pid: Int32
    public var uid: UInt32
    public var startSeconds: UInt64
    public var startMicroseconds: UInt64
    public var executable: String
    public var kind: ProtectedKind
    public var id: Int32 { pid }
    public init(pid: Int32, uid: UInt32, startSeconds: UInt64, startMicroseconds: UInt64,
                executable: String, kind: ProtectedKind) {
        self.pid = pid; self.uid = uid; self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds; self.executable = executable; self.kind = kind
    }
}
public struct ObservedExit: Codable, Sendable {
    public var family: IPFamily
    public var direct: String?
    public var proxied: String?
    public init(family: IPFamily, direct: String?, proxied: String?) { self.family = family; self.direct = direct; self.proxied = proxied }
}
public struct DiagnosticSnapshot: Codable, Sendable {
    public var checkedAt = Date()
    public var settings: GuardSettings
    public var checks: [CheckItem]
    public var proxyIP: String?
    public var tunnelIP: String?
    public var processes: [ProcessIdentity]
    public var desktopPath: String?
    public var codePaths: [String]
    public var familyExits: [ObservedExit] = []
    public var enabledFamilies: Set<IPFamily> = []
    public var ready: Bool {
        guard settings.validInterval, settings.hasSelection,
              let exit = proxyIP, exit == tunnelIP,
              settings.target(for: IPFamily.of(exit)) == exit else { return false }
        return !checks.contains { $0.level == .failed || $0.level == .unknown }
    }
    public var failureSummary: String {
        checks.filter { $0.level == .failed || $0.level == .unknown }.map { "\($0.title)：\($0.detail)" }.joined(separator: "；")
    }
    public init(settings: GuardSettings, checks: [CheckItem], proxyIP: String?, tunnelIP: String?,
                processes: [ProcessIdentity], desktopPath: String?, codePaths: [String]) {
        self.settings = settings; self.checks = checks; self.proxyIP = proxyIP; self.tunnelIP = tunnelIP
        self.processes = processes; self.desktopPath = desktopPath; self.codePaths = codePaths
    }
}
public enum GuardPhase: String, Sendable { case idle, armed, incident }
public struct GuardPolicy: Sendable {
    public private(set) var phase: GuardPhase = .idle
    public private(set) var reason = ""
    public init() {}
    @discardableResult public mutating func arm(_ snapshot: DiagnosticSnapshot, settings: GuardSettings) -> Bool {
        guard snapshot.settings == settings, snapshot.ready,
              Date().timeIntervalSince(snapshot.checkedAt) < 20 else { return false }
        phase = .armed; reason = ""; return true
    }
    public mutating func observe(_ snapshot: DiagnosticSnapshot) {
        if phase == .armed && !snapshot.ready { phase = .incident; reason = snapshot.failureSummary }
    }
    public mutating func trip(_ message: String) {
        if phase == .armed { phase = .incident; reason = message }
    }
    public mutating func stop() { phase = .idle; reason = "" }
}
public enum RouteEvidence {
    public static func interface(from output: String) -> String? {
        output.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && parts[0] == "interface" ? parts[1] : nil
        }.first
    }
    public static func sameTunnel(_ values: [String?]) -> String? {
        guard values.count >= 2, let first = values.first ?? nil,
              first.range(of: #"^utun[0-9]+$"#, options: .regularExpression) != nil,
              values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}
public enum ProcessClassifier {
    public static func classify(executable: String, arguments: [String], desktopRoots: [String], home: String) -> ProtectedKind? {
        if desktopRoots.contains(where: { executable.hasPrefix($0 + "/Contents/") }) { return .desktop }
        let nativeRoot = home + "/.local/share/claude/versions/"
        if executable.hasPrefix(nativeRoot), !executable.dropFirst(nativeRoot.count).contains("/") { return .code }
        for editor in [".vscode", ".cursor", ".vscode-insiders"] {
            let prefix = home + "/\(editor)/extensions/anthropic.claude-code-"
            if executable.hasPrefix(prefix) {
                let remainder = String(executable.dropFirst(prefix.count))
                let parts = remainder.split(separator: "/")
                if parts.count == 4, !parts[0].isEmpty, parts[1] == "resources", parts[2] == "native-binary", parts[3] == "claude" { return .code }
            }
        }
        // Native Homebrew installations have a versioned Claude cask directory.
        if executable.range(of: #"^/(opt/homebrew|usr/local)/Caskroom/claude-code/[^/]+/claude$"#, options: .regularExpression) != nil { return .code }
        guard URL(fileURLWithPath: executable).lastPathComponent == "node", arguments.count >= 2 else { return nil }
        // Only the actual first script argument qualifies; prompt text and arbitrary later arguments do not.
        let script = arguments[1]
        guard script.hasPrefix("/"), script.hasSuffix("/node_modules/@anthropic-ai/claude-code/cli.js") else { return nil }
        return .code
    }
    public static func mayTerminate(record: ProcessIdentity, current: ProcessIdentity?, settings: GuardSettings, uid: UInt32) -> Bool {
        record.pid > 1 && record.uid == uid && current == record && settings.includes(record.kind)
    }
}
