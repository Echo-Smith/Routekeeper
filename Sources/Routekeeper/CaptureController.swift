import Foundation
import AppKit
import Observation
import GuardCore

@MainActor @Observable
final class CaptureController {
    private(set) var interface = ""
    var destination = "1.1.1.1"
    var seconds = 15
    var busy = false
    var report = ""
    var message = ""
    var valid: Bool { CapturePlan(interface: interface, destination: destination, seconds: seconds).valid }

    init() {
        refreshRoute()
    }

    func refreshRoute() {
        guard IPAddress.normalized(destination) != nil else {
            interface = ""
            message = "目标地址格式不正确，暂时无法开始记录。"
            return
        }
        interface = NetworkEvidence.route(to: destination) ?? ""
        message = interface.isEmpty
            ? "无法识别当前网络路径；请检查目标地址和代理状态。"
            : ""
    }

    func start() {
        refreshRoute()
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl"), FileManager.default.isExecutableFile(atPath: "/usr/sbin/tcpdump") else {
            message = "此功能暂时无法使用；没有开始记录。"; return
        }
        let plan = CapturePlan(interface: interface, destination: destination, seconds: seconds)
        guard !busy, plan.valid, let script = plan.administratorScript(uid: getuid()) else { return }
        let alert = NSAlert()
        alert.messageText = "确认限时抓包"
        alert.informativeText = "将在 \(interface) 上记录发往 \(destination) 的 TCP/UDP 流量，最多 \(seconds) 秒、200 个数据包。只会保存包头摘要。\n\n开始后请访问测试目标。系统不会自动断开代理。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "开始抓包")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        busy = true; message = "正在记录，最长 \(seconds) 秒…"; report = ""
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Command.run("/usr/bin/osascript", ["-e", CapturePlan.appleScript(script)], timeout: Double(plan.seconds) + 120)
            }.value
            guard let self else { return }
            self.busy = false
            let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let validPath = path.range(of: #"^/private/tmp/routekeeper-capture\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil
            if validPath {
                defer { try? FileManager.default.removeItem(atPath: path) }
                guard result.status == 0,
                      let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 256_000 else {
                    self.message = "记录没有完成，可能已取消授权。"; return
                }
                let text = String(decoding: data, as: UTF8.self)
                let started = text.contains("listening on")
                self.report = "Routekeeper — 手动故障抓包记录\n时间：\(Date().ISO8601Format())\n接口：\(plan.interface)\n目标：\(plan.destination)\n时长上限：\(plan.seconds) 秒\n\n此记录不自动判定通过。需确认测试期间所选 Claude 确实尝试联网，包含正常、故障与恢复阶段，并结合进程归属和代理上游地址解释。无包可能是无活动或过滤条件错误。\n\n" + text
                self.message = started ? "记录已结束，可以导出后对比。" : "记录没有成功开始，请检查默认网卡是否需要修改。"
            } else {
                self.message = "记录没有完成，可能已取消授权。"; return
            }
        }
    }
    func export() {
        guard !report.isEmpty else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Routekeeper-capture.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try report.write(to: url, atomically: true, encoding: .utf8); message = "抓包记录已导出，包含网络地址，请按需分享" }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }

    func reset() {
        destination = "1.1.1.1"
        seconds = 15
        report = ""
        refreshRoute()
    }
}
