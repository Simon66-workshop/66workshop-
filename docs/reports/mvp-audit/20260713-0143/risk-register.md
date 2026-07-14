# Risk Register

| ID | Risk | Severity | Evidence | Impact | Recommended action | Blocks MVP? |
|---|---|---|---|---|---|---|
| R-01 | Real Hook Bridge heartbeat timeout under backlog/observer contention | P1 | `STATUS=error`; heartbeat timeout; one-shot later processed 47 signals | Delayed offsets and stale diagnostics | Instrument each bridge stage and validate one observer/one bridge over a sustained window | Yes for productionization |
| R-02 | Render auxiliary-read tail exceeds 160ms | P1 | Recent p99 233.577ms; auxiliary p95 166.562ms | Visible menu/radar refresh delay | Cache and bound auxiliary reads; repeat recent-window measurement | No hard reject, blocks PASS |
| R-03 | Overall workspace list has 7 missing hooks | P2 | 42 total / 35 trusted / 7 missing | Some workspaces cannot emit trusted turn signals | Add hooks only after user confirmation and manual Trust | No |
| R-04 | Hooks trust probe unavailable | P2 | `STATUS: probe_unavailable` | Trust state remains unknown for part of the inventory | Add a human-run trust evidence path | No |
| R-05 | State directory continues to grow | P2 | 10,477 tasks; 2,794 bindings; 965 clients; 292 report-only archive candidates | Future scan and disk pressure | Schedule bounded archive review; default remains report-only | No |
| R-06 | Duplicate observers can compete for `.lock` | P1 observation | 11 duplicate observers existed before runtime cleanup; one was restored | Bridge timeout amplification | Keep one managed observer and add duplicate-process alert | Yes until sustained runtime evidence |
| R-07 | Historical telemetry mixes old and new populations | P3 | All-time max 4.530979s vs recent no >500ms | Misleading aggregate score | Keep all-time and rolling-window metrics separate | No |
