# 66TaskLight WidgetKit Scaffold

This folder is a build-ready design scaffold for the future WidgetKit extension.
The current app is a SwiftPM-first macOS app without an Xcode project or app
extension target. The shipped runtime exports a sanitized `widget_snapshot.json`
and also writes the same payload into the App Group shared container when the app
is signed with `66TaskLightApp.entitlements`.

Desktop-ready integration still needs an Xcode app wrapper that embeds
`66TaskLightWidget.swift` as a WidgetKit extension and signs both app and widget
with the same App Group:

- Main app: `66TaskLightApp.entitlements`
- Widget extension: `66TaskLightWidgetExtension.entitlements`
- Shared group: `group.com.66tasklight.widget`
- Snapshot file: `widget_snapshot.json`

Safety rules:

- Read only `TaskLightWidgetSnapshot`.
- Do not read prompts, responses, auth files, or raw logs.
- Do not infer or write `global_status` or `lamp_status`.
- Do not connect provider APIs from the widget.
- Treat quota as display-only; it must not affect the main lamp.
