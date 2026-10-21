import XCTest
@testable import GuardCore
@testable import Routekeeper

final class ExternalActionHandoffTests: XCTestCase {
    func testScannerLoadsAValidFileExportAndFreezesPayload() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = root.appendingPathComponent("exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)

        let request = HandoffActionRequest(
            requestID: UUID(),
            kind: .exportFile,
            title: "Export reviewed notes",
            summary: "Deliver the reviewed notes to the host user.",
            payload: "notes.md",
            suggestedName: "notes.md"
        )
        try write(request: request, payload: Data("original".utf8), exchange: exchange)

        let first = HandoffActionScanner.scan(exchange: exchange)
        XCTAssertTrue(first.issues.isEmpty)
        let package = try XCTUnwrap(first.packages.first)
        XCTAssertEqual(package.payloadData, Data("original".utf8))

        let handoffDirectory = try HandoffActionScanner.prepareDirectory(in: exchange)
        try Data("changed".utf8).write(
            to: handoffDirectory.appendingPathComponent("notes.md"),
            options: .atomic
        )
        XCTAssertEqual(package.payloadData, Data("original".utf8))
        XCTAssertEqual(HandoffActionScanner.scan(exchange: exchange).packages.first?.payloadData,
                       Data("changed".utf8))
    }

    func testScannerRejectsRealLinksCredentialsAndAbsolutePaths() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = root.appendingPathComponent("exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)

        for summary in [
            "Open https://example.com/private",
            "Use token=do-not-share",
            "Read /Users/example/.ssh/config"
        ] {
            try? FileManager.default.removeItem(
                at: exchange.appendingPathComponent(HandoffActionScanner.directoryName)
            )
            let request = HandoffActionRequest(
                requestID: UUID(),
                kind: .exportFile,
                title: "Invalid request",
                summary: summary,
                payload: "result.md",
                suggestedName: "result.md"
            )
            try write(request: request, payload: Data("safe payload".utf8), exchange: exchange)
            let result = HandoffActionScanner.scan(exchange: exchange)
            XCTAssertTrue(result.packages.isEmpty)
            XCTAssertEqual(result.issues.count, 1)
        }
    }

    func testScannerRejectsSymlinkPayloadsAndDuplicateRequestIDs() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = root.appendingPathComponent("exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        let directory = try HandoffActionScanner.prepareDirectory(in: exchange)
        let outside = root.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outside)

        let request = HandoffActionRequest(
            requestID: UUID(),
            kind: .exportFile,
            title: "Symlink request",
            summary: "Must be rejected.",
            payload: "linked.md",
            suggestedName: "linked.md"
        )
        try writeManifest(request, to: directory.appendingPathComponent("a.json"))
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("linked.md"),
            withDestinationURL: outside
        )
        XCTAssertTrue(HandoffActionScanner.scan(exchange: exchange).packages.isEmpty)

        try FileManager.default.removeItem(at: directory.appendingPathComponent("linked.md"))
        try Data("first".utf8).write(to: directory.appendingPathComponent(request.payload))
        try writeManifest(request, to: directory.appendingPathComponent("a.json"))
        let duplicate = HandoffActionRequest(
            requestID: request.requestID,
            kind: .exportFile,
            title: "Duplicate request",
            summary: "Uses the same request ID.",
            payload: "duplicate.md",
            suggestedName: "duplicate.md"
        )
        try Data("second".utf8).write(to: directory.appendingPathComponent(duplicate.payload))
        try writeManifest(duplicate, to: directory.appendingPathComponent("b.json"))

        let result = HandoffActionScanner.scan(exchange: exchange)
        XCTAssertEqual(result.packages.count, 1)
        XCTAssertTrue(result.issues.contains { $0.message.localizedCaseInsensitiveContains("request ID") })
    }

    func testScannerCapsTheNumberOfManifestsItProcesses() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = root.appendingPathComponent("exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        let directory = try HandoffActionScanner.prepareDirectory(in: exchange)

        for index in 0...HandoffActionScanner.maximumManifests {
            try Data("{}".utf8).write(
                to: directory.appendingPathComponent(String(format: "%03d.json", index)),
                options: .atomic
            )
        }

        let result = HandoffActionScanner.scan(exchange: exchange)
        XCTAssertTrue(result.packages.isEmpty)
        XCTAssertEqual(result.issues.count, HandoffActionScanner.maximumManifests + 1)
        XCTAssertTrue(result.issues.contains {
            $0.message.contains("only the first \(HandoffActionScanner.maximumManifests) were scanned")
        })
    }

    func testGitPatchExecutorAppliesUnstagedChangesWithoutCommitting() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        XCTAssertEqual(Command.run("/usr/bin/git", ["-C", repository.path, "init"], timeout: 10).status, 0)
        XCTAssertEqual(Command.run("/usr/bin/git", ["-C", repository.path, "config", "user.email", "test@example.com"], timeout: 10).status, 0)
        XCTAssertEqual(Command.run("/usr/bin/git", ["-C", repository.path, "config", "user.name", "Routekeeper Test"], timeout: 10).status, 0)
        let file = repository.appendingPathComponent("notes.txt")
        try Data("one\n".utf8).write(to: file)
        XCTAssertEqual(Command.run("/usr/bin/git", ["-C", repository.path, "add", "notes.txt"], timeout: 10).status, 0)
        XCTAssertEqual(Command.run("/usr/bin/git", ["-C", repository.path, "commit", "-m", "initial"], timeout: 10).status, 0)
        let before = Command.run("/usr/bin/git", ["-C", repository.path, "rev-parse", "HEAD"], timeout: 10).output

        let patch = Data(
            """
            diff --git a/notes.txt b/notes.txt
            --- a/notes.txt
            +++ b/notes.txt
            @@ -1 +1,2 @@
             one
            +two

            """.utf8
        )
        let request = HandoffActionRequest(
            requestID: UUID(),
            kind: .applyGitPatch,
            title: "Apply reviewed patch",
            summary: "Add a second line.",
            payload: "change.patch",
            suggestedName: "change.patch"
        )
        let package = HandoffActionPackage(
            request: request,
            manifestName: "action.json",
            payloadData: patch,
            payloadSHA256: "test"
        )

        _ = try ExternalActionExecutor.applyGitPatch(package, repository: repository)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "one\ntwo\n")
        let after = Command.run("/usr/bin/git", ["-C", repository.path, "rev-parse", "HEAD"], timeout: 10).output
        XCTAssertEqual(after, before)
        let status = Command.run("/usr/bin/git", ["-C", repository.path, "status", "--short"], timeout: 10).output
        XCTAssertTrue(status.contains("M notes.txt"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-handoff-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(
        request: HandoffActionRequest,
        payload: Data,
        exchange: URL
    ) throws {
        let directory = try HandoffActionScanner.prepareDirectory(in: exchange)
        try writeManifest(request, to: directory.appendingPathComponent("action.json"))
        try payload.write(to: directory.appendingPathComponent(request.payload), options: .atomic)
    }

    private func writeManifest(_ request: HandoffActionRequest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(request).write(to: url, options: .atomic)
    }
}
