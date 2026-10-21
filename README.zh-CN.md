# Routekeeper

[English](README.md) | [简体中文](README.zh-CN.md)

Routekeeper 是一款原生 macOS 网络体检与监控工具。它会检查当前 IPv4 和
IPv6 流量是否沿预期路径传输，比较预期与实际代理出口，并持续监控所选应用的
网络变化。

当前版本为 **0.3.12**（构建号 22），面向 macOS 14 及以上系统的私有开发预览。
应用使用 ad-hoc 签名，本地 DMG 尚未经过公证。

## 功能

- 关闭主窗口后仍保留菜单栏监控；重新打开自建面板时恢复 Dock 图标。
- 检查 IPv4、IPv6 路由证据、系统代理与显式代理出口、DNS 解析器以及有界 UDP/STUN。
- 检查应用配置的网络服务是否可达。
- 在休眠唤醒、网络路径、DNS、代理和地址发生变化时作废旧结论；未知结果不会作为通过。
- 分阶段代理网关检查：当前路径、海外节点断开、代理客户端退出和恢复后复测。
  网络、代理或设置变化、休眠唤醒、应用重启以及超过 15 分钟都会使证据失效。
  选择代理网关保护后，没有新鲜有效证据时不能开启监控或启动桌面版。
- 可选使用 Network Extension 源码实现指定进程网络过滤。当前 ad-hoc 构建不具备激活系统扩展所需的授权。
- 用户明确授权后，可进行有上限、限时的数据包头抓取。
- 可选的实验性进程沙箱：Claude Code 在独立项目副本、独立 HOME 和所选会话
  时区中运行。网络只允许经过本机中继到 HTTP CONNECT 或 SOCKS5 上游，失败时
  停止网络访问。创建会话时会自动对齐可识别的系统代理地址、端口和协议，并核对
  Claude 路径、实际出口与已保存出口。原项目不会被自动修改。
- 可选的 CLI 长期凭据助手，凭据只保存在当前用户的 Keychain。
- 支持隐私脱敏报告导出，并保留本机监控记录。

Routekeeper 只报告当前 Mac 上取得的证据，不承诺零泄漏、账号服务端状态或覆盖所有应用私有网络路径。

进程沙箱仍是实验功能。它依赖动态生成的 macOS `sandbox-exec` 配置；Apple
已标记这套接口为弃用，并可能改变行为。启动前检查失败时，Claude Code 不会
退回无限制运行。为防止绕过，受限进程不能监听 localhost 项目端口，也不能
自动启动默认浏览器；需要预览时应在会话结束后打开工作副本。该功能会尽量统一
会话时区、语言和 locale，但隔离进程和文件，不等同于虚拟机，不能伪装硬件
销售地区，也不能保证账号、设备指纹或服务端风控结果。

## 环境要求

- macOS 14 或更高版本。
- Xcode 或兼容 Swift 5.10 的工具链。
- 不依赖第三方 Swift 包。

当前交付包使用 Apple Silicon 构建。Intel Mac 可使用匹配的 Swift 工具链从源码构建。

## 构建与测试

```sh
swift test --scratch-path /tmp/routekeeper-build
bash scripts/build-app.sh
bash scripts/build-dmg.sh
```

`build-app.sh` 会生成 ad-hoc 签名的 `dist/Routekeeper.app`，`build-dmg.sh`
会生成可拖入“应用程序”文件夹的 DMG。构建产物和签名配置不会提交到 Git。

当前共 98 项测试，覆盖路由证据、IPv6、DNS/UDP 探测、报告脱敏、监控状态、
进程范围、抓包输入校验、界面行为、本地中继协议、Seatbelt 文件与网络边界、
系统代理配置对齐、localhost 监听拦截、子进程继承、沙箱状态处理，以及代理
网关证据的过期和启动门禁。清空本地信息时还会校验 Routekeeper 自有数据、
沙箱副本和用户保留范围的边界。

## 只读命令行

```sh
"dist/Routekeeper.app/Contents/MacOS/Routekeeper" --self-check
"dist/Routekeeper.app/Contents/MacOS/Routekeeper" --egress-audit --output egress.json
```

这些命令不会开启监控、修改代理设置、安装系统扩展或开始抓包。返回码 `0`
表示所请求的检查通过，`2` 表示报告中包含失败项，`1` 表示命令或输出无法完成。

## 分发状态

仓库源码可构建本地开发包。公开分发前仍需 Developer ID 签名、公证，并在目标
macOS 版本上完成实机验收。Provisioning Profile 和私有签名资料不会提交到仓库。

## 文档

- [隔离运行器计划](docs/plans/2026-10-21-isolated-runner.md)
- [代理网关验证计划](docs/plans/2026-10-21-proxy-gateway-verification.md)
- [设计说明](docs/design.md)
- [网络验收](docs/network-v2-verification.md)
- [交接说明](HANDOFF.md)

## 隐私

设置保存在应用 UserDefaults，监控事件默认仅保留在内存，除非用户主动导出报告。
脱敏报告会移除地址、本地路径和进程标识。可选第三方网络体检会把当前出口地址
发送给该次体检使用的服务。
