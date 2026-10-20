# Routekeeper 0.3.10 交接说明

日期：2026-10-21；平台：macOS 14+。详细使用见 README，需求及设计见 `specs/network-v2/`，真实故障验收见 `docs/network-v2-verification.md`，当前 UI 设计记录见 `docs/design.md`。

## 0.3.10 当前交付

- 版本为 `0.3.10`，Bundle version 为 `19`；当前测试合计数为 73 项。
- 主窗口关闭后继续保留菜单栏应用；重新打开自建面板时恢复 Dock 图标。
- 完成中英文界面、免责声明、关于页、液态玻璃风格控件、银白色左右半填充盾牌图标和可拖入应用程序文件夹的 DMG。
- 抓包和网络证据按实际路由归属分析，保留未知结果门禁，不把未验证项目当作通过。
- DMG 为本地 ad-hoc 签名版本，未做 Developer ID 签名、公证或 App Store 上架。
- 隔离运行器的设计计划位于 `docs/plans/2026-10-21-isolated-runner.md`，目前只记录设计，尚未开始实现。

## 0.2.x 基础能力

- 双栈路由/出口检查；每个可用地址族需固定目标。
- 全局 DNS 解析器路径与有效查询；两处 STUN 的 IPv4/IPv6 UDP 映射。未知结果不当作安全，用户可关闭附加项目并保留未验证标记。
- 休眠、唤醒、路径、代理、DNS、地址变化作废旧结果；保留异常锁定。串行诊断避免取消后的旧请求与替代检查重叠。
- FlClash、Clash Verge 和同用户 mihomo 适配；轮询等待可设 1–300 秒，默认 2 秒。
- 可选按应用代理专用过滤的系统扩展源码、配置/关闭入口、能力门禁与签名构建脚本。
- 可选限时抓包入口，仅经用户确认与系统授权采集包头摘要，不自动制造故障，不自动判定通过。

## 关键模块

| 文件 | 职责 |
|---|---|
| `Sources/GuardCore/Models.swift` | 设置兼容迁移、固定目标与状态机 |
| `Sources/GuardCore/NetworkEvidence.swift` | 代理适配、双栈地址/路由、系统 DNS |
| `Sources/GuardCore/DatagramProbes.swift` | STUN/DNS 协议、事务校验、有界 UDP |
| `Sources/GuardCore/Diagnostics.swift` | 双栈并发检查和统一门禁 |
| `Sources/GuardCore/ConnectionPolicy.swift` | 独立过滤范围与本地代理允许规则 |
| `Sources/GuardCore/CapturePlan.swift` | 有界抓包计划、输入校验和授权脚本生成 |
| `Sources/Routekeeper/GuardStore.swift` | 监控、设置、事件作废、异常处置 |
| `Sources/Routekeeper/DiagnosticRunner.swift` | 串行诊断与取消请求隔离 |
| `Sources/Routekeeper/NetworkChanges.swift` | NWPathMonitor/SCDynamicStore/睡眠通知 |
| `Sources/Routekeeper/FilterController.swift` | 签名门禁、系统扩展激活和过滤配置 |
| `Sources/Routekeeper/CaptureController.swift` | 确认、采集与文本报告导出 |
| `Sources/Routekeeper/NetworkProtectionPage.swift` | 可选高级保护与抓包界面 |
| `NetworkExtension/` | NEFilterDataProvider、系统扩展入口和 entitlement |
| `scripts/build-signed-app.sh` | 使用用户提供的有效证书和 profiles 构建 |

## 网络扩展的准确边界

扩展按内核 audit token 取应用/进程身份，识别所选桌面、原生 Code 及明确 Node CLI 入口，只允许启用时指定的本地 HTTP 代理 socket。其他直接 IPv4/IPv6 TCP/UDP socket 被拒绝。它不允许直接 TUN 使用方式；客户端必须明确用代理。无法归属的流量和未识别子工具不算覆盖，代理自身上游也不受约束。

启用前须退出所选进程，防止已有连接沿用先前裁决。过滤独立于普通监控，停止/退出界面不会解除系统过滤；需在应用或系统设置关闭。更换范围/端口先关闭再启用。不覆盖其他产品的过滤配置。

本机无有效签名身份，普通构建不嵌入未授权扩展，启用按钮禁用。扩展已编译但未激活，真实过滤覆盖、提供者崩溃、系统重启及故障抓包未验收。不得将配置保存成功或编译成功称作已实现零泄漏。

## 验证及构建

```sh
swift test --scratch-path /tmp/routekeeper-build
bash scripts/build-app.sh
plutil -lint 'dist/Routekeeper.app/Contents/Info.plist'
codesign --verify --strict 'dist/Routekeeper.app'
```

测试包含隔离设置、模拟诊断、休眠竞态、未知门禁、协议畸形数据和 RFC 5769 标准向量。脚本测试只做 shell 语法及 AppleScript 编译，不执行管理员操作。实机验收清单单列未完成，见验证文档。

## 数据与分享

设置只在本应用 UserDefaults，监控事件和抓包结果在内存。导出诊断含出口 IP、路径和 PID；包头摘要含地址、端口与时间。检测会访问 ipify、STUN 和全局 DNS，服务可见出口 IP。用于 Node 识别的前两个参数只瞬时读取，不保存环境、完整参数或提示词。

当前 App 交付包为 `dist/Routekeeper-v0.3.10.dmg`。DMG 包含 App 和“应用程序”文件夹快捷方式，不包含 `.build`、个人设置、运行报告、证书或 profiles。

当前 App 为本地 ad-hoc 签名构建，适合内部测试和交接验证，不等同于 Developer ID 签名、公证或 App Store 分发版本。面向外部用户公开分发前仍需 Developer ID 签名、公证和实机验收。

源码交接可包含 Package.swift、README、HANDOFF、Sources、Tests、NetworkExtension、scripts、specs、docs；排除 dist、.build、`.DS_Store`、开发证书、provisioning profiles、实际运行报告和个人设置。

## 0.2.1 交互调整

侧栏收起后图标居中；概览仅保留监控按钮；自检查页运行检测，异常和下一步建议保持展开，通过及说明默认折叠；运行记录标记需注意事件；清理改为页内扫描、默认不选、逐项勾选后移到废纸篓；高级保护先解释用途、可用状态，技术信息可展开。新增展示状态测试，合计 30 项通过。网络扩展实机验收边界不变。
