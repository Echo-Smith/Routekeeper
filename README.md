<p align="center">
  <img src="docs/assets/routekeeper-icon.png" width="144" height="144" alt="Routekeeper icon">
</p>

<h1 align="center">Routekeeper</h1>

<p align="center"><strong>See the exit. Hold the boundary. Isolate the work.</strong></p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 5.10" src="https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white">
  <img alt="Noncommercial license" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-2F6FED">
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="docs/assets/routekeeper-demo.mp4">
    <img src="docs/assets/routekeeper-demo.gif" width="900" alt="Routekeeper workflow: overview, network protection and native title-bar menu">
  </a>
</p>

<p align="center"><sub>Anonymized interface and redacted network data. Select the preview to view the MP4.</sub></p>

Routekeeper is a native macOS network inspection, egress verification and
experimental execution-isolation utility. It goes beyond the fact that a proxy
client says it is connected and answers the questions that matter:

1. Where does the traffic actually leave from?
2. Is that evidence still valid, and will traffic fail closed if the proxy fails?
3. Can sensitive work run inside a separate file, network and sign-in boundary?

Routekeeper is built for personal study, research and technical exchange. It
focuses on observability, reviewability and fail-closed behavior. It does not
promise anonymity, zero leakage or a way around any service restriction.

> [!IMPORTANT]
> Routekeeper is licensed under the **PolyForm Noncommercial License 1.0.0**.
> Personal study, research, experiments and other noncommercial use are
> permitted. Commercial use requires separate authorization. This is a
> source-available noncommercial project, not an OSI-approved open-source
> project. See [LICENSE](LICENSE) and [Terms](TERMS.md).

> [!NOTE]
> The current source version is **0.3.12 (build 24)**. The repository is
> source-first. Local builds are ad-hoc signed by default; a public binary still
> needs Developer ID signing, notarization and release-specific validation.

## Contents

- [Why Routekeeper](#why-routekeeper)
- [The workflow](#the-workflow)
- [Feature overview](#feature-overview)
- [Isolation model](#isolation-model)
- [Evidence and fail-closed behavior](#evidence-and-fail-closed-behavior)
- [Interface](#interface)
- [Quick start](#quick-start)
- [Command line](#command-line)
- [Local data](#local-data)
- [Privacy and security](#privacy-and-security)
- [Project layout](#project-layout)
- [Current limitations](#current-limitations)
- [Documentation](#documentation)
- [License](#license)

## Why Routekeeper

A proxy client reporting "connected" does not prove that the intended traffic
uses the intended path. The system proxy, TUN routing, explicit proxies, IPv4,
IPv6, DNS, application-level connections and the upstream node can all form
different paths.

Routekeeper turns those signals into a reviewable evidence chain:

```text
Observe the local path
    ↓
Compare intended and observed exits
    ↓
Verify that a proxy failure really blocks traffic
    ↓
Run sensitive work in an isolated session
    ↓
Review changes, clean up data, retain the result
```

It never treats "not checked" as "passed", and it does not modify proxy clients,
subscriptions, nodes or macOS proxy settings on your behalf.

## The workflow

### 1. Observe

Routekeeper reads IPv4/IPv6 routes, system and explicit proxy settings, DNS,
TUN indicators and selected process connections, then confirms the observed
public exit through external services.

### 2. Verify

It compares the intended exit, system path, proxy path and external observation.
Evidence expires after a network, proxy, DNS or address change, sleep/wake, app
restart or its own time limit.

### 3. Fail closed

Unknown, stale or failed evidence never becomes a protected state. When gateway
protection is selected, monitoring and protected launches remain blocked until
the current network session produces fresh passing evidence.

### 4. Isolate

Experimental isolation gives terminal-style tasks, desktop applications and web
sessions their own workspace copy, HOME, logs, temporary directory and controlled
network relay. The original project is a read-only source and is never replaced
automatically.

### 5. Review and clean

Users can inspect workspace changes, external handoff requests and local reports,
then clean owned caches, sessions, browser profiles and other Routekeeper data.

## Feature overview

| Area | Capabilities |
| --- | --- |
| Overview | Health, protection completeness, protected scopes, gateway status, recent checks and attention items |
| Network protection | IPv4/IPv6, system and explicit proxy paths, exit consistency, DNS, UDP/STUN and service reachability |
| Proxy gateway | Current-path, node-failure, client-exit and restored-path verification; 15-minute evidence lifetime |
| Experimental isolation | Three run targets, shared environment settings, separate workspaces, isolated HOME, local relay and fail-closed startup |
| Credentials | Keychain-backed CLI credentials; independent desktop and web sign-in state |
| Workspaces | User-visible copies, change review, Finder reveal, authorized handoff and unstaged Git patch application |
| Cleanup | Allowlisted scans, ownership markers, running-process protection, symlink refusal and Trash-based cleanup |
| Activity | Local events, connection investigation, exit history, redacted reports and raw local reports |
| Interface | Native sidebar, title-bar menus, menu-bar residency, light/dark appearance, text scaling and bilingual UI |
| Automation | Read-only self-check and egress-audit CLI with JSON output and explicit exit codes |

### Network inspection

- Inspects IPv4 and IPv6 without treating an inactive IPv6 stack as a failure.
- Compares system, proxy, explicit-proxy and externally observed exits.
- Checks DNS routing, UDP/STUN mappings and target-service TLS reachability.
- Detects physical IPv6 exposure, unconfirmed TUN routing, dual-stack mismatch
  and exit drift.
- Keeps the last two complete reports and up to 20 exit-history records for
  comparison.
- Supports automatic checks, continuous monitoring, attention notifications and
  an optional bounded packet-header capture.

### Proxy gateway verification

The gateway check is split into consecutive stages:

1. The current path can reach the target.
2. Disconnecting the node blocks target access.
3. Quitting the proxy client still blocks target access.
4. Restoring the proxy brings the exit back to the intended value.

Only complete evidence from the current network session passes. Proxy, network,
DNS or settings changes, sleep/wake, app restarts and the 15-minute time limit
invalidate earlier evidence.

### Protection completeness

The score in Overview is an evidence map, not a marketing number. It covers:

- protection settings;
- the local path;
- external exits and services;
- the execution environment;
- proxy fail-closed behavior.

Disabled optional features are not counted as failures. Insufficient, stale or
mismatched evidence cannot be presented as a high score.

## Isolation model

Experimental isolation supports three target types:

| Target | Intended work | Isolation |
| --- | --- | --- |
| Terminal-style target | Code, scripts and local project operations | Separate workspace, HOME, terminal session and controlled upstream |
| Desktop application target | GUI work that may need local sign-in state | Signature validation, separate HOME, optional persistent sign-in and controlled network |
| Browser target | Web work with independent downloads and sign-in | Separate browser profile, download directory and network pause/resume |

All three targets share one timezone, language, region, proxy and fixed-exit
configuration, while each session remains independent.

### File boundaries

```text
Original project (read-only source)
    ↓ copied automatically
~/Routekeeper/Workspaces/<project>/<session>/workspace/
    ├── working copy
    └── session.json

~/Library/Application Support/Routekeeper/
    ├── Isolation/<UUID>/     # HOME, logs, control files and temporary data
    └── Profiles/             # Persistent sign-in and dedicated browser profiles
```

Workspaces live in a user-visible folder in the home directory and can be
revealed in Finder at any time. Ending a session does not overwrite the original
project, commit changes or push a branch.

### Network boundary

- Each isolated session reaches only its own local relay.
- The relay supports loopback HTTP CONNECT, SOCKS5 and mixed upstreams.
- If the relay or upstream is unavailable, the session fails instead of falling
  back to direct internet access.
- Direct LAN and public connections are disabled by default.
- Isolated processes cannot listen on arbitrary host localhost ports or open the
  default browser automatically.
- Sleep closes networking immediately. Wake revalidates the path, and a manual
  pause never resumes by itself.

### Authorized handoff

When a restricted task needs to write back to the host, it can submit a JSON
manifest and payload instead of receiving host Git remotes, SSH keys, access
tokens or unrestricted file access.

Routekeeper:

- freezes the request in memory;
- displays file size, SHA256 and actual contents;
- requires explicit approval or rejection;
- saves only to a selected location or applies an unstaged Git patch;
- never commits, pushes, publishes or uploads automatically.

## Evidence and fail-closed behavior

Routekeeper describes results with three states:

| State | Meaning |
| --- | --- |
| Pass | Valid evidence was obtained in the current network session |
| Fail | The check completed but the result did not match expectations |
| Unknown / stale | There is not enough valid evidence to call the check a pass |

Fail-closed behavior applies across monitoring, gateway checks, isolated startup
and cleanup. If process state, ownership markers or evidence cannot be verified,
Routekeeper stops rather than guessing.

## Interface

- Native macOS sidebar and detail layout with standard split-view shortcuts.
- Native title-bar menus for network protection and isolation.
- Menu-bar status item that remains available after the main window closes.
- Light, dark and system appearance.
- Multiple text-scale levels and accessibility-aware motion.
- Simplified Chinese, English and system-language modes.
- A native layered app-icon pipeline with current macOS glass, lighting and
  appearance variants.
- First-run terms confirmation, page-level help, privacy details and risk
  notices.

## Quick start

### Requirements

- macOS 14 or later
- Xcode or a Swift 5.10-compatible toolchain
- No third-party Swift packages

### Build

```sh
git clone <repository-url>
cd Routekeeper

swift test --scratch-path /tmp/routekeeper-build
bash scripts/build-app.sh
open dist/Routekeeper.app
```

Create a local DMG:

```sh
bash scripts/build-dmg.sh
```

Local builds are ad-hoc signed by default. They are intended for development and
verification, not as a final public distribution package.

The current suite contains **226 tests**, with 3 environment-gated network
acceptance tests skipped by default. Coverage includes path evidence, IPv6,
report redaction, gateway invalidation, isolation boundaries, workspaces,
session cleanup, interface state and termination confirmation.

## Command line

Run a read-only self-check:

```sh
dist/Routekeeper.app/Contents/MacOS/Routekeeper --self-check
```

Write a redacted egress report:

```sh
dist/Routekeeper.app/Contents/MacOS/Routekeeper \
  --egress-audit \
  --output egress.json
```

Optional flags select target addresses, check intervals, DNS/UDP skipping and
third-party IP intelligence. The CLI does not enable monitoring, modify proxy
settings, install a system extension or start packet capture.

| Exit code | Meaning |
| --- | --- |
| `0` | The requested checks passed or the report was written |
| `1` | Arguments, output or command execution failed |
| `2` | Checks completed but the report contains failures |

## Local data

| Data | Location |
| --- | --- |
| App settings | macOS `UserDefaults` |
| Exit history and recent reports | Routekeeper local application data |
| CLI credential | macOS Keychain |
| Isolated HOME, logs and temporary files | `~/Library/Application Support/Routekeeper/Isolation/` |
| Persistent sign-in and browser profiles | `~/Library/Application Support/Routekeeper/Profiles/` |
| User workspaces | `~/Routekeeper/Workspaces/` |
| Exported reports | A location selected by the user |

Routekeeper has no developer-operated account system, telemetry, advertising SDK
or automatic report upload. Inspections connect directly to IP lookup, STUN, DNS
and user-configured proxy upstreams; those third parties may see the current
public exit and request metadata. See the [Privacy Notice](PRIVACY.md) for the
full data flow.

## Privacy and security

- Third-party IP intelligence is off by default.
- CLI credentials are stored only in Keychain and never in projects, reports,
  logs or the exchange directory.
- Reports support redacted export that removes IP addresses, local paths and
  process identifiers.
- Persistent sign-in and browser profiles are isolated and do not import host
  cookies, passwords or history automatically.
- Cleanup only targets allowlisted items carrying Routekeeper ownership markers.
- Running processes lock cleanup targets; unverifiable process state fails
  closed.
- Workspaces, sign-in profiles and exchange files are never uploaded
  automatically.

Do not paste credentials, cookies, full IP addresses, personal paths or logs into
a public issue. See [SECURITY.md](SECURITY.md) for reporting guidance.

## Project layout

```text
Sources/
├── GuardCore/          # Network evidence, exits, isolation models, cleanup and reports
├── Routekeeper/        # SwiftUI + AppKit app, interface and session control
└── CAuditToken/        # Process identity verification helper

NetworkExtension/       # Process-scoped filtering source and authorization boundary
Tests/                  # Core, network, isolation and presentation tests
scripts/                # Build, signing, DMG and native icon generation
docs/                   # Features, design, network verification and release notes
```

SwiftUI provides the main interface. AppKit integrates windows, the menu bar,
title-bar menus, the Dock icon and other macOS system surfaces. Runtime isolation
combines Seatbelt profiles, process identity checks and a local relay.

## Current limitations

- The current development build is ad-hoc signed and not notarized.
- Process-scoped Network Extension filtering exists in source but cannot be
  activated by the current ad-hoc build.
- Experimental isolation depends on macOS `sandbox-exec`, which Apple marks as
  deprecated.
- Isolation is a process, file and network boundary, not a virtual machine.
- It does not virtualize every host network detail, including interface names,
  local addresses, routes and resolver configuration.
- It does not spoof hardware sales regions or guarantee server-side risk, account
  or device-fingerprint outcomes.
- Restricted targets cannot listen on host localhost project ports or launch the
  default browser automatically.
- Workspace copies never overwrite the source project, and Git patches are never
  committed or pushed automatically.
- Routekeeper does not modify proxy clients or subscriptions.
- Results describe evidence from the current Mac and current network session;
  they are not a guarantee of zero leakage or permanent validity.

## Documentation

- [Feature list](docs/FEATURES.zh-CN.md)
- [Authorized handoff](docs/authorization-handoff.md)
- [Design notes](docs/design.md)
- [Network verification](docs/network-v2-verification.md)
- [Terms](TERMS.md)
- [Privacy notice](PRIVACY.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## License

Routekeeper uses the [PolyForm Noncommercial License 1.0.0](LICENSE).

- Personal study, research, experiments and other noncommercial use are allowed.
- Distribution and modification are allowed within the license terms.
- Unauthorized commercial use, paid distribution and commercial integration are
  prohibited.
- This is not an OSI-approved open-source license.

For commercial authorization, contact the maintainers through a repository
issue.
