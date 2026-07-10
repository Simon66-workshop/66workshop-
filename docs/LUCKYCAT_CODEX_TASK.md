# Codex Task｜66TaskLight M2.5 LuckyCat 66VS UI Skin

## Project Path

`/Users/macmini-simon66/Documents/Codex状态桌面栏提醒`

## Read First

1. `docs/LUCKYCAT_UI_SPEC.md`
2. `docs/LUCKYCAT_FIGMA_COMPONENTS.md`
3. `design/luckycat-ui/params/luckycat_tokens.json`
4. `design/luckycat-ui/params/luckycat_layout.json`
5. `design/luckycat-ui/params/status_mapping.json`
6. `design/luckycat-ui/engineering/FILE_TREE.md`
7. `design/luckycat-ui/engineering/ACCEPTANCE_CHECKLIST.md`

## Goal

Implement the approved LuckyCat 66VS UI skin for the existing 66TaskLight macOS dashboard.

The compact main title must remain a dynamic global status title, not a fixed brand word. The UI should show a cute LuckyCat-style compact panel with five paw chips:

- 阻塞
- 运行
- 完成
- 待验
- 观察

## Hard Boundaries

1. Do not call external APIs.
2. Do not read Codex App private databases.
3. Do not do screenshot/OCR scraping.
4. Do not modify 66GOS / Hermes / Obsidian runtime.
5. Do not commit or push.
6. Do not change task protocol semantics.
7. `done_unverified` remains pending/blue and never triggers green sound.
8. `done_verified` is the only green completion state.
9. Observed threads are display-only and must not write managed task completion.
10. App remains read-only; CLI remains authoritative writer.

## Required New SwiftUI Files

Create these files under `mac/66TaskLight/Sources/TaskLightApp/`:

```text
Theme/LuckyCatTokens.swift
Theme/LuckyCatStatusStyle.swift
Theme/LuckyCatLayout.swift
Components/LuckyCatGlassPanel.swift
Components/LuckyCatMascotView.swift
Components/LuckyCatFaceView.swift
Components/LuckyCatEarView.swift
Components/LuckyCatBellView.swift
Components/LuckyCatStatusOrb.swift
Components/LuckyCatPawCounterChip.swift
Components/LuckyCatTaskCard.swift
Components/LuckyCatObservedThreadCard.swift
Screens/LuckyCatCompactView.swift
Screens/LuckyCatExpandedDashboardView.swift
Screens/LuckyCatDashboardRootView.swift
Preview/LuckyCatPreviewData.swift
```

Use `design/luckycat-ui/templates/swiftui/` as implementation guidance, not as blind copy if the actual model names differ.

## Allowed Existing File Changes

```text
mac/66TaskLight/Sources/TaskLightApp/TaskLightRootView.swift
mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift
mac/66TaskLight/Sources/TaskLightApp/TaskLightPanelController.swift
mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift
README.md
```

## Compact UI Requirements

- Panel size: `360 × 220`
- Rounded glass panel, radius `34`
- Main title: dynamic global display title
- Subtitle: `M{managed_active_count} · O{observed_active_count}`
- LuckyCat mascot left side
- Five paw chips with exact labels: 阻塞 / 运行 / 完成 / 待验 / 观察
- Global status glow follows existing lamp rules
- Clicking compact panel can toggle expanded panel, preserving existing behavior

## Expanded Dashboard Requirements

- Size: `680 × 500`
- Left mascot area
- Top summary strip with five chips
- Managed Tasks section
- Live Observed Threads section
- Observed thread cards must include: `未接管，仅显示活跃状态`
- Sort order: blocked, stale, running, queued, done_unverified, done_verified

## Status Mapping

- `blocked/stale` → red
- `running/queued` → blue
- `done_unverified` → amber label, contributes to blue global lamp
- `done_verified` → green
- `observed_active` → cyan/blue display-only
- `idle` → gray/gold

## Checks

After implementation, run:

```bash
./script/check_all.sh
./script/build_and_run.sh --verify
```

Normal `build_and_run.sh` runs from a temporary runtime bundle and does not
refresh the Desktop app copy. Use this explicit mode only when the Desktop
shortcut itself must be replaced:

```bash
./script/build_and_run.sh install-desktop
```

## Acceptance

1. App launches and compact panel shows LuckyCat UI.
2. Main title displays the dynamic global status title (`IDLE` / `RUNNING` / `BLOCKED` / `DONE`).
3. M/O counts are correct.
4. Five paw chips show correct counts.
5. `done_unverified` does not trigger green.
6. Observed thread disappearance remains silent.
7. Managed blocked and done_verified sound logic remains unchanged.
8. Existing smoke tests pass.

## Output Required

1. Modified file list
2. New component list
3. State mapping summary
4. Run commands
5. Test results
6. Current limitations
