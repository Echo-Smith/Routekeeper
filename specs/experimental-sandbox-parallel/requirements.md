# Experimental Sandbox Parallel Targets

## Problem

The current experimental sandbox stores one exclusive application target. Claude
Code and Claude Desktop therefore cannot be configured and observed as separate
protected targets even though most of their scope is shared.

## Scope

- Keep the sidebar label `Sandbox` with the neutral `Experimental` badge.
- Use `Experimental Sandbox` as the window/accessibility title.
- Present Claude Code and Claude Desktop as independent protected targets.
- Share project, exchange root, timezone and upstream proxy settings.
- Keep target-specific installation, sign-in and runtime state independent.
- Use separate workspaces and exchange subdirectories for parallel sessions.
- Move proxy consistency and boundary details into the toolbar overflow menu.
- Keep a visible, confirmed action for turning the experimental sandbox off.
- Add sandbox topics to a unified Routekeeper Help window.

## Acceptance Criteria

- When the sandbox page opens, the system shall display both protected targets
  with independent enabled and runtime states.
- When one target is enabled or prepared, the system shall not change the other
  target's lifecycle state.
- When shared settings change outside an active session, the system shall apply
  the same basic settings to both target sessions.
- When two sessions prepare from the same project, each session shall use its own
  workspace and exchange subdirectory.
- When an active session locks configuration, the system shall prevent shared
  settings from changing until every active session has ended.
- When the toolbar overflow menu is used, the system shall expose proxy
  consistency, proxy boundaries and session-specific actions without duplicating
  the removed toolbar status pill.
- When turning off the experimental sandbox, the system shall require a visible
  confirmation action and shall reject the operation while a session is active.
- When Help opens from the sandbox page or Help menu, the system shall deep-link
  to the relevant sandbox topic in the unified help window.

## Non-Goals

- Combining both targets into one sandbox profile.
- Sharing one writable workspace between concurrent targets.
- Changing ordinary network monitoring behavior.
