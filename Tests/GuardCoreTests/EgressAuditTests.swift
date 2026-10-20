import XCTest
@testable import GuardCore

final class EgressAuditTests: XCTestCase {
    func testFamilyConsistencyRequiresBothPaths() {
        XCTAssertEqual(EgressAudit.familyState(direct: nil, proxied: nil), .notObserved)
        XCTAssertEqual(EgressAudit.familyState(direct: "1.2.3.4", proxied: nil), .incomplete)
        XCTAssertEqual(EgressAudit.familyState(direct: nil, proxied: "1.2.3.4"), .incomplete)
        XCTAssertEqual(EgressAudit.familyState(direct: "1.2.3.4", proxied: "1.2.3.4"), .consistent)
        XCTAssertEqual(EgressAudit.familyState(direct: "1.2.3.4", proxied: "5.6.7.8"), .mismatch)
    }

    func testHTTPForbiddenStillProvesTLSReachability() {
        let probe = EgressAudit.parseCurlProbe(
            "403\t0.006\t0.572\t0.872\t203.0.113.13",
            exitStatus: 0,
            target: "claude.ai",
            route: .system
        )
        XCTAssertTrue(probe.reachedTLS)
        XCTAssertEqual(probe.httpStatus, 403)
        XCTAssertEqual(probe.tlsMilliseconds, 572)
        XCTAssertNil(probe.failure)
    }

    func testFailedTLSIsNotTreatedAsReachable() {
        let probe = EgressAudit.parseCurlProbe(
            "000\t0.000\t0.000\t2.000\t",
            exitStatus: 28,
            target: "api.anthropic.com",
            route: .proxy
        )
        XCTAssertFalse(probe.reachedTLS)
        XCTAssertNil(probe.httpStatus)
        XCTAssertNotNil(probe.failure)
    }

    func testIntelligenceParsersPreserveASNAndRiskFields() throws {
        let who = try XCTUnwrap(EgressAudit.parseIPWho(Data("""
        {
          "ip": "203.0.113.13",
          "success": true,
          "country": "United States",
          "country_code": "US",
          "region": "California",
          "city": "Los Angeles",
          "connection": {"asn": 400951, "org": "Akari Networks LLC", "isp": "Akari Networks LLC"},
          "timezone": {"id": "America/Los_Angeles"}
        }
        """.utf8)))
        XCTAssertEqual(who.asn, "AS400951")
        XCTAssertEqual(who.countryCode, "US")
        XCTAssertEqual(who.city, "Los Angeles")

        let risk = try XCTUnwrap(EgressAudit.parseIPAPI(Data("""
        {
          "ip": "203.0.113.13",
          "is_datacenter": true,
          "is_proxy": false,
          "is_vpn": false,
          "is_tor": false,
          "is_abuser": false,
          "is_crawler": false,
          "asn": {"asn": 400951, "org": "Akari Networks LLC"},
          "company": {"name": "Akari Networks LLC"},
          "location": {"country": "United States", "country_code": "US", "city": "Los Angeles"}
        }
        """.utf8)))
        let merged = EgressAudit.merge(who, with: risk)
        XCTAssertEqual(Set(merged.sources), Set(["ipwho.is", "ipapi.is"]))
        XCTAssertEqual(merged.riskFlags, [.datacenter])
        XCTAssertTrue(merged.hasRiskMetadata)
    }

    func testMalformedIntelligenceDegradesWithoutNetworkFailure() {
        XCTAssertNil(EgressAudit.parseIPWho(Data("not-json".utf8)))
        XCTAssertNil(EgressAudit.parseIPAPI(Data("{\"success\":false}".utf8)))
        let family = EgressFamilyObservation(
            family: .ipv4, directIP: "1.2.3.4", proxiedIP: "1.2.3.4", targetIP: "1.2.3.4"
        )
        let assessment = EgressAudit.assess(
            families: [family], services: [], intelligence: [],
            intelligenceStatus: .unavailable
        )
        XCTAssertEqual(assessment.level, .insufficient)
        XCTAssertTrue(assessment.findings.contains(.riskIntelligenceUnavailable))
    }

    func testCountryAndASNMismatchAreExplicitFindings() {
        let first = IPIntelligence(ip: "1.2.3.4", sources: ["test"], countryCode: "US", asn: "AS1")
        let second = IPIntelligence(ip: "5.6.7.8", sources: ["test"], countryCode: "JP", asn: "AS2")
        let findings = EgressAudit.intelligenceFindings([first, second])
        XCTAssertTrue(findings.contains(.countryMismatch))
        XCTAssertTrue(findings.contains(.asnMismatch))
    }

    func testDualStackIntelligenceOnlyNeedsRiskMetadataForPrimaryExit() {
        let primary = IPIntelligence(ip: "1.2.3.4", sources: ["test"], countryCode: "US",
                                     asn: "AS1", isDatacenter: false)
        let secondary = IPIntelligence(ip: "2001:db8::1", sources: ["test"], countryCode: "US",
                                       asn: "AS1")
        let status = EgressAudit.intelligenceStatus(
            requestedIPs: ["1.2.3.4", "2001:db8::1"],
            intelligence: [primary, secondary],
            primaryIP: "1.2.3.4",
            enabled: true
        )
        XCTAssertEqual(status, .available)
    }

    func testIntelligenceStatusDegradesWhenPrimaryRiskIsMissing() {
        let primary = IPIntelligence(ip: "1.2.3.4", sources: ["test"], countryCode: "US", asn: "AS1")
        let status = EgressAudit.intelligenceStatus(
            requestedIPs: ["1.2.3.4"], intelligence: [primary],
            primaryIP: "1.2.3.4", enabled: true
        )
        XCTAssertEqual(status, .partial)
        XCTAssertEqual(
            EgressAudit.intelligenceStatus(requestedIPs: [], intelligence: [], primaryIP: nil, enabled: false),
            .disabled
        )
        XCTAssertEqual(
            EgressAudit.intelligenceStatus(requestedIPs: ["1.2.3.4"], intelligence: [], primaryIP: "1.2.3.4", enabled: true),
            .unavailable
        )
    }

    func testOneSidedExitEvidenceCannotPass() {
        let family = EgressFamilyObservation(
            family: .ipv4, directIP: "1.2.3.4", proxiedIP: nil, targetIP: "1.2.3.4"
        )
        let assessment = EgressAudit.assess(
            families: [family], services: [], intelligence: [],
            intelligenceStatus: .disabled
        )
        XCTAssertEqual(assessment.level, .insufficient)
        XCTAssertTrue(assessment.findings.contains(.incompleteExitEvidence))
        XCTAssertFalse(assessment.findings.contains(.exitMismatch))
    }

    func testRiskFlagRaisesAttentionButMobileAloneDoesNot() {
        let family = EgressFamilyObservation(
            family: .ipv4, directIP: "1.2.3.4", proxiedIP: "1.2.3.4", targetIP: "1.2.3.4"
        )
        let mobile = IPIntelligence(ip: "1.2.3.4", sources: ["test"], countryCode: "US",
                                    asn: "AS1", isMobile: true)
        let clear = EgressAudit.assess(families: [family], services: [], intelligence: [mobile],
                                       intelligenceStatus: .available)
        XCTAssertEqual(clear.level, .clear)
        XCTAssertTrue(clear.findings.contains(.mobileNetwork))

        let tor = IPIntelligence(ip: "1.2.3.4", sources: ["test"], countryCode: "US",
                                 asn: "AS1", isTor: true)
        let attention = EgressAudit.assess(families: [family], services: [], intelligence: [tor],
                                           intelligenceStatus: .available)
        XCTAssertEqual(attention.level, .attention)
        XCTAssertTrue(attention.findings.contains(.torSignal))
    }

    func testHistoryDeduplicatesCapsAndDetectsDrift() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = EgressHistoryEntry(capturedAt: start, ip: "1.1.1.1", asn: "AS1",
                                       countryCode: "US", city: "A", sources: [])
        var entries = EgressHistory.append(first, to: [])
        let repeated = EgressHistoryEntry(capturedAt: start.addingTimeInterval(60), ip: "1.1.1.1",
                                          asn: "AS1", countryCode: "US", city: "A", sources: [])
        entries = EgressHistory.append(repeated, to: entries)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].capturedAt, repeated.capturedAt)

        let changed = EgressHistoryEntry(capturedAt: start.addingTimeInterval(120), ip: "2.2.2.2",
                                         asn: "AS2", countryCode: "JP", city: "B", sources: [])
        entries = EgressHistory.append(changed, to: entries)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(EgressHistory.drift(currentIP: "2.2.2.2", in: Array(entries.dropFirst()))?.previousIP, "1.1.1.1")

        for index in 0..<30 {
            let entry = EgressHistoryEntry(
                capturedAt: start.addingTimeInterval(Double(1_000 + index)), ip: "10.0.0.\(index)",
                asn: nil, countryCode: nil, city: nil, sources: []
            )
            entries = EgressHistory.append(entry, to: entries)
        }
        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(entries.first?.ip, "10.0.0.29")
    }

    func testTimeZoneAuditRequiresEvidenceAndComparesCurrentOffsets() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let consistent = EgressTimeZoneAudit.evaluate(
            primaryIP: "1.2.3.4",
            intelligence: [.init(ip: "1.2.3.4", sources: ["test"], timezone: "Asia/Shanghai")],
            intelligenceEnabled: true, now: now, systemTimeZone: shanghai
        )
        XCTAssertEqual(consistent.state, .consistent)
        XCTAssertEqual(consistent.offsetDifferenceHours, 0)

        let mismatch = EgressTimeZoneAudit.evaluate(
            primaryIP: "1.2.3.4",
            intelligence: [.init(ip: "1.2.3.4", sources: ["test"], timezone: "America/Los_Angeles")],
            intelligenceEnabled: true, now: now, systemTimeZone: shanghai
        )
        XCTAssertEqual(mismatch.state, .mismatch)
        XCTAssertEqual(mismatch.exitIdentifier, losAngeles.identifier)
        XCTAssertGreaterThan(mismatch.offsetDifferenceHours ?? 0, 0)

        let disabled = EgressTimeZoneAudit.evaluate(
            primaryIP: "1.2.3.4", intelligence: [], intelligenceEnabled: false,
            now: now, systemTimeZone: shanghai
        )
        XCTAssertEqual(disabled.state, .disabled)

        let missing = EgressTimeZoneAudit.evaluate(
            primaryIP: "1.2.3.4",
            intelligence: [.init(ip: "1.2.3.4", sources: ["test"])],
            intelligenceEnabled: true, now: now, systemTimeZone: shanghai
        )
        XCTAssertEqual(missing.state, .unverified)

        let missingPrimary = EgressTimeZoneAudit.evaluate(
            primaryIP: "1.2.3.4",
            intelligence: [.init(ip: "5.6.7.8", sources: ["test"], timezone: "Asia/Shanghai")],
            intelligenceEnabled: true, now: now, systemTimeZone: losAngeles
        )
        XCTAssertEqual(missingPrimary.state, .unverified)
        XCTAssertNil(missingPrimary.exitIdentifier)
    }

    func testTimeZoneFindingsAffectAssessment() {
        let family = EgressFamilyObservation(
            family: .ipv4, directIP: "1.2.3.4", proxiedIP: "1.2.3.4", targetIP: "1.2.3.4"
        )
        let mismatch = EgressTimeZoneCheck(
            state: .mismatch, systemIdentifier: "Asia/Shanghai", systemOffsetSeconds: 28_800,
            exitIdentifier: "America/Los_Angeles", exitOffsetSeconds: -28_800
        )
        let attention = EgressAudit.assess(
            families: [family], services: [], intelligence: [], intelligenceStatus: .available,
            timeZone: mismatch
        )
        XCTAssertEqual(attention.level, .attention)
        XCTAssertTrue(attention.findings.contains(.timeZoneMismatch))

        let unverified = EgressTimeZoneCheck(
            state: .unverified, systemIdentifier: "Asia/Shanghai", systemOffsetSeconds: 28_800,
            exitIdentifier: nil, exitOffsetSeconds: nil
        )
        let insufficient = EgressAudit.assess(
            families: [family], services: [], intelligence: [], intelligenceStatus: .available,
            timeZone: unverified
        )
        XCTAssertEqual(insufficient.level, .insufficient)
        XCTAssertTrue(insufficient.findings.contains(.timeZoneUnverified))
    }

    func testRedactedReportRemovesRawAddressesAndPaths() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let report = EgressAuditReport(
            auditedAt: now,
            snapshotTime: now,
            proxyConfigured: true,
            primaryIP: "203.0.113.13",
            families: [
                .init(family: .ipv4, directIP: "203.0.113.13",
                      proxiedIP: "203.0.113.13", targetIP: "203.0.113.13"),
                .init(family: .ipv6, directIP: "2606:4700:4700::1111",
                      proxiedIP: "2606:4700:4700::1111", targetIP: "2606:4700:4700::1111")
            ],
            services: [
                .init(target: "claude.ai", route: .system, reachedTLS: true, httpStatus: 403,
                      remoteIP: "203.0.113.13", connectMilliseconds: 20,
                      tlsMilliseconds: 600, totalMilliseconds: 800, failure: nil)
            ],
            intelligence: [
                .init(ip: "203.0.113.13", sources: ["ipwho.is"], countryCode: "US",
                      timezone: "America/Los_Angeles", asn: "AS400951", isDatacenter: true)
            ],
            intelligenceStatus: .available,
            assessment: .init(level: .attention, findings: [.datacenterNetwork]),
            ipv6: .init(
                localAddress: "2606:4700:4700::1111",
                systemPublicExit: "2606:4700:4700::1111",
                proxyPublicExit: "2606:4700:4700::1111",
                probes: [
                    .init(target: "claude.ai", resolvedAddresses: ["2606:4700:4700::1111"],
                          remoteAddress: "2606:4700:4700::1111", routeInterface: "utun4",
                          routeKind: .tunnel, reachedTLS: true, httpStatus: 403,
                          tlsMilliseconds: 600, failure: nil)
                ],
                state: .tunneled
            ),
            leaks: .init(
                dns: .init(id: "dns", title: "DNS",
                           detail: "203.0.113.13 → utun4；2606:4700:4700::1111 → 有效响应",
                           level: .passed),
                udpIPv4: nil, udpIPv6: nil, dualStack: nil
            ),
            timeZone: .init(
                state: .mismatch, systemIdentifier: "Asia/Shanghai", systemOffsetSeconds: 28_800,
                exitIdentifier: "America/Los_Angeles", exitOffsetSeconds: -28_800
            )
        )
        let history = [
            EgressHistoryEntry(
                capturedAt: now, ip: "203.0.113.13", asn: "AS400951",
                countryCode: "US", city: "Los Angeles", sources: ["ipwho.is"]
            )
        ]
        let data = try EgressReportExport.redactedData(
            report: report, history: history, appVersion: "0.2.5", generatedAt: now
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("203.0.113.13"))
        XCTAssertFalse(text.contains("2606:4700:4700::1111"))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertTrue(text.contains("IPv4-01"))
        XCTAssertTrue(text.contains("IPv6-01"))
        XCTAssertTrue(text.contains(EgressReportExport.schema))

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["appVersion"] as? String, "0.2.5")
        XCTAssertNotNil(object["timeZone"])
    }

    func testReportComparisonHighlightsNetworkAndServiceChanges() {
        let previousTime = Date(timeIntervalSince1970: 1_700_000_000)
        let currentTime = previousTime.addingTimeInterval(1_800)
        let previous = EgressAuditReport(
            auditedAt: previousTime,
            snapshotTime: previousTime,
            proxyConfigured: true,
            primaryIP: "1.2.3.4",
            families: [],
            services: [
                .init(target: "claude.ai", route: .system, reachedTLS: true, httpStatus: 200,
                      remoteIP: "1.2.3.4", connectMilliseconds: 10,
                      tlsMilliseconds: 100, totalMilliseconds: 200, failure: nil)
            ],
            intelligence: [
                .init(ip: "1.2.3.4", sources: ["test"], countryCode: "US",
                      timezone: "America/Los_Angeles", asn: "AS1")
            ],
            intelligenceStatus: .available,
            assessment: .init(level: .clear, findings: []),
            ipv6: .init(localAddress: nil, systemPublicExit: nil, proxyPublicExit: nil,
                        probes: [], state: .disabled),
            timeZone: .init(state: .consistent, systemIdentifier: "America/Los_Angeles",
                            systemOffsetSeconds: -28_800,
                            exitIdentifier: "America/Los_Angeles",
                            exitOffsetSeconds: -28_800)
        )
        let current = EgressAuditReport(
            auditedAt: currentTime,
            snapshotTime: currentTime,
            proxyConfigured: true,
            primaryIP: "5.6.7.8",
            families: [],
            services: [
                .init(target: "claude.ai", route: .system, reachedTLS: false, httpStatus: nil,
                      remoteIP: nil, connectMilliseconds: nil, tlsMilliseconds: nil,
                      totalMilliseconds: nil, failure: "timeout")
            ],
            intelligence: [
                .init(ip: "5.6.7.8", sources: ["test"], countryCode: "JP",
                      timezone: "Asia/Tokyo", asn: "AS2")
            ],
            intelligenceStatus: .available,
            assessment: .init(level: .attention, findings: [.serviceUnreachable]),
            ipv6: .init(localAddress: "2001:db8::1", systemPublicExit: nil,
                        proxyPublicExit: nil, probes: [], state: .directExposure),
            timeZone: .init(state: .mismatch, systemIdentifier: "America/Los_Angeles",
                            systemOffsetSeconds: -28_800,
                            exitIdentifier: "Asia/Tokyo", exitOffsetSeconds: 32_400)
        )
        let comparison = EgressReportComparison(previous: previous, current: current)
        XCTAssertTrue(comparison.hasChanges)
        XCTAssertTrue(comparison.addedFindings.contains(.serviceUnreachable))
        XCTAssertEqual(comparison.previousPrimaryExit, "1.2.3.4")
        XCTAssertEqual(comparison.currentPrimaryExit, "5.6.7.8")
        XCTAssertEqual(comparison.previousCountryCode, "US")
        XCTAssertEqual(comparison.currentCountryCode, "JP")
        XCTAssertEqual(comparison.previousASN, "AS1")
        XCTAssertEqual(comparison.currentASN, "AS2")
        XCTAssertEqual(comparison.previousTimeZoneState, .consistent)
        XCTAssertEqual(comparison.currentTimeZoneState, .mismatch)
        XCTAssertEqual(comparison.previousIPv6State, .disabled)
        XCTAssertEqual(comparison.currentIPv6State, .directExposure)
        XCTAssertEqual(comparison.serviceReachabilityChanges.count, 1)
        XCTAssertFalse(comparison.serviceReachabilityChanges[0].currentReachedTLS)
    }
}
