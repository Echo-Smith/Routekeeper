# GitHub 发布清单

本文用于首次公开 Routekeeper 源码。目标不是把所有开发资料一次性上传，而是让
访问者能理解项目、构建项目、报告问题和遵守非商业许可，同时不泄露作者或测试
用户的本地信息。

## 推荐的项目介绍

仓库短描述建议使用：

> 原生 macOS 网络体检、出口核验与 Claude 环境隔离工具。源码公开，仅限个人
> 学习与非商业交流。

英文短描述建议使用：

> Native macOS network inspection, egress verification and experimental Claude
> environment isolation. Source-available for personal, noncommercial use.

首屏介绍应说明：

- 它解决什么问题：核验 IPv4/IPv6 路径、代理出口、Claude 可达性和实验性隔离；
- 它不是哪些东西：不是 Claude 官方产品、不是虚拟机、不承诺匿名、零泄漏或
  账号风控结果；
- 许可边界：个人和非商业用途免费，禁止商业使用，不是 OSI 开源许可；
- 当前分发状态：源码可构建，DMG 仍需 Developer ID 签名和 Apple 公证；
- 隐私边界：没有遥测，报告和沙箱数据保存在本机，体检会直接连接第三方服务；
- 安全边界：实验性沙箱使用已弃用的 `sandbox-exec`，不能替代虚拟机。

避免使用“绝对安全”“零泄漏”“防封”“绕过地区限制”等不可验证或以规避服务
控制为目的的宣传。

## 建议公开的文件

- `LICENSE`
- `README.md`、`README.zh-CN.md`
- `TERMS.md`、`TERMS.zh-CN.md`
- `PRIVACY.md`、`PRIVACY.zh-CN.md`
- `SECURITY.md`、`CONTRIBUTING.md`
- `Package.swift`
- `Sources/`
- `Tests/`
- `NetworkExtension/`
- `scripts/`
- `docs/assets/routekeeper-icon.png`
- `docs/FEATURES.zh-CN.md`
- `docs/authorization-handoff.md`
- `docs/design.md`
- `docs/network-v2-verification.md`

## 不应提交的内容

- `.build/`、`dist/`、`DerivedData/`、`.xcarchive`、DMG、ZIP 和本地 `.app`；
- Provisioning Profile、`.p12`、证书、私钥、钥匙串导出和签名脚本参数；
- `.DS_Store`、Xcode 用户状态、编辑器配置和本地环境文件；
- 真实运行报告、出口历史、抓包结果、日志、沙箱 HOME、工作副本和 Chrome profile；
- 真实 IP、账号、Cookie、token、邮箱、用户名、绝对路径、聊天截图或聊天记录；
- 未经授权公开的第三方私有代码、素材、文档或凭据。

`HANDOFF.md`、`docs/plans/`、`specs/` 和
`docs/claude-switcher-comparison.md` 属于开发历史、内部计划或第三方对比材料，
不建议作为首次公开仓库的主文档。如需保留，应放入私有维护分支或内部目录，并
在发布前单独审查。

## 发布前检查

1. 在干净检出中运行 `swift test --disable-sandbox --scratch-path /tmp/routekeeper-build`。
2. 运行 `bash scripts/build-app.sh` 和 `git diff --check`。
3. 搜索 `token`、`password`、`secret`、`BEGIN PRIVATE KEY`、邮箱、真实用户名、
   绝对路径和公网 IP；测试数据只使用 RFC 5737/3849 文档地址或示例值。
4. 确认 `git ls-files signing`、`git ls-files dist` 和 `git ls-files .build`
   均为空。
5. 检查 Git 历史中的旧提交是否曾包含凭证或个人文件。若包含，仅删除当前文件
   不够，必须撤销凭证并清理历史后再公开。
6. 检查 README 中的下载链接、版本号、测试数量和公证状态是否与实际情况一致。

## Release 建议

首个公开版本可以提供源码、经审核的 Release Notes，以及明确标注为开发预览的
ad-hoc DMG。DMG 页面必须写明“未经 Developer ID 签名和 Apple 公证”，不得将
它描述为生产级安全发行包。若要提供稳定版公共二进制：

- 使用 Developer ID Application 证书签名；
- 完成 Apple 公证和 `stapler` 附加；
- 标明 macOS 最低版本和 CPU 架构；
- 提供 SHA-256 校验值；
- 在 `SECURITY.md` 和发布说明中明确支持范围；
- 不使用未公证的 ad-hoc 包作为正式公开下载。
