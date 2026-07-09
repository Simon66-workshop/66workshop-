#if canImport(WidgetKit)
import SwiftUI
import WidgetKit
import TaskLightCore

struct TaskLightWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TaskLightWidgetSnapshot?
}

struct TaskLightWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskLightWidgetEntry {
        TaskLightWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskLightWidgetEntry) -> Void) {
        completion(TaskLightWidgetEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskLightWidgetEntry>) -> Void) {
        let entry = TaskLightWidgetEntry(date: Date(), snapshot: loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }

    private func loadSnapshot() -> TaskLightWidgetSnapshot? {
        if let shared = TaskLightStore(config: .fromEnvironment()).loadWidgetSnapshotFromAppGroup() {
            return shared
        }
        return TaskLightStore(config: .fromEnvironment()).loadWidgetSnapshot()
    }
}

struct TaskLightWidgetView: View {
    let entry: TaskLightWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.snapshot?.display_title ?? "66TaskLight")
                .font(.system(size: 16, weight: .black, design: .rounded))
            Text("Run \(entry.snapshot?.running_count ?? 0) · Pend \(entry.snapshot?.pending_count ?? 0)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(entry.snapshot?.quota_text ?? "Q?")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .padding()
        .containerBackground(.thinMaterial, for: .widget)
    }
}

struct TaskLightWidget: Widget {
    let kind = TaskLightWidgetBridge.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskLightWidgetProvider()) { entry in
            TaskLightWidgetView(entry: entry)
        }
        .configurationDisplayName("66TaskLight")
        .description("Codex status, task counts, quota, and workspace health from sanitized local snapshot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
#endif
