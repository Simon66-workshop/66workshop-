# Bug List

## P1

### P1-01 Real Hook Bridge timeout under backlog

- **Evidence:** Final runtime check observed `health_state=error`, `last_error=tasklight heartbeat timed out after 10s`, with pending signals. A sanitized one-shot bridge run later processed 47 signals successfully.
- **Impact:** The LaunchAgent can temporarily stop advancing offsets, making status freshness appear stale and delaying task projection.
- **Recommendation:** Capture a persistent stage timeline around `start/reactivate/status/heartbeat/release` in the LaunchAgent, then close the remaining lock/contention or launch-runtime cause. Keep the semantic stale gate unchanged.
- **MVP blocking:** Yes for unrestricted productionization; controlled trial only with human runtime observation.

### P1-02 Current render p99 above target

- **Evidence:** Recent 100 sanitized records: p99 233.577ms, p95 178.573ms, 35/100 over 160ms, 0 over 500ms. `read_model_assembly` p95 is 14.308ms; `auxiliary_reads` p95 is 166.562ms.
- **Impact:** Menu/radar/diagnostic refreshes can still feel delayed under active state churn.
- **Recommendation:** Split and cache auxiliary reads further; capture page-specific first-frame telemetry before claiming the 160ms line is closed.
- **MVP blocking:** No hard reject by itself, but it blocks a clean PASS.

## P2

### P2-01 Hooks trust probe unavailable

- **Evidence:** `check_codex_hooks_trust.sh` returned `STATUS: probe_unavailable`.
- **Impact:** Trust state cannot be independently confirmed for every discovered workspace.
- **Recommendation:** Keep this as unknown; provide a human-confirmed trust evidence path. Never auto-trust.
- **MVP blocking:** No.

### P2-02 Workspace coverage includes non-core missing hooks

- **Evidence:** 42 discovered, 35 trusted, 7 missing; preferred coverage is 7/7 trusted and active_recent coverage is 3/3.
- **Impact:** Overall coverage warning can look larger than the active product risk.
- **Recommendation:** Populate explicit optional/archived/temporary tiers from a human-reviewed configuration.
- **MVP blocking:** No.

## P3

### P3-01 Historical telemetry retains old outliers

- **Evidence:** Full sanitized telemetry retains a historical maximum of 4.530979s; the post-restart recent window has no sample over 500ms.
- **Impact:** Aggregate p99 remains pessimistic until a sufficient clean window replaces the old population.
- **Recommendation:** Report rolling windows separately from all-time history; do not delete evidence.
- **MVP blocking:** No.
