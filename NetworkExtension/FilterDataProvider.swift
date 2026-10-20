import Foundation
import NetworkExtension
import Network
import Security
import GuardCore
import CAuditToken
import Darwin
import os.log

final class FilterDataProvider: NEFilterDataProvider {
    private let log = Logger(subsystem: "local.routekeeper.macos.filter", category: "attribution")
    private var scope: FilterScope?
    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        guard let data = filterConfiguration.vendorConfiguration?["scope"] as? Data,
              let scope = try? JSONDecoder().decode(FilterScope.self, from: data), scope.valid else {
            completionHandler(NSError(domain: "Routekeeper.Filter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid filter scope"]))
            return
        }
        self.scope = scope
        // Loopback defaults to allow in NEFilterSettings; explicitly send it to this provider too.
        let loop4 = NENetworkRule(remoteNetwork: NWHostEndpoint(hostname: "127.0.0.0", port: "0"), remotePrefix: 8, localNetwork: nil, localPrefix: 0, protocol: .any, direction: .outbound)
        let loop6 = NENetworkRule(remoteNetwork: NWHostEndpoint(hostname: "::1", port: "0"), remotePrefix: 128, localNetwork: nil, localPrefix: 0, protocol: .any, direction: .outbound)
        apply(NEFilterSettings(rules: [NEFilterRule(networkRule: loop4, action: .filterData), NEFilterRule(networkRule: loop6, action: .filterData)], defaultAction: .filterData), completionHandler: completionHandler)
    }
    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let scope else { return .drop() }
        // Audit token lookup avoids PID reuse and validates the identity supplied by the kernel.
        let identities = [flow.sourceAppAuditToken, flow.sourceProcessAuditToken].compactMap { $0 }.compactMap(Self.identity)
        guard !identities.isEmpty else {
            // Unattributed traffic is not claimed as covered; never block unrelated apps globally.
            log.warning("Unable to resolve source audit token; allowing traffic outside the selected scope")
            return .allow()
        }
        guard identities.contains(where: {
            scope.matches(path: $0.path, owner: $0.uid, arguments: $0.arguments,
                          bundleID: $0.bundleID, signingIdentifier: $0.signingIdentifier)
        }) else { return .allow() }
        guard let socket = flow as? NEFilterSocketFlow,
              let endpoint = socket.remoteEndpoint as? NWHostEndpoint else { return .drop() }
        return scope.permitsRemote(host: endpoint.hostname, port: Int(endpoint.port), isTCP: socket.socketProtocol == IPPROTO_TCP) ? .allow() : .drop()
    }
    private static func identity(_ token: Data) -> (path: String, uid: UInt32, arguments: [String], bundleID: String?, signingIdentifier: String?)? {
        var uid: uid_t = 0
        var pid: pid_t = 0
        let decoded = token.withUnsafeBytes { rawBuffer in
            RoutekeeperReadAuditToken(rawBuffer.baseAddress, rawBuffer.count, &uid, &pid)
        }
        guard decoded, pid > 1 else { return nil }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?; var info: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let path = values[kSecCodeInfoMainExecutable as String] as? URL else { return nil }
        let executable = path.resolvingSymlinksInPath().path
        let signingIdentifier = values[kSecCodeInfoIdentifier as String] as? String
        let bundleID = values["CFBundleIdentifier"] as? String ?? Bundle(path: URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path)?.bundleIdentifier
        var arguments = URL(fileURLWithPath: executable).lastPathComponent == "node" ? LocalProcesses.classificationArguments(pid) : []
        if arguments.count > 1, arguments[1].hasPrefix("/") {
            arguments[1] = URL(fileURLWithPath: arguments[1]).resolvingSymlinksInPath().path
        }
        // Re-resolve the complete kernel audit token after reading argv, so PID reuse cannot substitute a new process.
        var stillRunning: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &stillRunning) == errSecSuccess else { return nil }
        return (executable, uid, arguments, bundleID, signingIdentifier)
    }
}
