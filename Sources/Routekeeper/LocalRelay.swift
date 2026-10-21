import Darwin
import Foundation
import GuardCore

enum LocalRelayError: Error, LocalizedError {
    case socket(String)
    case invalidClient
    case authenticationFailed
    case targetRejected
    case upstreamFailed(String)
    case stopped

    var errorDescription: String? {
        switch self {
        case .socket(let message): return "本地中继无法建立连接：\(message)"
        case .invalidClient: return "本地中继拒绝了格式无效的代理请求。"
        case .authenticationFailed: return "本地中继拒绝了未授权连接。"
        case .targetRejected: return "本地中继拒绝了本机或局域网目标。"
        case .upstreamFailed(let message): return "上游代理连接失败：\(message)"
        case .stopped: return "本地中继已停止。"
        }
    }
}

struct LocalRelaySnapshot: Equatable, Sendable {
    var running: Bool
    var port: Int?
    var activeConnections: Int
    var lastError: String
}

final class LocalRelay: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.routekeeper.isolation.relay", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var activeSockets: Set<Int32> = []
    private var generation = 0
    private var isRunning = false
    private var boundPort: Int?
    private var lastError = ""
    private var upstream: IsolationUpstream?
    private var clientUsername = ""
    private var clientPassword = ""
    private var authHeader = ""
    private let handshakeTimeoutSeconds: Int

    init(handshakeTimeoutSeconds: Int = 20) {
        self.handshakeTimeoutSeconds = max(1, handshakeTimeoutSeconds)
    }

    deinit { stop() }

    func start(upstream: IsolationUpstream) throws -> Int {
        guard upstream.isValid else { throw LocalRelayError.upstreamFailed("上游代理必须是本机地址。") }
        stop(preservePort: true)
        if clientUsername.isEmpty {
            clientUsername = "rk-\(UUID().uuidString.lowercased().prefix(8))"
            clientPassword = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            authHeader = "Basic " + Data("\(clientUsername):\(clientPassword)".utf8).base64EncodedString()
        }
        self.upstream = upstream

        let descriptor = try makeListener(preferredPort: boundPort)
        let port = try Self.boundPort(descriptor)
        lock.withLock {
            listener = descriptor
            boundPort = port
            isRunning = true
            lastError = ""
            generation += 1
        }
        let currentGeneration = lock.withLock { generation }
        queue.async { [weak self] in
            self?.acceptLoop(descriptor: descriptor, generation: currentGeneration)
        }
        return port
    }

    func pause() {
        stop(preservePort: true)
    }

    func stop(preservePort: Bool = false) {
        let sockets: [Int32] = lock.withLock {
            generation += 1
            isRunning = false
            let values = [listener] + Array(activeSockets)
            listener = -1
            activeSockets.removeAll()
            if !preservePort { boundPort = nil }
            return values.filter { $0 >= 0 }
        }
        for descriptor in sockets {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
        }
    }

    func snapshot() -> LocalRelaySnapshot {
        lock.withLock {
            .init(running: isRunning, port: boundPort, activeConnections: activeSockets.count, lastError: lastError)
        }
    }

    func proxyEnvironment() -> [String: String] {
        let credentials: (String, String, Int) = lock.withLock {
            (clientUsername, clientPassword, boundPort ?? 0)
        }
        guard credentials.2 > 0 else { return [:] }
        let user = credentials.0.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? credentials.0
        let password = credentials.1.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? credentials.1
        let value = "http://\(user):\(password)@127.0.0.1:\(credentials.2)"
        return ["HTTP_PROXY": value, "HTTPS_PROXY": value, "ALL_PROXY": value, "NO_PROXY": ""]
    }

    func relayURL() -> String? {
        lock.withLock {
            guard let boundPort else { return nil }
            return "http://127.0.0.1:\(boundPort)"
        }
    }

    func socks5URL() -> String? {
        lock.withLock {
            guard let boundPort else { return nil }
            return "socks5://127.0.0.1:\(boundPort)"
        }
    }

    private func makeListener(preferredPort: Int?) throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalRelayError.socket(String(cString: strerror(errno))) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(preferredPort ?? 0).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(descriptor, 64) == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            throw LocalRelayError.socket(message)
        }
        return descriptor
    }

    private static func boundPort(_ descriptor: Int32) throws -> Int {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard result == 0 else { throw LocalRelayError.socket("无法读取本地中继端口") }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func acceptLoop(descriptor: Int32, generation expectedGeneration: Int) {
        while shouldAccept(descriptor: descriptor, generation: expectedGeneration) {
            var address = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(descriptor, &address, &length)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            setSocketTimeout(client, seconds: handshakeTimeoutSeconds)
            register(client)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(client)
            }
        }
    }

    private func shouldAccept(descriptor: Int32, generation expected: Int) -> Bool {
        lock.withLock {
            listener == descriptor && isRunning && generation == expected
        }
    }

    private func handle(_ client: Int32) {
        var upstreamSocket: Int32 = -1
        var stage = "读取客户端请求"
        defer {
            unregisterAndClose(client)
            if upstreamSocket >= 0 { unregisterAndClose(upstreamSocket) }
        }
        do {
            guard let upstream else { throw LocalRelayError.stopped }
            let first = try receiveExactly(client, count: 1)[0]
            if first == 0x05 {
                let target = try negotiateSOCKS(client: client, firstByte: first)
                stage = "连接上游代理"
                upstreamSocket = try connectUpstream(upstream)
                register(upstreamSocket)
                stage = "建立上游 SOCKS5 会话"
                try establishSOCKSUpstream(upstreamSocket, upstream: upstream, target: target)
                stage = "回复本地 SOCKS5 客户端"
                try sendAll(client, Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
            } else {
                let target = try negotiateHTTP(client: client, firstByte: first)
                stage = "连接上游代理"
                upstreamSocket = try connectUpstream(upstream)
                register(upstreamSocket)
                stage = "建立上游 HTTP CONNECT 会话"
                try establishHTTPUpstream(upstreamSocket, upstream: upstream, target: target)
                stage = "回复本地 HTTP 客户端"
                try sendAll(client, Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8))
            }
            stage = "转发数据"
            clearReceiveTimeout(client)
            clearReceiveTimeout(upstreamSocket)
            relay(client, upstreamSocket)
        } catch {
            lock.withLock { lastError = "\(stage)：\(error.localizedDescription)" }
            if client >= 0 {
                _ = try? sendAll(client, Data("HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8))
            }
        }
    }

    private func negotiateHTTP(client: Int32, firstByte: UInt8) throws -> RelayTarget {
        var data = Data([firstByte])
        while data.count < 64 * 1024 && data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let chunk = try receive(client, maximum: 4096)
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard let text = String(data: data, encoding: .utf8),
              let separator = text.range(of: "\r\n") else { throw LocalRelayError.invalidClient }
        let requestLine = String(text[..<separator.lowerBound]).split(separator: " ")
        guard requestLine.count >= 3, requestLine[0] == "CONNECT",
              let target = RelayTarget(authority: String(requestLine[1])),
              !target.blocksDirectLocalAccess else { throw LocalRelayError.targetRejected }
        let headers = text
            .split(separator: "\r\n")
            .dropFirst()
            .reduce(into: [String: String]()) { result, line in
                guard let colon = line.firstIndex(of: ":") else { return }
                let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                result[key] = value
            }
        guard headers["proxy-authorization"] == authHeader else {
            throw LocalRelayError.authenticationFailed
        }
        return target
    }

    private func negotiateSOCKS(client: Int32, firstByte: UInt8) throws -> RelayTarget {
        let methodsHeader = try receiveExactly(client, count: 2)
        let methodCount = Int(methodsHeader[0])
        guard methodCount > 0 else { throw LocalRelayError.invalidClient }
        var methods = Data([methodsHeader[1]])
        if methodCount > 1 {
            methods.append(try receiveExactly(client, count: methodCount - 1))
        }
        if methods.contains(0x02) {
            _ = try sendAll(client, Data([0x05, 0x02]))
            let authVersion = try receiveExactly(client, count: 1)[0]
            let usernameLength = Int(try receiveExactly(client, count: 1)[0])
            let username = String(decoding: try receiveExactly(client, count: usernameLength), as: UTF8.self)
            let passwordLength = Int(try receiveExactly(client, count: 1)[0])
            let password = String(decoding: try receiveExactly(client, count: passwordLength), as: UTF8.self)
            guard authVersion == 0x01, username == clientUsername, password == clientPassword else {
                throw LocalRelayError.authenticationFailed
            }
            _ = try sendAll(client, Data([0x01, 0x00]))
        } else if methods.contains(0x00) {
            // Chromium command-line proxies support SOCKS5 without an auth callback.
            _ = try sendAll(client, Data([0x05, 0x00]))
        } else {
            throw LocalRelayError.authenticationFailed
        }

        let request = try receiveExactly(client, count: 4)
        guard request[0] == 0x05, request[1] == 0x01 else { throw LocalRelayError.invalidClient }
        let host: String
        switch request[3] {
        case 0x01:
            host = try receiveExactly(client, count: 4).map(String.init).joined(separator: ".")
        case 0x04:
            let bytes = try receiveExactly(client, count: 16)
            var address = in6_addr()
            bytes.withUnsafeBytes { source in
                withUnsafeMutableBytes(of: &address) { destination in
                    destination.copyBytes(from: source)
                }
            }
            var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &output, socklen_t(output.count)) != nil else {
                throw LocalRelayError.invalidClient
            }
            host = String(cString: output)
        case 0x03:
            let length = Int(try receiveExactly(client, count: 1)[0])
            host = String(decoding: try receiveExactly(client, count: length), as: UTF8.self)
        default:
            throw LocalRelayError.invalidClient
        }
        let portBytes = try receiveExactly(client, count: 2)
        let port = Int(UInt16(portBytes[0]) << 8 | UInt16(portBytes[1]))
        guard let target = RelayTarget(authority: "\(host):\(port)"),
              !target.blocksDirectLocalAccess else { throw LocalRelayError.targetRejected }
        return target
    }

    private func connectUpstream(_ endpoint: IsolationUpstream) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(endpoint.host, String(endpoint.port), &hints, &result)
        guard status == 0, let first = result else {
            throw LocalRelayError.upstreamFailed(String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            let descriptor = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if descriptor >= 0 {
                setSocketTimeout(descriptor, seconds: 10)
                if Darwin.connect(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    return descriptor
                }
                close(descriptor)
            }
            current = info.pointee.ai_next
        }
        throw LocalRelayError.upstreamFailed("请确认本机代理已启动，且端口和协议填写正确。")
    }

    private func establishHTTPUpstream(_ descriptor: Int32, upstream: IsolationUpstream, target: RelayTarget) throws {
        var request = "CONNECT \(target.host):\(target.port) HTTP/1.1\r\nHost: \(target.host):\(target.port)\r\nProxy-Connection: Keep-Alive\r\n"
        if !upstream.username.isEmpty || !upstream.password.isEmpty {
            let basic = Data("\(upstream.username):\(upstream.password)".utf8).base64EncodedString()
            request += "Proxy-Authorization: Basic \(basic)\r\n"
        }
        request += "\r\n"
        try sendAll(descriptor, Data(request.utf8))
        let response = try readHeader(descriptor)
        guard let text = String(data: response, encoding: .utf8),
              let first = text.split(separator: "\r\n").first,
              first.contains(" 200 ") else {
            throw LocalRelayError.upstreamFailed("上游代理拒绝连接目标。")
        }
    }

    private func establishSOCKSUpstream(_ descriptor: Int32, upstream: IsolationUpstream, target: RelayTarget) throws {
        let requiresAuthentication = !upstream.username.isEmpty || !upstream.password.isEmpty
        let greeting = requiresAuthentication ? Data([0x05, 0x02, 0x00, 0x02]) : Data([0x05, 0x01, 0x00])
        try sendAll(descriptor, greeting)
        let method = try receiveExactly(descriptor, count: 2)
        guard method[0] == 0x05, method[1] != 0xff else {
            throw LocalRelayError.upstreamFailed("上游 SOCKS5 不接受可用认证方式。")
        }
        if method[1] == 0x02 {
            let username = Array(upstream.username.utf8.prefix(255))
            let password = Array(upstream.password.utf8.prefix(255))
            var auth = Data([0x01, UInt8(username.count)])
            auth.append(contentsOf: username)
            auth.append(UInt8(password.count))
            auth.append(contentsOf: password)
            try sendAll(descriptor, auth)
            let response = try receiveExactly(descriptor, count: 2)
            guard response == Data([0x01, 0x00]) else {
                throw LocalRelayError.upstreamFailed("上游 SOCKS5 用户名或密码无效。")
            }
        }

        var request = Data([0x05, 0x01, 0x00])
        if let normalized = IPAddress.normalized(target.host) {
            if IPFamily.of(normalized) == .ipv4 {
                var address = in_addr()
                inet_pton(AF_INET, normalized, &address)
                request.append(0x01)
                withUnsafeBytes(of: &address) { request.append(contentsOf: $0) }
            } else {
                var address = in6_addr()
                inet_pton(AF_INET6, normalized, &address)
                request.append(0x04)
                withUnsafeBytes(of: &address) { request.append(contentsOf: $0) }
            }
        } else {
            let host = Array(target.host.utf8.prefix(255))
            request.append(0x03)
            request.append(UInt8(host.count))
            request.append(contentsOf: host)
        }
        request.append(UInt8(target.port >> 8))
        request.append(UInt8(target.port & 0xff))
        try sendAll(descriptor, request)

        let response = try receiveExactly(descriptor, count: 4)
        guard response[0] == 0x05, response[1] == 0x00 else {
            throw LocalRelayError.upstreamFailed("上游 SOCKS5 无法连接目标。")
        }
        switch response[3] {
        case 0x01: _ = try receiveExactly(descriptor, count: 4 + 2)
        case 0x04: _ = try receiveExactly(descriptor, count: 16 + 2)
        case 0x03:
            let length = Int(try receiveExactly(descriptor, count: 1)[0])
            _ = try receiveExactly(descriptor, count: length + 2)
        default: throw LocalRelayError.upstreamFailed("上游 SOCKS5 返回了未知地址类型。")
        }
    }

    private func relay(_ client: Int32, _ upstream: Int32) {
        var buffers = [pollfd(fd: client, events: Int16(POLLIN), revents: 0),
                       pollfd(fd: upstream, events: Int16(POLLIN), revents: 0)]
        while snapshot().running {
            buffers[0].revents = 0
            buffers[1].revents = 0
            let ready = poll(&buffers, 2, 500)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }
            if buffers[0].revents & Int16(POLLIN) != 0 {
                do {
                    let data = try receive(client, maximum: 32 * 1024)
                    guard !data.isEmpty else { break }
                    try sendAll(upstream, data)
                } catch { break }
            }
            if buffers[1].revents & Int16(POLLIN) != 0 {
                do {
                    let data = try receive(upstream, maximum: 32 * 1024)
                    guard !data.isEmpty else { break }
                    try sendAll(client, data)
                } catch { break }
            }
            if buffers[0].revents & Int16(POLLHUP | POLLERR) != 0
                || buffers[1].revents & Int16(POLLHUP | POLLERR) != 0 { break }
        }
    }

    private func readHeader(_ descriptor: Int32) throws -> Data {
        var data = Data()
        while data.count < 64 * 1024 && data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let chunk = try receive(descriptor, maximum: 4096)
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }

    private func receive(_ descriptor: Int32, maximum: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: maximum)
        let count = Darwin.recv(descriptor, &bytes, maximum, 0)
        if count < 0 { throw LocalRelayError.socket(String(cString: strerror(errno))) }
        return Data(bytes.prefix(Int(count)))
    }

    private func receiveExactly(_ descriptor: Int32, count: Int) throws -> Data {
        guard count >= 0, count <= 65_535 else { throw LocalRelayError.invalidClient }
        var data = Data()
        while data.count < count {
            let chunk = try receive(descriptor, maximum: count - data.count)
            guard !chunk.isEmpty else { throw LocalRelayError.invalidClient }
            data.append(chunk)
        }
        return data
    }

    private func sendAll(_ descriptor: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let count = Darwin.send(descriptor, base.advanced(by: sent), raw.count - sent, 0)
                if count <= 0 { throw LocalRelayError.socket(String(cString: strerror(errno))) }
                sent += count
            }
        }
    }

    private func register(_ descriptor: Int32) {
        lock.withLock { _ = activeSockets.insert(descriptor) }
    }

    private func unregisterAndClose(_ descriptor: Int32) {
        let shouldClose = lock.withLock { activeSockets.remove(descriptor) != nil }
        if shouldClose {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
        }
    }

    private func setSocketTimeout(_ descriptor: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func clearReceiveTimeout(_ descriptor: Int32) {
        var timeout = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
