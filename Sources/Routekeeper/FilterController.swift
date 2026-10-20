import Foundation
import AppKit
import Observation
import Security
import SystemExtensions
import NetworkExtension
import GuardCore

@MainActor @Observable
final class FilterController: NSObject, OSSystemExtensionRequestDelegate {
    static let bundleID = "local.routekeeper.macos.filter"
    var configured = false
    var busy = false
    var message = "尚未读取系统过滤配置"
    var installedScope: FilterScope?
    private var pendingScope: FilterScope?
    var canInstall: Bool { installValidationError == nil }
    private var installValidationError: String? {
        let extensionURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(Self.bundleID).systemextension")
        guard FileManager.default.fileExists(atPath: extensionURL.path) else { return "缺少系统扩展" }
        guard let bundle = Bundle(url: extensionURL), bundle.bundleIdentifier == Self.bundleID,
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "RoutekeeperFilter" else {
            return "系统扩展 Bundle Identifier 或可执行文件不匹配"
        }
        guard let appInfo = Self.signingInformation(for: Bundle.main.bundleURL),
              let extInfo = Self.signingInformation(for: extensionURL),
              let appTeam = appInfo[kSecCodeInfoTeamIdentifier as String] as? String,
              let extTeam = extInfo[kSecCodeInfoTeamIdentifier as String] as? String,
              !appTeam.isEmpty, appTeam == extTeam else {
            return "主应用与系统扩展签名 Team ID 不一致"
        }
        guard let appEntitlements = appInfo[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              appEntitlements["com.apple.developer.system-extension.install"] as? Bool == true,
              (appEntitlements["com.apple.developer.networking.networkextension"] as? [String] ?? []).contains("content-filter-provider-systemextension"),
              let extEntitlements = extInfo[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              (extEntitlements["com.apple.developer.networking.networkextension"] as? [String] ?? []).contains("content-filter-provider-systemextension") else {
            return "应用或系统扩展缺少网络过滤授权"
        }
        guard let appProfile = Self.provisioningInformation(at: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")),
              let filterProfile = Self.provisioningInformation(at: extensionURL.appendingPathComponent("Contents/embedded.provisionprofile")) else {
            return "缺少可解析的 App 或系统扩展 provisioning profile"
        }
        guard Self.profileMatches(appProfile, teamID: appTeam, bundleID: "local.routekeeper.macos", requireInstall: true),
              Self.profileMatches(filterProfile, teamID: extTeam, bundleID: Self.bundleID, requireInstall: false) else {
            return "provisioning profile 的 Team ID、App ID 或授权不匹配"
        }
        return nil
    }
    private static func signingInformation(for url: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?; var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any] else { return nil }
        return values
    }
    private static func provisioningInformation(at url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let task = Process(); let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["cms", "-D", "-i", url.path]
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        guard task.terminationStatus == 0,
              let object = try? PropertyListSerialization.propertyList(from: pipe.fileHandleForReading.readDataToEndOfFile(), format: nil),
              let values = object as? [String: Any] else { return nil }
        return values
    }
    private static func profileMatches(_ profile: [String: Any], teamID: String, bundleID: String, requireInstall: Bool) -> Bool {
        let teams = profile["TeamIdentifier"] as? [String] ?? []
        guard teams.contains(teamID), let entitlements = profile["Entitlements"] as? [String: Any] else { return false }
        let identifiers = [entitlements["application-identifier"] as? String, entitlements["com.apple.application-identifier"] as? String].compactMap { $0 }
        guard identifiers.contains(where: { $0.hasSuffix(".\(bundleID)") }) else { return false }
        guard !requireInstall || entitlements["com.apple.developer.system-extension.install"] as? Bool == true else { return false }
        return (entitlements["com.apple.developer.networking.networkextension"] as? [String] ?? []).contains("content-filter-provider-systemextension")
    }
    func refresh() {
        guard canInstall else {
            configured = false
            message = "暂时无法使用。若此前已开启过滤，可在系统设置中查看或关闭。"
            return
        }
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.message = "读取过滤配置失败：\(error.localizedDescription)"; return }
                let manager = NEFilterManager.shared()
                guard manager.providerConfiguration?.filterDataProviderBundleIdentifier == Self.bundleID else {
                    self.configured = false
                    self.message = self.canInstall ? "尚未启用；需系统批准，启用后请进行抓包验收" : "此开发版本未包含有效签名与授权的系统扩展，无法启用强制保护"
                    return
                }
                self.configured = manager.isEnabled
                self.installedScope = (manager.providerConfiguration?.vendorConfiguration?["scope"] as? Data).flatMap { try? JSONDecoder().decode(FilterScope.self, from: $0) }
                self.message = manager.isEnabled ? "系统配置已启用代理专用过滤；提供者运行状态及实际覆盖仍需抓包验证。停止普通监控不会关闭过滤。" : "系统过滤配置已关闭"
            }
        }
    }
    func enable(settings: GuardSettings) {
        guard canInstall, !busy else { return }
        guard let proxy = ProxyEndpoint.current(), proxy.isLoopback,
              let host = IPAddress.normalized(proxy.host) ?? (proxy.host.lowercased() == "localhost" ? "127.0.0.1" : nil) else {
            message = "必须先启用明确的本机 HTTP/HTTPS 系统代理"; return
        }
        let root = ApplicationDiscovery.path(bundleID: ApplicationDiscovery.desktopID, name: "Claude")
        let scan = LocalProcesses.scan(desktopRoots: root.map { [$0] } ?? [])
        guard scan.available, scan.records.allSatisfy({ !settings.includes($0.kind) }) else {
            message = "请先完全退出所选 Claude 应用和 Code，以免已有连接绕过新规则，再重试。"; return
        }
        guard settings.hasSelection else { message = "请先选择保护对象"; return }
        let desktopIDs = root.map { Self.desktopIdentity(at: $0) } ?? (bundleIDs: [], signingIdentifiers: [])
        let scope = FilterScope(uid: getuid(), home: NSHomeDirectory(), desktopRoots: root.map { [$0] } ?? [],
                                desktop: settings.protectDesktop, code: settings.protectCode, proxyHost: host, proxyPort: proxy.port,
                                desktopBundleIDs: desktopIDs.bundleIDs, desktopSigningIdentifiers: desktopIDs.signingIdentifiers)
        guard scope.valid else { message = "过滤范围无效"; return }
        pendingScope = scope; busy = true
        message = "请求系统扩展批准；完成前不代表已阻断"
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.bundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    private static func desktopIdentity(at path: String) -> (bundleIDs: [String], signingIdentifiers: [String]) {
        var bundleIDs = [String](); var signingIdentifiers = [String]()
        if let id = Bundle(path: path)?.bundleIdentifier { bundleIDs.append(id) }
        var staticCode: SecStaticCode?; var info: CFDictionary?
        if SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
           let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let values = info as? [String: Any], let id = values[kSecCodeInfoIdentifier as String] as? String {
            signingIdentifiers.append(id)
        }
        return (Array(Set(bundleIDs)), Array(Set(signingIdentifiers)))
    }
    private func savePendingScope() {
        guard let scope = pendingScope else { busy = false; return }
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.finish(error); return }
                let manager = NEFilterManager.shared()
                if let existing = manager.providerConfiguration?.filterDataProviderBundleIdentifier, existing != Self.bundleID {
                    self.finish(NSError(domain: "Routekeeper", code: 1, userInfo: [NSLocalizedDescriptionKey: "已有其他内容过滤器；不会覆盖其配置"]))
                    return
                }
                // System approval can take minutes; recheck scope and running apps immediately before saving.
                let scan = LocalProcesses.scan(desktopRoots: scope.desktopRoots)
                guard scope.uid == getuid(), scan.available,
                      !scan.records.contains(where: { $0.kind == .desktop ? scope.desktop : scope.code }) else {
                    self.finish(NSError(domain: "Routekeeper", code: 3, userInfo: [NSLocalizedDescriptionKey: "批准期间所选应用已重新运行。请完全退出后重试；尚未保存启用配置。"])); return
                }
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterPackets = false
                configuration.filterDataProviderBundleIdentifier = Self.bundleID
                configuration.vendorConfiguration = ["scope": (try? JSONEncoder().encode(scope)) ?? Data()]
                manager.providerConfiguration = configuration
                manager.localizedDescription = "Routekeeper — selected apps, local proxy only"
                manager.isEnabled = true
                manager.saveToPreferences { error in Task { @MainActor in self.finish(error) } }
            }
        }
    }
    func disable() {
        guard !busy else { return }; busy = true
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.finish(error); return }
                let manager = NEFilterManager.shared()
                guard manager.providerConfiguration?.filterDataProviderBundleIdentifier == Self.bundleID else {
                    self.finish(NSError(domain: "Routekeeper", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到本应用过滤配置，不修改其他过滤器"]))
                    return
                }
                manager.isEnabled = false
                manager.saveToPreferences { error in Task { @MainActor in self.finish(error) } }
            }
        }
    }
    private func finish(_ error: Error?) {
        busy = false; pendingScope = nil
        if let error { message = "系统过滤操作失败：\(error.localizedDescription)" }
        else { refresh() }
    }
    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in message = "请在系统设置中批准 Routekeeper 系统扩展；当前仍未完成启用" }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in finish(error) }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            if result == .completed { savePendingScope() }
            else { busy = false; pendingScope = nil; message = "系统要求重启；重启后再启用并验证过滤配置" }
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
}
