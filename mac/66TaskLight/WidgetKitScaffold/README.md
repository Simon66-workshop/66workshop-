# 66TaskLight WidgetKit Scaffold

This folder is a build-ready design scaffold for the future WidgetKit extension.
The current app is a SwiftPM-first macOS app without an Xcode project or app
extension target. The shipped runtime exports a sanitized `widget_snapshot.json`
and also writes the same payload into the App Group shared container when the app
is signed with `66TaskLightApp.entitlements`.

Desktop-ready integration is scaffolded through `../project.yml`, an XcodeGen
spec that creates a main app target and embeds `66TaskLightWidget.swift` as a
WidgetKit extension. Both app and widget must be signed with the same App Group:

- Main app: `66TaskLightApp.entitlements`
- Widget extension: `66TaskLightWidgetExtension.entitlements`
- Shared group: `group.com.66tasklight.widget`
- Snapshot file: `widget_snapshot.json`
- Xcode wrapper app Info.plist: `../XcodeWrapper/AppInfo.plist`

Implementation status:

- Done: sanitized `TaskLightWidgetSnapshot` export.
- Done: App Group shared-container read/write bridge.
- Done: WidgetKit `TimelineProvider`, `WidgetBundle`, small layout, medium layout.
- Done: local app bundle ad-hoc signing includes `66TaskLightApp.entitlements`.
- Done: XcodeGen wrapper spec for app + embedded WidgetKit extension.
- Remaining: configure a real Team ID / provisioning profile for App Group signing.
- Remaining: install the signed app and add the widget from macOS Desktop widgets.

Generate the Xcode project when XcodeGen is available:

```bash
cd mac/66TaskLight
xcodegen generate
```

Desktop acceptance gates:

1. Main app and widget extension both carry `group.com.66tasklight.widget`.
2. The widget reads only `widget_snapshot.json` from the shared container.
3. Removing the snapshot shows placeholder content, not a crash.
4. Updating app state refreshes the widget timeline within the expected window.
5. Quota remains display-only and never mutates `global_status` or `lamp_status`.

Safety rules:

- Read only `TaskLightWidgetSnapshot`.
- Do not read prompts, responses, auth files, or raw logs.
- Do not infer or write `global_status` or `lamp_status`.
- Do not connect provider APIs from the widget.
- Treat quota as display-only; it must not affect the main lamp.
