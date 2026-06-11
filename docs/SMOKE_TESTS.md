# 66TaskLight Smoke Tests

These smoke tests validate the M2.1 multi-task protocol without adding new product
features. The M2.3 observation smoke is included as well.

## Run Order

```bash
./script/smoke_multitask.sh
./script/smoke_verify_gate.sh
./script/smoke_ttl.sh
./script/smoke_invalid_task_json.sh
./script/smoke_observations.sh
./script/smoke_current_thread_binding.sh
./script/smoke_observer_health.sh
./script/check_all.sh
```

## Expected Status Matrix

| Scenario | Expected result |
| --- | --- |
| `A done_unverified` + `B running` | `global_status = running` |
| `A done_unverified` + `B blocked` | `global_status = blocked` |
| All tasks verified and no active tasks | `global_status = done_verified` |
| `done_unverified` past `TASKLIGHT_VERIFICATION_TTL_SECONDS` | visible status becomes `stale` |
| One task JSON corrupt, one task healthy | corrupt task becomes `invalid_json` and the healthy task remains visible |
| A live Codex-like process that is not wrapper-managed | appears in `observations_state.json` |
| A disappeared observed thread after 2-3 scans | removed from the active observation list |
| Current Codex thread binding start -> done -> verify | task stays managed and only turns green after `verify` |

## Acceptance Points

- `done_unverified` does not play the green completion sound.
- `blocked` and `stale` use the same red diagnostic path.
- `pending_verify_count` counts only unexpired `done_unverified` tasks.
- A corrupt per-task JSON file remains isolated from the rest of the board.
- `status` and `show <task_id>` should keep working when one task file is broken.
- `observe-local` must not duplicate wrapper-managed tasks.
- current Codex session binding must fail closed when `CODEX_THREAD_ID` is missing.
- Observed threads are display-only and do not play sound on disappearance.
- `check_observer.sh` should report `running` when the watcher is active and `not_running` when it is not.

## Notes

- `script/check_all.sh` runs the smoke suite automatically.
- Sound playback is not manually validated by the automated smoke scripts.
- If you want to perform a human speaker check, do it separately after the smoke suite.
- `script/smoke_observations.sh` checks for its own unique command token, so it can run on a machine that already has other Codex/Hermes processes.
