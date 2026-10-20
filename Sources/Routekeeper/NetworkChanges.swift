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
    var onChange: ((String, Bool, Bool) -> Void)?
    init() {
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.receivedInitialPath { self.receivedInitialPath = true; return }
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
            SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Global/.*", "State:/Network/Service/.*/IPv[46]", "State:/Network/Service/.*/DNS", "State:/Network/Service/.*/Proxies"] as CFArray)
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
