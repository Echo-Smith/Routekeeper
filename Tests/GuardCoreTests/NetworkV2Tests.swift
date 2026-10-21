import XCTest
@testable import GuardCore

final class NetworkV2Tests: XCTestCase {
    func testOldSettingsMigrateWithoutLosingProtectionOrConsent() throws {
        XCTAssertFalse(GuardSettings().protectDesktop)
        let old = Data(#"{"targetIP":"1.2.3.4","protectDesktop":false,"protectCode":true,"action":"terminate","cleanupConsented":true}"#.utf8)
        let value = try JSONDecoder().decode(GuardSettings.self, from: old)
        XCTAssertEqual(value.targetIP, "1.2.3.4"); XCTAssertFalse(value.protectDesktop)
        XCTAssertEqual(value.action, .terminate); XCTAssertTrue(value.cleanupConsented)
        XCTAssertEqual(value.pollInterval, 2); XCTAssertEqual(value.proxyClient, .automatic)
        XCTAssertTrue(value.dnsProbeEnabled); XCTAssertTrue(value.udpProbeEnabled)
        XCTAssertFalse(value.experimentalSandboxEnabled)
        XCTAssertEqual(try JSONDecoder().decode(GuardSettings.self, from: JSONEncoder().encode(value)), value)
    }
    func testIntervalAndAddressFamilyTargets() {
        var s = GuardSettings(); s.targetIP = "1.2.3.4"; s.alternateTargetIP = "2001:db8::1"
        XCTAssertEqual(s.fixedIPv4TargetIP, "1.2.3.4"); XCTAssertEqual(s.fixedIPv6TargetIP, "2001:db8::1")
        XCTAssertEqual(s.target(for: .ipv4), "1.2.3.4"); XCTAssertEqual(s.target(for: .ipv6), "2001:db8::1")
        s.setFixedExit("2001:db8::2", for: .ipv6)
        XCTAssertEqual(s.fixedIPv6TargetIP, "2001:db8::2"); XCTAssertEqual(s.target(for: .ipv6), "2001:db8::2")
        s.setFixedExit("5.6.7.8", for: .ipv4)
        XCTAssertEqual(s.fixedIPv4TargetIP, "5.6.7.8"); XCTAssertEqual(s.target(for: .ipv4), "5.6.7.8")
        for delay in [0, 0.9, 301, Double.nan, Double.infinity] { s.pollInterval = delay; XCTAssertFalse(s.validInterval) }
        for delay in [1.0, 2, 300] { s.pollInterval = delay; XCTAssertTrue(s.validInterval) }
    }
    func testIPv6OnlyTargetIsAvailableToMonitoring() {
        var s = GuardSettings(); s.targetIP = "2001:db8::1"
        XCTAssertNil(s.target(for: .ipv4))
        XCTAssertEqual(s.target(for: .ipv6), "2001:db8::1")
        XCTAssertTrue(s.hasSelection)
        var alternateOnly = GuardSettings(); alternateOnly.alternateTargetIP = "2001:db8::2"
        XCTAssertNil(alternateOnly.target(for: .ipv4))
        XCTAssertEqual(alternateOnly.target(for: .ipv6), "2001:db8::2")
    }
    func testDualStackCannotSilentlySkipObservedIPv6() {
        let active = FamilyRoutes(family: .ipv6, interfaces: ["utun4", "utun4"], hasUsableAddress: true)
        XCTAssertEqual(NetworkEvidence.familyGate(active, target: nil, observed: "2001:db8::1", proxied: "2001:db8::1").level, .unknown)
        XCTAssertEqual(NetworkEvidence.familyGate(active, target: "2001:db8::1", observed: nil, proxied: "2001:db8::1").level, .unknown)
        XCTAssertEqual(NetworkEvidence.familyGate(active, target: "2001:db8::1", observed: "2001:db8::2", proxied: "2001:db8::1").level, .failed)
        XCTAssertEqual(NetworkEvidence.familyGate(active, target: "2001:db8::1", observed: "2001:db8::1", proxied: "2001:db8::1").level, .passed)
        let direct = FamilyRoutes(family: .ipv6, interfaces: ["en0", "en0"], hasUsableAddress: true)
        XCTAssertEqual(NetworkEvidence.familyGate(direct, target: "2001:db8::1", observed: "2001:db8::1", proxied: "2001:db8::1").level, .failed)
    }
    func testPublicIPv6WithoutEgressIsAutomaticallySkipped() {
        let routes = FamilyRoutes(family: .ipv6, interfaces: ["en0", "en0"], hasUsableAddress: true)
        XCTAssertFalse(NetworkEvidence.familyActive(routes, observed: nil, proxied: nil))
        let result = NetworkEvidence.familyGate(routes, target: nil, observed: nil, proxied: nil)
        XCTAssertEqual(result.level, .passed)
        XCTAssertTrue(result.detail.contains("未观察到可用的 IPv6 出口"))
        XCTAssertTrue(result.detail.contains("不要求 IPv6 固定目标"))
    }
    func testIPv6IsActiveWhenOnlyOneEgressObservationSucceeds() {
        let routes = FamilyRoutes(family: .ipv6, interfaces: ["utun4", "utun4"], hasUsableAddress: true)
        XCTAssertTrue(NetworkEvidence.familyActive(routes, observed: "2001:db8::1", proxied: nil))
        XCTAssertTrue(NetworkEvidence.familyActive(routes, observed: nil, proxied: "2001:db8::1"))
        XCTAssertEqual(NetworkEvidence.familyGate(routes, target: nil, observed: nil, proxied: "2001:db8::1").level, .unknown)
    }
    func testDisabledIPv6IsSkippedEvenWhenTunnelOrProxyReportsIPv6() {
        let routes = FamilyRoutes(family: .ipv6, interfaces: ["utun4", "utun4"], hasUsableAddress: false)
        let result = NetworkEvidence.familyGate(
            routes,
            target: nil,
            observed: "2001:db8::2",
            proxied: "2001:db8::1"
        )
        XCTAssertEqual(result.level, .passed)
        XCTAssertTrue(result.detail.contains("不要求 IPv6 固定目标"))
    }
    func testIPv6LocalAddressClassification() {
        XCTAssertTrue(NetworkEvidence.hasUsableAddress("2001:db8::1", family: .ipv6))
        XCTAssertFalse(NetworkEvidence.hasUsableAddress("fe80::1", family: .ipv6))
        XCTAssertFalse(NetworkEvidence.hasUsableAddress("fd00::1", family: .ipv6))
        XCTAssertFalse(NetworkEvidence.hasUsableAddress("::1", family: .ipv6))
        XCTAssertTrue(NetworkEvidence.hasUsableAddress("192.168.1.10", family: .ipv4))
        XCTAssertFalse(NetworkEvidence.hasUsableAddress("169.254.1.10", family: .ipv4))
    }
    private let tx: [UInt8] = Array(0..<12)
    private func stunReply(_ bytes: [UInt8], v6: Bool = false) -> Data {
        let mask: [UInt8] = [0x21, 0x12, 0xa4, 0x42] + tx
        let xor = bytes.enumerated().map { $0.element ^ mask[$0.offset] }
        let length = xor.count + 4
        return Data([1, 1, 0, UInt8(length + 4), 0x21, 0x12, 0xa4, 0x42] + tx + [0, 0x20, 0, UInt8(length), 0, v6 ? 2 : 1, 0, 0] + xor)
    }
    func testSTUNIPv4IPv6AndMalformedPackets() {
        let v4 = stunReply([1, 2, 3, 4])
        XCTAssertEqual(STUNCodec.mappedAddress(v4, transaction: tx), "1.2.3.4")
        let v6 = stunReply([0x20, 1, 0xd, 0xb8] + [UInt8](repeating: 0, count: 11) + [1], v6: true)
        XCTAssertEqual(STUNCodec.mappedAddress(v6, transaction: tx), "2001:db8::1")
        XCTAssertNil(STUNCodec.mappedAddress(v4, transaction: [UInt8](repeating: 9, count: 12)))
        for count in 0..<v4.count { XCTAssertNil(STUNCodec.mappedAddress(v4.prefix(count), transaction: tx)) }
        var cookie = Array(v4); cookie[4] ^= 1
        XCTAssertNil(STUNCodec.mappedAddress(Data(cookie), transaction: tx))
        var overflow = Array(v4); overflow[23] = 250
        XCTAssertNil(STUNCodec.mappedAddress(Data(overflow), transaction: tx))
    }
    func testRFC5769IPv4ResponseVector() {
        // RFC 5769 section 2.2, independent of the request/reply builders above.
        let hex = "0101003c2112a442b7e7a701bc34d686fa87dfae8022000b7465737420766563746f7220002000080001a147e112a643000800142b91f599fd9e90c38c7489f92af9ba53f06be7d780280004c07d4c96"
        let pairs = stride(from: 0, to: hex.count, by: 2).map { i -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: i)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        XCTAssertEqual(STUNCodec.mappedAddress(Data(pairs), transaction: Array(pairs[8..<20])), "192.0.2.1")
        let ipv6 = "010100482112a442b7e7a701bc34d686fa87dfae8022000b7465737420766563746f7220002000140002a1470113a9faa5d3f179bc25f4b5bed2b9d900080014a382954e4be67bf11784c97c8292c275bfe3ed4180280004c8fb0b4c"
        let v6bytes = stride(from: 0, to: ipv6.count, by: 2).map { i -> UInt8 in
            let start = ipv6.index(ipv6.startIndex, offsetBy: i)
            return UInt8(ipv6[start..<ipv6.index(start, offsetBy: 2)], radix: 16)!
        }
        XCTAssertEqual(STUNCodec.mappedAddress(Data(v6bytes), transaction: Array(v6bytes[8..<20])), "2001:db8:1234:5678:11:2233:4455:6677")
    }
    func testGeneratedCaptureShellAndAppleScriptCompileWithoutExecuting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = CapturePlan(interface: "en0", destination: "2001:db8::1", seconds: 15).administratorScript(uid: 501)!
        let shell = root.appendingPathComponent("capture.sh")
        try script.write(to: shell, atomically: true, encoding: .utf8)
        let syntax = Process(); syntax.executableURL = URL(fileURLWithPath: "/bin/sh"); syntax.arguments = ["-n", shell.path]
        try syntax.run(); syntax.waitUntilExit(); XCTAssertEqual(syntax.terminationStatus, 0)
        let source = root.appendingPathComponent("capture.applescript")
        try CapturePlan.appleScript(script).write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        compiler.arguments = ["-o", root.appendingPathComponent("capture.scpt").path, source.path]
        try compiler.run(); compiler.waitUntilExit(); XCTAssertEqual(compiler.terminationStatus, 0)
    }
    func testSTUNTimeoutsAreUnknownAndMismatchIsFailure() {
        XCTAssertEqual(DatagramProbes.evaluateUDP([nil, nil], family: .ipv4, expected: "1.2.3.4").level, .unknown)
        XCTAssertEqual(DatagramProbes.evaluateUDP(["1.2.3.4", nil], family: .ipv4, expected: "1.2.3.4").level, .unknown)
        XCTAssertEqual(DatagramProbes.evaluateUDP(["9.8.7.6", nil], family: .ipv4, expected: "1.2.3.4").level, .failed)
        XCTAssertEqual(DatagramProbes.evaluateUDP(["1.2.3.4", "1.2.3.4"], family: .ipv4, expected: "1.2.3.4").level, .passed)
    }
    func testDNSRejectsWrongTransactionTruncationAndError() {
        var reply = Array(DNSCodec.request(id: 123))
        reply[2] = 0x81; reply[3] = 0x80; reply[7] = 1
        reply += [0xc0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 198, 18, 0, 1]
        XCTAssertTrue(DNSCodec.validResponse(Data(reply), id: 123))
        XCTAssertFalse(DNSCodec.validResponse(Data(reply), id: 124))
        for count in 0..<reply.count { XCTAssertFalse(DNSCodec.validResponse(Data(reply.prefix(count)), id: 123)) }
        var error = reply; error[3] = 0x83; XCTAssertFalse(DNSCodec.validResponse(Data(error), id: 123))
        var truncated = reply; truncated[2] |= 2; XCTAssertFalse(DNSCodec.validResponse(Data(truncated), id: 123))
        var wrongQuestion = reply; wrongQuestion[13] = 88; XCTAssertFalse(DNSCodec.validResponse(Data(wrongQuestion), id: 123))
    }
    func testUnknownEvidenceCannotArm() {
        var s = GuardSettings(); s.targetIP = "1.2.3.4"
        let snapshot = DiagnosticSnapshot(settings: s, checks: [.init("dns", "DNS", "timeout", .unknown)], proxyIP: s.targetIP, tunnelIP: s.targetIP, processes: [], desktopPath: nil, codePaths: [])
        var policy = GuardPolicy(); XCTAssertFalse(snapshot.ready); XCTAssertFalse(policy.arm(snapshot, settings: s))
    }
    func testFilterScopeCannotAffectOtherUserOrUnselectedApp() {
        let scope = FilterScope(uid: 501, home: "/Users/test", desktopRoots: ["/Applications/Claude.app"], desktop: true, code: false, proxyHost: "127.0.0.1", proxyPort: 7890)
        XCTAssertTrue(scope.valid)
        XCTAssertTrue(scope.matches(path: "/Applications/Claude.app/Contents/MacOS/Claude", owner: 501))
        XCTAssertFalse(scope.matches(path: "/Applications/Claude.app/Contents/MacOS/Claude", owner: 502))
        XCTAssertFalse(scope.matches(path: "/Applications/Other.app/Contents/MacOS/Other", owner: 501))
        XCTAssertFalse(scope.matches(path: "/Users/test/.local/share/claude/versions/2.1.0", owner: 501))
        XCTAssertTrue(scope.permitsRemote(host: "127.0.0.1", port: 7890, isTCP: true))
        for host: String? in [nil, "1.2.3.4", "::1", "::ffff:127.0.0.1"] { XCTAssertFalse(scope.permitsRemote(host: host, port: 7890, isTCP: true)) }
        XCTAssertFalse(scope.permitsRemote(host: "127.0.0.1", port: 22, isTCP: true))
        XCTAssertFalse(scope.permitsRemote(host: "127.0.0.1", port: 7890, isTCP: false))
    }
    func testCaptureRejectsCommandInjectionAndUnboundedDuration() {
        for interface in ["en0;id", "en0\nwhoami", "any", "-i en0", "bridge0"] {
            XCTAssertNil(CapturePlan(interface: interface, destination: "1.2.3.4", seconds: 15).administratorScript(uid: 501))
        }
        XCTAssertNotNil(CapturePlan(interface: "utun4", destination: "1.2.3.4", seconds: 15).administratorScript(uid: 501))
        XCTAssertNotNil(CapturePlan(interface: "pdp_ip0", destination: "1.2.3.4", seconds: 15).administratorScript(uid: 501))
        for ip in ["1.2.3.4;id", "$(whoami)", "example.com"] {
            XCTAssertFalse(CapturePlan(interface: "en0", destination: ip, seconds: 15).valid)
        }
        for seconds in [-1, 0, 61, 99999] { XCTAssertFalse(CapturePlan(interface: "en0", destination: "1.2.3.4", seconds: seconds).valid) }
        let script = CapturePlan(interface: "en0", destination: "2001:db8::1", seconds: 15).administratorScript(uid: 501)
        XCTAssertNotNil(script); XCTAssertTrue(script!.contains("alarm shift")); XCTAssertTrue(script!.contains("' 15 /usr/sbin/tcpdump")); XCTAssertTrue(script!.contains("-c 200"))
    }
    func testLegacyFilterScopeDecodesWithoutIdentityMetadata() throws {
        let old = Data(#"{"uid":501,"home":"/Users/test","desktopRoots":["/Applications/Claude.app"],"desktop":true,"code":false,"proxyHost":"127.0.0.1","proxyPort":7890}"#.utf8)
        let scope = try JSONDecoder().decode(FilterScope.self, from: old)
        XCTAssertTrue(scope.desktopBundleIDs.isEmpty)
        XCTAssertTrue(scope.desktopSigningIdentifiers.isEmpty)
        XCTAssertTrue(scope.matches(path: "/Applications/Claude.app/Contents/MacOS/Claude", owner: 501))
    }
    func testDesktopIdentitySurvivesApplicationPathChanges() {
        let scope = FilterScope(uid: 501, home: "/Users/test", desktopRoots: ["/Applications/Old.app"], desktop: true, code: false,
                                proxyHost: "127.0.0.1", proxyPort: 7890,
                                desktopBundleIDs: ["com.anthropic.claudefordesktop"], desktopSigningIdentifiers: ["com.anthropic.claudefordesktop"])
        XCTAssertTrue(scope.matches(path: "/Applications/Updated.app/Contents/MacOS/Claude", owner: 501, bundleID: "com.anthropic.claudefordesktop"))
        XCTAssertTrue(scope.matches(path: "/Applications/Updated.app/Contents/MacOS/Claude", owner: 501, signingIdentifier: "com.anthropic.claudefordesktop"))
        XCTAssertFalse(scope.matches(path: "/Applications/Updated.app/Contents/MacOS/Claude", owner: 501, bundleID: "com.example.other"))
    }
    func testCodeFilterNeedsTheActualFirstNodeScript() {
        let scope = FilterScope(uid: 501, home: "/Users/test", desktopRoots: [], desktop: false, code: true, proxyHost: "::1", proxyPort: 7890)
        let node = "/opt/homebrew/bin/node"
        let cli = "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        XCTAssertTrue(scope.matches(path: node, owner: 501, arguments: [node, cli]))
        XCTAssertFalse(scope.matches(path: node, owner: 501, arguments: [node, "/tmp/app.js", cli]))
        XCTAssertFalse(scope.matches(path: "/Applications/Claude.app/Contents/MacOS/Claude", owner: 501))
        XCTAssertTrue(scope.permitsRemote(host: "::1", port: 7890, isTCP: true))
        XCTAssertFalse(scope.permitsRemote(host: "2001:db8::1", port: 7890, isTCP: true))
    }
}
