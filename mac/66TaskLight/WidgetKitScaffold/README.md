# 66TaskLight WidgetKit Scaffold

This folder is a build-ready design scaffold for the future WidgetKit extension.
The current app is a SwiftPM-first macOS app without an Xcode project or app
extension target, so the shipped runtime exports a sanitized
`widget_snapshot.json` first. The actual desktop widget should be wired through
an Xcode app wrapper with an App Group shared container before it is presented as
desktop-ready.

Safety rules:

- Read only `TaskLightWidgetSnapshot`.
- Do not read prompts, responses, auth files, or raw logs.
- Do not infer or write `global_status` or `lamp_status`.
- Do not connect provider APIs from the widget.
- Treat quota as display-only; it must not affect the main lamp.

