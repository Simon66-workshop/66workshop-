# Runtime Score Formula｜M3.3

## Formula

```text
runtime_score = base_confidence × freshness_score × identity_score × consistency_score
```

## Freshness Score

```text
age <= ttl            -> 1.0
ttl < age <= 2*ttl    -> 0.5
age > 2*ttl           -> 0.0
```

Recommended TTLs:

| Candidate kind | TTL |
|---|---:|
| `codex_hook active` | 12s |
| `codex_appserver active` | 10s |
| `private_probe active` | 6s |
| `process_observer` | 5s |
| `current_thread_watcher` | 8s |

## Identity Score

```text
has turn_id       -> 1.0
has thread_id     -> 0.8
pid/cwd only      -> 0.4
global only       -> 0.2
```

## Consistency Score

```text
hook + appserver agree        -> 1.0
only one strong source fresh  -> 0.9
appserver idle but hook stale -> 0.3
process only                  -> max 0.6
private global only           -> max 0.3
```

## Scope Thresholds

```text
runtime_score >= 0.85              -> active_execution
0.55 <= runtime_score < 0.85       -> observed_active_high_confidence
0.35 <= runtime_score < 0.55       -> observed_only
runtime_score < 0.35               -> ignored
```

## Practical Consequences

- Fresh `codex_hook` with `turn_id` usually becomes `active_execution`.
- Fresh `codex_appserver` active thread can become `active_execution` or high-confidence observed active.
- `process_observer` alone cannot reach `active_execution` because identity and consistency are low.
- `private_probe global-only` cannot drive global RUNNING.

