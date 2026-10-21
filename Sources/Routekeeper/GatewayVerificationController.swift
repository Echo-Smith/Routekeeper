import Foundation
import GuardCore
import Observation

@MainActor
@Observable
final class GatewayVerificationController {
    typealias BaselineProbe = @Sendable () async -> GatewayProbeReport
    typealias BlockedProbe = @Sendable () async -> GatewayCheckResult

    var record: GatewayVerificationRecord?
    var busy = false
    var message = ""

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let baselineProbe: BaselineProbe
    @ObservationIgnored private let blockedProbe: BlockedProbe
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let freshness: TimeInterval
    @ObservationIgnored private let storageKey = "routekeeper-gateway-verification-v1"

    init(
        defaults: UserDefaults = .standard,
        invalidateLoadedEvidence: Bool = true,
        freshness: TimeInterval = 15 * 60,
        now: @escaping () -> Date = Date.init,
        baselineProbe: @escaping BaselineProbe = { await GatewayNetworkProbes.baseline() },
        blockedProbe: @escaping BlockedProbe = { await GatewayNetworkProbes.claudeTargetBlocked() }
    ) {
        preferences = defaults
        self.freshness = freshness
        self.now = now
        self.baselineProbe = baselineProbe
        self.blockedProbe = blockedProbe
        if let data = defaults.data(forKey: storageKey),
           let restored = try? JSONDecoder().decode(GatewayVerificationRecord.self, from: data) {
            record = restored
            if invalidateLoadedEvidence {
                invalidate(reason: L10n.resolvedEnglish
                    ? "Routekeeper restarted after this evidence was collected."
                    : "Routekeeper 重启后，旧证据需要重新检查。")
            }
        }
    }

    func status(for mode: GatewayProtectionMode) -> GatewayVerificationStatus {
        record?.status(at: now(), maxAge: freshness, currentMode: mode) ?? .unverified
    }

    var isFreshlyVerified: Bool {
        record?.status(at: now(), maxAge: freshness) == .verified
    }

    func isFreshlyVerified(for mode: GatewayProtectionMode) -> Bool {
        status(for: mode) == .verified
    }

    func runBaseline(for mode: GatewayProtectionMode) async {
        guard !busy else { return }
        guard mode != .off else {
            message = L10n.resolvedEnglish
                ? "Choose split routing or Claude-only restriction before verifying the gateway."
                : "请先在网络体检的检查设置中选择“分流保护”或“仅限制 Claude”，再检查代理网关。"
            return
        }
        busy = true
        defer { busy = false }
        let report = await baselineProbe()
        let checkedAt = now()
        var next = GatewayVerificationRecord(sessionID: UUID(), mode: mode)
        next.baselineAt = checkedAt
        next.baselinePassed = report.passed
        next.baselineChecks = report.checks
        record = next
        message = report.passed
            ? (L10n.resolvedEnglish
                ? "The current gateway path passed. Next, disable only the selected overseas node and test again."
                : "当前代理路径已通过。下一步只停用所选海外节点，再测试 Claude 是否断网。")
            : (L10n.resolvedEnglish
                ? "The current gateway path did not pass all required checks."
                : "当前代理路径没有通过全部必需检查。")
        persist()
    }

    func testNodeFailure(for mode: GatewayProtectionMode) async {
        guard !busy, let current = record,
              current.mode == mode, mode != .off,
              current.status(at: now(), maxAge: freshness, currentMode: mode) == .needsNodeFailureTest else {
            return
        }
        busy = true
        defer { busy = false }
        let check = await blockedProbe()
        var next = current
        next.invalidatedAt = nil
        next.invalidationReason = nil
        next.nodeFailureAt = now()
        next.nodeFailureCheck = check
        record = next
        message = check.level == .passed
            ? (L10n.resolvedEnglish
                ? "Claude did not connect while the node was unavailable. Restore the node, then quit the proxy client for the next test."
                : "节点不可用时，Claude 没有连通。请恢复节点，然后退出代理客户端，再做下一项测试。")
            : (L10n.resolvedEnglish
                ? "Claude still connected while the node was unavailable. This result fails the fail-closed check."
                : "节点不可用时 Claude 仍能联网，失败关闭检查未通过。")
        persist()
    }

    func testClientExit(for mode: GatewayProtectionMode) async {
        guard !busy, let current = record,
              current.mode == mode, mode != .off,
              current.status(at: now(), maxAge: freshness, currentMode: mode) == .needsClientExitTest else {
            return
        }
        busy = true
        defer { busy = false }
        let check = await blockedProbe()
        var next = current
        next.invalidatedAt = nil
        next.invalidationReason = nil
        next.clientExitAt = now()
        next.clientExitCheck = check
        record = next
        message = check.level == .passed
            ? (L10n.resolvedEnglish
                ? "Claude stayed offline after the proxy client exited. Restart the proxy and finish verification."
                : "代理客户端退出后，Claude 仍未连通。请重新启动代理，然后完成验证。")
            : (L10n.resolvedEnglish
                ? "Claude connected after the proxy client exited, so direct fallback is possible."
                : "代理客户端退出后 Claude 仍能联网，存在回落直连的风险。")
        persist()
    }

    func completeRecovery(for mode: GatewayProtectionMode) async {
        guard !busy, let current = record,
              current.mode == mode, mode != .off,
              current.status(at: now(), maxAge: freshness, currentMode: mode) == .needsRecovery else {
            return
        }
        busy = true
        defer { busy = false }
        let report = await baselineProbe()
        var next = current
        next.recoveryChecks = report.checks
        next.recoveredAt = now()
        if report.passed {
            next.invalidatedAt = nil
            next.invalidationReason = nil
        }
        record = next
        message = report.passed
            ? (L10n.resolvedEnglish
                ? "Gateway verification is complete for this network session."
                : "本次网络会话的代理网关检查已完成。")
            : (L10n.resolvedEnglish
                ? "The restored gateway did not pass. Restore the original node and client state, then try again."
                : "恢复代理后仍未通过检查。请恢复原来的节点与客户端状态，再试一次。")
        persist()
    }

    func invalidate(reason: String) {
        guard var current = record, current.baselineAt != nil else { return }
        current.invalidatedAt = now()
        current.invalidationReason = reason
        record = current
        message = reason
        persist()
    }

    func clear() {
        record = nil
        message = ""
        preferences.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let record,
              let data = try? JSONEncoder().encode(record) else { return }
        preferences.set(data, forKey: storageKey)
    }
}
