import Foundation
import GuardCore

/// Serialize rounds even when a cancelled round still has bounded system calls in flight.
actor DiagnosticRunner {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let operation: @Sendable (GuardSettings) async -> DiagnosticSnapshot
    init(operation: @escaping @Sendable (GuardSettings) async -> DiagnosticSnapshot) { self.operation = operation }
    func run(_ settings: GuardSettings) async -> DiagnosticSnapshot {
        if occupied { await withCheckedContinuation { waiters.append($0) } }
        else { occupied = true }
        defer {
            if waiters.isEmpty { occupied = false }
            else { waiters.removeFirst().resume() }
        }
        guard !Task.isCancelled else {
            return .init(settings: settings, checks: [.init("cancelled", "检查已取消", "旧请求作废", .unknown)], proxyIP: nil, tunnelIP: nil, processes: [], desktopPath: nil, codePaths: [])
        }
        return await operation(settings)
    }
}
