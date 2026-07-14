# Storage Lifecycle Analysis

## Read-only baseline

| Directory | Files | Bytes | Last 1d | Last 7d | Last 30d | Scan ms |
|---|---:|---:|---:|---:|---:|---:|
| tasks | 10,477 | 7,189,220 | 879 | 6,424 | 10,213 | 560.776 |
| turn_bindings | 2,794 | 3,480,671 | 78 | 814 | 2,765 | 170.507 |
| observations | 19 | 14,080 | 0 | 19 | 19 | 1.749 |
| ui_clients | 965 | 513,583 | 21 | 769 | 929 | 43.002 |

Event tail reads are bounded to 98,304 bytes and measured at 0.039ms in the captured baseline. The report-only maintenance planner identified 292 archive candidates in the latest check.

## Safety contract

- Default mode is `report_only`; no real file was moved or deleted.
- `running`, `queued`, `blocked`, `stale`, and `done_unverified` are protected.
- Eligible `done_verified`, `cancelled`, and `released` records are moved to a month archive only after explicit `--apply`.
- Archive operations are atomic moves, not permanent deletion.
- The main lamp does not depend on archive scanning.

## Verification

`smoke_storage_lifecycle.sh` passed with active/blocked/pending records protected and only done/cancelled records archived in the isolated fixture.
