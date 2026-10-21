import CryptoKit
import Darwin
import Foundation

public enum HandoffActionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case exportFile = "file.export"
    case applyGitPatch = "git.applyPatch"
}

public struct HandoffActionRequest: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var requestID: UUID
    public var kind: HandoffActionKind
    public var title: String
    public var summary: String
    public var payload: String
    public var suggestedName: String

    public var id: UUID { requestID }

    public init(
        schemaVersion: Int = 1,
        requestID: UUID,
        kind: HandoffActionKind,
        title: String,
        summary: String,
        payload: String,
        suggestedName: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.payload = payload
        self.suggestedName = suggestedName
    }
}

public struct HandoffActionPackage: Equatable, Identifiable, Sendable {
    public var request: HandoffActionRequest
    public var manifestName: String
    public var payloadData: Data
    public var payloadSHA256: String

    public var id: String {
        "\(request.requestID.uuidString)-\(payloadSHA256.prefix(12))"
    }

    public var payloadBytes: Int { payloadData.count }
}

public struct HandoffScanIssue: Equatable, Identifiable, Sendable {
    public var id: String { "\(manifestName)-\(message)" }
    public var manifestName: String
    public var message: String

    public init(manifestName: String, message: String) {
        self.manifestName = manifestName
        self.message = message
    }
}

public struct HandoffScanResult: Equatable, Sendable {
    public var packages: [HandoffActionPackage]
    public var issues: [HandoffScanIssue]

    public init(packages: [HandoffActionPackage] = [], issues: [HandoffScanIssue] = []) {
        self.packages = packages
        self.issues = issues
    }
}

public enum HandoffActionScanner {
    public static let directoryName = ".routekeeper-actions"
    public static let maximumManifestBytes = 16 * 1024
    public static let maximumFileExportBytes = 8 * 1024 * 1024
    public static let maximumGitPatchBytes = 16 * 1024 * 1024
    public static let maximumPackages = 16
    public static let maximumManifests = 128
    public static let maximumTotalPayloadBytes = 32 * 1024 * 1024

    public static func prepareDirectory(in exchange: URL) throws -> URL {
        let exchange = exchange.standardizedFileURL
        var exchangeInfo = stat()
        let exchangeStatus = exchange.path.withCString { lstat($0, &exchangeInfo) }
        guard exchangeStatus == 0,
              (exchangeInfo.st_mode & S_IFMT) == S_IFDIR else {
            throw HandoffActionError.invalidExchangeDirectory
        }

        let directory = exchange.appendingPathComponent(directoryName, isDirectory: true)
        var info = stat()
        let directoryStatus = directory.path.withCString { lstat($0, &info) }
        if directoryStatus == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR else {
                throw HandoffActionError.invalidHandoffDirectory
            }
        } else if errno == ENOENT {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            throw HandoffActionError.invalidHandoffDirectory
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let readme = directory.appendingPathComponent("README.txt", isDirectory: false)
        if !FileManager.default.fileExists(atPath: readme.path) {
            try Data(Self.readme.utf8).write(to: readme, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: readme.path)
        }
        return directory
    }

    public static func scan(exchange: URL, notBefore: Date? = nil) -> HandoffScanResult {
        let directory: URL
        do {
            directory = try prepareDirectory(in: exchange)
        } catch {
            return HandoffScanResult(
                issues: [.init(manifestName: directoryName, message: error.localizedDescription)]
            )
        }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .filter { url in
                guard let notBefore else { return true }
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                return modified.map { $0 >= notBefore } ?? false
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            return HandoffScanResult(
                issues: [.init(manifestName: directoryName, message: "Unable to read handoff directory.")]
            )
        }

        var issues: [HandoffScanIssue] = []
        let manifests: ArraySlice<URL>
        if urls.count > maximumManifests {
            issues.append(.init(
                manifestName: directoryName,
                message: "Too many handoff manifests; only the first \(maximumManifests) were scanned."
            ))
            manifests = urls.prefix(maximumManifests)
        } else {
            manifests = urls[...]
        }

        var packages: [HandoffActionPackage] = []
        var requestIDs = Set<UUID>()
        var totalBytes = 0

        for manifestURL in manifests {
            if packages.count >= maximumPackages {
                issues.append(.init(
                    manifestName: manifestURL.lastPathComponent,
                    message: "Too many pending actions; remaining manifests were ignored."
                ))
                break
            }

            do {
                let manifestData = try readRegularFile(
                    at: manifestURL,
                    maximumBytes: maximumManifestBytes,
                    requireCurrentUser: true
                )
                let request = try JSONDecoder().decode(HandoffActionRequest.self, from: manifestData)
                try validate(request)
                guard requestIDs.insert(request.requestID).inserted else {
                    throw HandoffActionError.duplicateRequestID
                }

                let payloadURL = directory.appendingPathComponent(request.payload, isDirectory: false)
                let maximumPayloadBytes = request.kind == .applyGitPatch
                    ? maximumGitPatchBytes
                    : maximumFileExportBytes
                let payloadData = try readRegularFile(
                    at: payloadURL,
                    maximumBytes: maximumPayloadBytes,
                    requireCurrentUser: true
                )
                guard totalBytes + payloadData.count <= maximumTotalPayloadBytes else {
                    throw HandoffActionError.totalPayloadTooLarge
                }
                totalBytes += payloadData.count
                let digest = SHA256.hash(data: payloadData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                packages.append(
                    .init(
                        request: request,
                        manifestName: manifestURL.lastPathComponent,
                        payloadData: payloadData,
                        payloadSHA256: digest
                    )
                )
            } catch {
                issues.append(
                    .init(
                        manifestName: manifestURL.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return HandoffScanResult(packages: packages, issues: issues)
    }

    public static func validate(_ request: HandoffActionRequest) throws {
        guard request.schemaVersion == 1 else {
            throw HandoffActionError.unsupportedSchema
        }
        guard !cleanedText(request.title, maximumCharacters: 120, allowNewlines: false).isEmpty,
              cleanedText(request.title, maximumCharacters: 120, allowNewlines: false) == request.title.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw HandoffActionError.invalidTitle
        }
        guard request.summary.count <= 1_000,
              cleanedText(request.summary, maximumCharacters: 1_000, allowNewlines: true)
                == request.summary.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw HandoffActionError.invalidSummary
        }
        guard !containsSensitiveLocator(request.title),
              !containsSensitiveLocator(request.summary) else {
            throw HandoffActionError.sensitiveLocator
        }
        try validateFileName(request.payload, field: "payload")
        try validateFileName(request.suggestedName, field: "suggestedName")
        if request.kind == .applyGitPatch {
            let extensionName = URL(fileURLWithPath: request.payload).pathExtension.lowercased()
            guard ["patch", "diff"].contains(extensionName) else {
                throw HandoffActionError.invalidPatchName
            }
        }
    }

    private static func validateFileName(_ value: String, field: String) throws {
        guard !value.isEmpty,
              value.count <= 120,
              value != ".",
              value != "..",
              !value.hasPrefix("."),
              !value.contains("/"),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              URL(fileURLWithPath: value).lastPathComponent == value else {
            throw field == "payload"
                ? HandoffActionError.invalidPayloadName
                : HandoffActionError.invalidSuggestedName
        }
    }

    private static func cleanedText(
        _ value: String,
        maximumCharacters: Int,
        allowNewlines: Bool
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maximumCharacters else { return "" }
        for scalar in trimmed.unicodeScalars {
            if scalar == "\n" || scalar == "\t", allowNewlines {
                continue
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                return ""
            }
        }
        return trimmed
    }

    private static func containsSensitiveLocator(_ value: String) -> Bool {
        let lower = value.lowercased()
        let markers = [
            "://", "file:", "/users/", "/private/", "/var/folders/", "~/",
            "bearer ", "password=", "passwd=", "secret=", "token=",
            "api_key=", "apikey=", "github_pat_", "ghp_", "secret_"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func readRegularFile(
        at url: URL,
        maximumBytes: Int,
        requireCurrentUser: Bool
    ) throws -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw HandoffActionError.unreadableFile(url.lastPathComponent)
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG else {
            throw HandoffActionError.notRegularFile(url.lastPathComponent)
        }
        if requireCurrentUser {
            guard info.st_uid == getuid() else {
                throw HandoffActionError.unexpectedOwner(url.lastPathComponent)
            }
        }
        guard info.st_size >= 0, info.st_size <= maximumBytes else {
            throw HandoffActionError.fileTooLarge(url.lastPathComponent)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw HandoffActionError.unreadableFile(url.lastPathComponent)
            }
            guard data.count + count <= maximumBytes else {
                throw HandoffActionError.fileTooLarge(url.lastPathComponent)
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static let readme = """
    Routekeeper external action handoff

    Write each request as one JSON manifest directly in this directory. The payload
    must be a regular file in the same directory. Never include passwords, tokens,
    cookies, account URLs, file URLs or absolute local paths.

    {
      "schemaVersion": 1,
      "requestID": "GENERATE-A-UUID",
      "kind": "file.export",
      "title": "Short human-readable title",
      "summary": "What the operation will do and what data it contains.",
      "payload": "result.md",
      "suggestedName": "result.md"
    }

    Supported kinds:
    - file.export: the host user can save the payload to a chosen location.
    - git.applyPatch: the host user can apply the payload as an unstaged patch
      to a repository chosen outside the sandbox. Routekeeper never pushes.
    """
}

public enum HandoffActionError: Error, LocalizedError, Equatable, Sendable {
    case invalidExchangeDirectory
    case invalidHandoffDirectory
    case unsupportedSchema
    case invalidTitle
    case invalidSummary
    case invalidPayloadName
    case invalidSuggestedName
    case invalidPatchName
    case sensitiveLocator
    case duplicateRequestID
    case unreadableFile(String)
    case notRegularFile(String)
    case unexpectedOwner(String)
    case fileTooLarge(String)
    case totalPayloadTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidExchangeDirectory:
            return "The exchange folder is unavailable."
        case .invalidHandoffDirectory:
            return "The handoff directory is not a regular directory."
        case .unsupportedSchema:
            return "Unsupported handoff schema version."
        case .invalidTitle:
            return "The title is empty, too long or contains control characters."
        case .invalidSummary:
            return "The summary is too long or contains control characters."
        case .invalidPayloadName:
            return "The payload must be a plain file name without path components."
        case .invalidSuggestedName:
            return "The suggested name must be a safe plain file name."
        case .invalidPatchName:
            return "Git patch payloads must use a .patch or .diff extension."
        case .sensitiveLocator:
            return "The request contains a URL, credential marker or absolute local path."
        case .duplicateRequestID:
            return "Another manifest already uses this request ID."
        case .unreadableFile(let name):
            return "Unable to read \(name)."
        case .notRegularFile(let name):
            return "\(name) is not a regular file."
        case .unexpectedOwner(let name):
            return "\(name) is not owned by the current user."
        case .fileTooLarge(let name):
            return "\(name) exceeds the handoff size limit."
        case .totalPayloadTooLarge:
            return "The pending handoff payloads exceed the total size limit."
        }
    }
}
