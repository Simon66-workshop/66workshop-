# 66TaskLight MVP Auditor Rerun After P0 Fix

Generated: 2026-06-15 14:32 Asia/Shanghai

## Conclusion

- Decision: `CONDITIONAL_PASS`
- Previous P0 hard gate: cleared
- MVP trial readiness: can enter a 3-day real trial; not recommended for direct production hardening
- Commit/push status: no commit, no push

The previous `REJECT` condition was caused by `./script/check_all.sh` failing with `KeyError: 'total'`. The rerun confirms `check_all` now passes and the error no longer appears.

## Evidence Summary

| Check | Result | Evidence |
| --- | --- | --- |
| `./script/check_all.sh` | PASS | `mvp-auditor-rerun-after-p0.log` |
| `KeyError: 'total'` | CLEARED | no `KeyError`, `Traceback`, or `FAILED` marker in rerun log |
| `./script/smoke_check_all_total_schema.sh` | PASS | `smoke_check_all_total_schema: ok` |
| `./script/check_state_projector.sh` | PASS | `STATUS=ok`, `writer_status=ok` |
| `./script/check_hook_bridge_launch_agent.sh` | PASS | rerun shows `STATUS=ok`, `hook_bridge_health_state=ok` |
| `./script/check_ui_client.sh` | PASS | `STATUS=ok` |
| `./script/check_codex_workspaces_coverage.sh --skip-appserver` | PASS with risk | `workspace_count=35`, `trusted=6`, `missing_hooks=29` |
| `./script/check_codex_quota.sh` | PASS | `STATUS=ok`, `quota_status=watch` |
| `./script/smoke_codex_quota.sh` | PASS | `smoke_codex_quota: ok` |

## Required P0 Semantics

- `ui_state.counts` was not force-filled with `total`.
- `tasklight status` remains sourced from `state_projector`.
- `tasklight status.counts` does not include `total`.
- `tasklight status` carries the compatibility note: use `tasklight list` for legacy task-file aggregation.
- `tasklight list.counts.total` is present and currently reports `1312`.

This preserves the intended semantic split:

- Projected UI status counts describe display/status categories.
- Legacy task total belongs to the task-file aggregate returned by `tasklight list`.

## Residual Risks

| Priority | Risk | Evidence | MVP Impact |
| --- | --- | --- | --- |
| P1 | Workspace hooks coverage gap | `missing_hooks=29` out of `workspace_count=35` | Some discovered workspaces cannot reliably emit trusted hook signals. |
| P2 | Hook Bridge LaunchAgent stale status was seen in the P0 verification pass | `p0-fix-verification.md` recorded `STATUS=stale`; this rerun shows `STATUS=ok` | Not currently reproduced, but should remain a runtime-health watch item during trial. |
| P2 | Quota display depends on fresh local source | `quota_status=watch`, `quota_source=codex_appserver`, warning for collapsed duplicate buckets | Display-only risk; no evidence it affects main lamp. |
| P2 | Appserver/private active-like evidence still requires real-session observation | runtime candidates show active execution and ignored weak candidates | Requires 3-day trial incident tracking for false-blue/false-red cases. |

## Trial Recommendation

Proceed to a 3-day real trial with explicit incident logging for:

- false blue / false red / false green
- stale writer or stale LaunchAgent health
- workspace turns without trusted hooks
- quota staleness or misleading display

Do not treat this as production-ready until the 29 missing-hook workspaces are triaged and the historical LaunchAgent stale observation is either explained or no longer reproducible over the trial window.

## Evidence Files

- Rerun log: `docs/reports/mvp-audit/20260615-1352/mvp-auditor-rerun-after-p0.log`
- P0 fix verification: `docs/reports/mvp-audit/20260615-1352/p0-fix-verification.md`
- P0 self-review: `docs/reports/self-review/P0-check-all-total-fix/final-review.md`
