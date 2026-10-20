import XCTest
@testable import GuardCore

final class DiagnosticReportExportTests: XCTestCase {
    func testSelfCheckRedactionRemovesIPsPathsPIDsAndProcessPaths() throws {
        let settings = GuardSettings()
        var snapshot = DiagnosticSnapshot(
            settings: settings,
            checks: [
                .init("desktop", "Claude desktop",
                      "1.2.3.4 · /Users/alice/Applications/Claude.app · /opt/homebrew/bin/claude",
                      .passed)
            ],
            proxyIP: "1.2.3.4",
            tunnelIP: "1.2.3.4",
            processes: [
                .init(pid: 4242, uid: 501, startSeconds: 1, startMicroseconds: 2,
                      executable: "/Users/alice/.local/share/claude/versions/2.1.0",
                      kind: .code)
            ],
            desktopPath: "/Applications/Claude.app",
            codePaths: ["/Users/alice/.local/bin/claude"]
        )
        snapshot.familyExits = [
            .init(family: .ipv4, direct: "1.2.3.4", proxied: "1.2.3.4")
        ]
        snapshot.enabledFamilies = [.ipv4]

        let data = try DiagnosticReportExport.redactedData(
            snapshot: snapshot, appVersion: "0.3.0",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("1.2.3.4"))
        XCTAssertFalse(text.contains("/Users/alice"))
        XCTAssertFalse(text.contains("/Applications/Claude.app"))
        XCTAssertFalse(text.contains("/opt/homebrew/bin/claude"))
        XCTAssertFalse(text.contains("4242"))
        XCTAssertTrue(text.contains(DiagnosticReportExport.schema))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["appVersion"] as? String, "0.3.0")
        XCTAssertEqual((object["installations"] as? [String: Any])?["desktopFound"] as? Bool, true)
        XCTAssertEqual((object["installations"] as? [String: Any])?["codePathCount"] as? Int, 1)
    }
}
