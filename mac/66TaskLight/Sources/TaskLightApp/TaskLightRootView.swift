import SwiftUI
import TaskLightCore

struct TaskLightRootView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    var body: some View {
        LuckyCatDashboardRootView(viewModel: viewModel)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.toggleExpanded()
            }
            .contextMenu {
                Button(viewModel.muted ? "Unmute" : "Mute") {
                    viewModel.toggleMute()
                }
                Button("Open Log") {
                    viewModel.openLog()
                }
                Button("Copy Blocker") {
                    viewModel.copyBlocker()
                }
                Button("Clear") {
                    viewModel.clearTask()
                }
            }
    }
}

private struct LegacyTaskLightRootView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    var body: some View {
        let dashboard = viewModel.dashboard
        VStack(alignment: .leading, spacing: 10) {
            Text("Legacy TaskLight")
                .font(.headline)
            Text("Global \(viewModel.statusLabel())")
                .font(.caption)
            Text(viewModel.compactCountsLabel())
                .font(.caption2.monospacedDigit())
            if let first = dashboard.tasks.first {
                Text(first.title)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(
            width: viewModel.expanded ? LuckyCatLayout.expandedWidth : LuckyCatLayout.compactWidth,
            height: viewModel.expanded ? LuckyCatLayout.expandedHeight : LuckyCatLayout.compactHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: LuckyCatLayout.cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
