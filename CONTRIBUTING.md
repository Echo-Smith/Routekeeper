# Contributing to Routekeeper

Routekeeper is a source-available, noncommercial project for personal learning
and technical exchange. Contributions are welcome when they improve safety,
correctness, accessibility, documentation or maintainability without adding
commercial or abusive capabilities.

Routekeeper 是仅限非商业用途的源码公开项目。欢迎围绕安全、正确性、可访问性、
文档和可维护性提交改进；不接受商业集成、规避服务控制或滥用能力。

## Before contributing

- Read `LICENSE`, `TERMS.md` and `PRIVACY.md`.
- Open an issue before a large behavior, data-flow, permission or dependency
  change.
- Never include credentials, cookies, personal paths, complete IP addresses,
  signing profiles, provisioning profiles, private keys or unredacted reports.
- Use synthetic or documentation IP ranges in tests. Never commit a real user's
  egress address or account data.

## Development

Requirements:

- macOS 14 or later;
- Xcode or a Swift 5.10-compatible toolchain;
- no third-party Swift package dependencies.

Build and test:

```sh
swift build --disable-sandbox --scratch-path /tmp/routekeeper-build
swift test --disable-sandbox --scratch-path /tmp/routekeeper-build
bash scripts/build-app.sh
```

Before submitting:

```sh
git diff --check
```

Keep changes focused. Add or update tests for state transitions, parsing,
security boundaries, cleanup ownership and other non-UI behavior. UI changes
should be checked in both Chinese and English and at supported window sizes.

## Security-sensitive changes

Changes involving `sandbox-exec`, the Network Extension, process identity,
credential handling, Keychain access, local relays, cleanup, Chrome profiles,
workspace copying or Git handoff require:

- an explicit threat-boundary description;
- a fail-closed path when identity or state cannot be verified;
- tests for rejection, cancellation and malformed input;
- no expansion of host file, network or credential access without clear user
  benefit and documentation.

Do not weaken checks merely to make a preview or launch pass.

## Licensing of contributions

By submitting a contribution, you agree that it may be distributed as part of
Routekeeper under the repository's current noncommercial license and that you
have the right to submit it. Do not copy code with incompatible terms. Identify
third-party code, data or assets and their licenses in the pull request.

提交贡献即表示你同意该贡献按项目当前的非商业许可分发，并确认你有权提交。
不要引入许可不兼容的代码、数据或素材。

## Review and conduct

Be factual, specific and respectful. Security findings and privacy risks take
priority over visual polish. Maintainers may reject changes that conflict with
the project's noncommercial scope, safety boundaries or verification standards.
