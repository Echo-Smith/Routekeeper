import Foundation

public enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(currentVersion: String)
    case available(
        currentVersion: String,
        latestVersion: String,
        packageURL: URL,
        releaseURL: URL
    )
}

public enum AppUpdateCheckError: Error, Equatable {
    case invalidResponse
    case invalidVersion(String)
    case missingPackage
}

public enum AppUpdateCheck {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let releaseURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case releaseURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    public static func evaluate(
        releaseData: Data,
        currentVersion: String
    ) throws -> AppUpdateCheckResult {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: releaseData)
        } catch {
            throw AppUpdateCheckError.invalidResponse
        }

        let latestVersion = displayVersion(release.tagName)
        guard let latestComponents = versionComponents(latestVersion) else {
            throw AppUpdateCheckError.invalidVersion(release.tagName)
        }
        guard let currentComponents = versionComponents(currentVersion) else {
            throw AppUpdateCheckError.invalidVersion(currentVersion)
        }
        guard let package = release.assets.first(where: {
            $0.name.lowercased().hasSuffix(".dmg")
        }) else {
            throw AppUpdateCheckError.missingPackage
        }

        guard compare(latestComponents, currentComponents) > 0 else {
            return .upToDate(currentVersion: displayVersion(currentVersion))
        }
        return .available(
            currentVersion: displayVersion(currentVersion),
            latestVersion: latestVersion,
            packageURL: package.downloadURL,
            releaseURL: release.releaseURL
        )
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidateComponents = versionComponents(candidate),
              let currentComponents = versionComponents(current) else {
            return false
        }
        return compare(candidateComponents, currentComponents) > 0
    }

    private static func displayVersion(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.first?.lowercased() == "v" {
            result.removeFirst()
        }
        return result
    }

    private static func versionComponents(_ value: String) -> [Int]? {
        let version = displayVersion(value)
        guard let core = version.split(whereSeparator: { $0 == "-" || $0 == "+" }).first,
              !core.isEmpty else {
            return nil
        }

        var result: [Int] = []
        for component in core.split(separator: ".", omittingEmptySubsequences: false) {
            let digits = component.prefix(while: \.isNumber)
            guard !digits.isEmpty, let number = Int(digits) else { return nil }
            result.append(number)
        }
        while result.count > 1, result.last == 0 {
            result.removeLast()
        }
        return result
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }
        return 0
    }
}
