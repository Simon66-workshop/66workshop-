import AppKit
import SwiftUI
import TaskLightCore

enum TaskLightPanelDisplayMode {
    case compact
    case edgeRail
    case expanded
}

struct TaskLightRootView: View {
    @ObservedObject var viewModel: TaskLightViewModel
    let displayMode: TaskLightPanelDisplayMode

    var body: some View {
        switch displayMode {
        case .compact:
            compactRoot
        case .edgeRail:
            LuckyCatEdgeRailView(viewModel: viewModel)
        case .expanded:
            LuckyCatExpandedDashboardView(viewModel: viewModel)
                .contentShape(Rectangle())
                .overlay {
                    ExpandedCollapseGestureLayer {
                        viewModel.collapseExpanded()
                    }
                }
        }
    }

    private var compactRoot: some View {
        LuckyCatCompactView(viewModel: viewModel)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.toggleExpanded()
            }
    }
}

private struct ExpandedCollapseGestureLayer: NSViewRepresentable {
    let onCollapse: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCollapse: onCollapse)
    }

    func makeNSView(context: Context) -> NSView {
        let view = ExpandedCollapseGestureNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCollapse = onCollapse
        (nsView as? ExpandedCollapseGestureNSView)?.coordinator = context.coordinator
    }

    final class Coordinator {
        var onCollapse: () -> Void

        init(onCollapse: @escaping () -> Void) {
            self.onCollapse = onCollapse
        }
    }
}

private final class ExpandedCollapseGestureNSView: NSView {
    weak var coordinator: ExpandedCollapseGestureLayer.Coordinator?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeEventMonitor()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .rightMouseDown {
                self.coordinator?.onCollapse()
                return nil
            }
            if event.type == .leftMouseDown && event.clickCount >= 2 {
                self.coordinator?.onCollapse()
                return nil
            }
            return event
        }
    }

    deinit {
        removeEventMonitor()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
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
