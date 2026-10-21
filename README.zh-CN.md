<p align="center">
  <img src="docs/assets/routekeeper-icon.png" width="160" height="160" alt="Routekeeper 图标">
</p>

<h1 align="center">Routekeeper</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.zh-CN.md">简体中文</a>
</p>

Routekeeper 是一款原生 macOS 网络体检与监控工具。它会检查当前 IPv4 和
IPv6 流量是否沿预期路径传输，比较预期与实际代理出口，并持续监控所选应用的
网络变化。

当前版本为 **0.3.12**（构建号 22），面向 macOS 14 及以上系统的私有开发预览。
应用使用 ad-hoc 签名，本地 DMG 尚未经过公证。

## 下载与安装

[下载 Routekeeper 0.3.12](https://github.com/Echo-Smith/Routekeeper/releases/tag/v0.3.12)

1. 打开 DMG。
2. 将 `Routekeeper.app` 拖入“应用程序”文件夹。
3. 从“应用程序”启动 Routekeeper。

当前安装包使用 ad-hoc 签名，尚未经过 Apple 公证。首次打开如被 macOS 拦截，
请前往“系统设置 → 隐私与安全性”允许打开。当前交付包仅支持 Apple Silicon。

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
- 可选的实验性进程沙箱：Claude Code 和已通过 Anthropic Team ID 校验的官方
  Claude Desktop 在独立工作副本、独立 HOME 和所选会话时区中运行。网络只允许
  经过本机中继到 HTTP CONNECT 或 SOCKS5 上游，失败时停止网络访问。创建会话时
  会自动对齐可识别的系统代理地址、端口和协议，并核对 Claude 路径与实际出口。
  原项目不会被自动修改。
- 沙箱现在是独立一级入口，不再隐藏在保护二级菜单中。开启后，网络体检会直接
  切换为沙箱自己的出口、中继、启动前检查和会话操作；可在同一流程中检测并保存
  一致出口，不再要求先绕到普通网络体检。
- 网络监控事件先经过约 1.6 秒稳定窗口和网络指纹复检。只有代理地址、端口、
  协议或认证标识发生实质变化，或最终预检失败时才关闭中继；重复路径、DNS
  和无关接口通知不会再直接中断 Claude。休眠会立即断网，唤醒后若原配置仍有效
  则自动恢复，手动关闭的网络不会自行恢复。
- 可为 Claude Desktop 显式启用持久登录：工作副本、日志和临时文件仍然逐会话
  隔离，而 Cookie、本地登录状态和 Claude 数据保存在 Routekeeper 专属 HOME。
  可在界面中单独清除这部分敏感数据。该选项默认关闭。
- 输入法兼容只开放当前已启用或已选中的输入法 `.app` 包只读权限，例如
  `/Library/Input Methods/WeType.app`；不会开放整个 `/Library`，也不会读取
  输入法词典、历史、学习记录或其他用户数据。
- Claude Desktop 邮件登录使用本地回调桥：从邮件中复制官方
  `claude.ai/magic-link` 链接并粘贴到 Routekeeper。应用只在内存中校验，不访问、
  不保存且不记录链接中的 token，并只把回调交给当前记录的沙箱 Claude 实例，
  不回退到沙箱外的浏览器。
- 授权隔离允许 Claude 把外部操作写成交换目录中的 JSON 清单和交付文件，但不会
  向沙箱暴露 Git remote、SSH key、GitHub/Notion token 或宿主链接。Routekeeper
  在内存中冻结 payload、展示实际内容，并由用户确认后在宿主侧保存文件或应用
  未暂存的 Git 补丁；不会自动 commit 或 push。
- 对不含 `Claude Science Shell.app` 的官方 Science 包，Routekeeper 不修改、
  不重签应用；它会在外层 Seatbelt 中启动包内已签名的 `claude-science` daemon，
  并用非持久化 `WKWebView` 承载官方 Web UI。WebView 只允许访问 daemon 实际
  建立的两个回环端口，外部导航、额外窗口和其他本机端口会被阻止，下载只会写入
  本次交换文件夹。
- 清理按宿主 Claude Desktop、宿主 Claude Code、宿主/沙箱 Claude Science、
  当前与历史 Routekeeper 会话、持久登录 profile 分组。只处理白名单内的缓存、
  临时文件和日志；会话与 profile 必须带有 Routekeeper 归属标记。相关 Claude
  或沙箱仍在运行时自动锁定，无法核验进程状态时按失败关闭策略跳过。Cookie、
  IndexedDB、Local Storage、Session Storage、WebStorage、HTTPStorages、
  对话、项目、设置、OAuth 与设备标识不会进入普通清理。
- 可选的 CLI 长期凭据助手，凭据只保存在当前用户的 Keychain。
- 支持隐私脱敏报告导出，并保留本机监控记录。

Routekeeper 只报告当前 Mac 上取得的证据，不承诺零泄漏、账号服务端状态或覆盖所有应用私有网络路径。

进程沙箱仍是实验功能。它依赖动态生成的 macOS `sandbox-exec` 配置；Apple
已标记这套接口为弃用，并可能改变行为。启动前检查失败时，Claude Code 不会
退回无限制运行。为防止绕过，受限进程不能监听 localhost 项目端口，也不能
自动启动默认浏览器；需要预览时应在会话结束后打开工作副本。该功能会尽量统一
会话时区、语言和 locale，但隔离进程和文件，不等同于虚拟机，不能伪装硬件
销售地区，也不能保证账号、设备指纹或服务端风控结果。

Claude Desktop 可以在沙箱内使用本机回环服务，但局域网和公网直连仍被禁止。
如果 Claude 尝试打开系统浏览器完成 OAuth，这一步可能失败；Routekeeper 不会
为此自动放宽公网访问。界面语言由会话时区推导，例如 `Asia/Shanghai` 对应
简体中文；这是启动参数和独立 HOME 的结果，不是读取了系统应用的界面语言设置。

Seatbelt 不会虚拟化主机网络元数据。沙箱中的 Claude 进程仍可调用
`/usr/sbin/ipconfig`、`/sbin/ifconfig` 或 `netstat` 等命令，读取网卡名称、
本机地址、路由和 DNS 解析器配置。这些信息不能让它绕过中继直连局域网或公网，
但可能参与设备指纹。若需要隐藏这些元数据，必须引入虚拟机或其他网络命名空间
边界；仅屏蔽命令名没有实际意义，因为同一信息仍可通过系统 API 读取。

Claude Science daemon 自带的嵌套沙箱无法在外层 Seatbelt 内再次申请
`sandbox-exec`，所以其日志可能显示内层沙箱不可用并继续运行。这里的强制边界
始终是 Routekeeper 创建的外层 Seatbelt；Routekeeper 不会使用
`--dangerously-no-sandbox`，也不会因为内层沙箱不可用而回退到无限制启动。

出口核对优先使用精确 IP 匹配。若代理节点让 Claude CDN 看到每次请求都变化的
IPv6 地址，Routekeeper 会改用同一中继的稳定 IPv4 出口作为锚点，并同时记录
本次 IPv6 证据；界面不会把两者描述成字面相等。直接粘贴一次轮换 IPv6 地址
不能作为稳定校验目标。

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

当前共 145 项测试，覆盖路由证据、IPv6、DNS/UDP 探测、报告脱敏、监控状态、
进程范围、抓包输入校验、界面行为、本地中继协议、Seatbelt 文件与网络边界、
系统代理配置对齐、localhost 监听拦截、子进程继承、沙箱状态处理，以及代理
网关证据的过期和启动门禁。测试还覆盖 Claude Science 官方包发现、daemon
启动、控制 socket、两个回环端口白名单、WebKit 内容规则编译、一次性 nonce
日志脱敏，以及轮换 IPv6 的稳定 IPv4 锚点。清空本地信息时还会校验
Routekeeper 自有数据、沙箱副本和用户保留范围的边界；缓存清理测试覆盖归属
标记、符号链接拒绝、宿主/会话/profile 分区，以及运行中进程的失败关闭保护。

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
- [授权隔离与外部操作交接](docs/authorization-handoff.md)
- [代理网关验证计划](docs/plans/2026-10-21-proxy-gateway-verification.md)
- [设计说明](docs/design.md)
- [网络验收](docs/network-v2-verification.md)
- [交接说明](HANDOFF.md)

## 隐私

设置保存在应用 UserDefaults，监控事件默认仅保留在内存，除非用户主动导出报告。
脱敏报告会移除地址、本地路径和进程标识。可选第三方网络体检会把当前出口地址
发送给该次体检使用的服务。
