import Foundation
import AppKit
import SystemConfiguration
import Darwin

public struct CommandResult: Sendable { public var status: Int32; public var output: String }
public enum Command {
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 8) -> CommandResult {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        // The probes never inherit proxy credentials, curl settings, or user shell initialization.
        p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "HOME": NSHomeDirectory()]
        do { try p.run() } catch { return .init(status: -1, output: "无法执行 \(URL(fileURLWithPath: path).lastPathComponent)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if p.isRunning { p.terminate(); Thread.sleep(forTimeInterval: 0.1); if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return .init(status: p.terminationStatus, output: String(decoding: data.prefix(64_000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
public struct ProxyEndpoint: Sendable, Equatable {
    public var host: String; public var port: Int
    public var url: String { "http://\(host.contains(":") ? "[\(host)]" : host):\(port)" }
    public var isLoopback: Bool { ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) }
    public static func current() -> ProxyEndpoint? {
        guard let dict = SCDynamicStoreCopyProxies(nil) as? [String: Any],
              (dict["HTTPSEnable"] as? NSNumber)?.boolValue == true,
              let host = dict["HTTPSProxy"] as? String,
              let port = dict["HTTPSPort"] as? NSNumber, (1...65535).contains(port.intValue) else { return nil }
        return .init(host: host, port: port.intValue)
    }
}
public enum ApplicationDiscovery {
    public static let desktopID = "com.anthropic.claudefordesktop"
    public static let flClashID = "com.follow.clash"
    public static func path(bundleID: String, name: String) -> String? {
        let candidates: [String?] = [NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path,
                          "/Applications/\(name).app", NSHomeDirectory() + "/Applications/\(name).app"]
        return candidates.compactMap { $0 }.first { Bundle(path: $0)?.bundleIdentifier == bundleID }
    }
    public static func codePathsInstalled() -> Bool {
        let home = NSHomeDirectory()
        let roots = [home + "/.local/bin/claude", home + "/.npm-global/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/Caskroom/claude-code", "/usr/local/Caskroom/claude-code"]
        if roots.contains(where: { FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0) }) { return true }
        for editor in [".vscode", ".cursor", ".vscode-insiders"] {
            let dir = home + "/\(editor)/extensions"
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir),
               entries.contains(where: { $0.hasPrefix("anthropic.claude-code-") }) { return true }
        }
        return false
    }
    public static func codePaths() -> [String] {
        let home = NSHomeDirectory()
        var candidates = [home + "/.local/bin/claude", home + "/.npm-global/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        let nvm = home + "/.nvm/versions/node"
        candidates += ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).map { nvm + "/\($0)/bin/claude" }
        for editor in [".vscode", ".cursor", ".vscode-insiders"] {
            let root = home + "/\(editor)/extensions"
            candidates += ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
                .filter { $0.hasPrefix("anthropic.claude-code-") }
                .map { root + "/\($0)/resources/native-binary/claude" }
        }
        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
public struct ProcessScan: Sendable {
    public var records: [ProcessIdentity]
    public var available: Bool
}
public enum LocalProcesses {
    /// Only argv[0..1]; no prompts, environment or persistent logging.
    public static func classificationArguments(_ pid: Int32) -> [String] { arguments(pid) }
    public static func ownExecutablePaths() -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var ids = [Int32](repeating: 0, count: Int(count) + 1024)
        let actual = proc_listallpids(&ids, Int32(ids.count * MemoryLayout<Int32>.size))
        guard actual > 0 else { return [] }
        return ids.prefix(min(Int(actual), ids.count)).compactMap { pid in
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  info.pbi_uid == getuid() else { return nil }
            return executable(pid)
        }
    }
    private static func executable(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
    private static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 4, size < 2_000_000 else { return [] }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return [] }
        let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc < 100_000 else { return [] }
        var offset = 4
        while offset < size && data[offset] != 0 { offset += 1 }
        while offset < size && data[offset] == 0 { offset += 1 }
        var result: [String] = []
        // Only argv[0] and argv[1] are needed. Never persist arguments or environment.
        for _ in 0..<min(Int(argc), 2) {
            let start = offset
            while offset < size && data[offset] != 0 { offset += 1 }
            result.append(String(decoding: data[start..<offset], as: UTF8.self)); offset += 1
            if offset >= size { break }
        }
        return result
    }
    public static func identity(_ pid: Int32, desktopRoots: [String]) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), let path = executable(pid) else { return nil }
        var args = URL(fileURLWithPath: path).lastPathComponent == "node" ? arguments(pid) : []
        if args.count > 1, args[1].hasPrefix("/") { args[1] = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath().path }
        guard let kind = ProcessClassifier.classify(executable: path, arguments: args, desktopRoots: desktopRoots, home: NSHomeDirectory()) else { return nil }
        return .init(pid: pid, uid: info.pbi_uid, startSeconds: info.pbi_start_tvsec,
                     startMicroseconds: info.pbi_start_tvusec, executable: path, kind: kind)
    }
    public static func scan(desktopRoots: [String]) -> ProcessScan {
        var ownInfo = proc_bsdinfo()
        guard proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &ownInfo, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
              executable(getpid()) != nil else { return .init(records: [], available: false) }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return .init(records: [], available: false) }
        var ids = [Int32](repeating: 0, count: Int(count) + 1024)
        let actual = proc_listallpids(&ids, Int32(ids.count * MemoryLayout<Int32>.size))
        guard actual > 0 else { return .init(records: [], available: false) }
        let records = ids.prefix(min(Int(actual), ids.count)).filter { $0 != getpid() }.compactMap { identity($0, desktopRoots: desktopRoots) }
        return .init(records: records, available: true)
    }
    public static func requestExit(_ record: ProcessIdentity, settings: GuardSettings, desktopRoots: [String]) -> String {
        guard ProcessClassifier.mayTerminate(record: record, current: identity(record.pid, desktopRoots: desktopRoots), settings: settings, uid: getuid()) else {
            return "PID \(record.pid)：已退出、身份变化或不在所选范围，未发送信号"
        }
        return kill(record.pid, SIGTERM) == 0 ? "PID \(record.pid)：已发送退出请求，等待进程结束" : "PID \(record.pid)：退出请求失败（\(errno)），请手动处理"
    }
}
