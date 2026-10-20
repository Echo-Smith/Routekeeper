# Routekeeper

[English](README.md) | [简体中文](README.zh-CN.md)

Routekeeper is a native macOS network inspection and monitoring utility. It
checks whether observed IPv4 and IPv6 traffic follows the expected route,
helps compare expected and observed proxy exits, and can monitor selected
applications for network changes.

Version **0.3.10** (build 19) is a private development preview for macOS 14 or
later. The app is ad-hoc signed and the local DMG is not notarized.

## Features

- Menu bar monitoring that keeps running when the main window is closed and
  restores the Dock icon when the panel is reopened.
- IPv4 and IPv6 route evidence, system and explicit-proxy exit comparison,
  DNS resolver checks, and bounded UDP/STUN checks.
- Network service reachability checks for the endpoints configured by the
  application.
- Sleep, wake, path, DNS, proxy, and address-change invalidation. Unknown
  evidence never counts as a pass.
- Optional selected-process network filtering source using a Network
  Extension. The current ad-hoc build cannot activate the required system
  extension entitlement.
- Optional, time-limited packet-header capture after explicit administrator
  approval.
- An optional long-lived CLI credential helper that stores its value in the
  user's Keychain.
- Redacted diagnostic export and local monitoring history.

Routekeeper reports evidence from the current Mac. It does not promise
zero-leak operation, server-side account status, or immunity from every
application-specific network path. Review the on-screen limitations and
verification documents before relying on a check.

## Requirements

- macOS 14 or later.
- Xcode or a Swift 5.10-compatible toolchain.
- No third-party Swift packages.

The current release artifact is built for Apple Silicon. Intel Macs can build
from source with a matching Swift toolchain.

## Build and test

```sh
swift test --scratch-path /tmp/routekeeper-build
bash scripts/build-app.sh
bash scripts/build-dmg.sh
```

`build-app.sh` creates an ad-hoc signed `dist/Routekeeper.app`.
`build-dmg.sh` creates a draggable-to-Applications DMG for local distribution.
Build output and signing profiles are excluded from Git.

The test suite currently contains 73 tests covering route evidence, IPv6,
DNS/UDP probes, report redaction, monitoring state, process scope, capture
validation, and presentation behavior.

## Read-only CLI

```sh
"dist/Routekeeper.app/Contents/MacOS/Routekeeper" --self-check
"dist/Routekeeper.app/Contents/MacOS/Routekeeper" --egress-audit --output egress.json
```

These commands do not enable monitoring, change proxy settings, install a
system extension, or start packet capture. Exit code `0` means the requested
checks passed, `2` means the report contains failures, and `1` means the
command or output could not be completed.

## Distribution status

The checked-in source can build a local development package. Public
distribution still requires Developer ID signing, notarization, and validation
on the target macOS versions. Provisioning profiles and private signing
material are intentionally not committed.

## Documentation

- [Isolated runner plan](docs/plans/2026-10-21-isolated-runner.md)
- [Design notes](docs/design.md)
- [Network verification](docs/network-v2-verification.md)
- [Handoff notes](HANDOFF.md)

## Privacy

Settings remain in the app's user defaults and monitoring events remain in
memory unless the user exports a report. Diagnostic exports are designed to
redact addresses, paths, and process identifiers when the redacted format is
selected. Optional external checks may reveal the current exit address to the
third-party service used for that check.
