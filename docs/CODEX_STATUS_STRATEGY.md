# Codex Status Strategy

66TaskLight M3.0 separates three identities that were previously easy to blur:

- `thread`: the Codex conversation container.
- `turn`: one user/model work cycle inside a thread.
- `task`: the managed tasklight record shown by the app.

A thread can contain many turns, and a verified task must never be reused as a
running task for a later turn.

## Signal Priority

Status fusion uses this priority order:

1. explicit tasklight helper / wrapper events
2. Codex App Server JSON-RPC events
3. Codex hooks events
4. Codex cloud stub fixtures
5. private Codex local metadata probe
6. process observer

`codex cloud list --json` is not called in M3.0 because the product remains
local-only. It is represented only as a stub signal source for fixtures.

## App Server Bridge

`script/codex_appserver_bridge.py` can now:

- `--probe`: inspect local app-server capabilities and schema method names.
- `--listen --timeout <seconds>`: start a local stdio JSON-RPC bridge, initialize
  with a read-only client identity, and convert safe server notifications into
  tasklight signals.
- `--fixture <path>`: convert saved app-server event fixtures for smoke tests.

The bridge does not print thread previews, prompts, responses, auth data, or raw
log bodies. `thread/list` is treated conservatively: `notLoaded` is not running,
and only explicit active/error/quiet status values become signals.

## Private Probe Role

`script/codex_private_state_probe.py` is a fallback. It reads local metadata only
and must not output prompts, responses, auth data, or raw log bodies.

Global recent log activity is not enough to refresh a managed heartbeat. A
private signal can refresh managed state only when:

- `thread_scoped=true`
- `confidence>=0.70`
- fusion returns `decision=refresh_managed_heartbeat`

Global-only private activity is `observed_only` or `unknown_short_lease`.

## Fail-Closed Rule

When signals conflict or are unknown, the watcher uses a short lease and releases
quiet bindings. It is better to under-report running than to keep a false blue
light indefinitely.
