# Sandbox stability and Claude identity

Date: 2026-10-21

## Goal

Reduce avoidable network pauses in the experimental sandbox, allow an explicit
Claude Desktop identity home to survive across sessions, and document the
boundaries around input methods and external services.

## P0: Network stability

- Build an in-memory network fingerprint containing the system proxy identity,
  upstream protocol, an irreversible authentication marker, relay reachability
  and the stable exit anchor. Never persist the proxy password or a raw magic
  link.
- Keep the system monitor as a signal source, but debounce related path,
  dynamic-store and wake events for 1.6 seconds before acting.
- If the effective proxy address, port, protocol and authentication marker stay
  the same, rerun preflight against the existing relay without restarting it.
  Do not interrupt an already-running Claude process.
- Pause automatically only when the proxy configuration materially changes or
  the final preflight fails. A later valid preflight may restore an
  automatically paused relay.
- Distinguish manual pause from automatic sleep/network pause. Manual pause must
  never resume on its own.
- Sleep pauses immediately. Wake waits for the stability window, then either
  restores an automatic pause or reports the material configuration change.

## P0: Persistent Claude Desktop login

- Add `persistClaudeLogin` to the isolation configuration with backward-
  compatible decoding.
- Add a separate profile home under
  `~/Library/Application Support/Routekeeper/Profiles/ClaudeDesktop/Home`.
  Workspace, temporary files, logs and control files remain per session.
- Route the desktop profile, environment, preflight and locale files through
  the selected runtime home.
- Add a UI toggle and a separate destructive action that clears only the saved
  Claude Desktop profile after the session and Claude have stopped.
- Include the profile in the local-data reset boundary.

## P1: Input methods

- Capture the actual InputMethodKit denial before changing the profile.
- If needed, allow read-only access to the exact application bundle of an
  enabled third-party input method. Do not allow its user dictionaries,
  learning data or arbitrary files under `~/Library`.
- Keep `/System/Library/Input Methods` available through the existing read-only
  system rules and add regression tests for the exact-path behavior.

## P2: External services and documentation

- Document that Claude Desktop may use loopback services, but direct LAN and
  public connections remain blocked. System-browser OAuth is not silently
  widened.
- Document that Seatbelt does not virtualize host network metadata. A sandboxed
  process may read interface, address, route and resolver configuration through
  system commands or APIs, while direct LAN and public traffic remains blocked.
- Document persistent-login security tradeoffs, the Chinese UI cause, and the
  difference between Chat, Code and Claude Science.
- Verify targeted tests, the full suite, a release build and one real sandbox
  session.

## P2: Layered cache cleanup

- Group cleanup by host Claude Desktop, host Claude Code, host and sandboxed
  Claude Science, current and historical sandbox sessions, and the persistent
  Desktop profile.
- Expand only regenerable cache, temporary-file and log targets, including
  Chromium caches, crash staging, Claude Code telemetry/usage caches, Conda
  package caches and Bun download caches.
- Scan a session only when it has `.routekeeper-session`; scan the persistent
  profile only when it has `.routekeeper-profile`. Never follow an unowned or
  symbolic-link root.
- Lock a target while the matching Claude process or sandbox session is running.
  Lock all process-dependent targets when process state cannot be inspected.
- Preserve conversations, projects, settings, cookies, browser storage,
  HTTPStorages, OAuth files, encryption keys, workspaces and artifacts. All
  selected items are moved to Trash rather than unlinked.

## Acceptance criteria

- Duplicate path or non-material dynamic-store notifications do not stop an
  active relay or close Claude connections.
- A real proxy address/port/protocol change still fails closed.
- A failed final preflight still pauses the relay and explains why.
- Manual pause and automatic pause behave differently after wake.
- A desktop session can opt into a stable profile home and clear it explicitly.
- Existing session isolation and original-project read-only tests continue to
  pass.
- Unowned session/profile directories and symbolic-link targets never appear as
  cleanable, and a running process/session blocks its matching cache targets.

## Verification

- `swift test --scratch-path /tmp/routekeeper-build` passes
  139 tests with 2 integration tests skipped when the signed Claude app path is
  not provided.
