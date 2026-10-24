import XCTest
@testable import GuardCore

final class ProtectionCompletenessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testNoSnapshotHasNoScore() {
        let result = ProtectionCompleteness.evaluate(
            snapshot: nil,
            egress: nil,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(result.state, .notRun)
        XCTAssertNil(result.score)
        XCTAssertEqual(result.evidenceQuality, .insufficient)
    }

    func testInvalidatedEvidenceIsMarkedForReviewInsteadOfNeverRun() {
        let result = ProtectionCompleteness.evaluate(
            snapshot: nil,
            egress: nil,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            hasInvalidatedEvidence: true,
            now: now
        )

        XCTAssertEqual(result.state, .needsReview)
        XCTAssertNil(result.score)
    }

    func testMissingEgressReportIsIncompleteInsteadOfLowScore() {
        let result = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: nil,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(result.state, .incomplete)
        XCTAssertNil(result.score)
    }

    func testStaleSnapshotRequiresReview() {
        let result = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: egress(),
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now.addingTimeInterval(ProtectionCompleteness.snapshotFreshness + 1)
        )

        XCTAssertEqual(result.state, .needsReview)
        XCTAssertNil(result.score)
    }

    func testReportFromDifferentSnapshotRequiresReview() {
        let report = egress(auditedAt: now, snapshotTime: now.addingTimeInterval(-5))
        let result = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: report,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(result.state, .needsReview)
        XCTAssertNil(result.score)
    }

    func testInsufficientEgressEvidenceHasNoScore() {
        let result = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: egress(assessment: .init(
                level: .insufficient,
                findings: [.incompleteExitEvidence]
            )),
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(result.state, .incomplete)
        XCTAssertNil(result.score)
    }

    func testDirectProcessEvidenceCanReachFullScore() {
        let result = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: egress(),
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(result.state, .scored)
        XCTAssertEqual(result.evidenceQuality, .direct)
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.band, .strong)
        XCTAssertTrue(result.attentionAreas.isEmpty)
    }

    func testActiveProbeWithoutProcessConnectionIsCapped() {
        let result = ProtectionCompleteness.evaluate(
            snapshot: snapshot(includeProcessNetwork: false),
            egress: egress(),
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(result.state, .scored)
        XCTAssertEqual(result.evidenceQuality, .crossChecked)
        XCTAssertEqual(result.score, 92)
    }

    func testGatewayOffIsNotApplicableAndFailedGatewayLowersScore() {
        let off = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: egress(),
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )
        let failed = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: egress(),
            gatewayMode: .claudeOnly,
            gatewayStatus: .failed,
            now: now
        )

        XCTAssertEqual(off.score, 100)
        XCTAssertFalse(off.attentionAreas.contains(.gatewayFailClosed))
        XCTAssertNotNil(failed.score)
        XCTAssertLessThanOrEqual(failed.score!, 74)
        XCTAssertLessThan(failed.score!, off.score!)
        XCTAssertTrue(failed.attentionAreas.contains(.gatewayFailClosed))
    }

    func testExperimentalSandboxSettingDoesNotChangeScore() {
        let regular = ProtectionCompleteness.evaluate(
            snapshot: snapshot(),
            egress: egress(),
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )
        let sandbox = ProtectionCompleteness.evaluate(
            snapshot: snapshot(experimentalSandboxEnabled: true),
            egress: egress(),
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(regular.score, sandbox.score)
        XCTAssertEqual(regular.state, sandbox.state)
    }

    func testFailedEvidenceStillScoresForExplanationButFlagsAreas() {
        let failedChecks = baseChecks().map { check -> CheckItem in
            switch check.id {
            case "proxy", "tun", "dns", "process-access", "claude-trace-exit",
                 "code", "code-environment":
                return .init(check.id, check.title, check.detail, .failed)
            default:
                return check
            }
        }
        let report = egress(assessment: .init(
            level: .attention,
            findings: [.exitMismatch, .serviceUnreachable]
        ))
        let result = ProtectionCompleteness.evaluate(
            snapshot: snapshot(checks: failedChecks, includeProcessNetwork: false),
            egress: report,
            gatewayMode: .off,
            gatewayStatus: .unverified,
            now: now
        )

        XCTAssertEqual(result.state, .scored)
        XCTAssertNotNil(result.score)
        XCTAssertTrue(result.attentionAreas.contains(.localPath))
        XCTAssertTrue(result.attentionAreas.contains(.egressConsistency))
        XCTAssertTrue(result.attentionAreas.contains(.claudeEnvironment))
    }

    func testProcessNetworkParserSeparatesLoopbackAndRemoteConnections() {
        let summary = LocalProcesses.parseNetworkConnections("""
        p123
        n127.0.0.1:51000->127.0.0.1:7890
        p456
        n10.0.0.2:51001->1.1.1.1:443
        n[::1]:51002->[::1]:8080
        """)

        XCTAssertTrue(summary.readable)
        XCTAssertEqual(summary.processCount, 2)
        XCTAssertEqual(summary.establishedConnections, 3)
        XCTAssertEqual(summary.loopbackConnections, 2)
        XCTAssertEqual(summary.nonLoopbackConnections, 1)
    }

    func testEnvironmentParserNeverRetainsCredentials() {
        let summary = LocalProcesses.parseCodeEnvironment("""
        /usr/local/bin/claude HTTPS_PROXY=http://user:secret@127.0.0.1:7890 \
        NO_PROXY=localhost,127.0.0.1 ANTHROPIC_BASE_URL=https://gateway.example.com/v1 \
        LANG=zh_CN.UTF-8 TZ=Asia/Shanghai
        """)

        XCTAssertTrue(summary.readable)
        XCTAssertTrue(summary.proxyConfigured)
        XCTAssertEqual(summary.proxyHosts, ["127.0.0.1:7890"])
        XCTAssertTrue(summary.noProxyConfigured)
        XCTAssertTrue(summary.apiBaseConfigured)
        XCTAssertEqual(summary.apiBaseHost, "gateway.example.com")
        XCTAssertEqual(summary.locale, "zh_CN.UTF-8")
        XCTAssertEqual(summary.timeZone, "Asia/Shanghai")
        XCTAssertFalse(summary.proxyHosts.joined().contains("secret"))
    }

    private func snapshot(
        checks: [CheckItem]? = nil,
        includeProcessNetwork: Bool = true,
        experimentalSandboxEnabled: Bool = false
    ) -> DiagnosticSnapshot {
        var settings = GuardSettings()
        settings.targetIP = "203.0.113.10"
        settings.protectCode = true
        settings.protectDesktop = false
        settings.experimentalSandboxEnabled = experimentalSandboxEnabled
        var value = DiagnosticSnapshot(
            settings: settings,
            checks: checks ?? baseChecks(),
            proxyIP: "203.0.113.10",
            tunnelIP: "203.0.113.10",
            processes: [
                .init(
                    pid: 321,
                    uid: 501,
                    startSeconds: 1,
                    startMicroseconds: 2,
                    executable: "/usr/local/bin/claude",
                    kind: .code
                )
            ],
            desktopPath: nil,
            codePaths: ["/usr/local/bin/claude"]
        )
        value.checkedAt = now
        value.familyExits = [
            .init(family: .ipv4, direct: "203.0.113.10", proxied: "203.0.113.10"),
            .init(family: .ipv6, direct: nil, proxied: nil)
        ]
        value.enabledFamilies = [.ipv4]
        if includeProcessNetwork {
            value.claudeProcessNetwork = .init(
                processCount: 1,
                establishedConnections: 1,
                loopbackConnections: 1,
                nonLoopbackConnections: 0,
                readable: true
            )
        } else {
            value.claudeProcessNetwork = nil
        }
        value.codeEnvironment = .init(
            readable: true,
            proxyConfigured: true,
            proxyHosts: ["127.0.0.1:7890"],
            locale: "zh_CN.UTF-8",
            timeZone: "Asia/Shanghai"
        )
        return value
    }

    private func baseChecks() -> [CheckItem] {
        [
            .init("target", "target", "", .passed),
            .init("scope", "scope", "", .passed),
            .init("interval", "interval", "", .passed),
            .init("proxy-client", "proxy client", "", .passed),
            .init("proxy", "proxy", "", .passed),
            .init("tun", "tun", "", .passed),
            .init("dns", "dns", "", .passed),
            .init("udp-ipv4", "udp", "", .passed),
            .init("process-access", "process access", "", .passed),
            .init("claude-trace-exit", "trace", "", .passed),
            .init("code", "code", "", .passed),
            .init("code-environment", "environment", "", .passed),
            .init("boundary", "boundary", "", .warning)
        ]
    }

    private func egress(
        auditedAt: Date? = nil,
        snapshotTime: Date? = nil,
        assessment: EgressAssessment = .init(level: .clear, findings: [])
    ) -> EgressAuditReport {
        .init(
            auditedAt: auditedAt ?? now,
            snapshotTime: snapshotTime ?? now,
            proxyConfigured: true,
            primaryIP: "203.0.113.10",
            families: [
                .init(
                    family: .ipv4,
                    directIP: "203.0.113.10",
                    proxiedIP: "203.0.113.10",
                    targetIP: "203.0.113.10"
                ),
                .init(family: .ipv6, directIP: nil, proxiedIP: nil, targetIP: nil)
            ],
            services: EgressAudit.serviceTargets.map {
                .init(
                    target: $0,
                    route: .system,
                    reachedTLS: true,
                    httpStatus: 200,
                    remoteIP: "203.0.113.10",
                    connectMilliseconds: 20,
                    tlsMilliseconds: 40,
                    totalMilliseconds: 60,
                    failure: nil
                )
            },
            intelligence: [],
            intelligenceStatus: .disabled,
            assessment: assessment
        )
    }
}
