import Foundation

/// Permanent proxy-only restriction, independent of the UI's polling loop.
public struct FilterScope: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case uid, home, desktopRoots, desktopBundleIDs, desktopSigningIdentifiers
        case desktop, code, proxyHost, proxyPort
    }
    public var uid: UInt32
    public var home: String
    public var desktopRoots: [String]
    public var desktopBundleIDs: [String]
    public var desktopSigningIdentifiers: [String]
    public var desktop: Bool
    public var code: Bool
    public var proxyHost: String
    public var proxyPort: Int
    public init(uid: UInt32, home: String, desktopRoots: [String], desktop: Bool, code: Bool, proxyHost: String, proxyPort: Int,
                desktopBundleIDs: [String] = [], desktopSigningIdentifiers: [String] = []) {
        self.uid = uid; self.home = home; self.desktopRoots = desktopRoots
        self.desktopBundleIDs = desktopBundleIDs; self.desktopSigningIdentifiers = desktopSigningIdentifiers
        self.desktop = desktop; self.code = code; self.proxyHost = proxyHost; self.proxyPort = proxyPort
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(UInt32.self, forKey: .uid)
        home = try c.decode(String.self, forKey: .home)
        desktopRoots = try c.decodeIfPresent([String].self, forKey: .desktopRoots) ?? []
        desktopBundleIDs = try c.decodeIfPresent([String].self, forKey: .desktopBundleIDs) ?? []
        desktopSigningIdentifiers = try c.decodeIfPresent([String].self, forKey: .desktopSigningIdentifiers) ?? []
        desktop = try c.decode(Bool.self, forKey: .desktop)
        code = try c.decode(Bool.self, forKey: .code)
        proxyHost = try c.decode(String.self, forKey: .proxyHost)
        proxyPort = try c.decode(Int.self, forKey: .proxyPort)
    }
    public var valid: Bool {
        home.hasPrefix("/") && home != "/" && (desktop || code) &&
        ["127.0.0.1", "::1"].contains(proxyHost) && (1...65535).contains(proxyPort)
    }
    public func matches(path: String, owner: UInt32, arguments: [String] = [],
                        bundleID: String? = nil, signingIdentifier: String? = nil) -> Bool {
        guard valid, owner == uid else { return false }
        let identifiedDesktop = (bundleID.map(desktopBundleIDs.contains) ?? false) ||
            (signingIdentifier.map(desktopSigningIdentifiers.contains) ?? false)
        let kind: ProtectedKind? = identifiedDesktop ? .desktop :
            ProcessClassifier.classify(executable: path, arguments: arguments, desktopRoots: desktopRoots, home: home)
        guard let kind else { return false }
        return kind == .desktop ? desktop : code
    }
    public func permitsRemote(host: String?, port: Int?, isTCP: Bool) -> Bool {
        guard valid, isTCP, let host, let port else { return false }
        return IPAddress.normalized(host) == proxyHost && port == proxyPort
    }
}
