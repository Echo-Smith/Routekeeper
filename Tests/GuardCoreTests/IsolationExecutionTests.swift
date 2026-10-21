import Foundation
import XCTest
@testable import GuardCore

final class IsolationExecutionTests: XCTestCase {
    func testGeneratedProfileBlocksOutsideWritesAndDirectNetworkForChildProcesses() throws {
        let sandbox = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        guard FileManager.default.isExecutableFile(atPath: sandbox.path) else {
            throw XCTSkip("sandbox-exec is unavailable on this macOS version.")
        }

        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("routekeeper-profile-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = home.appendingPathComponent("Projects/App", isDirectory: true)
        let exchange = home.appendingPathComponent("Exchange", isDirectory: true)
        let session = home.appendingPathComponent(
            "Library/Application Support/Routekeeper/Isolation/\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [project, exchange, session] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let config = IsolationConfiguration(
            projectPath: project.path,
            exchangePath: exchange.path,
            timezoneIdentifier: "Asia/Shanghai",
            upstream: IsolationUpstream()
        )
        let paths = try IsolationPathValidator.validate(config, sessionRoot: session, home: home)
        for directory in paths.layout.writablePaths + [paths.layout.control] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let canary = paths.layout.control.appendingPathComponent("canary")
        try Data("private".utf8).write(to: canary)
        let relay = try LoopbackListener()
        defer { relay.close() }
        let script = paths.layout.temporary.appendingPathComponent("self-check.sh")
        let scriptText = """
        set -u
        printf 'workspace-ok' > "$ISOLATION_WORKSPACE/inside"
        printf 'exchange-ok' > "$ISOLATION_EXCHANGE/inside"
        if printf 'must-not-write' > "$ISOLATION_ORIGINAL/forbidden" 2>/dev/null; then exit 20; fi
        /bin/sh -c 'printf "must-not-write" > "$ISOLATION_ORIGINAL/nested"' 2>/dev/null && exit 21
        if /bin/cat "$ISOLATION_CONTROL/canary" >/dev/null 2>&1; then exit 22; fi
        if /usr/bin/curl --noproxy '*' --silent --connect-timeout 1 --max-time 2 http://1.1.1.1 >/dev/null 2>&1; then exit 23; fi
        if /usr/bin/host -W 1 example.com >/dev/null 2>&1; then exit 24; fi
        if /usr/bin/nc -u -z -w 1 1.1.1.1 53 >/dev/null 2>&1; then exit 25; fi
        if ! /usr/bin/nc -z -w 1 127.0.0.1 \(relay.port) >/dev/null 2>&1; then exit 26; fi
        printf 'profile-passed' > "$ISOLATION_WORKSPACE/result"
        """
        try Data(scriptText.utf8).write(to: script)
        let profileText = IsolationSandboxProfile.make(
            paths: paths,
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            relayPort: relay.port
        )
        for directory in [paths.layout.control] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(profileText.utf8).write(to: paths.layout.profile)

        let process = Process()
        let output = Pipe()
        process.executableURL = sandbox
        process.arguments = ["-f", paths.layout.profile.path, "/bin/sh", script.path]
        process.standardOutput = output
        process.standardError = output
        process.currentDirectoryURL = paths.layout.workspace
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": paths.layout.home.path,
            "TMPDIR": paths.layout.temporary.path,
            "TZ": "Asia/Shanghai",
            "ISOLATION_WORKSPACE": paths.layout.workspace.path,
            "ISOLATION_EXCHANGE": paths.exchange.path,
            "ISOLATION_ORIGINAL": paths.originalProject.path,
            "ISOLATION_CONTROL": paths.layout.control.path
        ]
        try process.run()
        process.waitUntilExit()
        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let resultText = (try? String(
            contentsOf: paths.layout.workspace.appendingPathComponent("result"),
            encoding: .utf8
        )) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, "sandbox profile output: \(text), profile:\n\(profileText)")
        XCTAssertEqual(resultText, "profile-passed", "sandbox profile output: \(text)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.layout.workspace.appendingPathComponent("inside").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.exchange.appendingPathComponent("inside").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("forbidden").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("nested").path))
    }
}

private final class LoopbackListener {
    private let descriptor: Int32
    let port: Int

    init() throws {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.ENOTSOCK) }
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(socketFD, 4) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(code)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        descriptor = socketFD
        port = Int(UInt16(bigEndian: bound.sin_port))
        DispatchQueue.global().async { [weak self] in
            while let self {
                let client = accept(self.descriptor, nil, nil)
                if client < 0 { return }
                Darwin.close(client)
            }
        }
    }

    func close() {
        shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }
}
