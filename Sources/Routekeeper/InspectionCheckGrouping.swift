import GuardCore

enum InspectionCheckGroupKind: String, CaseIterable, Hashable, Identifiable {
    case configuration
    case localPath
    case externalServices
    case claudeEnvironment
    case additional

    var id: String { rawValue }

    var title: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .configuration:
            return en ? "Configuration and protection" : "配置与保护"
        case .localPath:
            return en ? "Local network path" : "本机网络路径"
        case .externalServices:
            return en ? "Exits and services" : "出口与服务"
        case .claudeEnvironment:
            return en ? "Claude environment" : "Claude 环境"
        case .additional:
            return en ? "Other checks" : "其他检查"
        }
    }

    var subtitle: String {
        let en = L10n.resolvedEnglish
        switch self {
        case .configuration:
            return en ? "Targets, scope and probe settings" : "保护对象、目标出口与探测参数"
        case .localPath:
            return en ? "Address families, DNS, UDP and TUN routing" : "地址族、DNS、UDP 与 TUN 路由"
        case .externalServices:
            return en ? "Exits observed locally and by external services" : "代理、系统与外部服务看到的出口"
        case .claudeEnvironment:
            return en ? "Process and client discovery" : "进程与 Claude 客户端识别"
        case .additional:
            return en ? "Uncategorised evidence retained for compatibility" : "为兼容新检查保留的未分类证据"
        }
    }

    var symbol: String {
        switch self {
        case .configuration: return "slider.horizontal.3"
        case .localPath: return "point.3.connected.trianglepath.dotted"
        case .externalServices: return "network"
        case .claudeEnvironment: return "app.badge.checkmark"
        case .additional: return "ellipsis.circle"
        }
    }

    func contains(_ id: String) -> Bool {
        switch self {
        case .configuration:
            return Self.configurationIDs.contains(id) || id.hasPrefix("target-")
        case .localPath:
            return Self.localPathIDs.contains(id)
        case .externalServices:
            return Self.externalServiceIDs.contains(id) || id.hasPrefix("egress-")
        case .claudeEnvironment:
            return Self.claudeEnvironmentIDs.contains(id)
        case .additional:
            return false
        }
    }

    private static let configurationIDs: Set<String> = [
        "target", "alternate-target", "stack-ipv4", "stack-ipv6",
        "scope", "proxy-client", "proxy", "interval"
    ]
    private static let localPathIDs: Set<String> = [
        "ipv4", "ipv6", "dns", "udp-ipv4", "udp-ipv6", "tun"
    ]
    private static let externalServiceIDs: Set<String> = [
        "proxy-exit", "tun-exit", "ipinfo-exit", "claude-trace-exit"
    ]
    private static let claudeEnvironmentIDs: Set<String> = [
        "process-access", "desktop", "code"
    ]
}

enum InspectionCheckGroupLevel {
    case notRun
    case passed
    case notice
    case unverified
    case needsAttention

    var isResolved: Bool {
        self == .passed || self == .notRun
    }
}

struct InspectionCheckGroup: Identifiable {
    let kind: InspectionCheckGroupKind
    let checks: [CheckItem]

    var id: InspectionCheckGroupKind { kind }

    var level: InspectionCheckGroupLevel {
        guard !checks.isEmpty else { return .notRun }
        if checks.contains(where: { $0.level == .failed }) { return .needsAttention }
        if checks.contains(where: { $0.level == .unknown }) { return .unverified }
        if checks.contains(where: { $0.level == .warning }) { return .notice }
        return .passed
    }

    var passedCount: Int {
        checks.filter { $0.level == .passed }.count
    }
}

enum InspectionCheckGrouping {
    static func groups(from checks: [CheckItem]) -> [InspectionCheckGroup] {
        let visibleChecks = checks.filter { $0.id != "boundary" }
        return InspectionCheckGroupKind.allCases.compactMap { kind in
            let grouped = visibleChecks.filter {
                kind == .additional ? !isKnown($0.id) : kind.contains($0.id)
            }
            guard !grouped.isEmpty else { return nil }
            return InspectionCheckGroup(kind: kind, checks: grouped)
        }
    }

    static func isKnown(_ id: String) -> Bool {
        InspectionCheckGroupKind.allCases
            .filter { $0 != .additional }
            .contains { $0.contains(id) }
    }
}
