import AppKit
import Foundation
import Security

public struct ClaudeWebBrowserInstallation: Equatable, Sendable {
    public var appURL: URL
    public var executableURL: URL
    public var bundleIdentifier: String
    public var displayName: String
    public var signingIdentifier: String
    public var teamIdentifier: String
    public var shortVersion: String?
    public var bundleVersion: String?

    public init(
        appURL: URL,
        executableURL: URL,
        bundleIdentifier: String,
        displayName: String,
        signingIdentifier: String,
        teamIdentifier: String,
        shortVersion: String?,
        bundleVersion: String?
    ) {
        self.appURL = appURL
        self.executableURL = executableURL
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.shortVersion = shortVersion
        self.bundleVersion = bundleVersion
    }
}

public enum ClaudeWebBrowserDiscovery {
    public static let bundleIdentifier = "com.google.Chrome"
    public static let teamIdentifier = "EQHXZ8M8AV"
    public static let claudeURL = URL(string: "https://claude.ai/")!

    /// Validate Google's official Chrome bundle before using it with a
    /// Routekeeper-owned browser profile.
    public static func locate(workspace: NSWorkspace = .shared) -> ClaudeWebBrowserInstallation? {
        var candidates: [String] = []
        if let registered = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            candidates.append(registered.path)
        }
        candidates.append("/Applications/Google Chrome.app")
        candidates.append(NSHomeDirectory() + "/Applications/Google Chrome.app")

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if let installation = inspect(at: URL(fileURLWithPath: path, isDirectory: true)) {
                return installation
            }
        }
        return nil
    }

    public static func inspect(at appURL: URL) -> ClaudeWebBrowserInstallation? {
        let appURL = appURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == bundleIdentifier,
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

        return ClaudeWebBrowserInstallation(
            appURL: appURL,
            executableURL: executableURL,
            bundleIdentifier: bundleIdentifier,
            displayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "Google Chrome",
            signingIdentifier: signingIdentifier,
            teamIdentifier: teamIdentifier,
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            bundleVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
