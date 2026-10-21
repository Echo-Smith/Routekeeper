import Foundation

/// A narrowly validated Claude desktop login callback. The original input may
/// contain a one-time secret, so callers must never log the raw value or errors
/// containing URL substrings.
public struct ClaudeLoginCallback: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case magicLink
        case ssoCallback
        case googleAuth

        fileprivate var path: String {
            switch self {
            case .magicLink: return "/magic-link"
            case .ssoCallback: return "/sso-callback"
            case .googleAuth: return "/google-auth"
            }
        }
    }

    public let kind: Kind
    public let host: String
    public let callbackURL: URL

    private init(kind: Kind, host: String, callbackURL: URL) {
        self.kind = kind
        self.host = host
        self.callbackURL = callbackURL
    }

    public static func parse(_ input: String) throws -> ClaudeLoginCallback {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw ClaudeLoginCallbackError.empty }
        guard raw.utf8.count <= 8_192 else { throw ClaudeLoginCallbackError.tooLong }
        guard raw.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }),
              !raw.contains("\\") else {
            throw ClaudeLoginCallbackError.invalidCharacters
        }
        guard let separator = raw.range(of: "://") else {
            throw ClaudeLoginCallbackError.malformed
        }

        let scheme = raw[..<separator.lowerBound].lowercased()
        guard scheme == "https" || scheme == "claude" else {
            throw ClaudeLoginCallbackError.unsupportedScheme
        }

        let remainder = raw[separator.upperBound...]
        guard let authorityEnd = remainder.firstIndex(where: { "/?#".contains($0) }) else {
            throw ClaudeLoginCallbackError.malformed
        }
        let authority = String(remainder[..<authorityEnd]).lowercased()
        guard ["claude.ai", "claude.com"].contains(authority),
              !authority.contains("@"),
              !authority.contains(":") else {
            throw ClaudeLoginCallbackError.untrustedHost
        }

        let suffix = remainder[authorityEnd...]
        let pathEnd = suffix.firstIndex(where: { "?#".contains($0) }) ?? suffix.endIndex
        let path = String(suffix[..<pathEnd])
        guard let kind = kind(forPath: path) else {
            throw ClaudeLoginCallbackError.unsupportedPath
        }

        let parameters = String(suffix[pathEnd...])
        let parsed = try parseParameters(parameters)
        switch kind {
        case .magicLink:
            try validateMagicLinkFragment(parsed.fragment)
        case .ssoCallback:
            guard let query = parsed.query, !query.isEmpty else {
                throw ClaudeLoginCallbackError.malformedCallback
            }
        case .googleAuth:
            guard let query = parsed.query,
                  query.split(separator: "&").contains(where: { item in
                      item.hasPrefix("code=") && item.dropFirst("code=".count).count >= 8
                  }) else {
                throw ClaudeLoginCallbackError.malformedCallback
            }
        }

        guard let callbackURL = URL(string: "claude://\(remainder)") else {
            throw ClaudeLoginCallbackError.malformed
        }
        return ClaudeLoginCallback(kind: kind, host: authority, callbackURL: callbackURL)
    }

    private static func kind(forPath path: String) -> Kind? {
        switch path {
        case Kind.magicLink.path: return .magicLink
        case Kind.ssoCallback.path: return .ssoCallback
        case Kind.googleAuth.path: return .googleAuth
        default: return nil
        }
    }

    private static func parseParameters(
        _ value: String
    ) throws -> (query: String?, fragment: String?) {
        guard !value.isEmpty else { return (nil, nil) }
        let fragmentParts = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard fragmentParts.count <= 2 else { throw ClaudeLoginCallbackError.malformed }

        var query: String?
        if var queryPart = fragmentParts.first.map(String.init), !queryPart.isEmpty {
            guard queryPart.first == "?" else { throw ClaudeLoginCallbackError.malformed }
            queryPart.removeFirst()
            guard !queryPart.isEmpty else { throw ClaudeLoginCallbackError.malformed }
            query = queryPart
        }
        let fragment = fragmentParts.count == 2 && !fragmentParts[1].isEmpty
            ? String(fragmentParts[1])
            : nil
        if fragmentParts.count == 2
            && (fragment == nil || fragmentParts[1].contains("#")) {
            throw ClaudeLoginCallbackError.malformedCallback
        }
        return (query, fragment)
    }

    private static func validateMagicLinkFragment(_ fragment: String?) throws {
        guard let fragment,
              fragment.filter({ $0 == ":" }).count == 1 else {
            throw ClaudeLoginCallbackError.malformedCallback
        }
        let tokens = fragment.split(separator: ":", omittingEmptySubsequences: false)
        guard tokens.count == 2 else { throw ClaudeLoginCallbackError.malformedCallback }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/="
        )
        guard tokens.allSatisfy({ token in
            token.count >= 8
                && token.unicodeScalars.allSatisfy(allowed.contains)
        }) else {
            throw ClaudeLoginCallbackError.malformedCallback
        }
    }
}

public enum ClaudeLoginCallbackError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case invalidCharacters
    case malformed
    case unsupportedScheme
    case untrustedHost
    case unsupportedPath
    case malformedCallback
}
