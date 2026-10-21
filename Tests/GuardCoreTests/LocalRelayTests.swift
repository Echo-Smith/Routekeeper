import Darwin
import Foundation
import XCTest
@testable import GuardCore
@testable import Routekeeper

final class LocalRelayTests: XCTestCase {
    func testHTTPConnectClientReachesConfiguredLocalUpstreamAndPauseFailsClosed() throws {
        let upstream = try FakeHTTPConnectProxy()
        defer { upstream.close() }
        let relay = LocalRelay()
        let localPort = try relay.start(
            upstream: IsolationUpstream(host: "127.0.0.1", port: upstream.port, protocolType: .httpConnect)
        )
        defer { relay.stop() }

        let environment = relay.proxyEnvironment()
        let proxyURL = try XCTUnwrap(environment["HTTPS_PROXY"])
        let authorization = try XCTUnwrap(BasicProxyCredentials(proxyURL: proxyURL)).header
        let client = try connect(port: localPort)
        defer { close(client) }
        try send(client, Data(connectRequest(host: "example.com:443", authorization: authorization).utf8))
        let response = try readHeader(client)
        XCTAssertTrue(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 200"))
        XCTAssertEqual(upstream.lastTarget, "example.com:443")

        try send(client, Data("ping".utf8))
        XCTAssertEqual(try receiveExactly(client, count: 4), Data("ping".utf8))

        relay.pause()
        XCTAssertFalse(relay.snapshot().running)
        XCTAssertThrowsError(try connect(port: localPort))

        let resumedPort = try relay.start(
            upstream: IsolationUpstream(host: "127.0.0.1", port: upstream.port, protocolType: .httpConnect)
        )
        XCTAssertEqual(resumedPort, localPort)
    }

    func testHTTPConnectTunnelSurvivesIdlePeriodLongerThanHandshakeTimeout() throws {
        let upstream = try FakeHTTPConnectProxy()
        defer { upstream.close() }
        let relay = LocalRelay(handshakeTimeoutSeconds: 1)
        let localPort = try relay.start(
            upstream: IsolationUpstream(host: "127.0.0.1", port: upstream.port, protocolType: .httpConnect)
        )
        defer { relay.stop() }

        let proxyURL = try XCTUnwrap(relay.proxyEnvironment()["HTTPS_PROXY"])
        let authorization = try XCTUnwrap(BasicProxyCredentials(proxyURL: proxyURL)).header
        let client = try connect(port: localPort)
        defer { close(client) }
        try send(client, Data(connectRequest(host: "example.com:443", authorization: authorization).utf8))
        XCTAssertTrue(String(decoding: try readHeader(client), as: UTF8.self).hasPrefix("HTTP/1.1 200"))

        Thread.sleep(forTimeInterval: 1.5)

        try send(client, Data("ping".utf8))
        XCTAssertEqual(try receiveExactly(client, count: 4), Data("ping".utf8))
    }

    func testHTTPConnectRequiresSessionCredentialAndRejectsLocalTargets() throws {
        let upstream = try FakeHTTPConnectProxy()
        defer { upstream.close() }
        let relay = LocalRelay()
        let port = try relay.start(
            upstream: IsolationUpstream(host: "127.0.0.1", port: upstream.port, protocolType: .httpConnect)
        )
        defer { relay.stop() }

        let unauthorized = try connect(port: port)
        defer { close(unauthorized) }
        try send(unauthorized, Data("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n".utf8))
        XCTAssertTrue(String(decoding: try readHeader(unauthorized), as: UTF8.self).hasPrefix("HTTP/1.1 403"))

        let authorization = try XCTUnwrap(BasicProxyCredentials(proxyURL: relay.proxyEnvironment()["HTTPS_PROXY"] ?? "")).header
        let localTarget = try connect(port: port)
        defer { close(localTarget) }
        try send(localTarget, Data(connectRequest(host: "127.0.0.1:80", authorization: authorization).utf8))
        let rejection = try readHeader(localTarget)
        XCTAssertTrue(String(decoding: rejection, as: UTF8.self).hasPrefix("HTTP/1.1 403"))
    }

    func testSOCKS5ClientUsesConfiguredSOCKS5Upstream() throws {
        let upstream = try FakeSOCKS5Proxy()
        defer { upstream.close() }
        let relay = LocalRelay()
        let port = try relay.start(
            upstream: IsolationUpstream(host: "127.0.0.1", port: upstream.port, protocolType: .socks5)
        )
        defer { relay.stop() }
        let credentials = try XCTUnwrap(BasicProxyCredentials(proxyURL: relay.proxyEnvironment()["HTTPS_PROXY"] ?? ""))
        let client = try connect(port: port)
        defer { close(client) }

        try send(client, Data([0x05, 0x01, 0x02]))
        let greetingResponse: Data
        do {
            greetingResponse = try receiveExactly(client, count: 2)
        } catch {
            XCTFail("SOCKS greeting failed: \(error), relay: \(relay.snapshot())")
            return
        }
        XCTAssertEqual(greetingResponse, Data([0x05, 0x02]))
        let username = Array(credentials.username.utf8)
        let password = Array(credentials.password.utf8)
        var auth = Data([0x01, UInt8(username.count)])
        auth.append(contentsOf: username)
        auth.append(UInt8(password.count))
        auth.append(contentsOf: password)
        try send(client, auth)
        XCTAssertEqual(try receiveExactly(client, count: 2), Data([0x01, 0x00]))

        let host = Array("example.com".utf8)
        var request = Data([0x05, 0x01, 0x00, 0x03, UInt8(host.count)])
        request.append(contentsOf: host)
        request.append(contentsOf: [0x01, 0xbb])
        try send(client, request)
        let response = try receiveExactly(client, count: 10)
        XCTAssertEqual(response[0], 0x05, "Unexpected relay response: \(String(decoding: response, as: UTF8.self)), \(relay.snapshot())")
        XCTAssertEqual(response[1], 0x00)
        XCTAssertEqual(upstream.lastTarget, "example.com:443")
        try send(client, Data("ping".utf8))
        XCTAssertEqual(try receiveExactly(client, count: 4), Data("ping".utf8))
    }

    func testSOCKS5ClientWithoutAuthenticationUsesConfiguredUpstream() throws {
        let upstream = try FakeSOCKS5Proxy()
        defer { upstream.close() }
        let relay = LocalRelay()
        let port = try relay.start(
            upstream: IsolationUpstream(host: "127.0.0.1", port: upstream.port, protocolType: .socks5)
        )
        defer { relay.stop() }
        XCTAssertEqual(relay.socks5URL(), "socks5://127.0.0.1:\(port)")
        let client = try connect(port: port)
        defer { close(client) }

        try send(client, Data([0x05, 0x01, 0x00]))
        XCTAssertEqual(try receiveExactly(client, count: 2), Data([0x05, 0x00]))

        let host = Array("claude.ai".utf8)
        var request = Data([0x05, 0x01, 0x00, 0x03, UInt8(host.count)])
        request.append(contentsOf: host)
        request.append(contentsOf: [0x01, 0xbb])
        try send(client, request)
        let response = try receiveExactly(client, count: 10)
        XCTAssertEqual(response[0], 0x05)
        XCTAssertEqual(response[1], 0x00)
        XCTAssertEqual(upstream.lastTarget, "claude.ai:443")
        try send(client, Data("ping".utf8))
        XCTAssertEqual(try receiveExactly(client, count: 4), Data("ping".utf8))
    }

    private func connect(port: Int) throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(descriptor)
            throw POSIXError(error)
        }
        return descriptor
    }

    private func send(_ descriptor: Int32, _ data: Data) throws {
        let result = data.withUnsafeBytes { raw in
            Darwin.send(descriptor, raw.baseAddress, raw.count, 0)
        }
        guard result == data.count else { throw POSIXError(.EIO) }
    }

    private func readHeader(_ descriptor: Int32) throws -> Data {
        var result = Data()
        while result.range(of: Data("\r\n\r\n".utf8)) == nil {
            result.append(try receive(descriptor, maximum: 1024))
        }
        return result
    }

    private func receiveExactly(_ descriptor: Int32, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            result.append(try receive(descriptor, maximum: count - result.count))
        }
        return result
    }

    private func receive(_ descriptor: Int32, maximum: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: maximum)
        let count = Darwin.recv(descriptor, &bytes, maximum, 0)
        guard count > 0 else { throw POSIXError(.ECONNRESET) }
        return Data(bytes.prefix(count))
    }

    private func connectRequest(host: String, authorization: String? = nil) -> String {
        var request = "CONNECT \(host) HTTP/1.1\r\nHost: \(host)\r\n"
        if let authorization { request += "Proxy-Authorization: \(authorization)\r\n" }
        return request + "\r\n"
    }
}

private struct BasicProxyCredentials {
    var header: String
    var username: String
    var password: String

    init?(proxyURL: String) {
        guard let url = URL(string: proxyURL), let user = url.user, let password = url.password else { return nil }
        username = user
        self.password = password
        header = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }
}

private final class FakeHTTPConnectProxy: @unchecked Sendable {
    private let listener: Int32
    private let lock = NSLock()
    private var storedTarget = ""
    let port: Int

    var lastTarget: String { lock.withLock { storedTarget } }

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(descriptor, 16) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(descriptor)
            throw POSIXError(code)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        listener = descriptor
        port = Int(UInt16(bigEndian: bound.sin_port))
        DispatchQueue.global().async { [weak self] in self?.acceptLoop() }
    }

    func close() {
        shutdown(listener, SHUT_RDWR)
        Darwin.close(listener)
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { return }
            handle(client)
        }
    }

    private func handle(_ client: Int32) {
        defer { Darwin.close(client) }
        var request = Data()
        while request.range(of: Data("\r\n\r\n".utf8)) == nil {
            var bytes = [UInt8](repeating: 0, count: 1024)
            let count = Darwin.recv(client, &bytes, bytes.count, 0)
            if count <= 0 { return }
            request.append(contentsOf: bytes.prefix(count))
        }
        guard let text = String(data: request, encoding: .utf8),
              let line = text.split(separator: "\r\n").first else { return }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return }
        lock.withLock { storedTarget = String(parts[1]) }
        _ = Darwin.send(client, "HTTP/1.1 200 Connection Established\r\n\r\n", 39, 0)
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.recv(client, &bytes, bytes.count, 0)
            if count <= 0 { return }
            _ = bytes.withUnsafeBytes { Darwin.send(client, $0.baseAddress, count, 0) }
        }
    }
}

private final class FakeSOCKS5Proxy: @unchecked Sendable {
    private let listener: Int32
    private let lock = NSLock()
    private var storedTarget = ""
    let port: Int

    var lastTarget: String { lock.withLock { storedTarget } }

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(descriptor, 16) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(descriptor)
            throw POSIXError(code)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        listener = descriptor
        port = Int(UInt16(bigEndian: bound.sin_port))
        DispatchQueue.global().async { [weak self] in self?.acceptLoop() }
    }

    func close() {
        shutdown(listener, SHUT_RDWR)
        Darwin.close(listener)
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { return }
            handle(client)
        }
    }

    private func handle(_ client: Int32) {
        defer { Darwin.close(client) }
        guard let greeting = try? receive(client, 2),
              greeting[0] == 0x05,
              let methods = try? receive(client, Int(greeting[1])),
              methods.contains(0x00) else { return }
        _ = send(client, Data([0x05, 0x00]))
        guard let header = try? receive(client, 4), header[0] == 0x05, header[1] == 0x01 else { return }
        let host: String
        switch header[3] {
        case 0x03:
            guard let length = try? receive(client, 1),
                  let value = try? receive(client, Int(length[0])) else { return }
            host = String(decoding: value, as: UTF8.self)
        case 0x01:
            guard let value = try? receive(client, 4) else { return }
            host = value.map(String.init).joined(separator: ".")
        default:
            return
        }
        guard let portData = try? receive(client, 2) else { return }
        let targetPort = Int(UInt16(portData[0]) << 8 | UInt16(portData[1]))
        lock.withLock { storedTarget = "\(host):\(targetPort)" }
        _ = send(client, Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            if count <= 0 { return }
            _ = buffer.withUnsafeBytes { Darwin.send(client, $0.baseAddress, count, 0) }
        }
    }

    private func receive(_ descriptor: Int32, _ maximum: Int) throws -> Data {
        var result = Data()
        while result.count < maximum {
            var bytes = [UInt8](repeating: 0, count: maximum - result.count)
            let count = Darwin.recv(descriptor, &bytes, bytes.count, 0)
            guard count > 0 else { throw POSIXError(.ECONNRESET) }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }

    @discardableResult
    private func send(_ descriptor: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, data.count, 0) } == data.count
    }
}
