import Foundation
import XCTest
@testable import GuardCore

final class ClaudeCodeDiscoveryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-claude-code-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testInspectsExecutableClaudeCommand() throws {
        let command = try makeCommand(named: "claude", executable: true)

        let installation = try XCTUnwrap(ClaudeCodeDiscovery.inspect(path: command.path))

        XCTAssertEqual(installation.executableURL, command.standardizedFileURL)
        XCTAssertEqual(installation.canonicalURL, command.resolvingSymlinksInPath())
        XCTAssertEqual(installation.source, .automatic)
    }

    func testRejectsAFileWithAnotherName() throws {
        let command = try makeCommand(named: "claude-wrapper", executable: true)

        XCTAssertNil(ClaudeCodeDiscovery.inspect(path: command.path))
    }

    func testRejectsANonExecutableClaudeFile() throws {
        let command = try makeCommand(named: "claude", executable: false)

        XCTAssertNil(ClaudeCodeDiscovery.inspect(path: command.path))
    }

    func testManualSelectionIsPreferredAndReported() throws {
        let command = try makeCommand(named: "claude", executable: true)

        let installation = try XCTUnwrap(
            ClaudeCodeDiscovery.locate(manualPath: command.path)
        )

        XCTAssertEqual(installation.executableURL, command.standardizedFileURL)
        XCTAssertEqual(installation.source, .manuallySelected)
    }

    private func makeCommand(named name: String, executable: Bool) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        } else {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path
            )
        }
        return url
    }
}
