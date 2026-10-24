import GuardCore
import SwiftUI

struct InspectionDiagnosticsSheet: View {
    @Bindable var store: GuardStore

    @Environment(\.dismiss) private var dismiss

    private func text(_ zh: String, _ en: String) -> String {
        L10n.resolvedEnglish ? en : zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text("连接排查", "Connection diagnostics"))
                        .routekeeperFont(.title2, weight: .semibold)
                    Text(text("短时记录连接，用于对比代理开启和关闭。",
                              "Record connections briefly to compare proxy on and off."))
                        .routekeeperFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(text("完成", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            AppHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(text("自动识别当前网络路径", "Detect the current network route"))
                                .routekeeperFont(.callout, weight: .medium)
                            Text(routeSummary)
                                .routekeeperFont(.caption, monospacedDigit: true)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button(text("开始记录", "Start recording")) {
                            store.capture.start()
                        }
                        .routekeeperProminentButton()
                        .disabled(!store.capture.valid || store.capture.busy)
                        .accessibilityIdentifier("capture-start")
                    }
                    .padding(14)
                    .appSurface(.inset, corner: 10)

                    DisclosureGroup(text("需要修改测试地址或时长？",
                                          "Change the test address or duration")) {
                        HStack(spacing: 12) {
                            Text(text("目标 IP", "Destination IP"))
                                .routekeeperFont(.callout)
                                .foregroundStyle(.secondary)
                            TextField(text("目标 IP", "Destination IP"), text: $store.capture.destination)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                                .frame(minHeight: 24)

                            Text(text("记录时长", "Duration"))
                                .routekeeperFont(.callout)
                                .foregroundStyle(.secondary)
                            Stepper(
                                text("\(store.capture.seconds) 秒",
                                     "\(store.capture.seconds) seconds"),
                                value: $store.capture.seconds,
                                in: 5...60
                            )
                            .fixedSize()

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(text(
                        "需要管理员授权；最多保存 200 个数据包的包头摘要。记录不会自动判定通过。",
                        "Requires administrator approval and stores headers for at most 200 packets. A recording is never treated as a pass automatically."
                    ))
                    .routekeeperFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button(text("导出本次记录…", "Export this recording…")) {
                            store.capture.export()
                        }
                        .routekeeperSecondaryButton()
                        .disabled(store.capture.report.isEmpty || store.capture.busy)

                        if store.capture.busy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if !store.capture.message.isEmpty {
                        Text(store.capture.message)
                            .routekeeperFont(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !store.capture.report.isEmpty {
                        ScrollView {
                            Text(store.capture.report)
                                .routekeeperFont(.caption, design: .monospaced)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 180, maxHeight: 300)
                        .padding(12)
                        .appSurface(.inset, corner: 10)
                    }
                }
                .padding(20)
                .disabled(store.capture.busy)
            }
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 480, idealHeight: 600)
        .task(id: store.capture.destination) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            store.capture.refreshRoute()
        }
        .accessibilityIdentifier("inspection-diagnostics-sheet")
    }

    private var routeSummary: String {
        let interface = store.capture.interface.isEmpty
            ? text("正在识别", "Detecting")
            : store.capture.interface
        return "\(interface) → \(store.capture.destination) · \(store.capture.seconds) \(text("秒", "seconds"))"
    }
}
