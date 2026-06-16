# Risk Register

| Severity | Risk | Evidence | Impact | Recommendation | Blocks MVP |
| --- | --- | --- | --- | --- | --- |
| High | Workspace coverage gap remains outside the currently trusted workspaces. | missing_hooks=29 | Some Codex turns may not emit trusted hook signals, causing stale or fallback-only status. | Prioritize common workspaces, then require manual Trust in Codex UI and fresh turn verification. | no |
| Medium | Appserver active-like evidence is intentionally allowed to drive RUNNING only when fresh and high-confidence. | runtime arbiter matrix and docs | Field behavior still needs observation across real Codex Desktop sessions. | Track false-blue incidents during the 3-day trial. | no |
| Medium | Quota display depends on local appserver or fallback import freshness. | quota_state exists | Quota may show unknown or stale values, though it must not affect the main lamp. | Keep quota as display-only and verify it against Codex Usage UI manually. | no |
| Medium | LaunchAgent changes require human review before production hardening. | Hook Bridge and State Projector LaunchAgent checks | Resident-process drift can cause stale writers or monitoring gaps. | Review plist ownership, writer identity, and process count after trial. | no |
