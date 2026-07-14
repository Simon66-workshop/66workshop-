# Performance Analysis

## Evidence

All values are from sanitized render telemetry. No prompt, response, raw log body or secret was read into the report.

### Full retained population

| Records | p50 | p95 | p99 | p99.9 | Max | >160ms | >500ms | >1000ms |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 896 | 70.754ms | 178.092ms | 562.001ms | 3079.895ms | 3079.895ms | 144 (16.07%) | 9 (1.00%) | 6 (0.67%) |

The retained file includes historical and current records; the all-time p99 is dominated by older outliers and is reported separately in `evidence/render-performance.json`.

### Current rolling window

The latest 100 records have p50 153.510ms, p95 178.573ms, p99 233.577ms and max 233.577ms. There are no samples above 500ms or 1000ms. The read-model assembly stage is now p95 14.308ms / max 18.984ms; auxiliary reads are p95 166.562ms / max 221.514ms.

## Large-state smoke

An isolated temporary fixture with 10,000 tasks, 3,000 bindings, 1,000 UI clients and approximately 20MB events passed:

- heartbeat: 0.102s
- start: 0.099s
- release: 0.100s

This validates the active CLI path, not a claim that every UI surface is under 160ms.

## Conclusion

The major full-directory rebuild bottleneck is reduced: active heartbeat/start/release paths use bounded snapshot logic, and stale projector fallback overlays only the newest 2,000 task files. The 160ms p99 objective is not yet proven for the current rolling window because auxiliary reads remain above target.
