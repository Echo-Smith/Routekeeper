<p align="center">
  <img src="docs/assets/routekeeper-icon.png" width="160" height="160" alt="Routekeeper icon">
</p>

<h1 align="center">Routekeeper</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.zh-CN.md">简体中文</a>
</p>

Routekeeper is a native macOS network inspection and monitoring utility. It
checks whether observed IPv4 and IPv6 traffic follows the expected route,
helps compare expected and observed proxy exits, and can monitor selected
applications for network changes.

Version **0.3.12** (build 22) is a private development preview for macOS 14 or
later. The app is ad-hoc signed and the local DMG is not notarized.

## Download and install

[Download Routekeeper 0.3.12](https://github.com/Echo-Smith/Routekeeper/releases/tag/v0.3.12)

1. Open the DMG.
2. Drag `Routekeeper.app` into the Applications folder.
3. Launch Routekeeper from Applications.

The current package is ad-hoc signed and not notarized by Apple. If macOS blocks
the first launch, allow it from System Settings → Privacy & Security. The
current artifact supports Apple Silicon only.

## Features

- Menu bar monitoring that keeps running when the main window is closed and
  restores the Dock icon when the panel is reopened.
- IPv4 and IPv6 route evidence, system and explicit-proxy exit comparison,
  DNS resolver checks, and bounded UDP/STUN checks.
- Network service reachability checks for the endpoints configured by the
  application.
- An explainable Protection completeness score in Overview. It summarizes only
  applicable evidence, never treats disabled optional features as failures, and
  never blocks Claude, monitoring, sign-in or the experimental sandbox.
- Live Claude process evidence uses TCP connection counts plus redacted proxy,
  custom API, locale and timezone variable metadata. Raw environment values,
  arguments and credentials are not stored in reports.
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
- An optional experimental process sandbox for Claude Code and a signature-
  verified official Claude Desktop app. It uses a reviewed workspace copy, an
  isolated HOME, a selected session timezone, local HTTP CONNECT or SOCKS5
  upstreams, and process-level fail-closed networking. A detectable system
  proxy is aligned automatically, and the Claude path and observed exit are
  checked. The original project is never changed automatically.
- Sandbox is a top-level workspace rather than a hidden Protection submenu.
  Enabling it turns Network check into the sandbox's own exit, relay, preflight
  and session checks. Routekeeper can detect and save the matching exit directly
  in that flow instead of requiring a separate ordinary-check detour.
- Network notifications pass through a roughly 1.6-second stability window and
  fingerprint recheck. The relay closes only for a material proxy address, port,
  protocol or credential change, or a final preflight failure. Duplicate path,
  DNS and unrelated-interface notifications no longer interrupt Claude. Sleep
  closes immediately; wake restores an automatic pause only when the original
  configuration still validates. A manual pause never resumes by itself.
- Claude Desktop sign-in persistence is explicit. Workspaces, logs and temporary
  files remain session-scoped, while cookies, local sign-in state and Claude data
  can stay in a Routekeeper-owned HOME and be cleared separately. The option is
  off by default.
- Input-method compatibility grants read access only to the exact `.app` bundles
  of currently enabled or selected input methods, such as
  `/Library/Input Methods/WeType.app`. It does not open all of `/Library` and
  does not read dictionaries, history, learning data or other input-method user
  data.
- Claude Desktop email sign-in uses a local callback broker: copy the official
  `claude.ai/magic-link` URL from the email and paste it into Routekeeper. It
  validates the link in memory, never fetches it, never saves or logs its token,
  and delivers the callback only to the currently recorded sandboxed Claude
  instance instead of falling back to a browser outside the sandbox.
- Authorization handoff lets Claude submit external operations as a JSON
  manifest and payload in the exchange folder without exposing Git remotes, SSH
  keys, GitHub/Notion tokens or host links to the sandbox. Routekeeper freezes
  the payload in memory, shows its actual contents, and only after user approval
  saves a file or applies an unstaged Git patch on the host. It never commits or
  pushes automatically.
- For an official Science package without `Claude Science Shell.app`,
  Routekeeper does not modify or re-sign the app. It starts the signed
  `claude-science` daemon inside an outer Seatbelt profile and hosts the
  official web UI in a non-persistent `WKWebView`. The view can reach only the
  daemon's two actual loopback ports; external navigation, extra windows and
  other local ports are blocked, and downloads go only to the session exchange
  folder.
- Cleanup is grouped by host Claude Desktop, host Claude Code, host/sandboxed
  Claude Science, current and past Routekeeper sessions, and the persistent
  sign-in profile. Only allowlisted caches, temporary files and logs are
  considered; sessions and profiles must carry Routekeeper ownership markers.
  Matching running processes lock their targets, and unavailable process
  inspection fails closed. Cookies, IndexedDB, Local Storage, Session Storage,
  WebStorage, HTTPStorages, conversations, projects, settings, OAuth files and
  device identifiers are excluded from ordinary cleanup.
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

Claude Desktop may use loopback services inside the sandbox, but direct LAN and
public connections remain blocked. If Claude attempts to open the system browser
for OAuth, that step may fail; Routekeeper does not widen public access for it.
The UI language is derived from the session timezone (for example,
`Asia/Shanghai` maps to Simplified Chinese) through launch arguments and the
isolated HOME rather than by reading the host app's UI language.

Seatbelt does not virtualize host network metadata. A sandboxed Claude process
can run queries such as `/usr/sbin/ipconfig`, `/sbin/ifconfig` or `netstat` and
may read interface names, local addresses, routes and resolver configuration.
This does not permit direct LAN or public traffic, but it can contribute to
device fingerprinting. Hiding those metadata requires a VM or another network
namespace boundary; blocking the command names alone would be cosmetic because
the same data is available through system APIs.

The Claude Science daemon's own nested sandbox cannot apply `sandbox-exec` a
second time inside the outer Seatbelt, so its log may report that the inner
sandbox is unavailable and continue. Routekeeper's outer Seatbelt remains the
enforced boundary. Routekeeper never uses `--dangerously-no-sandbox` and never
falls back to an unrestricted launch merely because the nested probe failed.

Exit checks use an exact IP match when possible. If the proxy node presents a
different IPv6 address to the Claude CDN for each request, Routekeeper instead
anchors verification on the same relay's stable IPv4 exit and records the
observed IPv6 evidence. The UI does not claim that the rotating IPv6 and stable
IPv4 addresses are literally equal, and pasting one rotating IPv6 address is
not treated as a stable verification target.

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

The test suite currently contains 203 tests (3 environment-gated skips)
covering route evidence, IPv6, DNS/UDP probes, report redaction, monitoring
state, process scope, capture
validation, presentation behavior, local relay protocols, Seatbelt file and
network enforcement, system-proxy alignment, localhost-listener blocking,
child-process inheritance, sandbox status handling, local-data reset boundaries,
proxy-gateway evidence freshness, ordinary-monitoring and desktop launch gating,
the sandbox's warning-only policy, official Claude Science
discovery and daemon startup, control-socket access, two-port WebKit rules,
content-rule compilation, one-time nonce redaction, the rotating-IPv6
stable-IPv4 anchor, ownership-marker boundaries, symbolic-link refusal,
cache-scope partitioning, and fail-closed running-process protection.

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
- [Authorization handoff](docs/authorization-handoff.md)
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
