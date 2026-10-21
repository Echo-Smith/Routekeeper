import AppKit
import Network
import SystemConfiguration

/// Delivers coarse path changes AND DNS/proxy/address changes that NWPathMonitor may not report.
@MainActor
final class NetworkChanges {
    private let monitor = NWPathMonitor()
    private var store: SCDynamicStore?
    private var tokens: [NSObjectProtocol] = []
    private var receivedInitialPath = false
    private var lastPathSignature = ""
    var onChange: ((String, Bool, Bool) -> Void)?
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let signature = "\(String(describing: path.status)):"
                    + path.availableInterfaces
                        .map { "\($0.name):\(String(describing: $0.type))" }
                        .sorted()
                        .joined(separator: ",")
                defer { self.lastPathSignature = signature }
                if !self.receivedInitialPath { self.receivedInitialPath = true; return }
                guard signature != self.lastPathSignature else { return }
                self.onChange?("网络路径变化，旧检查已作废", false, false)
            }
        }
        monitor.start(queue: DispatchQueue(label: "local.routekeeper.path"))
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "RoutekeeperChanges" as CFString, { _, _, info in
            guard let info else { return }
            let instance = Unmanaged<NetworkChanges>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { instance.onChange?("系统代理、DNS 或网络地址发生变化", false, false) }
        }, &context)
        if let store {
            // DNS is resolved by the upstream proxy, so resolver churn is not a
            // reason to interrupt the relay. Route changes still arrive from
            // NWPathMonitor and preflight remains the fail-closed backstop.
            SCDynamicStoreSetNotificationKeys(
                store,
                nil,
                [
                    "State:/Network/Global/Proxies",
                    "State:/Network/Global/IPv4",
                    "State:/Network/Global/IPv6",
                    "State:/Network/Service/.*/Proxies"
                ] as CFArray
            )
            SCDynamicStoreSetDispatchQueue(store, .main)
        }
        let nc = NSWorkspace.shared.notificationCenter
        tokens.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?("系统即将休眠，旧检查已作废", true, false) }
        })
        tokens.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?("系统已唤醒，正在重新核验", false, true) }
        })
    }
    deinit {
        monitor.cancel()
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
