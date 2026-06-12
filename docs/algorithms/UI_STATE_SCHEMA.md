# UI State Schema｜M3.3

`~/.66tasklight/ui_state.json` is the only status truth for LuckyCat UI.

## Required top-level shape

```json
{
  "schema_version": "0.1",
  "source": "state_projector",
  "projector_version": "M3.3",
  "projector_generated_at": "2026-06-11T15:30:00+08:00",
  "projector_pid": 12345,
  "projector_executable_path": "/Users/.../script/state_projector.py",
  "projector_code_hash": "sha256:...",
  "projector_launch_label": "com.66tasklight.state-projector",
  "projector_instance_id": "20260611-abc123",
  "global_status": "running",
  "lamp_status": "running",
  "global_display_title": "RUNNING",
  "state_confidence": 0.95,
  "counts": {
    "blocked": 0,
    "stale": 0,
    "running": 1,
    "queued": 0,
    "pending_verify_count": 0,
    "done_verified_visible": 1,
    "observed_active": 0,
    "appserver_active": 1,
    "process_observed": 0,
    "managed_active": 1
  },
  "runtime_candidates": [],
  "tasks": [],
  "observations": [],
  "diagnostics": {}
}
```

## Required diagnostics

```json
{
  "hook_bridge_status": "ok|not_running|stale|unknown",
  "signal_bus_status": "readable|missing|error",
  "signal_bus_record_count": 0,
  "signal_bus_source_counts": {},
  "active_turn_bindings": 0,
  "latest_active_turn_age_sec": null,
  "latest_observed_age_sec": null,
  "observed_false_positive_count": 0,
  "runtime_candidate_count": 0,
  "top_runtime_candidates": [],
  "writer_status": "ok|old_writer|multiple_writers|stale|unknown",
  "state_dir": "~/.66tasklight",
  "app_bundle_path": null,
  "projector_reason": []
}
```

## UI Contract

Swift / LuckyCat must:

1. Read `ui_state.json` first.
2. Trust `global_display_title`, `lamp_status`, and `counts` from `ui_state.json`.
3. Not reimplement global precedence in Swift.
4. Fallback to legacy only when `ui_state.json` is missing / stale / invalid.
5. Surface `writer_status` if old/multiple projector writers are detected.

