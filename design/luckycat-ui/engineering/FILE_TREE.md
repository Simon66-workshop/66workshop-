# Engineering File Tree｜LuckyCat UI Skin

## New SwiftUI Files

```text
mac/66TaskLight/Sources/TaskLightApp/
├─ Theme/
│  ├─ LuckyCatTokens.swift
│  ├─ LuckyCatStatusStyle.swift
│  └─ LuckyCatLayout.swift
│
├─ Components/
│  ├─ LuckyCatGlassPanel.swift
│  ├─ LuckyCatMascotView.swift
│  ├─ LuckyCatFaceView.swift
│  ├─ LuckyCatEarView.swift
│  ├─ LuckyCatBellView.swift
│  ├─ LuckyCatStatusOrb.swift
│  ├─ LuckyCatPawCounterChip.swift
│  ├─ LuckyCatTaskCard.swift
│  ├─ LuckyCatObservedThreadCard.swift
│  └─ LuckyCatWindowControls.swift
│
├─ Screens/
│  ├─ LuckyCatCompactView.swift
│  ├─ LuckyCatExpandedDashboardView.swift
│  └─ LuckyCatDashboardRootView.swift
│
└─ Preview/
   └─ LuckyCatPreviewData.swift
```

## Existing Files Allowed To Edit

```text
mac/66TaskLight/Sources/TaskLightApp/TaskLightRootView.swift
mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift
mac/66TaskLight/Sources/TaskLightApp/TaskLightPanelController.swift
mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift
README.md
docs/STATUS_PROTOCOL.md only for UI-skin notes, not protocol changes
```

## Hard Rule

Do not pile the LuckyCat UI into `TaskLightRootView.swift`. Keep it as a skin with separated tokens, components, and screens.
