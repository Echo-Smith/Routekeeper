import AppKit
import Foundation
import Security

public enum ClaudeDesktopRuntimeFamily: String, Equatable, Sendable {
    case electron
    case operonHostedWeb
}

public struct ClaudeDesktopInstallation: Equatable, Sendable {
    public var appURL: URL
    public var executableURL: URL
    public var scienceWebExecutableURL: URL?
    public var bundleIdentifier: String
    public var displayName: String
    public var signingIdentifier: String?
    public var teamIdentifier: String?
    public var shortVersion: String?
    public var bundleVersion: String?

    public init(
        appURL: URL,
        executableURL: URL,
        scienceWebExecutableURL: URL?,
        bundleIdentifier: String,
        displayName: String,
        signingIdentifier: String?,
        teamIdentifier: String?,
        shortVersion: String?,
        bundleVersion: String?
    ) {
        self.appURL = appURL
        self.executableURL = executableURL
        self.scienceWebExecutableURL = scienceWebExecutableURL
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.shortVersion = shortVersion
        self.bundleVersion = bundleVersion
    }

    public var runtimeFamily: ClaudeDesktopRuntimeFamily {
        bundleIdentifier == ClaudeDesktopDiscovery.currentBundleIdentifier
            ? .operonHostedWeb
            : .electron
    }

    public var supportsIsolatedLaunch: Bool {
        runtimeFamily == .electron || scienceWebExecutableURL != nil
    }
}

public enum ClaudeDesktopDiscovery {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"
    public static let currentBundleIdentifier = "com.anthropic.operon"
    public static let supportedBundleIdentifiers = [
        bundleIdentifier,
        currentBundleIdentifier
    ]
    public static let teamIdentifier = "Q6L2SF6YDW"

    /// Locate and validate the installed official client without launching it.
    public static func locate(workspace: NSWorkspace = .shared) -> ClaudeDesktopInstallation? {
        var candidates: [String] = []
        for identifier in supportedBundleIdentifiers {
            if let registered = workspace.urlForApplication(withBundleIdentifier: identifier) {
                candidates.append(registered.path)
            }
        }
        candidates.append("/Applications/Claude.app")
        candidates.append("/Applications/Claude Science.app")
        candidates.append(NSHomeDirectory() + "/Applications/Claude.app")
        candidates.append(NSHomeDirectory() + "/Applications/Claude Science.app")
        let volumeKeys: Set<URLResourceKey> = [.volumeIsLocalKey]
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(volumeKeys),
            options: [.skipHiddenVolumes]
        ) ?? []
        for volume in mountedVolumes {
            // App discovery must never read a network volume just to look for Claude.
            guard (try? volume.resourceValues(forKeys: volumeKeys).volumeIsLocal) == true else {
                continue
            }
            for name in ["Claude.app", "Claude Science.app"] {
                candidates.append(volume.appendingPathComponent(name).path)
                candidates.append(volume.appendingPathComponent("Applications/\(name)").path)
            }
        }

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if let installation = inspect(at: URL(fileURLWithPath: path, isDirectory: true)) {
                return installation
            }
        }
        return nil
    }

    /// Validate the bundle identity and Apple code signature before an isolated launch.
    public static func inspect(at appURL: URL) -> ClaudeDesktopInstallation? {
        let appURL = appURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let bundle = Bundle(url: appURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              supportedBundleIdentifiers.contains(bundleIdentifier),
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(
                    rawValue: kSecCSCheckAllArchitectures
                        | kSecCSCheckNestedCode
                        | kSecCSStrictValidate
                ),
                nil
              ) == errSecSuccess else {
            return nil
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let values = signingInformation as? [String: Any],
        let signingIdentifier = values[kSecCodeInfoIdentifier as String] as? String,
        signingIdentifier == bundleIdentifier,
        let teamIdentifier = values[kSecCodeInfoTeamIdentifier as String] as? String,
        teamIdentifier == Self.teamIdentifier else {
            return nil
        }

        let scienceWebExecutableURL = bundleIdentifier == currentBundleIdentifier
            ? hostedScienceWebExecutable(at: appURL)
            : nil
        return ClaudeDesktopInstallation(
            appURL: appURL,
            executableURL: executableURL,
            scienceWebExecutableURL: scienceWebExecutableURL,
            bundleIdentifier: bundleIdentifier,
            displayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "Claude Desktop",
            signingIdentifier: signingIdentifier,
            teamIdentifier: teamIdentifier,
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            bundleVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    private static func hostedScienceWebExecutable(at appURL: URL) -> URL? {
        let executable = appURL
            .appendingPathComponent("Contents/Resources/bin/claude-science", isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              signingIdentity(
                at: executable,
                expectedIdentifier: "com.anthropic.operon.cli",
                checkNestedCode: false
              ) != nil else {
            return nil
        }
        return executable
    }

    private static func signingIdentity(
        at codeURL: URL,
        expectedIdentifier: String,
        checkNestedCode: Bool
    ) -> (identifier: String, team: String)? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(codeURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }
        var flags = kSecCSCheckAllArchitectures | kSecCSStrictValidate
        if checkNestedCode { flags |= kSecCSCheckNestedCode }
        guard SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: flags), nil) == errSecSuccess else {
            return nil
        }
        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let values = signingInformation as? [String: Any],
        let identifier = values[kSecCodeInfoIdentifier as String] as? String,
        identifier == expectedIdentifier,
        let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
        team == teamIdentifier else {
            return nil
        }
        return (identifier, team)
    }

    /// Claude Desktop normally enforces a single running instance. Returning a
    /// clear error is safer than letting it activate an instance outside the sandbox.
    public static func runningBundleIdentifiers() -> Set<String> {
        Set(
            supportedBundleIdentifiers.filter {
                !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
            }
        )
    }
}
