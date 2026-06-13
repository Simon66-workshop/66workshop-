# 66TaskLight Failure Taxonomy

The Phase 1 arbiter emits these failure classes:

- `false_blue_running`
- `false_green_done`
- `false_red_blocked`
- `weak_signal_promoted`
- `stale_writer`
- `fallback_leak`
- `missing_evidence`
- `launch_agent_unhealthy`
- `signal_bus_pollution`
- `privacy_boundary_violation`

Each reflection item must include:

- evidence
- root cause
- next bounded action
- do not touch next
- decision

## Typical Mappings

- `process_observer` only but UI shows `RUNNING` -> `false_blue_running`
- global-only private probe but UI shows `RUNNING` -> `weak_signal_promoted`
- `done_verified` without `verify` path -> `false_green_done`
- stale writer or multiple writer -> `stale_writer`
- unreadable or missing required command evidence -> `missing_evidence`
- trust or LaunchAgent instability -> `launch_agent_unhealthy`
