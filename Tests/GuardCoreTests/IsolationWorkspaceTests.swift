import Foundation
import XCTest
@testable import GuardCore

final class IsolationWorkspaceTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var sessions: URL!
    private var workspaces: URL!
    private var profiles: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-workspace-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        sessions = root.appendingPathComponent("Isolation", isDirectory: true)
        workspaces = root.appendingPathComponent("Routekeeper/Workspaces", isDirectory: true)
        profiles = root.appendingPathComponent("Profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaces, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testCreatesProjectCopyInsideVisibleWorkspaceRootAndWritesManifest() throws {
        let sessionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_760_000_000)
        let source = home.appendingPathComponent("Projects/Sample App", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let created = try IsolationWorkspaceStore.create(
            in: workspaces,
            sessionID: sessionID,
            target: .claudeCode,
            projectPath: source.path,
            createdAt: createdAt
        )

        XCTAssertTrue(created.container.deletingLastPathComponent().path.hasPrefix(workspaces.path + "/"))
        XCTAssertEqual(created.container.deletingLastPathComponent().lastPathComponent, "Sample App")
        XCTAssertEqual(created.workspace.path, created.container.appendingPathComponent("workspace").path)

        let markerData = try Data(
            contentsOf: created.container.appendingPathComponent(IsolationWorkspaceMarker.fileName)
        )
        XCTAssertEqual(try IsolationWorkspaceCoding.decodeMarker(markerData), created.marker)
        XCTAssertEqual(created.marker.sessionID, sessionID)
        XCTAssertEqual(created.marker.target, .claudeCode)

        let manifestData = try Data(
            contentsOf: created.container.appendingPathComponent(IsolationWorkspaceManifest.fileName)
        )
        let manifest = try IsolationWorkspaceCoding.decodeManifest(manifestData)
        XCTAssertEqual(manifest.sessionID, sessionID)
        XCTAssertEqual(manifest.target, .claudeCode)
        XCTAssertEqual(manifest.projectName, "Sample App")
        XCTAssertEqual(manifest.sourceProjectPath, source.path)
        XCTAssertNil(manifest.endedAt)
    }

    func testMarkEndedPreservesManifestIdentity() throws {
        let sessionID = UUID()
        let created = try IsolationWorkspaceStore.create(
            in: workspaces,
            sessionID: sessionID,
            target: .claudeDesktop,
            projectPath: ""
        )
        let endedAt = Date(timeIntervalSince1970: 1_760_000_500)

        try IsolationWorkspaceStore.markEnded(at: created.container, endedAt: endedAt)

        let manifestData = try Data(
            contentsOf: created.container.appendingPathComponent(IsolationWorkspaceManifest.fileName)
        )
        let manifest = try IsolationWorkspaceCoding.decodeManifest(manifestData)
        XCTAssertEqual(manifest.sessionID, sessionID)
        XCTAssertEqual(manifest.target, .claudeDesktop)
        XCTAssertEqual(manifest.endedAt, endedAt)
    }

    func testRejectsSymlinkedProjectFolderInsideWorkspaceRoot() throws {
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: workspaces.appendingPathComponent("Linked Project", isDirectory: true),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try IsolationWorkspaceStore.create(
            in: workspaces,
            sessionID: UUID(),
            target: .claudeCode,
            projectPath: "/tmp/Linked Project"
        )) { error in
            guard case .unsafeDirectory(let path) = error as? IsolationWorkspaceError else {
                return XCTFail("Expected unsafeDirectory, got \(error)")
            }
            XCTAssertTrue(path.hasSuffix("/Routekeeper/Workspaces/Linked Project"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testSanitizesHiddenAndTraversalLikeProjectNames() {
        XCTAssertEqual(IsolationWorkspaceStore.pathComponent(".."), "Workspace")
        XCTAssertEqual(IsolationWorkspaceStore.pathComponent("."), "Workspace")
        XCTAssertEqual(IsolationWorkspaceStore.pathComponent(".hidden"), "_hidden")
        XCTAssertEqual(IsolationWorkspaceStore.pathComponent("A/B"), "A-B")
    }

    func testProjectCopyIncludesFilesAndGitMetadata() throws {
        let source = root.appendingPathComponent("source-project", isDirectory: true)
        let destination = root.appendingPathComponent("copied-project", isDirectory: true)
        let gitDirectory = source.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source.appendingPathComponent("README.md"))
        try Data("ref: refs/heads/main\n".utf8).write(to: gitDirectory.appendingPathComponent("HEAD"))

        _ = try IsolationProjectCopier.copy(from: source, to: destination)

        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("README.md"), encoding: .utf8),
            "hello"
        )
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent(".git/HEAD"), encoding: .utf8),
            "ref: refs/heads/main\n"
        )
    }

    func testProjectCopyIsRejectedWhenDestinationAlreadyExists() throws {
        let source = root.appendingPathComponent("source-project", isDirectory: true)
        let destination = root.appendingPathComponent("existing-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        XCTAssertThrowsError(try IsolationProjectCopier.copy(from: source, to: destination)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileWriteFileExists)
        }
    }

    func testCleanupIncludesOnlyMarkedWorkspaceBackedByOwnedSession() throws {
        let fileManager = FileManager.default
        let sessionID = UUID()
        let sessionRoot = sessions.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
        try Data("owned\n".utf8).write(to: sessionRoot.appendingPathComponent(".routekeeper-session"))

        let created = try IsolationWorkspaceStore.create(
            in: workspaces,
            sessionID: sessionID,
            target: .claudeCode,
            projectPath: home.appendingPathComponent("Projects/App").path
        )
        try fileManager.createDirectory(at: created.workspace, withIntermediateDirectories: true)
        try Data("project-copy".utf8).write(to: created.workspace.appendingPathComponent("main.swift"))

        let userProject = workspaces.appendingPathComponent("Manual/Work", isDirectory: true)
        try fileManager.createDirectory(at: userProject, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: userProject.appendingPathComponent("notes.txt"))

        let forgedContainer = workspaces.appendingPathComponent("Manual/Forged", isDirectory: true)
        try fileManager.createDirectory(at: forgedContainer, withIntermediateDirectories: true)
        let forgedMarker = IsolationWorkspaceMarker(sessionID: UUID(), target: .claudeCode)
        try IsolationWorkspaceCoding.encodeMarker(forgedMarker).write(
            to: forgedContainer.appendingPathComponent(IsolationWorkspaceMarker.fileName)
        )

        let plan = CacheCleaner.scan(
            home: home.path,
            sessionsRoot: sessions,
            workspacesRoot: workspaces,
            profilesRoot: profiles
        )

        let owned = try XCTUnwrap(plan.targets.first { $0.scope == .workspace })
        XCTAssertEqual(owned.path, created.container.standardizedFileURL.path)
        XCTAssertEqual(owned.owningRoot, sessionRoot.standardizedFileURL.path)
        XCTAssertEqual(owned.fileCount, 3)
        XCTAssertFalse(plan.targets.contains { $0.path == userProject.path })
        XCTAssertFalse(plan.targets.contains { $0.path == forgedContainer.path })
    }

    func testRunningWorkspaceIsBlockedForCleanup() {
        let container = workspaces.appendingPathComponent("App/2026_Session", isDirectory: true)
        let target = CleanupTarget(
            path: container.path,
            labelZh: "工作副本",
            labelEn: "Workspace",
            kindZh: "项目副本",
            kindEn: "Project copy",
            scope: .workspace,
            fileCount: 1,
            exists: true,
            owningRoot: sessions.appendingPathComponent(UUID().uuidString).path
        )
        let safety = CleanupSafetyContext(
            processInspectionAvailable: true,
            runningWorkspaceRoots: [container.path]
        )

        XCTAssertEqual(CacheCleaner.blocker(for: target, safety: safety), .sessionRunning)
    }

    func testWorkspaceOverlappingProjectIsRejected() throws {
        let project = home.appendingPathComponent("Projects/App", isDirectory: true)
        let exchange = home.appendingPathComponent("Exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        let sessionRoot = home.appendingPathComponent(
            "Library/Application Support/Routekeeper/Isolation/\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = project.appendingPathComponent("Sandbox/workspace", isDirectory: true)
        let configuration = IsolationConfiguration(
            projectPath: project.path,
            exchangePath: exchange.path,
            timezoneIdentifier: "Asia/Shanghai",
            target: .claudeCode
        )

        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration,
            sessionRoot: sessionRoot,
            home: home,
            workspace: workspace
        )) { error in
            guard case .unsafePath(let path) = error as? IsolationValidationError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
            XCTAssertTrue(path.hasSuffix("/home/Projects/App/Sandbox/workspace"))
        }
    }
}
