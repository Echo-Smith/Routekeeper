import Foundation
import XCTest
@testable import GuardCore

final class IsolationModelsTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var project: URL!
    private var exchange: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("routekeeper-isolation-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        project = home.appendingPathComponent("Projects/App", isDirectory: true)
        exchange = home.appendingPathComponent("Exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func configuration(
        project: URL? = nil,
        exchange: URL? = nil,
        timezone: String = "Asia/Shanghai",
        upstream: IsolationUpstream = IsolationUpstream()
    ) -> IsolationConfiguration {
        .init(
            projectPath: (project ?? self.project).path,
            exchangePath: (exchange ?? self.exchange).path,
            timezoneIdentifier: timezone,
            upstream: upstream
        )
    }

    private func sessionRoot() -> URL {
        home.appendingPathComponent(
            "Library/Application Support/Routekeeper/Isolation/\(UUID().uuidString)",
            isDirectory: true
        )
    }

    func testValidatesExistingDirectoriesAndBuildsOwnedLayout() throws {
        let paths = try IsolationPathValidator.validate(
            configuration(),
            sessionRoot: sessionRoot(),
            home: home
        )
        XCTAssertEqual(paths.originalProject.resolvingSymlinksInPath(), project.resolvingSymlinksInPath())
        XCTAssertEqual(paths.exchange.resolvingSymlinksInPath(), exchange.resolvingSymlinksInPath())
        XCTAssertTrue(paths.layout.home.path.hasSuffix("/home"))
        XCTAssertTrue(paths.layout.workspace.path.hasSuffix("/workspace"))
    }

    func testRejectsOverlappingProjectAndExchange() throws {
        let nested = project.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(exchange: nested),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            XCTAssertEqual(error as? IsolationValidationError, .pathsOverlap)
        }
    }

    func testRejectsHomeRootAndNonDirectory() throws {
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(project: home),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            guard case .unsafePath(let value) = error as? IsolationValidationError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
            XCTAssertTrue(value.hasSuffix("/home"))
        }
        let file = project.appendingPathComponent("README.md")
        try Data("test".utf8).write(to: file)
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(project: file),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            guard case .notDirectory(let value) = error as? IsolationValidationError else {
                return XCTFail("Expected notDirectory, got \(error)")
            }
            XCTAssertTrue(value.hasSuffix("/home/Projects/App/README.md"))
        }
    }

    func testRejectsSessionRootOutsideApplicationSupportAndInputPathsInsideIt() throws {
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(),
            sessionRoot: home.appendingPathComponent("WrongPlace/Session", isDirectory: true),
            home: home
        )) { error in
            XCTAssertEqual(error as? IsolationValidationError, .sessionRootOutsideApplicationSupport)
        }

        let owned = sessionRoot()
        let ownedProject = owned.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: ownedProject, withIntermediateDirectories: true)
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(project: ownedProject),
            sessionRoot: owned,
            home: home
        ))
    }

    func testValidatesTimezoneAndLoopbackUpstream() {
        XCTAssertThrowsError(try IsolationPathValidator.validate(
            configuration(timezone: "Mars/Olympus"),
            sessionRoot: sessionRoot(),
            home: home
        )) { error in
            XCTAssertEqual(error as? IsolationValidationError, .invalidTimezone)
        }
        for upstream in [
            IsolationUpstream(host: "192.168.1.2", port: 7890),
            IsolationUpstream(host: "127.0.0.1", port: 0),
            IsolationUpstream(host: "127.0.0.1", port: 70000),
            IsolationUpstream(host: "127.0.0.1/path", port: 7890)
        ] {
            XCTAssertThrowsError(try IsolationPathValidator.validate(
                configuration(upstream: upstream),
                sessionRoot: sessionRoot(),
                home: home
            )) { error in
                XCTAssertEqual(error as? IsolationValidationError, .invalidUpstream)
            }
        }
        XCTAssertTrue(configuration(upstream: IsolationUpstream(host: "::1", port: 1080, protocolType: .socks5)).upstream.isValid)
    }

    func testSandboxProfileOnlyWritesSessionWorkspaceExchangeAndLoopbackPort() throws {
        let paths = try IsolationPathValidator.validate(
            configuration(),
            sessionRoot: sessionRoot(),
            home: home
        )
        let profile = IsolationSandboxProfile.make(
            paths: paths,
            executableURL: URL(fileURLWithPath: "/usr/local/bin/claude"),
            relayPort: 43123
        )
        XCTAssertTrue(profile.contains("(deny default)"))
        XCTAssertTrue(profile.contains("(deny network*)"))
        XCTAssertTrue(profile.contains("(deny mach-lookup)"))
        XCTAssertTrue(profile.contains(paths.layout.workspace.path))
        XCTAssertTrue(profile.contains(paths.exchange.path))
        XCTAssertTrue(profile.contains("localhost:43123"))
        XCTAssertFalse(profile.contains("(allow network-outbound (remote ip \"*:"))
        XCTAssertFalse(profile.contains(#"(subpath "/Users")"#))
        XCTAssertFalse(profile.contains("workspace.sb\" injection"))
    }

    func testProfileEscapesQuotesAndBackslashesInPaths() throws {
        let weirdParent = root.appendingPathComponent(#"quote"folder\name"#, isDirectory: true)
        let weirdProject = weirdParent.appendingPathComponent("Project", isDirectory: true)
        let weirdExchange = weirdParent.appendingPathComponent("Exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: weirdProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: weirdExchange, withIntermediateDirectories: true)
        let paths = try IsolationPathValidator.validate(
            configuration(project: weirdProject, exchange: weirdExchange),
            sessionRoot: sessionRoot(),
            home: home
        )
        let profile = IsolationSandboxProfile.make(
            paths: paths,
            executableURL: URL(fileURLWithPath: "/usr/local/bin/claude"),
            relayPort: 43123
        )
        XCTAssertTrue(profile.contains(#"\""#))
        XCTAssertTrue(profile.contains(#"\\"#))
    }

    func testRelayTargetParsesAuthoritiesAndRejectsLocalDestinations() {
        XCTAssertEqual(RelayTarget(authority: "api.example.com:443"), .init(host: "api.example.com", port: 443))
        XCTAssertEqual(RelayTarget(authority: "[2001:4860:4860::8888]:443"), .init(host: "2001:4860:4860::8888", port: 443))
        for value in ["", "example.com", ":443", "example.com:0", "example.com:70000", "bare:abc"] {
            XCTAssertNil(RelayTarget(authority: value), value)
        }
        for value in [
            "localhost:443", "router.local:443", "127.0.0.1:443", "10.0.0.1:443",
            "172.20.1.1:443", "192.168.1.1:443", "169.254.1.1:443",
            "100.64.0.1:443", "[::1]:443", "[fd00::1]:443", "[fe80::1]:443"
        ] {
            XCTAssertTrue(RelayTarget(authority: value)?.blocksDirectLocalAccess == true, value)
        }
        XCTAssertFalse(RelayTarget(authority: "8.8.8.8:443")?.blocksDirectLocalAccess == true)
    }
}
