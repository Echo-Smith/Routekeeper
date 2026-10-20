import Foundation
import AppKit
import SystemConfiguration
import Darwin

public enum IPFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case ipv4, ipv6
    public var af: Int32 { self == .ipv4 ? AF_INET : AF_INET6 }
    public var displayName: String { self == .ipv4 ? "IPv4" : "IPv6" }
    public static func of(_ ip: String) -> IPFamily { ip.contains(":") ? .ipv6 : .ipv4 }
    public var destinations: [String] {
        self == .ipv4 ? ["1.1.1.1", "9.9.9.9"] : ["2606:4700:4700::1111", "2620:fe::fe"]
    }
}

public enum ProxyClient: String, Codable, CaseIterable, Sendable {
    case automatic, clash, flClash, clashVerge, mihomo, v2ray, shadowsocks
    public var title: String {
        switch self {
        case .automatic: return L10n.resolvedEnglish ? "Automatic" : "自动识别"
        case .clash: return "Clash"
        case .flClash: return "FlClash"
        case .clashVerge: return "Clash Verge"
        case .mihomo: return "mihomo CLI"
        case .v2ray: return "V2Ray"
        case .shadowsocks: return "Shadowsocks"
        }
    }
}
public struct ProxyIdentification: Sendable {
    public var client: ProxyClient
    public var running: Bool
    public var detail: String
}
public enum ProxyAdapters {
    public static func identify(_ selection: ProxyClient) -> ProxyIdentification {
        let apps: [(ProxyClient, [(String, String)])] = [
            (.clash, [
                ("com.west2online.ClashX", "ClashX"),
                ("com.west2online.ClashXPro", "ClashX Pro")
            ]),
            (.flClash, [("com.follow.clash", "FlClash")]),
            (.clashVerge, [("io.github.clash-verge-rev.clash-verge-rev", "Clash Verge")]),
            (.v2ray, [
                ("net.yanue.V2rayU", "V2RayU"),
                ("com.github.Cenmiao.V2RayX", "V2RayX")
            ]),
            (.shadowsocks, [
                ("com.qiuyuzhou.ShadowsocksX-NG", "ShadowsocksX-NG"),
                ("com.qiuyuzhou.ShadowsocksX-NG-R8", "ShadowsocksX-NG-R8")
            ])
        ]
        let appCandidates = apps
            .filter { selection == .automatic || selection == .clash || selection == $0.0 }
            .flatMap { client, entries in
                entries.map { id, name in
                    let installed = ApplicationDiscovery.path(bundleID: id, name: name) != nil
                    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
                    return ProxyIdentification(
                        client: client,
                        running: installed && running,
                        detail: "\(name) · \(running ? "运行中" : "未运行")"
                    )
                }
            }
        if let active = appCandidates.first(where: \.running) { return active }

        let processes: [(ProxyClient, Set<String>)] = [
            (.clash, ["clash", "clash-meta", "verge-mihomo"]),
            (.mihomo, ["mihomo", "verge-mihomo"]),
            (.v2ray, ["v2ray", "xray"]),
            (.shadowsocks, ["ss-local", "sslocal"])
        ]
        let acceptedProcesses = processes
            .filter { selection == .automatic || selection == .clash || selection == $0.0 }
            .reduce(into: [String: ProxyClient]()) { result, entry in
                for name in entry.1 { result[name] = entry.0 }
            }
        if !acceptedProcesses.isEmpty {
            // Match executable basename and owner, never a substring in command arguments.
            let paths = LocalProcesses.ownExecutablePaths()
            if let path = paths.first(where: {
                acceptedProcesses[URL(fileURLWithPath: $0).lastPathComponent] != nil
            }), let client = acceptedProcesses[URL(fileURLWithPath: path).lastPathComponent] {
                return .init(
                    client: client,
                    running: true,
                    detail: "\(URL(fileURLWithPath: path).lastPathComponent) · 运行中"
                )
            }
        }
        return appCandidates.first ?? .init(
            client: selection,
            running: false,
            detail: "未识别到所选代理；不读取订阅、节点或控制密钥"
        )
    }
}

public struct FamilyRoutes: Sendable {
    public var family: IPFamily
    public var interfaces: [String?]
    public var hasUsableAddress: Bool
    public var tunnel: String? { RouteEvidence.sameTunnel(interfaces) }
    public var absent: Bool { !hasUsableAddress }
}
public enum NetworkEvidence {
    public static func route(to destination: String) -> String? {
        guard IPAddress.normalized(destination) != nil else { return nil }
        let r = Command.run("/sbin/route", ["-n", "get", destination], timeout: 2)
        return r.status == 0 ? RouteEvidence.interface(from: r.output) : nil
    }
    public static func activeAddresses() -> [(String, String)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var values: [(String, String)] = []; var next: UnsafeMutablePointer<ifaddrs>? = first
        while let p = next {
            defer { next = p.pointee.ifa_next }
            let entry = p.pointee
            guard entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let addr = entry.ifa_addr, [AF_INET, AF_INET6].contains(Int32(addr.pointee.sa_family)) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                values.append((String(cString: entry.ifa_name), String(cString: host).components(separatedBy: "%")[0]))
            }
        }
        return values
    }
    public static func hasUsableAddress(_ ip: String, family: IPFamily) -> Bool {
        let value = ip.lowercased()
        switch family {
        case .ipv4:
            return IPFamily.of(value) == family && !value.hasPrefix("169.254.")
        case .ipv6:
            // Link-local and ULA addresses do not establish ordinary public IPv6 connectivity.
            guard IPFamily.of(value) == family, let first = value.split(separator: ":").first,
                  let prefix = UInt16(first, radix: 16) else { return false }
            return prefix & 0xe000 == 0x2000
        }
    }
    public static func routes(_ family: IPFamily) -> FamilyRoutes {
        let usable = activeAddresses().contains { _, ip in
            hasUsableAddress(ip, family: family)
        }
        return .init(family: family, interfaces: family.destinations.map { route(to: $0) }, hasUsableAddress: usable)
    }
    public static func dnsServers() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "Routekeeper" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] else { return [] }
        return Array(Set((dict["ServerAddresses"] as? [String] ?? []).compactMap(IPAddress.normalized))).sorted()
    }
    public static func familyActive(_ routes: FamilyRoutes, observed: String?, proxied: String?) -> Bool {
        !routes.absent && (observed != nil || proxied != nil)
    }
    public static func familyGate(_ routes: FamilyRoutes, target: String?, observed: String?, proxied: String?) -> CheckItem {
        let id = "stack-\(routes.family.rawValue)"
        let title = routes.family.displayName
        if routes.absent {
            let detail = routes.family == .ipv6
                ? "本机未启用可用的 IPv6 地址；已跳过 IPv6 出口检查，不要求 IPv6 固定目标"
                : "本机未发现可用的 IPv4 地址；已跳过 IPv4 出口检查"
            return .init(id, title, detail, .passed)
        }
        guard familyActive(routes, observed: observed, proxied: proxied) else {
            let detail = routes.family == .ipv6
                ? "本次未观察到可用的 IPv6 出口；已自动跳过 IPv6，不要求 IPv6 固定目标"
                : "本次未观察到可用的 IPv4 出口；没有可验证的 IPv4 路径"
            return .init(id, title, detail, .passed)
        }
        guard let target else { return .init(id, title, "已观察到 \(routes.family.displayName) 出口；请填写此地址族固定出口", .unknown) }
        guard let tunnel = routes.tunnel else { return .init(id, title, "两个公网目的地未确认经过同一 utun", .failed) }
        guard let observed, let proxied else { return .init(id, title, "\(tunnel) · 出口探测未取得完整结果", .unknown) }
        return .init(id, title, "\(tunnel) · 路由出口 \(observed) · 代理出口 \(proxied)",
                     observed == target && proxied == target ? .passed : .failed)
    }
}
