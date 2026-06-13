import AppKit
import SwiftUI
import TaskLightCore

enum TaskLightPanelDisplayMode {
    case compact
    case expanded
}

struct TaskLightRootView: View {
    @ObservedObject var viewModel: TaskLightViewModel
    let displayMode: TaskLightPanelDisplayMode

    var body: some View {
        switch displayMode {
        case .compact:
            LuckyCatCompactView(viewModel: viewModel)
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
        case .expanded:
            LuckyCatExpandedDashboardView(viewModel: viewModel)
                .contentShape(Rectangle())
                .overlay {
                    RightClickCollapseLayer {
                        viewModel.collapseExpanded()
                    }
                }
        }
    }
}

private struct RightClickCollapseLayer: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RightClickCollapseNSView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RightClickCollapseNSView)?.onRightClick = onRightClick
    }
}

private final class RightClickCollapseNSView: NSView {
    var onRightClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

private struct LegacyTaskLightRootView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    var body: some View {
        let managedTasks = viewModel.sortedManagedTasks()
        VStack(alignment: .leading, spacing: 10) {
            Text("Legacy TaskLight")
                .font(.headline)
            Text("Global \(viewModel.statusLabel())")
                .font(.caption)
            Text(viewModel.compactCountsLabel())
                .font(.caption2.monospacedDigit())
            if let first = managedTasks.first {
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
