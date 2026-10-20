# Routekeeper

[English](README.md) | [简体中文](README.zh-CN.md)

Routekeeper 是一款原生 macOS 网络体检与监控工具。它会检查当前 IPv4 和
IPv6 流量是否沿预期路径传输，比较预期与实际代理出口，并持续监控所选应用的
网络变化。

当前版本为 **0.3.10**（构建号 19），面向 macOS 14 及以上系统的私有开发预览。
应用使用 ad-hoc 签名，本地 DMG 尚未经过公证。

## 功能

- 关闭主窗口后仍保留菜单栏监控；重新打开自建面板时恢复 Dock 图标。
- 检查 IPv4、IPv6 路由证据、系统代理与显式代理出口、DNS 解析器以及有界 UDP/STUN。
- 检查应用配置的网络服务是否可达。
- 在休眠唤醒、网络路径、DNS、代理和地址发生变化时作废旧结论；未知结果不会作为通过。
- 可选使用 Network Extension 源码实现指定进程网络过滤。当前 ad-hoc 构建不具备激活系统扩展所需的授权。
- 用户明确授权后，可进行有上限、限时的数据包头抓取。
- 可选的 CLI 长期凭据助手，凭据只保存在当前用户的 Keychain。
- 支持隐私脱敏报告导出，并保留本机监控记录。

Routekeeper 只报告当前 Mac 上取得的证据，不承诺零泄漏、账号服务端状态或覆盖所有应用私有网络路径。

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

当前共 73 项测试，覆盖路由证据、IPv6、DNS/UDP 探测、报告脱敏、监控状态、
进程范围、抓包输入校验和界面行为。

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
- [设计说明](docs/design.md)
- [网络验收](docs/network-v2-verification.md)
- [交接说明](HANDOFF.md)

## 隐私

设置保存在应用 UserDefaults，监控事件默认仅保留在内存，除非用户主动导出报告。
脱敏报告会移除地址、本地路径和进程标识。可选第三方网络体检会把当前出口地址
发送给该次体检使用的服务。
