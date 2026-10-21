# Routekeeper

[English](README.md) | [简体中文](README.zh-CN.md)

Routekeeper is a native macOS network inspection and monitoring utility. It
checks whether observed IPv4 and IPv6 traffic follows the expected route,
helps compare expected and observed proxy exits, and can monitor selected
applications for network changes.

Version **0.3.12** (build 22) is a private development preview for macOS 14 or
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
- A staged proxy-gateway check for the current path, overseas-node failure,
  proxy-client exit, and restored connectivity. Evidence expires after network,
  proxy or settings changes, sleep/wake, a Routekeeper restart, or 15 minutes.
  Selected gateway protection blocks monitoring and desktop launch until fresh
  evidence passes.
- Optional selected-process network filtering source using a Network
  Extension. The current ad-hoc build cannot activate the required system
  extension entitlement.
- Optional, time-limited packet-header capture after explicit administrator
  approval.
- An optional experimental process sandbox for Claude Code. It runs a reviewed
  project copy with an isolated HOME, a selected session timezone, local
  HTTP CONNECT or SOCKS5 proxy upstreams, and process-level fail-closed
  networking. A detectable system proxy is aligned automatically, and Claude
  reachability is compared with the saved exit. The original project is never
  changed automatically.
- An optional long-lived CLI credential helper that stores its value in the
  user's Keychain.
- Redacted diagnostic export and local monitoring history.

Routekeeper reports evidence from the current Mac. It does not promise
zero-leak operation, server-side account status, or immunity from every
application-specific network path. Review the on-screen limitations and
verification documents before relying on a check.

The process sandbox is experimental. It relies on dynamically generated macOS
`sandbox-exec` profiles, which Apple marks as deprecated and may change. A
preflight failure keeps Claude Code from launching with unrestricted access.
Sandboxed processes cannot listen on localhost project ports or launch the
default browser automatically; preview work after ending the session instead.
The sandbox keeps session timezone, language and locale consistent, but it is
process and file isolation, not a full virtual machine. It cannot spoof the
hardware sales region and does not guarantee account, device-fingerprint, or
server-side risk outcomes.

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

The test suite currently contains 98 tests covering route evidence, IPv6,
DNS/UDP probes, report redaction, monitoring state, process scope, capture
validation, presentation behavior, local relay protocols, Seatbelt file and
network enforcement, system-proxy alignment, localhost-listener blocking,
child-process inheritance, sandbox status handling, local-data reset boundaries,
and proxy-gateway evidence freshness and launch gating.

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

Apple Development and App Store signing use the `content-filter-provider`
Network Extension entitlement. Direct distribution signed with a Developer ID
Application certificate uses `content-filter-provider-systemextension`. The
signed build script selects the value allowed by the supplied provisioning
profiles.

## Documentation

- [Isolated runner plan](docs/plans/2026-10-21-isolated-runner.md)
- [Proxy gateway verification plan](docs/plans/2026-10-21-proxy-gateway-verification.md)
- [Design notes](docs/design.md)
- [Network verification](docs/network-v2-verification.md)
- [Handoff notes](HANDOFF.md)

## Privacy

Settings remain in the app's user defaults and monitoring events remain in
memory unless the user exports a report. Diagnostic exports are designed to
redact addresses, paths, and process identifiers when the redacted format is
selected. Optional external checks may reveal the current exit address to the
third-party service used for that check.
