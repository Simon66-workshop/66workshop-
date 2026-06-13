# 66TaskLight Review Matrix

Phase 1 review uses this state-accuracy matrix:

| Matrix ID | Expected Judgment | Primary Evidence |
| --- | --- | --- |
| `hook_running_is_running` | hook running should become `RUNNING` | `smoke_turn_runtime_arbiter`, `smoke_state_projector` |
| `process_only_not_running` | process-only should stay non-running | `smoke_turn_runtime_arbiter` |
| `private_global_only_not_running` | global private probe only should stay non-running | `smoke_turn_runtime_arbiter` |
| `appserver_unknown_not_running` | appserver `unknown/notLoaded` should stay non-running | `smoke_turn_runtime_arbiter` |
| `appserver_active_like_running` | fresh active-like appserver evidence may become `RUNNING` | `smoke_turn_runtime_arbiter` |
| `permission_request_blocked` | permission request should become `BLOCKED` | `smoke_turn_runtime_arbiter` |
| `stop_is_pending` | stop should become `PENDING` | `smoke_turn_runtime_arbiter`, `smoke_state_projector` |
| `verify_is_done` | verify should become `DONE` | `smoke_turn_runtime_arbiter`, `smoke_state_projector` |
| `old_projector_writer_detected` | old writer should be detected | `check_state_projector`, `smoke_turn_runtime_arbiter` |
| `multiple_projector_detected` | multiple writers should be detected | `check_state_projector`, `smoke_turn_runtime_arbiter` |

The matrix is allowed to use live-state anomaly detection on top of command
results. For example:

- `RUNNING` with only `process_observer` evidence is a `false_blue_running`
  failure even if a broad smoke suite passed in another context.
- `DONE` with pending stop-only evidence is a `false_green_done` failure.
