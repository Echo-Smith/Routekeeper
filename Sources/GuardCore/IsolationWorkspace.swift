import Foundation

public struct IsolationWorkspaceMarker: Codable, Equatable, Sendable {
    public static let fileName = ".routekeeper-workspace"

    public var version: Int
    public var sessionID: UUID
    public var target: IsolationApplicationTarget

    public init(
        version: Int = 1,
        sessionID: UUID,
        target: IsolationApplicationTarget
    ) {
        self.version = version
        self.sessionID = sessionID
        self.target = target
    }
}

public struct IsolationWorkspaceManifest: Codable, Equatable, Sendable {
    public static let fileName = "session.json"

    public var version: Int
    public var sessionID: UUID
    public var target: IsolationApplicationTarget
    public var projectName: String
    public var sourceProjectPath: String?
    public var createdAt: Date
    public var endedAt: Date?

    public init(
        version: Int = 1,
        sessionID: UUID,
        target: IsolationApplicationTarget,
        projectName: String,
        sourceProjectPath: String?,
        createdAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.version = version
        self.sessionID = sessionID
        self.target = target
        self.projectName = projectName
        self.sourceProjectPath = sourceProjectPath
        self.createdAt = createdAt
        self.endedAt = endedAt
    }
}

public enum IsolationWorkspaceCoding {
    public static func encodeMarker(_ marker: IsolationWorkspaceMarker) throws -> Data {
        try encoder.encode(marker)
    }

    public static func decodeMarker(_ data: Data) throws -> IsolationWorkspaceMarker {
        try decoder.decode(IsolationWorkspaceMarker.self, from: data)
    }

    public static func encodeManifest(_ manifest: IsolationWorkspaceManifest) throws -> Data {
        try encoder.encode(manifest)
    }

    public static func decodeManifest(_ data: Data) throws -> IsolationWorkspaceManifest {
        try decoder.decode(IsolationWorkspaceManifest.self, from: data)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct IsolationCreatedWorkspace: Equatable, Sendable {
    public var container: URL
    public var workspace: URL
    public var marker: IsolationWorkspaceMarker
    public var manifest: IsolationWorkspaceManifest

    public init(
        container: URL,
        marker: IsolationWorkspaceMarker,
        manifest: IsolationWorkspaceManifest
    ) {
        self.container = container
        self.workspace = container.appendingPathComponent("workspace", isDirectory: true)
        self.marker = marker
        self.manifest = manifest
    }
}

public enum IsolationWorkspaceError: LocalizedError, Equatable, Sendable {
    case unsafeDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeDirectory(let path):
            return "工作副本目录不是由 Routekeeper 安全创建或管理的文件夹：\(path)"
        }
    }
}

public enum IsolationProjectCopyKind: Equatable, Sendable {
    case clone
    case copy
}

public enum IsolationProjectCopier {
    public static func copy(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> IsolationProjectCopyKind {
        if !fileManager.fileExists(atPath: destination.path) {
            let result = source.path.withCString { sourcePath in
                destination.path.withCString { destinationPath in
                    clonefile(sourcePath, destinationPath, 0)
                }
            }
            if result == 0 {
                return .clone
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
        }

        guard !fileManager.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.copyItem(at: source, to: destination)
        return .copy
    }
}

public enum IsolationWorkspaceStore {
    public static func create(
        in workspacesRoot: URL,
        sessionID: UUID,
        target: IsolationApplicationTarget,
        projectPath: String,
        createdAt: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> IsolationCreatedWorkspace {
        try ensureManagedDirectory(workspacesRoot, createIfMissing: true, fileManager: fileManager)
        let projectText = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = projectText.isEmpty
            ? target.title
            : URL(fileURLWithPath: projectText, isDirectory: true).lastPathComponent
        let safeProjectName = pathComponent(projectName.isEmpty ? target.title : projectName)
        let projectRoot = workspacesRoot.appendingPathComponent(safeProjectName, isDirectory: true)
        var createdProjectRoot = false
        if !fileManager.fileExists(atPath: projectRoot.path) {
            try fileManager.createDirectory(
                at: projectRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            createdProjectRoot = true
        }
        try ensureManagedDirectory(projectRoot, createIfMissing: false, fileManager: fileManager)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let sessionName = "\(formatter.string(from: createdAt))_\(pathComponent(target.title))_\(sessionID.uuidString.prefix(8))"
        let container = projectRoot.appendingPathComponent(sessionName, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: container,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            let marker = IsolationWorkspaceMarker(sessionID: sessionID, target: target)
            try writePrivate(
                IsolationWorkspaceCoding.encodeMarker(marker),
                to: container.appendingPathComponent(IsolationWorkspaceMarker.fileName, isDirectory: false),
                fileManager: fileManager
            )
            let manifest = IsolationWorkspaceManifest(
                sessionID: sessionID,
                target: target,
                projectName: safeProjectName,
                sourceProjectPath: projectText.isEmpty ? nil : projectText,
                createdAt: createdAt
            )
            try writePrivate(
                IsolationWorkspaceCoding.encodeManifest(manifest),
                to: container.appendingPathComponent(IsolationWorkspaceManifest.fileName, isDirectory: false),
                fileManager: fileManager
            )
            return IsolationCreatedWorkspace(
                container: container,
                marker: marker,
                manifest: manifest
            )
        } catch {
            try? fileManager.removeItem(at: container)
            if createdProjectRoot,
               let remaining = try? fileManager.contentsOfDirectory(atPath: projectRoot.path),
               remaining.isEmpty {
                try? fileManager.removeItem(at: projectRoot)
            }
            throw error
        }
    }

    public static func markEnded(
        at container: URL,
        endedAt: Date = Date(),
        fileManager: FileManager = .default
    ) throws {
        let manifestURL = container.appendingPathComponent(IsolationWorkspaceManifest.fileName)
        let data = try Data(contentsOf: manifestURL)
        var manifest = try IsolationWorkspaceCoding.decodeManifest(data)
        guard manifest.endedAt == nil else { return }
        manifest.endedAt = endedAt
        try writePrivate(
            IsolationWorkspaceCoding.encodeManifest(manifest),
            to: manifestURL,
            fileManager: fileManager
        )
    }

    public static func pathComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let components = value.components(separatedBy: invalid)
        let cleaned = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else {
            return "Workspace"
        }
        let visible = cleaned.hasPrefix(".")
            ? "_" + String(cleaned.dropFirst())
            : cleaned
        return String(visible.prefix(80))
    }

    private static func ensureManagedDirectory(
        _ url: URL,
        createIfMissing: Bool,
        fileManager: FileManager
    ) throws {
        if !fileManager.fileExists(atPath: url.path) {
            guard createIfMissing else {
                throw IsolationWorkspaceError.unsafeDirectory(url.path)
            }
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            throw IsolationWorkspaceError.unsafeDirectory(url.path)
        }
    }

    private static func writePrivate(
        _ data: Data,
        to url: URL,
        fileManager: FileManager
    ) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
