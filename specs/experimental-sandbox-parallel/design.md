# Design

## Model

Introduce a shared sandbox configuration containing paths, timezone, upstream
proxy, enabled targets and the Desktop profile preference. Each target derives
an `IsolationConfiguration` with a fixed target value.

`SandboxCoordinator` owns two `SandboxSession` instances. It persists the shared
configuration, synchronizes external configuration changes, aggregates global
status and coordinates termination and cleanup. Each session keeps its own
runtime, preflight checks, processes, relay, external actions and changed files.

## Files And Paths

The selected exchange path is treated as a root. A session receives
`<exchange-root>/Claude Code` or `<exchange-root>/Claude Desktop`. The
coordinator creates the target directory before preparation. Each session still
copies the project into its own unique session workspace.

## Migration

If the shared configuration does not exist, migrate the legacy single
`IsolationConfiguration`. Only its selected target is initially enabled.
Legacy `SandboxSession` persistence remains available for isolated tests.

## UI

The page contains a shared configuration card, two target cards, shared exit
preparation, optional target operations, and a visible sandbox management card.
The toolbar uses the same popover pattern as network inspection and contains
proxy/boundary sheets plus session actions. A single contextual help button opens
the sandbox help topic.

## Help

The existing network help becomes a unified Routekeeper Help window with grouped
network and sandbox topics. Contextual entry points select a topic before opening
the window.

## Testing

- Unit-test migration and shared persistence.
- Unit-test target synchronization and exchange path derivation.
- Update navigation presentation tests.
- Run the full Swift test suite and build the application bundle.
