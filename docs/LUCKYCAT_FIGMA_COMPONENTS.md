# Figma Component Map｜66TaskLight LuckyCat UI

## Goal

Build Figma components first, then let Codex implement SwiftUI from fixed names, variants, and parameters.

## Page Structure

```text
66TaskLight LuckyCat UI
├─ 00 Cover
├─ 01 Tokens
├─ 02 Components
├─ 03 Compact States
├─ 04 Expanded Dashboard
├─ 05 Redline / SwiftUI Specs
└─ 06 Export Assets
```

## Components

| Component | Variants / Props | Notes |
|---|---|---|
| `66TaskLight/LuckyCatPanel` | `mode=compact/expanded`, `globalStatus=idle/running/blocked/done` | Main glass panel |
| `66TaskLight/CatMascot` | `mood=idle/happy/alert/running`, `paw=left/right/none` | Lucky cat body |
| `66TaskLight/CatFace` | `mood=happy/alert/focused/sleepy` | Face states |
| `66TaskLight/CatBell` | `state=normal/ringing/muted` | Bell icon, no business logic |
| `66TaskLight/StatusOrb` | `status=idle/running/blocked/done/pending/observed` | Main glow |
| `66TaskLight/PawCounterChip` | `status=blocked/running/done/pending/observed/idle` | Five compact counters |
| `66TaskLight/TaskCard` | `status=blocked/stale/running/pending/done` | Managed task list |
| `66TaskLight/ObservedThreadCard` | `status=observed_active/quiet/attention` | Display-only observed threads |
| `66TaskLight/GlassSurface` | `density=thin/regular/thick`, `tone=warm/cool/red/blue/green` | RasterGlass layer |
| `66TaskLight/WindowControls` | `state=normal/hover` | Close/minimize controls |

## Compact Layout

- Frame: `360 × 220`
- Corner radius: `34`
- Padding: `22`
- Mascot: `118 × 150`
- Five chips: `56 × 74`, gap `12`
- Paw chip labels and counts:
  - `阻塞`: `blocked + stale`
  - `运行`: `running + queued`
  - `完成`: current visible or recent-window `done_verified`, not all-time history
  - `待验`: `pending_verify_count / done_unverified`
  - `观察`: visible `observed_active` threads
- Title: dynamic global display title
  - `IDLE`
  - `RUNNING`
  - `BLOCKED`
  - `DONE`
- Subtitle: `M{managed_active_count} · O{observed_active_count}`

## Required State Preview Frames

Create these Figma frames:

1. `Compact / Idle`
2. `Compact / Running`
3. `Compact / Pending Verify`
4. `Compact / Blocked`
5. `Compact / Done`
6. `Expanded / Mixed Tasks`
7. `Expanded / Observed Threads`

## Exported Assets

Only export reference PNGs if needed. Prefer SwiftUI shapes for dynamic elements.
