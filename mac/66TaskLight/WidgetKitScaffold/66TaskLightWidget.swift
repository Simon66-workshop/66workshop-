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
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            default:
                smallBody
            }
        }
        .containerBackground(.thinMaterial, for: .widget)
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusTitle
            Text(entry.snapshot?.quota_text ?? "Q?")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(entry.snapshot?.quota_is_low == true ? .red : .primary)
                .monospacedDigit()
            Text("Run \(entry.snapshot?.running_count ?? 0) · Pend \(entry.snapshot?.pending_count ?? 0)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                statusTitle
                Text(entry.snapshot?.quota_text ?? "Q?")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(entry.snapshot?.quota_is_low == true ? .red : .primary)
                    .monospacedDigit()
                Text("Quota stays display-only")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                metric("Run", entry.snapshot?.running_count ?? 0)
                metric("Pend", entry.snapshot?.pending_count ?? 0)
                metric("Hooks", (entry.snapshot?.workspace_warning_count ?? 0) + (entry.snapshot?.workspace_attention_count ?? 0))
            }
        }
        .padding()
    }

    private var statusTitle: some View {
        Text(entry.snapshot?.display_title ?? "66TaskLight")
            .font(.system(size: 16, weight: .black, design: .rounded))
            .lineLimit(1)
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .monospacedDigit()
        }
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

@main
struct TaskLightWidgetBundle: WidgetBundle {
    var body: some Widget {
        TaskLightWidget()
    }
}
#endif
