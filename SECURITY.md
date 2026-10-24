# Security Policy

## Supported versions

Security fixes target the latest source revision and the latest published
0.3.x preview. Older builds may not receive fixes.

安全修复面向最新源码和最新的 0.3.x 预览版本；更早的构建不保证继续收到修复。

## Reporting a vulnerability

Use the repository's **Security → Advisories → Report a vulnerability** flow to
send a private report. If that flow is unavailable, open a minimal public issue
asking the maintainer for a private contact channel. Do not include exploit
details or sensitive evidence in that public issue.

请在仓库的 **Security → Advisories → Report a vulnerability** 中私下提交。若该
入口不可用，只创建一个不含漏洞细节的公开 Issue，请维护者提供私下联系方式。

Include:

- affected version, macOS version and architecture;
- a concise impact statement and reproduction outline;
- whether credentials, sandbox escape, network bypass, arbitrary file access or
  privilege escalation may be involved;
- sanitized logs or proof-of-concept material after a private channel is agreed.

请提供受影响版本、macOS 版本与架构、影响概述和复现思路。不要在首次公开消息中
粘贴真实凭证、Cookie、公网 IP、个人路径、完整日志或其他敏感材料。

## Out of scope

- Reports that only describe expected lack of anonymity, absence of a full VM,
  server-side risk decisions or third-party service changes.
- Vulnerabilities in Claude, Chrome, macOS, a proxy client or another third-party
  service that Routekeeper cannot fix. Report those to the relevant vendor.
- Social engineering, spam, denial-of-service testing against third-party
  services, or tests that modify systems you do not own or have permission to use.
- Requests to bypass account, region or service controls.

本项目不承诺漏洞赏金。安全报告会按可用时间和实际影响处理；在修复发布前，请给
维护者合理的私下处理时间。
