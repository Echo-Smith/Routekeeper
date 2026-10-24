# Routekeeper Privacy Notice

Effective date: 2026-10-24

This notice explains how the current Routekeeper version stores data locally,
when it contacts the network, and how you can remove local data. It applies to
the macOS app, source builds and repository documentation.

## Summary

- Routekeeper has no developer-operated account system, telemetry, advertising
  SDK or automatic report-upload service.
- The developer does not automatically receive your IP address, browsing
  content, credentials, workspaces or logs through Routekeeper.
- Checks, proxies, Claude, Chrome, DNS, STUN and optional IP-information lookups
  connect directly to third parties, which may see your public egress address and
  request metadata.
- Reports, egress history, sandbox sessions and browser profiles remain local
  until you clear them.
- GitHub access, Issues and Release downloads are handled by GitHub under its own
  policies.

## Local data

| Data | Location | Purpose and retention |
|---|---|---|
| App settings, language and terms version | macOS `UserDefaults` | Store UI and check preferences until app data is cleared |
| Egress history and the two latest reports | macOS `UserDefaults` | Compare egress changes in the app; can be cleared separately |
| Claude Code credential | macOS Keychain | Read only when saving it or launching Claude Code through Routekeeper |
| Sandbox HOME, temporary files, logs and control files | `~/Library/Application Support/Routekeeper/Isolation/` | Support the experimental sandbox; removable by ownership-aware cleanup |
| Persistent Claude sign-in profile | `~/Library/Application Support/Routekeeper/Profiles/ClaudeDesktop/Home/` | Stores cookies and local Claude data only when persistent sign-in is explicitly enabled |
| Routekeeper Chrome profile, cache and downloads | `~/Library/Application Support/Routekeeper/Profiles/ClaudeWeb/` | Used only by the dedicated Chrome instance; host Chrome data is not imported |
| Project workspaces and exchange files | `~/Routekeeper/Workspaces/` and user-selected exchange folders | Review, handoff and manual adoption; never copied back automatically |
| User-exported reports | User-selected location | Controlled and deleted by the user |

Workspaces, persistent sign-in profiles and browser profiles carry Routekeeper
ownership markers. Cleanup handles only data whose ownership can be verified and
fails closed when relevant process state cannot be checked or is still running.

## Network requests

Routekeeper connects directly to services only when the corresponding feature
runs. The current version may contact:

| Service or target | Trigger | Information potentially exposed |
|---|---|---|
| `api.ipify.org`, `api6.ipify.org` | Network checks, gateway verification, sandbox exit verification, manual egress audit | Public egress IP, time and TLS/HTTP metadata |
| `ipinfo.io` | Network-path and external-exit checks | Public egress IP, time and request metadata |
| `claude.ai`, `api.anthropic.com`, `console.anthropic.com` | Claude path, TLS, IPv6 and reachability checks | Public egress IP, time, target hostnames and network metadata |
| STUN services `stun.cloudflare.com`, `stun.l.google.com` | UDP probing enabled and a check runs | UDP mapped address, time and network metadata |
| System DNS resolvers and queried targets | DNS probing enabled and a check runs | Query name, time and resolver metadata |
| `ipwho.is`, `ipapi.is` | User enables third-party IP intelligence and runs a manual check | Current exit IP and request metadata; off by default |
| User-configured local proxy upstream | Proxy-path checks, monitoring or sandbox sessions | Handled by the proxy provider under its policy |
| Claude, Chrome and install/update pages | User explicitly launches, signs in or follows a link | Handled by the relevant third party under its policy |

Automatic egress audits do not call third-party IP-intelligence services.
Routekeeper does not automatically upload exported reports and does not send
reports, logs or workspaces to a developer-operated server.

## Credentials and browser data

Long-lived Claude Code credentials are stored in the macOS Keychain. Routekeeper
does not write them into projects, reports, exchange folders or ordinary logs.
Claude Code launched in the sandbox receives an isolated environment, and
Routekeeper does not automatically synchronize host and sandbox sign-in state.

Chrome uses a Routekeeper-owned profile. Routekeeper does not read or import
cookies, passwords, history, extensions or other configuration from the host
Chrome profile. Sign-in state in the dedicated profile remains until you clear
Chrome configuration or local data in the app.

Persistent Claude sign-in is off by default. When enabled, workspaces, logs and
temporary files remain session-scoped, while cookies and local Claude data remain
in a Routekeeper-owned HOME until you clear that profile or reset local data.

## Reports and logs

Ordinary diagnostic exports offer a redacted format that removes addresses,
local paths and process identifiers. Raw reports, packet-capture results or
manually selected sandbox logs may contain more specific information. Review
them before exporting or sharing.

Routekeeper includes no automatic crash-reporting or analytics SDK. macOS system
diagnostics, Apple services, GitHub and third-party services may process data
under their own policies.

## Your controls

- Use settings and Cleanup to remove egress history, reports, sandbox sessions,
  profiles and local data.
- Clear Chrome configuration and the persistent Claude sign-in profile separately.
- Disable DNS, STUN, third-party IP intelligence, automatic checks and other
  optional features.
- Stop monitoring, end sandbox sessions or quit Routekeeper at any time.

Some safety-sensitive operations refuse to continue when process state cannot be
verified, preventing deletion or overwrite of data whose ownership is unclear.

## Children and sensitive data

Routekeeper is intended for users who can manage their own macOS networking,
applications and third-party accounts. It is not directed to children. Never
post another person's credentials, cookies, identity documents, precise location
or other highly sensitive information in a check, issue, log or exported report.

## Changes

This notice may change when features, data flows or third-party services change.
Material changes will be identified through the in-app terms version, repository
commits or release notes.

## Contact

Use GitHub Issues for general privacy questions after removing IP addresses,
paths, credentials and device fingerprints. Report security vulnerabilities
privately according to `SECURITY.md`.
