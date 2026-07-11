# 66TaskLight M6-M7 Operations

## M6.0 Render Snapshot Coordinator

`TaskLightRenderSnapshotCoordinator` loads the final projected read model,
bounded event tail, replay tail, Hooks Doctor report, quota history, and opted-in
provider snapshots on one background serial queue. AppKit and SwiftUI surfaces
consume the same immutable payload. The coordinator is presentation-only and
never recomputes `global_status` or `lamp_status`.

`render_telemetry.jsonl` contains only load time, status, and cache metadata.
It is bounded and does not contain prompts, responses, credentials, raw logs, or
provider payloads.

## M6.1 Status Explanation and Repair Queue

Task Radar surfaces sanitized explanations for rejected process-only evidence,
old or multiple writers, stale LaunchAgents, weak runtime candidates, and
fallback read models. The Workspace Repair Queue is ordered by severity and
keeps installation confirmation plus manual Codex Trust as separate steps.

## M6.2 Quota Calendar

The quota calendar orders reset windows and available reset-credit expiry. It is
diagnostic only. Quota remains excluded from task state, the lamp, sounds,
hooks, and runtime arbitration.

## M6.3 WidgetKit Desktop Acceptance

Run:

```bash
./script/check_widgetkit_desktop_acceptance.py
```

`ready_for_human_desktop_acceptance` means the Xcode wrapper, App Group, and
sanitized snapshot path are ready for a signed desktop test. It is not a claim
that the widget was installed. `blocked_missing_codesign_identity` means a real
Team ID and App Group provisioning profile are still required.

## M7 Provider Opt-In

Non-Codex provider snapshots remain disabled unless the user creates a local,
user-owned opt-in file:

```json
{
  "schema_version": "0.1",
  "explicit_user_opt_in": true,
  "provider_ids": ["example"]
}
```

The default app path does not read auth files, does not call external provider
APIs, and does not pass application credentials to plugin processes. Provider
data remains diagnostic-only and cannot change the main lamp.
