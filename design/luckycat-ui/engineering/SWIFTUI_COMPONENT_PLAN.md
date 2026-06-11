# SwiftUI Component Plan

## Data Flow

```text
TaskLightStore
  ↓
TaskLightViewModel
  ↓
LuckyCatDashboardRootView
  ├─ LuckyCatCompactView
  └─ LuckyCatExpandedDashboardView
```

## Component Responsibilities

- `LuckyCatTokens`: colors, fonts, shadows, materials.
- `LuckyCatLayout`: dimensions and spacing.
- `LuckyCatStatusStyle`: status-to-color mapping.
- `LuckyCatGlassPanel`: shared frosted glass container.
- `LuckyCatMascotView`: cat body, ears, face, paw, bell.
- `LuckyCatPawCounterChip`: compact counter buttons.
- `LuckyCatTaskCard`: managed task row.
- `LuckyCatObservedThreadCard`: observed-only row.
- `LuckyCatDashboardRootView`: switches compact/expanded.

## Implementation Rule

Use SwiftUI shapes for dynamic UI first. Only use reference PNGs as design guidance, not as static UI background.
