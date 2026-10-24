# Sandbox Network Isolation

## Problem

Claude Desktop / Code 和受控浏览器运行在 macOS `sandbox-exec` 内时，网络流量已经收敛到本机 relay，但仍可能读取宿主物理网卡、IP、路由与 DNS 元数据；浏览器还可能通过 WebRTC/UDP 观察到真实出口。我们希望用 Network Extension 与 relay 组成双层控制面，使沙箱内工作负载只能通过受控出口通信，减少真实用户地址与本地网络暴露。

## Goals

1. 保护对象内的 TCP/UDP/DNS 流量默认阻断，仅允许本机 relay。
2. relay 按会话策略决定真实出口、上游代理与允许目标。
3. Claude 与受控浏览器共用同一隔离网络模型。
4. 过滤器、relay、沙箱任一组件不可用时按 fail-closed 处理。
5. 现有正常应用不受影响。

## Non-Goals

1. 不伪造 `ifconfig`、`route`、`SCDynamicStore`、DNS 配置等宿主网络元数据；macOS Seatbelt/Network Extension 不提供进程级网络 namespace。
2. 不做全机防火墙，不修改其他应用的网络配置。
3. 不依赖阻止读取元数据来宣称“物理网卡不可见”；隐私承诺只限流量出口与浏览器可观测网络面。
4. 不在缺少有效签名、授权与实机验收时宣称强制保护生效。

## User Stories

1. 作为用户，我启动隔离 Claude/浏览器后，它们不能直连公网、局域网或我的物理接口地址，只能经过 Routekeeper relay。
2. 作为用户，我断开上游代理或切换网络时，受控应用立即失去出口，而不是回落到真实网络。
3. 作为用户，我可以为一次会话配置允许的目标、出口接口或上游代理，并能在 UI 看到当前出口锚点与规则状态。
4. 作为用户，未选中的浏览器、编辑器、终端和其他应用保持原有联网能力。

## EARS Acceptance Criteria

1. When a protected Claude 或受控浏览器进程建立到非 `127.0.0.1:<relay-port>` 的 TCP/UDP flow, Network Extension shall drop the flow。
2. When a protected process 连接当前会话 relay, Network Extension shall allow only该 loopback endpoint。
3. When relay 收到目标 host/port, relay shall 先执行本地网段拒绝、目标 allow/deny 策略，再连接上游。
4. When 目标不在会话策略内, relay shall 拒绝连接并向客户端返回可诊断错误。
5. When 用户配置出口接口, relay 上游连接 shall 绑定该接口或其本机地址；不可用时 shall 拒绝建立上游而不是回落默认接口。
6. When NE 过滤器未安装、未运行、被用户拒绝或 provider 崩溃, UI shall 显示强制隔离未生效，并不得宣称已阻断。
7. When 系统休眠、唤醒、网络路径、代理、DNS 或 relay 端口变化, 当前会话 shall 保留进程但进入断流状态，等待重新验证后恢复。
8. When 隔离会话运行, 用户执行真实活动时, 有界抓包 shall 能在非 relay 的物理/tunnel 接口上观察到零条可归属到保护对象的外联包；无数据 shall 记录为 unknown，不判定为通过。
9. When 受控浏览器使用 WebRTC/STUN, 其 UDP shall 被 NE 或浏览器策略阻断，不得获得真实接口候选地址。
10. When 沙箱内进程读取宿主接口元数据, 系统仍可能返回真实数据；文档与 UI shall 明确该边界，不得将其表述为虚拟网卡。

## Constraints

1. Content Filter / System Extension 需要 Apple 付费团队的有效签名、provisioning profile 与用户授权；当前开发环境缺少该能力。
2. 现有 `FilterDataProvider` 已按 audit token 识别进程并只放行 relay；应优先扩展该实现，避免全机规则。
3. relay 只稳定覆盖显式使用 SOCKS5/HTTP CONNECT 的工作负载；直连 TUN、原生 UDP 与不遵守代理设置的进程必须由 NE 阻断。
4. NE 不保证过滤器进程故障时总能同步通知 UI；验收必须包含重启、升级与崩溃场景。
