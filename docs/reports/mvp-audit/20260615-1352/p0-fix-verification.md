# P0 Fix Verification: check_all KeyError total

Generated: 2026-06-15 14:27 Asia/Shanghai

## Result

- P0 status: fixed
- `./script/check_all.sh`: passed after fix
- `KeyError: 'total'`: no longer appears in the after-fix `check_all` run
- New regression smoke: `./script/smoke_check_all_total_schema.sh` passed
- Self-review: `CONDITIONAL_PASS`, score `100.0`, release evidence profile

## Root Cause

`script/smoke_stop_priority_guard.sh` read:

```sh
tasklight status | python3 -c '...["counts"]["total"]'
```

`tasklight status` is now sourced from projected `ui_state.json`. That projected read model has status-specific counts such as `running`, `blocked`, `pending_verify_count`, and `done_verified_visible`, but `counts.total` is not part of the projected UI status contract.

The `total` being checked in this smoke is the legacy task-file aggregate count. That value belongs to `tasklight list`, not to projected `tasklight status`.

## Files Changed

- `script/smoke_stop_priority_guard.sh`
- `script/smoke_check_all_total_schema.sh`
- `script/check_all.sh`
- `docs/reports/mvp-audit/20260615-1352/p0-check_all-keyerror-total.log`
- `docs/reports/mvp-audit/20260615-1352/p0-check_all-after-fix.log`
- `docs/reports/self-review/P0-check-all-total-fix/`

## Fix

- Replaced the old `tasklight status` `counts.total` read in `smoke_stop_priority_guard.sh` with a helper that reads `counts.total` from `tasklight list`.
- Added `smoke_check_all_total_schema.sh` to assert projected `tasklight status` can omit `counts.total` without crashing.
- Added the new regression smoke to `check_all.sh` before `smoke_stop_priority_guard.sh`.

No state light algorithm, Turn Runtime Arbiter rule, Hook Bridge semantic, Stop -> `done_unverified`, or verify-only-green behavior was changed.

## Verification

| Check | Result |
| --- | --- |
| `python3 -m py_compile script/*.py script/self-review/*.py script/self-review/auditors/*.py` | PASS |
| `./script/smoke_check_all_total_schema.sh` | PASS |
| `./script/smoke_stop_priority_guard.sh` | PASS |
| `./script/check_all.sh` | PASS |
| `./script/check_state_projector.sh` | PASS, `STATUS=ok`, `writer_status=ok` |
| `./script/check_hook_bridge_launch_agent.sh` | exit 0, `hook_bridge_health_state=ok`, `STATUS=stale` |
| `./script/check_ui_client.sh` | PASS, `STATUS=ok` |
| self-review `P0-check-all-total-fix` | `CONDITIONAL_PASS`, score `100.0` |

## Evidence

- Failure log: `docs/reports/mvp-audit/20260615-1352/p0-check_all-keyerror-total.log`
- After-fix log: `docs/reports/mvp-audit/20260615-1352/p0-check_all-after-fix.log`
- Self-review report: `docs/reports/self-review/P0-check-all-total-fix/final-review.md`

## Residual Notes

- The original MVP hard gate failure is cleared because `check_all` now passes.
- Hook Bridge LaunchAgent still reported `STATUS=stale` in a standalone health check despite exit code 0 and `hook_bridge_health_state=ok`; this should remain visible as a follow-up runtime-health observation, not as the fixed `counts.total` P0.
- A full MVP Auditor rerun is recommended now that the P0 hard gate is resolved.
