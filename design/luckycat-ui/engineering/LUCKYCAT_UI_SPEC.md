# 66TaskLight LuckyCat UI Spec

## Positioning

`66TaskLight LuckyCat UI` is a visual skin for the existing task status system. It must not change task protocol semantics.

## Compact Panel

- Size: `360 × 220`
- Corner radius: `34`
- Title: dynamic global display title
  - `idle` -> `IDLE`
  - `running / queued / done_unverified / observed_active` -> `RUNNING`
  - `blocked / stale / observed_attention` -> `BLOCKED`
  - `done_verified` with no active/observed threads -> `DONE`
- Subtitle: `M{managed_active_count} · O{observed_active_count}`
- Mascot: left side, cute lucky-cat style
- Counters: five paw chips
  - 阻塞: blocked + stale
  - 运行: running + queued
  - 完成: done_verified
  - 待验: pending_verify_count
  - 观察: observed_active

## Expanded Dashboard

- Size: `680 × 500`
- Left: larger LuckyCat mascot
- Top: five summary chips
- Main: Managed Tasks
- Bottom or second section: Live Observed Threads
- Observed card must show: `未接管，仅显示活跃状态`

## State Visuals

| State | Compact lamp | Chip color | Sound |
|---|---|---|---|
| blocked/stale | red | red | red lane |
| running/queued | blue | blue | none |
| done_unverified | blue global + amber chip | amber | none |
| done_verified | green | green | done sound |
| observed_active | blue global + cyan chip | cyan | none |
| idle | gray/gold | gray | none |

## Non-negotiables

1. Do not use `66VS` as the main title. The main title must reflect the global state.
2. `done_unverified` is not green.
3. `observed_active` is display-only.
4. Observed thread disappearance is silent.
5. CLI remains authoritative writer.
6. App remains read-only.
