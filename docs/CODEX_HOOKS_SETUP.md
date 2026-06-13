# Codex Hooks Setup

66TaskLight can consume Codex hook events as local status signals. Hooks are more
reliable than process observation because they are scoped to Codex turns and
tool events.

This setup is local-only:

- no external API calls
- no prompt, response, auth, or raw log body output
- no reads from `~/.codex/auth.json`
- no automatic trust changes
- no task status writes from the check script

## Install Project Hooks

The M3 installer writes project-local hook configuration:

```bash
./script/install_codex_hooks_status_bridge.sh
```

It creates:

- `.codex/hooks.json`
- `.codex/config.toml`
- a local signal spool under `~/.66tasklight/signals`

## Check Readiness

Run:

```bash
./script/check_codex_hooks_trust.sh
```

Machine-readable output:

```bash
./script/check_codex_hooks_trust.sh --json
```

Expected healthy-but-not-yet-trusted shape:

```text
HOOK_CONFIG: ok
HOOK_HANDLER: ok
HOOK_VISIBILITY: hidden_not_loaded|visible_untrusted|visible_trusted
PROJECT_TRUST: unknown_manual_required
STATUS: trusted_possible
```

If Codex app-server reports the project hooks as `untrusted`, the status becomes:

```text
STATUS: untrusted_or_not_loaded
NEXT_ACTION: open Codex UI and trust project hooks
```

If the checker reports `HOOK_VISIBILITY: hidden_not_loaded`, the hooks file is
present but Codex Desktop has not loaded that workspace yet. Reopen the
workspace in Codex first, then check the hook page again.

If the checker reports `HOOK_VISIBILITY: visible_untrusted`, the workspace is
loaded but still needs a manual Trust click in Codex UI.

The checker can prove only that hooks are configured, executable, and visible to
Codex app-server. It cannot force Codex Desktop to trust them.

## Manual Trust Step

Codex project hooks require a manual trust confirmation in the Codex UI. This is
intentional. Computer Use should not bypass Codex App security prompts or write
trust records directly.

In the Codex project thread, look near the permission/safety/hook prompt area for
project hook trust controls such as:

- `Hooks`
- `Project hooks`
- `Untrusted hooks`
- `Trust hooks`
- `Allow project hooks`
- `Approve hooks`

Approve the project hook command that points to:

```text
/Users/macmini-simon66/Documents/Codex状态桌面栏提醒/script/codex_hook_event.py
```

## Why Hooks Matter

When hooks are trusted, 66TaskLight can receive better turn-scoped evidence:

- `UserPromptSubmit` and `SessionStart` indicate active turns.
- `PreToolUse` and `PostToolUse` indicate tool execution.
- `PermissionRequest` maps to `blocked / needs_human_review`.
- `Stop` maps to `done_unverified`, never `done_verified`.

`done_verified` still requires the explicit tasklight `verify` transition.

If hooks are not active, M3 falls back to:

1. explicit tasklight helper / wrapper events
2. Codex app-server metadata
3. private probe with confidence gates
4. process observer as display-only fallback

The private probe and observer are conservative. They must not create a false
infinite `running` state.
