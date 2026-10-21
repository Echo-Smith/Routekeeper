import Foundation
import XCTest
@testable import GuardCore
@testable import Routekeeper

final class IsolationExecutionTests: XCTestCase {
    func testOfficialDesktopDaemonStartsUnderDesktopProfileWhenIntegrationPathIsProvided() throws {
        guard let appPath = ProcessInfo.processInfo.environment["ROUTEKEEPER_OFFICIAL_CLAUDE_APP"] else {
            throw XCTSkip("Set ROUTEKEEPER_OFFICIAL_CLAUDE_APP to run the signed-app integration check.")
        }
        let sandbox = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        guard FileManager.default.isExecutableFile(atPath: sandbox.path) else {
            throw XCTSkip("sandbox-exec is unavailable on this macOS version.")
        }

        let app = URL(fileURLWithPath: appPath, isDirectory: true)
        guard let installation = ClaudeDesktopDiscovery.inspect(at: app),
              installation.bundleIdentifier == ClaudeDesktopDiscovery.currentBundleIdentifier else {
            throw XCTSkip("This daemon check requires an official Claude Science bundle.")
        }
        let daemon = app.appendingPathComponent("Contents/Resources/bin/claude-science")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("routekeeper-desktop-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let exchange = root.appendingPathComponent("Exchange", isDirectory: true)
        let session = home.appendingPathComponent(
            "Library/Application Support/Routekeeper/Isolation/\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [home, exchange, session] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var configuration = IsolationConfiguration(
            projectPath: "",
            exchangePath: exchange.path,
            timezoneIdentifier: "Asia/Shanghai",
            target: .claudeDesktop
        )
        configuration.upstream = IsolationUpstream()
        let paths = try IsolationPathValidator.validate(
            configuration,
            sessionRoot: session,
            home: home
        )
        for directory in paths.layout.writablePaths + [paths.layout.control, paths.layout.logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let scienceHome = paths.layout.home.appendingPathComponent(".claude-science", isDirectory: true)
        try FileManager.default.createDirectory(at: scienceHome, withIntermediateDirectories: true)
        try Data("[sandbox]\nhard_fail = false\n".utf8).write(
            to: scienceHome.appendingPathComponent("config.toml")
        )
        let profileText = IsolationSandboxProfile.makeDesktop(
            paths: paths,
            applicationURL: app,
            relayPort: 43123
        )
        try Data(profileText.utf8).write(to: paths.layout.profile)

        let process = Process()
        let output = Pipe()
        process.executableURL = sandbox
        process.arguments = [
            "-f", paths.layout.profile.path,
            daemon.path,
            "serve",
            "--no-browser",
            "--port", "0",
            "--sandbox-port", "0",
            "--no-auto-update",
            "--verbose"
        ]
        process.currentDirectoryURL = paths.layout.workspace
        process.standardOutput = output
        process.standardError = output
        process.environment = [
            "HOME": paths.layout.home.path,
            "CFFIXED_USER_HOME": paths.layout.home.path,
            "TMPDIR": paths.layout.temporary.path,
            "TMP": paths.layout.temporary.path,
            "TEMP": paths.layout.temporary.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "zh_CN.UTF-8",
            "LC_ALL": "zh_CN.UTF-8",
            "LANGUAGE": "zh",
            "AppleLocale": "zh_CN",
            "TZ": "Asia/Shanghai",
            "ISOLATION_WORKSPACE": paths.layout.workspace.path,
            "ISOLATION_EXCHANGE": paths.exchange.path,
            "ISOLATION_ORIGINAL": "",
            "ISOLATION_CONTROL": paths.layout.control.path
        ]
        try process.run()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let running = process.isRunning
        let controlSocketExists = FileManager.default.fileExists(
            atPath: paths.layout.home.appendingPathComponent(".claude-science/daemon.sock").path
        )
        if running {
            terminateDescendants(of: process.processIdentifier)
            _ = Darwin.kill(process.processIdentifier, SIGTERM)
            let graceDeadline = Date().addingTimeInterval(0.75)
            while process.isRunning && Date() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                terminateDescendants(of: process.processIdentifier)
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        XCTAssertTrue(running, "Desktop daemon exited before becoming ready. Output:\n\(text)")
        XCTAssertTrue(controlSocketExists, "Science control socket was not created. Output:\n\(text)")
        XCTAssertFalse(text.contains("control socket: Error"), "Science control socket failed. Output:\n\(text)")
    }

    private func terminateDescendants(of rootPID: Int32) {
        for pid in descendantPIDs(of: rootPID).reversed() {
            _ = Darwin.kill(pid, SIGKILL)
        }
    }

    private func descendantPIDs(of rootPID: Int32) -> [Int32] {
        let result = Command.run("/bin/ps", ["-axo", "pid=,ppid="], timeout: 2)
        guard result.status == 0 else { return [] }
        var parentByChild: [Int32: Int32] = [:]
        for line in result.output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let parent = Int32(parts[1]) else { continue }
            parentByChild[pid] = parent
        }
        var pending = [rootPID]
        var children: [Int32] = []
        while let parent = pending.popLast() {
            let next = parentByChild.compactMap { $0.value == parent ? $0.key : nil }
            children.append(contentsOf: next)
            pending.append(contentsOf: next)
        }
        return children
    }

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
        /usr/bin/nc -l 127.0.0.1 0 >/dev/null 2>&1 &
        listener_pid=$!
        /bin/sleep 0.2
        if /bin/kill -0 "$listener_pid" >/dev/null 2>&1; then /bin/kill "$listener_pid" >/dev/null 2>&1 || true; exit 27; fi
        wait "$listener_pid" 2>/dev/null || true
        if /usr/bin/osascript -e 'path to application id "com.apple.Safari"' >/dev/null 2>&1; then exit 28; fi
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
            "ISOLATION_ORIGINAL": try XCTUnwrap(paths.originalProject).path,
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

    func testDesktopProfileWildcardListenerIsDetectedByRuntimeAudit() throws {
        let sandbox = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        guard FileManager.default.isExecutableFile(atPath: sandbox.path) else {
            throw XCTSkip("sandbox-exec is unavailable on this macOS version.")
        }

        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("routekeeper-listener-audit-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let exchange = root.appendingPathComponent("Exchange", isDirectory: true)
        let session = home.appendingPathComponent(
            "Library/Application Support/Routekeeper/Isolation/\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [home, exchange, session] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let configuration = IsolationConfiguration(
            projectPath: "",
            exchangePath: exchange.path,
            timezoneIdentifier: "Asia/Shanghai",
            target: .claudeDesktop
        )
        let paths = try IsolationPathValidator.validate(
            configuration,
            sessionRoot: session,
            home: home
        )
        for directory in paths.layout.writablePaths + [paths.layout.control, paths.layout.logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let profileText = IsolationSandboxProfile.makeDesktop(
            paths: paths,
            applicationURL: URL(fileURLWithPath: "/bin/sh"),
            relayPort: 43123
        )
        try Data(profileText.utf8).write(to: paths.layout.profile)
        let script = paths.layout.temporary.appendingPathComponent("wildcard-listener.sh")
        try Data(
            """
            /usr/bin/nc -l 0.0.0.0 0 >/dev/null 2>&1 &
            listener_pid=$!
            wait "$listener_pid"
            """.utf8
        ).write(to: script)

        let process = Process()
        process.executableURL = sandbox
        process.arguments = ["-f", paths.layout.profile.path, "/bin/sh", script.path]
        process.currentDirectoryURL = paths.layout.workspace
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = [
            "HOME": paths.layout.home.path,
            "TMPDIR": paths.layout.temporary.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "ISOLATION_WORKSPACE": paths.layout.workspace.path,
            "ISOLATION_EXCHANGE": paths.exchange.path,
            "ISOLATION_ORIGINAL": "",
            "ISOLATION_CONTROL": paths.layout.control.path
        ]
        try process.run()
        defer {
            terminateDescendants(of: process.processIdentifier)
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }

        var audit: ListenerAuditResult?
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.1)
            let pids = [process.processIdentifier] + descendantPIDs(of: process.processIdentifier)
            audit = SandboxSession.auditLoopbackListeners(pids: pids)
            if audit?.nonLoopback.isEmpty == false { break }
        }

        XCTAssertNil(audit?.error)
        XCTAssertFalse(
            audit?.nonLoopback.isEmpty ?? true,
            "The listener audit did not detect a wildcard TCP bind."
        )
        XCTAssertTrue(audit?.nonLoopback.contains(where: { $0.contains("*:") }) == true)
    }

    func testDesktopProfileExposesInterfaceMetadataButBlocksDirectNetwork() throws {
        let sandbox = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        guard FileManager.default.isExecutableFile(atPath: sandbox.path) else {
            throw XCTSkip("sandbox-exec is unavailable on this macOS version.")
        }

        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("routekeeper-interface-metadata-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let exchange = root.appendingPathComponent("Exchange", isDirectory: true)
        let session = home.appendingPathComponent(
            "Library/Application Support/Routekeeper/Isolation/\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [home, exchange, session] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let configuration = IsolationConfiguration(
            projectPath: "",
            exchangePath: exchange.path,
            timezoneIdentifier: "Asia/Shanghai",
            target: .claudeDesktop
        )
        let paths = try IsolationPathValidator.validate(
            configuration,
            sessionRoot: session,
            home: home
        )
        for directory in paths.layout.writablePaths + [paths.layout.control, paths.layout.logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let script = paths.layout.temporary.appendingPathComponent("interface-metadata.sh")
        let scriptText = """
        metadata=0
        if /usr/sbin/ipconfig getiflist >/dev/null 2>&1 && /sbin/ifconfig -a >/dev/null 2>&1; then
          metadata=1
        fi
        direct=0
        if /usr/bin/curl --noproxy '*' --silent --connect-timeout 1 --max-time 2 http://1.1.1.1 >/dev/null 2>&1; then
          direct=1
        fi
        printf 'metadata=%s direct=%s' "$metadata" "$direct" > "$ISOLATION_WORKSPACE/result"
        """
        try Data(scriptText.utf8).write(to: script)
        let profileText = IsolationSandboxProfile.makeDesktop(
            paths: paths,
            applicationURL: URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true),
            relayPort: 43123
        )
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
            "ISOLATION_WORKSPACE": paths.layout.workspace.path,
            "ISOLATION_EXCHANGE": paths.exchange.path,
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

        XCTAssertEqual(process.terminationStatus, 0, "sandbox profile output: \(text)")
        XCTAssertEqual(
            resultText,
            "metadata=1 direct=0",
            "Seatbelt should expose interface metadata while blocking direct egress"
        )
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
