# claude-switcher 源码分析与 Routekeeper 对比

此文比较基线为升级前的 Routekeeper 0.1.0。当前 0.2.0 已根据本报告补充能力，见 README；以下“当前”均指当时基线。

分析日期：2026-10-20。目标仓库：https://github.com/YOURSJEYO/claude-switcher 。查询到的 main 提交为 `74ea09e2e7db14968548a5fab7b97e96b4b1b330`；分析文件从紧接着下载的 main ZIP 取得，未单独校验 ZIP 与该提交的绑定。对比对象为当前工作区 Routekeeper 源码。静态阅读 macOS 主流程、探针、守护和安装卸载代码；Windows/Linux 仅作目录、说明和相关代码抽查。未安装、执行目标脚本，未改系统设置，未验证真实网络故障行为。

## 判断

方向高度重合：代理环境检查、出口监测、异常时退出 Claude。claude-switcher 扩展为“账号切换 + 环境检查 + 系统修复”的启动工具；Routekeeper 当前是“适配 FlClash，独立选择桌面版/Code，固定出口监测”的菜单栏工具。

它的功能面更宽，但源码不足以支持 README 中“物理上无法泄漏”“任一指标不达标就无法启动”的绝对承诺。我们当前也没有强制网络阻断能力，不能把相对更严谨的检测等同于零泄漏。

## 实现地图

| 模块 | 实现 | 作用 |
|---|---|---|
| 界面 | `app/main.swift`，471 行 | SwiftUI 调用 Bash，通过文本行解析检查与切换结果 |
| 核心 | `core/claude-switch.sh`，365 行 | 安检、状态、一键修复、A/B 账号存档交换 |
| UDP 探测 | `core/stun-probe.py`，69 行 | 并发请求四个 STUN 服务，解析 IPv4 映射地址 |
| 运行保护 | `daemons/claude-bodyguard.sh` + plist | launchd 每 10 秒调度，代理进程/TUN 特征缺失时 pkill |
| 配置恢复 | `daemons/tz-watchdog.sh` + plist | 每小时检查并恢复固定时区 |
| 安装 | `installer/安装.command` | 写脚本、装系统守护、改时区、关闭 Wi-Fi IPv6、覆盖代理扩展规则 |
| 其他平台 | `windows/`、`linux/` | PowerShell/WPF 与 Bash/systemd，项目标注 Beta |

以上行数对应本次下载。仓库 MIT 许可；引用代码应保留许可声明和版权信息。这里的阅读不是完整法律审查。

## 关键发现

### 1. Kill-Switch 实际是轮询后请求退出

证据：`daemons/local.claude-bodyguard.plist` 的 `StartInterval=10`；`daemons/claude-bodyguard.sh:7-13` 只检查 `verge-mihomo` 进程与 `inet 198.18.*` 地址，失败时 `pkill -f`。

在检查之间存在时间窗口；`pkill` 默认发送 SIGTERM，没有确认进程确实退出。代理进程与地址仍存在时，出口漂移、错误分流或隧道失效也可能不触发。所读 macOS 实现没有建立防火墙或 Network Extension 网络阻断规则。因此源码不能证明“一个 SYN 包都不会泄漏”。

### 2. 14 项检查没有统一成为启动门禁

证据：`core/claude-switch.sh:97-169` 输出 14 项；`app/main.swift:19-30,94-114` 只声明、映射 11 项。新增的客户端语言、ASN 属性、生态可达性结果不影响 GUI 的 ready 判定。`warn` 也不会阻止 ready。

`switch_to()`（核心脚本 310-347 行）没有调用 `check()`，切换到当前账号的分支直接 `open -a Claude`，其他分支交换目录后直接启动。界面检查与启动之间没有再次核验；直接双击 Claude 也不受这个启动器约束。

这说明它具有界面层面的启动前检查，但不是不可绕过的系统门禁。

### 3. IP 基线会被检查动作更新

证据：核心脚本 35-39、104-109 行，每次检查都会写 `lastip`，IP 变化只是 warning。重新检查后，新 IP 可成为比较基线。它没有实现我们当前的“用户确认固定目标 IP，运行结果必须匹配”约束。

### 4. STUN 是有价值的补充，但无响应不能判安全

证据：探针使用 `socket.AF_INET`；DNS 解析、收发失败返回 None，硬超时也输出 `RESULT:NONE`。核心脚本 123 行把 NONE 展示为“UDP 不出网，零暴露”。

无响应也可能来自 DNS 故障、服务器不可用、丢包或超时，不能据此证明 UDP 被阻断。它只测 IPv4 UDP 映射，不是实际浏览器 ICE/WebRTC 全流程，也不能证明 IPv6、TCP 或目标应用全部连接的行为。解析器还未校验响应事务 ID 与来源是否匹配请求。

可借鉴并发 STUN 对比思路，但应将结果分为“观察到一致出口”“观察到不同出口”“未取得有效结果”，第三类必须标记未知。

### 5. TUN、DNS、IPv6 的证据覆盖较窄

证据：核心脚本 21 行以任意接口的 `198.18.*` 地址判定 TUN；50-53 行以 `claude.ai` 返回 `198.18.*` 判 DNS 通过；47-48 行仅查询名为 Wi-Fi 的服务是否关闭 IPv6。

这些检查偏向特定 Clash Fake-IP 配置。地址存在不能证明实际目标路由被接管，Fake-IP 响应不能证明所有 DNS 无泄漏，Wi-Fi 的 IPv6 状态不覆盖以太网或其他服务。规则检查只是 grep 配置中的一个字符串，不验证完整规则优先级和运行内核的有效配置。

### 6. 账号快照并非完整事务或完整凭据隔离

证据：核心脚本 303-347 行使用 ditto 复制 `~/Library/Application Support/Claude`，然后 `rm -rf` 原目录再 mv 新目录；脚本仅 `set -u`，复制和归档错误没有在所有调用处强制中止，也没有切换互斥锁与完整回滚。

删除原目录与替换目录是多个步骤，不能称为原子交换。若复制失败或磁盘满，存在丢失当前数据或错误报告成功的风险。源码中未看到 Keychain 凭据同步/隔离处理，因此“全部 OAuth 凭据与设备指纹都独立”的覆盖仍需针对真实客户端版本验证。普通目录快照也不等于加密凭据保险箱。

### 7. 系统修改与安装交付有明显欠账

- 安装器 58-59、119 行引用 `installer/files/` 下的脚本与预编译 App，但本次源码 ZIP 没有该目录。README 的直接双击源码安装流程依赖未附带的文件，不能按当前仓库布局直接成立。
- 安装器 123 行和 fix 流程使用重定向覆盖 `profiles/Merge.yaml`，未备份、合并用户已有扩展规则。
- 系统 LaunchDaemon 以默认系统身份执行用户可写的 `~/.local/bin/*.sh`，造成不合适的特权信任边界；如设计特权 helper，应使用受保护安装位置并限制可执行操作。
- 卸载脚本移除守护和部分文件，但没有恢复原时区、IPv6 和代理规则。时区 watchdog 是每小时恢复时区，不是完整代理配置持续自愈；TUN 修复主要在用户触发 fix 时执行。
- 在所下载文件中没有发现测试套件或 CI 配置；没有据此评定其真实用户规模或实际故障率。

## 与当前 Routekeeper 对比

| 维度 | claude-switcher 的 macOS 版本 | 当前 Routekeeper |
|---|---|---|
| 产品主线 | A/B 账号启动与切换，附带检查/修复 | 固定出口监测与异常处置 |
| 代理适配 | Clash Verge、verge-mihomo、Fake-IP 特征 | FlClash、系统 HTTPS 代理、双目的地路由 |
| 保护范围 | 固定路径桌面主进程 | 桌面与 Code 分别可选，识别部分编辑器扩展路径 |
| 出口约束 | 美国判断；上次 IP 变化警告，检查更新基线 | 用户确认固定 IP；显式代理与不显式代理两路均匹配 |
| TUN 证据 | 找到 198.18.* 接口地址 | 两个公网目的地走同一 utun；仍不单独证明归属 |
| 异常动作 | 10 秒调度后按命令行模式 pkill | 每轮完成再等 3 秒；可提醒或身份复核后 SIGTERM |
| 恢复方式 | 后续轮询不再杀进程，没有持续事故锁定状态 | 异常锁定；用户重新检查并开启 |
| IPv6 | 关闭并检查 Wi-Fi IPv6 | 仅检查目标地址族；另一地址族尚未覆盖 |
| 附加探测 | STUN、DNS、时区、Locale、语言、ASN、连通性 | 当前未覆盖这些附加项 |
| 系统侵入 | 修改系统设置、代理配置、安装 root 守护 | 核心监测不修改系统网络配置 |
| 数据处理 | 替换账号数据目录 | 可选白名单缓存清理，移到废纸篓 |
| 强制断网 | 所读实现没有 | 没有 |

“每轮完成后等 3 秒”不等于固定 3 秒检测；网络查询和超时会延长周期。两者都有检测窗口。

## 对我们下一步的建议

1. **先补网络证据覆盖。** 双地址族检测、实际活动网络服务识别、网络切换后的重新检查、DNS/UDP 探测；统一输出通过、失败、未知及证据时间。沿用固定 IP 基线，绝不由检查动作静默改写。
2. **补代理 adapter 与持续健康诊断。** 在 FlClash 基础上扩展 Clash Verge/mihomo；抽象进程、系统代理、目标路由、内核健康和有效配置证据，避免把某个网段或客户端名称当成通用事实。
3. **把可靠恢复做成产品能力。** 休眠唤醒、Wi-Fi/以太网切换、代理重启后作废旧快照，解释原因、引导重新检查；继续保留事故锁定和进程身份复核。
4. **如要承诺强制防泄漏，应另立系统阻断阶段。** 必须先定义进程/流量归属、隧道失效与恢复策略，再验证强制网络约束。断代理、切网络、IPv6、休眠唤醒、子进程和保护器崩溃时应抓包验收。不能以更短轮询或更多检查项替代。
5. **多账号作为独立后续功能。** 先确认用户需求，再设计凭据范围、快照权限、互斥、容量预检、事务恢复与回滚。当前无需为追齐竞品而引入账号数据写入能力。

时区、语言、Locale、ASN 可以作为用户可理解的环境信息，不能无证据地等同于封号原因或默认自动修改。项目 README 关于平台风控机制与“绝大多数封号原因”的叙述，在本次源码中没有可核验依据。

建议定位：**让用户知道 Claude 当前是否走预期网络，并在异常后保持明确、可恢复的保护状态。** 功能数量之外，应以覆盖范围、检测误判、异常窗口、恢复行为和可复现验证建立差异。

## 来源

- [目标仓库](https://github.com/YOURSJEYO/claude-switcher)
- [核心脚本](https://github.com/YOURSJEYO/claude-switcher/blob/74ea09e2e7db14968548a5fab7b97e96b4b1b330/core/claude-switch.sh)
- [SwiftUI 界面](https://github.com/YOURSJEYO/claude-switcher/blob/74ea09e2e7db14968548a5fab7b97e96b4b1b330/app/main.swift)
- [STUN 探针](https://github.com/YOURSJEYO/claude-switcher/blob/74ea09e2e7db14968548a5fab7b97e96b4b1b330/core/stun-probe.py)
- [守护实现](https://github.com/YOURSJEYO/claude-switcher/tree/74ea09e2e7db14968548a5fab7b97e96b4b1b330/daemons)
- [安装卸载](https://github.com/YOURSJEYO/claude-switcher/tree/74ea09e2e7db14968548a5fab7b97e96b4b1b330/installer)
- 本地依据：`README.md`、`Sources/GuardCore/{Diagnostics,LocalSystem,Models,Cleaner}.swift`、`Sources/Routekeeper/GuardStore.swift`。未将旧 HANDOFF 中的测试成绩视为本轮重新测试结果。
