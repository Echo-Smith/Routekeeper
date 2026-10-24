# Routekeeper 0.3.12

Version: 0.3.12 (build 24)

This is the first public source release with a macOS installer image. The source
is available under the PolyForm Noncommercial License 1.0.0 for personal study,
research, experiments and other noncommercial purposes.

## Added

- Added staged proxy-gateway verification to network inspection.
- Added split-traffic protection and protected-target-only verification modes.
- Gateway verification now checks the current proxy path, failure after the
  selected node is disconnected, failure after the proxy client exits, and
  recovery after the proxy is restored.
- Overview, advanced network protection and experimental process isolation now
  share one gateway state.
- Monitoring and desktop-application launch are blocked when gateway protection
  is selected and fresh evidence for the current network session is unavailable.
- Network path, system proxy, DNS, address, sleep/wake, protection-setting or app
  restart changes invalidate earlier evidence.
- Gateway evidence expires after 15 minutes.
- Experimental process isolation aligns recognized system proxy address, port
  and protocol settings automatically.
- Isolation preflight now covers direct-network failure for the protected
  target, local relay reachability, observed-exit consistency, localhost listener
  blocking and default-browser launch blocking.
- Sandbox sessions apply a consistent timezone, language and locale without
  claiming to spoof the hardware sales region.
- Added a four-step isolation setup guide that routes users to network
  inspection, directory selection, credentials or session creation as needed.
- Preflight results emphasize failed and actionable checks while keeping the
  complete evidence expandable.
- Added a four-step Overview onboarding flow for starting the proxy, completing
  inspection, saving an exit and enabling monitoring.
- The Overview explains how ordinary monitoring and experimental isolation
  differ, including interface stability, compatibility and account-risk limits.
- Local data cleanup can stop active work and remove Routekeeper-owned settings,
  reports, activity, credentials, gateway evidence and sandbox copies.
- Cleanup output clearly lists retained data, including user projects, proxy
  client settings, system proxy configuration, exported files and unrelated
  Keychain items.

## Evidence and boundaries

- Checks contact ipinfo.io, target-service trace endpoints, IPv4/IPv6 probes,
  system DNS and UDP/STUN services.
- Required checks must pass before verification can continue; UDP/STUN remains
  supporting evidence and does not independently determine a strict result.
- Node disconnection and proxy-client exit are performed by the user or an
  external operator. Routekeeper does not read subscriptions, node names or
  credentials, and it does not execute agent-generated shell commands.
- Routekeeper stores redacted structured results, stages and timestamps, but not
  exit IP addresses, proxy credentials or raw configuration.
- Gateway conclusions cover only the current Mac and network session. When a
  proxy client uses process-based routing, Routekeeper cannot prove that every
  protected child process was routed correctly; experimental isolation performs
  its own process-level preflight.

## Verification

- 226 automated tests passed, with 3 environment-gated tests skipped.
- Coverage includes stage ordering, required and supporting checks, the
  15-minute expiry, network invalidation, restart invalidation and monitoring
  gates.
- Coverage includes system-proxy matching, IPv6 exit parsing, localhost listener
  blocking and the new isolation checks.
- Coverage includes local-data cleanup, Keychain credential removal,
  Routekeeper-owned sandbox-copy detection and terms-confirmation retention.
- Coverage includes the one-step exit confirmation with automatic sandbox
  shutdown and the initial visual anchor for all six product pages.

## Distribution

- Release assets include `Routekeeper-v0.3.12.dmg` and its SHA-256 checksum.
- The DMG requires macOS 14 or later. The current binary is built for Apple
  Silicon (`arm64`).
- This DMG is ad-hoc signed and has not been signed with a Developer ID or
  notarized by Apple. It is a public development preview. If macOS blocks the
  first launch, allow it in System Settings > Privacy & Security.
- Routekeeper does not promise anonymity, zero leakage or circumvention of any
  service restriction. Production distribution still requires Developer ID
  signing, Apple notarization and release-specific validation.
