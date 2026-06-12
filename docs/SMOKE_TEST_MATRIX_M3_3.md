# Smoke Test Matrix｜M3.3 Turn Runtime Arbiter

新增或更新：

```text
script/smoke_turn_runtime_arbiter.sh
script/smoke_state_projector.sh
script/check_state_projector.sh
script/check_all.sh
```

## Required cases

| # | Case | Expected |
|---:|---|---|
| 1 | fresh hook turn | `global_status=running` |
| 2 | fresh appserver active thread without managed task | `global_status=running`, `source=appserver_active` |
| 3 | process_observer only | observation count > 0, but global not RUNNING |
| 4 | private_probe global-only active | not RUNNING |
| 5 | private_probe thread-scoped but stale | not RUNNING |
| 6 | hook stale + appserver idle | not RUNNING |
| 7 | hook + appserver agree | high runtime_score RUNNING |
| 8 | PermissionRequest fresh | BLOCKED |
| 9 | old hook blocker stale/resolved | not permanently BLOCKED |
| 10 | done_unverified only | PENDING |
| 11 | verify | DONE |
| 12 | old projector writer metadata | check_state_projector flags old_writer |
| 13 | multiple projectors | check_state_projector flags multiple_writers |
| 14 | process false positives | app-server/node_repl/chronicle/Computer Use not active_execution |
| 15 | check_all | passes |

## Acceptance

```text
./script/check_all.sh passes
./script/smoke_turn_runtime_arbiter.sh passes
./script/check_state_projector.sh writer_status=ok in normal run
```

