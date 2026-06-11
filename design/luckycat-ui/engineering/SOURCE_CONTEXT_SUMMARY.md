# Source Context Summary

This pack assumes the current 66TaskLight project already has:

- Managed task state files under `~/.66tasklight/tasks/<task_id>.json`
- Aggregate `state.json`
- `observations_state.json` as display-only observed-thread snapshot
- `done_unverified` as pending/blue until explicit verify
- `done_verified` as only green completion state
- `blocked/stale` as red diagnostics
- Observed threads that are local-only, display-only, and not managed completion

Do not change those rules while implementing the LuckyCat UI skin.
