import Foundation
import Darwin

public enum STUNCodec {
    public static func request(transaction: [UInt8]) -> Data {
        Data([0, 1, 0, 0, 0x21, 0x12, 0xa4, 0x42] + transaction)
    }
    public static func mappedAddress(_ data: Data, transaction: [UInt8]) -> String? {
        let b = Array(data)
        guard transaction.count == 12, b.count >= 20, Array(b[0..<2]) == [1, 1],
              Array(b[4..<8]) == [0x21, 0x12, 0xa4, 0x42], Array(b[8..<20]) == transaction else { return nil }
        let size = Int(b[2]) << 8 | Int(b[3])
        guard size % 4 == 0, size + 20 == b.count else { return nil }
        var offset = 20
        while offset + 4 <= b.count {
            let type = Int(b[offset]) << 8 | Int(b[offset + 1])
            let length = Int(b[offset + 2]) << 8 | Int(b[offset + 3])
            let start = offset + 4
            guard start + length <= b.count else { return nil }
            if type == 0x20 || type == 1 {
                guard length >= 4, b[start] == 0 else { return nil }
                let af: Int32; let count: Int
                switch b[start + 1] {
                case 1: af = AF_INET; count = 4
                case 2: af = AF_INET6; count = 16
                default: return nil
                }
                guard length == count + 4 else { return nil }
                let mask = [UInt8]([0x21, 0x12, 0xa4, 0x42]) + transaction
                var bytes = Array(b[(start + 4)..<(start + 4 + count)])
                if type == 0x20 { for i in bytes.indices { bytes[i] ^= mask[i] } }
                var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                let ok = bytes.withUnsafeBytes { inet_ntop(af, $0.baseAddress, &output, socklen_t(output.count)) != nil }
                return ok ? String(cString: output) : nil
            }
            offset = start + ((length + 3) / 4 * 4)
        }
        return nil
    }
}

public enum DNSCodec {
    public static func request(id: UInt16) -> Data {
        var b: [UInt8] = [UInt8(id >> 8), UInt8(id & 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in ["claude", "ai"] { b.append(UInt8(label.count)); b += label.utf8 }
        b += [0, 0, 1, 0, 1]
        return Data(b)
    }
    public static func validResponse(_ data: Data, id: UInt16) -> Bool {
        let b = Array(data); let question = Array(request(id: id).dropFirst(12))
        guard b.count >= 12 + question.count,
              b[0] == UInt8(id >> 8), b[1] == UInt8(id & 255),
              b[2] & 0x80 != 0, b[2] & 0x7a == 0, b[3] & 15 == 0,
              b[4] == 0, b[5] == 1, Int(b[6]) << 8 | Int(b[7]) > 0,
              Array(b[12..<(12 + question.count)]) == question else { return false }
        // Require every advertised answer to fit; compression pointers must point inside this packet.
        var offset = 12 + question.count
        for _ in 0..<(Int(b[6]) << 8 | Int(b[7])) {
            var labels = 0
            while true {
                guard offset < b.count, labels < 128 else { return false }
                let length = Int(b[offset]); offset += 1; labels += 1
                if length == 0 { break }
                if length & 0xc0 == 0xc0 {
                    guard offset < b.count else { return false }
                    let pointer = (length & 63) << 8 | Int(b[offset]); offset += 1
                    guard pointer >= 12, pointer < b.count else { return false }; break
                }
                guard length <= 63, offset + length <= b.count else { return false }; offset += length
            }
            guard offset + 10 <= b.count else { return false }
            let length = Int(b[offset + 8]) << 8 | Int(b[offset + 9]); offset += 10
            guard offset + length <= b.count else { return false }; offset += length
        }
        return true
    }
}

enum DatagramTransport {
    static func exchange(ip: String, port: UInt16, payload: Data) -> Data? {
        guard let ip = IPAddress.normalized(ip) else { return nil }
        let family = IPFamily.of(ip)
        let fd = socket(family.af, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let connected: Int32
        if family == .ipv4 {
            var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return nil }
            connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        } else {
            var addr = sockaddr_in6(); addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6); addr.sin6_port = port.bigEndian
            guard inet_pton(AF_INET6, ip, &addr.sin6_addr) == 1 else { return nil }
            connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) } }
        }
        guard connected == 0, payload.withUnsafeBytes({ send(fd, $0.baseAddress, $0.count, 0) }) == payload.count else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = recv(fd, &bytes, bytes.count, 0)
        return count > 0 ? Data(bytes.prefix(count)) : nil
    }
    static func resolve(_ host: String, family: IPFamily) -> String? {
        let r = Command.run("/usr/bin/dig", ["+short", "+time=1", "+tries=1", host, family == .ipv4 ? "A" : "AAAA"], timeout: 2)
        guard r.status == 0 else { return nil }
        return r.output.split(separator: "\n").compactMap { IPAddress.normalized(String($0)) }.first { IPFamily.of($0) == family }
    }
}

public enum DatagramProbes {
    public static func udp(family: IPFamily, expected: String?) async -> CheckItem {
        let results: [String?] = await withTaskGroup(of: String?.self) { group in
            for host in ["stun.cloudflare.com", "stun.l.google.com"] {
                group.addTask {
                    await Task.detached(priority: .utility) {
                        guard let ip = DatagramTransport.resolve(host, family: family) else { return nil }
                        let tx = (0..<12).map { _ in UInt8.random(in: 0...255) }
                        guard let data = DatagramTransport.exchange(ip: ip, port: host.contains("google") ? 19302 : 3478, payload: STUNCodec.request(transaction: tx)) else { return nil }
                        return STUNCodec.mappedAddress(data, transaction: tx)
                    }.value
                }
            }
            var values: [String?] = []; for await result in group { values.append(result) }; return values
        }
        return evaluateUDP(results, family: family, expected: expected)
    }
    public static func evaluateUDP(_ results: [String?], family: IPFamily, expected: String?) -> CheckItem {
        let addresses = results.compactMap { $0 }; let id = "udp-\(family.rawValue)"
        if let expected, addresses.contains(where: { $0 != expected }) {
            return .init(id, "UDP · \(family.displayName)", "观察到与固定出口不同的 UDP 映射：\(addresses.joined(separator: ", "))", .failed)
        }
        guard let expected, results.count >= 2, addresses.count == results.count,
              addresses.allSatisfy({ $0 == expected }) else {
            return .init(id, "UDP · \(family.displayName)", "有效响应 \(addresses.count)/\(results.count)；结果未知，超时不证明阻断", .unknown)
        }
        return .init(id, "UDP · \(family.displayName)", "两处 STUN 映射均匹配 \(expected)；仅代表这些 UDP 探测", .passed)
    }
    public static func dns() async -> CheckItem {
        await Task.detached(priority: .utility) {
            let servers = NetworkEvidence.dnsServers()
            guard !servers.isEmpty else { return .init("dns", "DNS", "未取得系统全局 DNS 配置；无法核验", .unknown) }
            var details: [String] = []; var unknown = false; var failed = false
            for server in servers.prefix(4) {
                let route = NetworkEvidence.route(to: server)
                let loopback = server == "127.0.0.1" || server == "::1"
                let inTunnel = route?.range(of: #"^utun[0-9]+$"#, options: .regularExpression) != nil
                if loopback { unknown = true }
                else if !inTunnel { failed = true }
                let id = UInt16.random(in: 0...65535)
                let reply = DatagramTransport.exchange(ip: server, port: 53, payload: DNSCodec.request(id: id))
                let valid = reply.map { DNSCodec.validResponse($0, id: id) } ?? false
                if !valid { unknown = true }
                details.append("\(server) → \(route ?? "未知路由") · \(valid ? "有效响应" : "未取得有效响应")")
            }
            if servers.count > 4 { unknown = true }
            return .init("dns", "DNS", details.joined(separator: "；") + "。仅测试全局解析器与 claude.ai，不覆盖应用 DoH/分域 DNS；本地转发器上游无法证明。", failed ? .failed : unknown ? .unknown : .passed)
        }.value
    }
}
