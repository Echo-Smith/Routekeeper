# Routekeeper 隐私说明

生效日期：2026-10-24

本说明描述 Routekeeper 当前版本如何在本机保存数据、何时访问网络，以及你可以
如何清除相关数据。它适用于 macOS 应用、源码构建版本和仓库发布的文档。

## 摘要

- Routekeeper 没有开发者运营的账号系统、遥测、广告 SDK 或自动报告上传服务。
- 开发者不会通过 Routekeeper 自动收到你的 IP、浏览内容、登录凭证、工作区或日志。
- 体检、代理、Claude、Chrome、DNS、STUN 和可选 IP 情报查询会直接连接第三方，
  第三方可能看到你的公网出口 IP 和请求元数据。
- 报告、出口历史、沙箱会话和浏览器配置默认保存在本机，直到你主动清除。
- GitHub 的访问、Issue、Release 下载等由 GitHub 处理，适用 GitHub 自身政策。

## 本机保存的数据

| 数据 | 位置 | 用途与保留 |
|---|---|---|
| 应用设置、语言、协议版本 | macOS `UserDefaults` | 保存界面和检查偏好，直到清除应用数据 |
| 出口历史、最近两次体检报告 | macOS `UserDefaults` | 在应用内比较出口变化；可分别清除 |
| Claude Code 登录凭证 | macOS Keychain | 只在保存和由 Routekeeper 启动 Claude Code 时读取 |
| 沙箱会话 HOME、临时文件、日志、控制文件 | `~/Library/Application Support/Routekeeper/Isolation/` | 供实验性沙箱运行和诊断；可在清理页按归属清除 |
| 持久 Claude 登录 profile | `~/Library/Application Support/Routekeeper/Profiles/ClaudeDesktop/Home/` | 仅在用户显式启用持久登录时保存 Cookie 和 Claude 本地数据 |
| Routekeeper Chrome profile、缓存和下载 | `~/Library/Application Support/Routekeeper/Profiles/ClaudeWeb/` | 仅用于专用 Chrome 实例，不导入宿主 Chrome 配置 |
| 项目工作副本和交换文件 | `~/Routekeeper/Workspaces/` 及用户选择的交换目录 | 供用户审阅、交付和手动采用；不会自动覆盖原项目 |
| 用户主动导出的报告 | 用户选择的位置 | 由用户自行管理和删除 |

沙箱工作副本、持久登录 profile 和浏览器 profile 带有 Routekeeper 归属标记。
清理功能只处理能够确认归属的数据，并会在相关进程无法核验或仍在运行时采用失败
关闭策略。

## 网络请求

Routekeeper 只在执行相应功能时直接连接服务。当前版本可能访问：

| 服务或目标 | 触发条件 | 可能暴露的信息 |
|---|---|---|
| `api.ipify.org`、`api6.ipify.org` | 网络体检、网关核验、沙箱出口核验、手动出口体检 | 公网出口 IP、请求时间、TLS/HTTP 元数据 |
| `ipinfo.io` | 网络体检中的路径与出口检查 | 公网出口 IP、请求时间、请求元数据 |
| `claude.ai`、`api.anthropic.com`、`console.anthropic.com` | Claude 路径、TLS、IPv6 和可达性检查 | 公网出口 IP、请求时间、目标域名和网络元数据 |
| STUN 服务 `stun.cloudflare.com`、`stun.l.google.com` | 启用 UDP 探测并运行体检时 | UDP 映射地址、请求时间和网络元数据 |
| 系统 DNS 解析器及查询目标 | 启用 DNS 探测并运行体检时 | 查询名称、请求时间和解析器元数据 |
| `ipwho.is`、`ipapi.is` | 仅在用户开启第三方 IP 信息并手动运行体检时 | 当前出口 IP 和请求元数据；默认关闭 |
| 用户配置的本机代理上游 | 启动代理路径检查、监控或沙箱会话时 | 由代理服务商按其政策处理 |
| Claude、Chrome 和更新/安装页面 | 用户主动启动、登录或点击链接时 | 对应第三方按其政策处理 |

自动出口体检不会调用第三方 IP 情报服务。Routekeeper 不会自动上传导出的报告，
也不会把报告、日志或工作区发送到开发者服务器。

## 登录凭证与浏览器数据

Claude Code 长期凭证保存在 macOS Keychain。Routekeeper 不会把凭证写入项目、
报告、交换目录或普通日志。沙箱内启动使用独立环境，宿主和沙箱的登录状态不会
因为 Routekeeper 而自动同步。

Chrome 使用 Routekeeper 专用 profile，不读取或导入宿主 Chrome 的 Cookie、
密码、历史、扩展或其他配置。该专用 profile 中的登录状态会保留，直到你在应用内
清除 Chrome 配置或清空本地信息。

持久 Claude 登录默认关闭。启用后，工作副本、日志和临时文件仍按会话隔离，但
Cookie 和 Claude 本地数据会保存在 Routekeeper 专属 HOME 中，直到你清除该
profile 或重置本地信息。

## 报告与日志

普通诊断报告可选择脱敏格式，移除地址、本地路径和进程标识。原始报告、抓包结果
或手动选择的沙箱日志可能包含更具体的信息，导出前应自行检查并妥善保管。

Routekeeper 不包含自动崩溃上报或分析 SDK。macOS 自身的系统诊断、Apple 服务、
GitHub 和你使用的第三方服务可能按其各自政策处理数据。

## 用户控制

- 可在应用设置和清理页清除出口历史、报告、沙箱会话、profile 和本地数据。
- 可单独清除 Chrome 配置和持久 Claude 登录 profile。
- 可关闭 DNS、STUN、第三方 IP 情报和自动体检等可选功能。
- 可随时停止监控、结束沙箱会话或退出 Routekeeper。

某些安全相关操作会拒绝在进程状态无法核验时继续，以避免误删或覆盖无法确认
归属的数据。

## 儿童与敏感数据

Routekeeper 面向能够自行管理 macOS 网络、应用和第三方账号的用户，不面向儿童。
不要在网络检查、Issue、日志或导出报告中提交他人的凭证、Cookie、身份文件、
精确地址或其他高度敏感信息。

## 变更

功能、数据流或第三方服务发生变化时，本说明可能更新。重大变化会通过应用内协议
版本、仓库提交或发布说明提示。

## 联系

一般隐私问题请通过 GitHub Issues 提交，并先移除 IP、路径、凭证和设备指纹等
敏感内容。安全漏洞请按照 `SECURITY.md` 私下报告。
