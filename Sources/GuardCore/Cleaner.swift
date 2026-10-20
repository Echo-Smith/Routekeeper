import Foundation

/// Cleanup targets are intentionally conservative: only cache and log
/// directories that Claude recreates automatically. Never session data,
/// credentials, configuration, memory, or browser data.
public struct CleanupTarget: Identifiable, Sendable, Equatable {
    public var path: String
    public var label: String
    public var kind: String
    public var sizeBytes: Int64
 public var fileCount: Int
    public var exists: Bool
    public var id: String { path }
    public init(path: String, label: String, kind: String,
                sizeBytes: Int64 = 0, fileCount: Int = 0, exists: Bool = false) {
        self.path = path; self.label = label; self.kind = kind
        self.sizeBytes = sizeBytes; self.fileCount = fileCount; self.exists = exists
    }
}

public struct CleanupPlan: Sendable {
    public var targets: [CleanupTarget]
    public var totalBytes: Int64 { targets.reduce(0) { $0 + $1.sizeBytes } }
    public var totalFiles: Int { targets.reduce(0) { $0 + $1.fileCount } }
    public var availableCount: Int { targets.filter(\.exists).count }
}

public enum CacheCleaner {
    /// Explicit safe paths only. Adding a path requires updating this list,
    /// the UI description, and the unit tests together.
    public static func safePaths(home: String) -> [(path: String, label: String, kind: String)] {
        [
            (home + "/Library/Caches/Claude", "Claude 桌面版缓存", "HTTP 与图片缓存"),
            (home + "/Library/Caches/com.anthropic.claudefordesktop", "Claude 桌面版缓存（Bundle）", "系统级应用缓存"),
            (home + "/Library/Logs/Claude", "Claude 桌面版日志", "诊断与崩溃日志"),
            (home + "/.claude/statsig", "Claude Code 缓存", "功能开关与统计缓存"),
        ]
    }

    public static func scan(home: String) -> CleanupPlan {
        let fm = FileManager.default
        let targets = safePaths(home: home).map { entry -> CleanupTarget in
            let path = entry.path
            var size: Int64 = 0; var count = 0
            let exists = fm.fileExists(atPath: path)
            if exists {
                (size, count) = directorySize(path)
            }
            return CleanupTarget(path: path, label: entry.label, kind: entry.kind,
                                 sizeBytes: size, fileCount: count, exists: exists)
        }
        return CleanupPlan(targets: targets)
    }

    static func directorySize(_ path: String) -> (Int64, Int) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return (0, 0) }
        var total: Int64 = 0; var count = 0
        while let relative = enumerator.nextObject() as? String {
            let full = path + "/" + relative
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let type = attrs[.type] as? FileAttributeType else { continue }
            if type == .typeRegular || type == .typeSymbolicLink {
                total += (attrs[.size] as? NSNumber)?.int64Value ?? 0
                count += 1
            }
        }
        return (total, count)
    }

    /// Moves the directory to Trash. Recoverable; never uses unlink/rm.
    @discardableResult
    public static func trash(_ path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return true }
        do {
            try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return true
        } catch { return false }
    }
}
