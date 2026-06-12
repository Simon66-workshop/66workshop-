# Signal Confidence Matrix｜M3.3

## Base Confidence

| Signal source | Base confidence | Permission |
|---|---:|---|
| `explicit tasklight` | 1.00 | May directly affect managed task state |
| `wrapper managed task` | 0.98 | May directly affect managed task state |
| `codex_hook` with `turn_id` | 0.95 | Can drive running / blocker / pending |
| `codex_appserver` active thread/turn | 0.95 | Can drive cross-thread running |
| `private_probe` turn-scoped | 0.80 | Auxiliary running evidence |
| `private_probe` thread-scoped | 0.65-0.70 | Short lease / auxiliary only |
| `private_probe` global-only | 0.20-0.35 | Diagnostic only |
| `process_observer` | 0.25-0.40 | Observation chip only, not global RUNNING |
| `current_thread_watcher` | 0.60-0.75 | Compat-only path |

## Source Power

### Strong sources

```text
explicit tasklight
wrapper managed task
codex_hook with turn_id
codex_appserver active turn/thread
```

These can affect global lamp when fresh and consistent.

### Weak sources

```text
private_probe thread-scoped
current_thread_watcher
```

These can assist but should not dominate if no strong signal agrees.

### Display-only sources

```text
process_observer
private_probe global-only
```

These can appear in diagnostics / observation chip but must not alone trigger global RUNNING.

## Conflict Handling

| Conflict | Decision |
|---|---|
| hook active + appserver active agree | high confidence RUNNING |
| hook stale + appserver idle | not RUNNING |
| process observer only | observed_only |
| private global-only active | ignored/diagnostic |
| explicit blocker | BLOCKED regardless of weak active |
| done_unverified only | PENDING |
| verified recent done only | DONE |

