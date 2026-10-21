# 0.2.0 验证说明

## 已完成的开发验证

Release 主应用和系统扩展编译成功。普通应用包的 Info.plist 与 ad-hoc 签名已检查；当前没有付费 Apple Developer Program，也没有 Developer ID 身份。

- 基于模拟探测和隔离 UserDefaults 验证旧设置迁移、可配置轮询、双栈门禁、DNS/STUN 畸形包、未知结果不放行、范围约束和抓包参数输入。
- 休眠期间的旧开启请求不能开启监控；唤醒触发重新检查但异常状态不自动恢复；取消轮询后替代检查不会与仍在执行的旧检查重叠。
- STUN 解析使用 RFC 5769 的 IPv4/IPv6 标准响应向量验证；测试不校验 MESSAGE-INTEGRITY，探测也不要求服务认证，不能抵御控制网络路径的主动攻击者。
- 抓包 shell 语法和 AppleScript 编译检查只编译，不执行管理员操作。
- Network Extension 可以在当前 SDK 下编译和链接；不代表系统已授权或过滤已生效。
- 开发版界面显示双栈目标、轮询设置、附加探测和高级入口；缺签名的强制过滤入口禁用。

## 需要签名环境完成的实机验收

开发 Profile 使用 `content-filter-provider`，Developer ID 对外分发使用 `content-filter-provider-systemextension`。免费 Personal Team 不能取得 Content Filter 或系统扩展安装授权，因此下述实机验收必须使用付费团队的有效签名与 profiles 完成。

1. 在付费 Apple Developer Program 团队中使用 Apple Development 或 Developer ID 身份、证书和对应 profiles 构建；在 `/Applications` 安装，用户批准系统扩展和过滤配置。核实扩展启用状态及提供者实际运行日志，配置保存成功不等于运行成功。
2. 退出全部所选桌面/Code，清除其旧连接；启用前记录正常使用的本地代理地址。不要通过修改全机防火墙进行替代验收。
3. 让桌面/Code 明确使用本地代理，分别验证正常请求，记录测试目的 IP。验证未选中的应用照常联网。
4. 在实际物理接口上对测试目的 IP 抓包。测试目的不能是代理上游，避免正常隧道流量被误认成泄漏。应用保存文本包头摘要，不能按目的 IP 单独归属到进程；必要时结合系统进程网络观测工具判断来源。
5. 正常阶段必须有真实 Claude 活动和可观测的预期代理行为，建立正向对照。人工断开代理或停止其本地监听后重复同一操作，确认选定应用失败且没有观测到其直接外联；恢复后再次确认正常。
6. 分别覆盖 IPv4、IPv6、TCP、UDP、系统 DNS 代发、桌面 helper、原生 Code、Node CLI、编辑器扩展路径。未识别的自定义工具不能算作已覆盖。
7. 覆盖 Wi-Fi/以太网切换、IP/代理/DNS 配置变化、休眠唤醒。普通监控应立即作废旧结果并异常锁定，重新检查不能自动解除锁定。
8. 覆盖 Guard 界面退出、扩展提供者重启/崩溃、系统重启和软件升级。过滤器失败时系统行为没有在开发机验证；在这些场景验收前不得宣称 fail-closed 或零泄漏。
9. 验证“停止监控”保留独立过滤；“关闭过滤”只关闭本产品配置。确认卸载/关闭后其他应用及代理配置不变。

## 判断原则

无包、探测超时、缺少正向活动或无法归属均为“无法确认”，不等于通过。观测到同目的 IP 的包首先是线索，应排除其他应用及代理上游。每份结果需记录系统/客户端版本、过滤配置、保护范围、协议、测试时间和人工故障步骤；发布前清除地址和本地路径等个人信息。

## API 依据

- [Apple NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)
- 本机 macOS SDK 的 `NEFilterDataProvider.h`、`NEFilterSettings.h`、`NEFilterProviderConfiguration.h`、`NEProvider.h`、`NEFilterFlow.h` 和 SystemExtensions 头文件。
- [Apple NEFilterDataProvider](https://developer.apple.com/documentation/networkextension/nefilterdataprovider)
- [RFC 5769](https://www.rfc-editor.org/rfc/rfc5769.html)
