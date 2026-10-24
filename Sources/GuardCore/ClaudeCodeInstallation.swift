import Foundation

public enum ClaudeCodeInstallationSource: String, Equatable, Sendable {
    case automatic
    case manuallySelected
}

public struct ClaudeCodeInstallation: Equatable, Sendable {
    public var executableURL: URL
    public var canonicalURL: URL
    public var source: ClaudeCodeInstallationSource

    public init(
        executableURL: URL,
        canonicalURL: URL,
        source: ClaudeCodeInstallationSource
    ) {
        self.executableURL = executableURL
        self.canonicalURL = canonicalURL
        self.source = source
    }
}

public enum ClaudeCodeDiscovery {
    public static let manualPathPreferenceKey = "routekeeper-claude-code-command-path-v1"

    /// Locate an executable `claude` command without reading its output or user data.
    public static func locate(manualPath: String? = nil) -> ClaudeCodeInstallation? {
        let manual = manualPath.flatMap {
            inspect(path: $0, source: .manuallySelected)
        }
        if let manual {
            return manual
        }

        var seen = Set<String>()
        for path in ApplicationDiscovery.codePaths() {
            guard let installation = inspect(path: path),
                  seen.insert(installation.canonicalURL.path).inserted else {
                continue
            }
            return installation
        }
        return nil
    }

    public static func inspect(
        executableURL: URL,
        source: ClaudeCodeInstallationSource = .automatic
    ) -> ClaudeCodeInstallation? {
        inspect(path: executableURL.path, source: source)
    }

    public static func inspect(
        path: String,
        source: ClaudeCodeInstallationSource = .automatic
    ) -> ClaudeCodeInstallation? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }

        let executableURL = URL(fileURLWithPath: expanded).standardizedFileURL
        guard executableURL.lastPathComponent == "claude",
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }

        return ClaudeCodeInstallation(
            executableURL: executableURL,
            canonicalURL: executableURL.resolvingSymlinksInPath(),
            source: source
        )
    }
}
