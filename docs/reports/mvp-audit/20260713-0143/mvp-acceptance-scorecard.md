# MVP Acceptance Scorecard

| Dimension | Score | Rationale |
|---|---:|---|
| Functional completeness | 19/20 | Core UI, projector, bridge, quota display and diagnostics are covered; real Bridge runtime still needs closure |
| State accuracy | 24/25 | Existing false-green guards, process-only suppression, stop/verify gates and quota isolation pass; runtime backlog remains observable |
| Stability | 9/15 | `check_all` and fixture timeline pass, but the real LaunchAgent can still report heartbeat timeout after a large gate run |
| Test coverage | 15/15 | Python, Swift, unit tests, three final `check_all` runs, retention, bridge, storage and large-state smokes pass |
| Security boundary | 10/10 | No secret reads/output, external API, auto-trust, purchase, reset or push |
| Explainability/diagnostics | 9/10 | Bridge reason fields, storage audit, stage telemetry and coverage tiers are present; real timeout root cause still needs operator evidence |
| Report quality | 4/5 | Full markdown evidence package and editable PPT generated; final decision remains deliberately non-green |
| **Total** | **90/100** | **NEEDS_HUMAN_REVIEW** |

## Hard Gates

| Gate | Result |
|---|---|
| `check_all` failure | Cleared: 3 final consecutive runs exit 0 |
| Fixed-date retention fixture | Cleared |
| False green/process-only RUNNING | Existing guard suite passed |
| Quota changes main lamp | Existing quota and core checks passed |
| Auth/secret/raw log boundary | No violation observed in this audit |
| Auto trust/purchase/reset | Not performed |
| Critical report generation | Passed; this package and PPT exist |
| Multiple writer detection | Existing guard suite passed; runtime process duplication is recorded separately |
