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
    @State private var richCompactReady = false
    @State private var scheduledRichCompactMount = false
    private let startupTransition = Animation.easeInOut(duration: 0.22)

    var body: some View {
        switch displayMode {
        case .compact:
            compactRoot
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
        ZStack {
            LuckyCatCompactStartupView(statusTitle: viewModel.luckyCatPresentationTitle())
                .opacity(richCompactReady ? 0 : 1)
                .scaleEffect(richCompactReady ? 0.984 : 1)
                .blur(radius: richCompactReady ? 1.2 : 0)
                .allowsHitTesting(!richCompactReady)

            LuckyCatCompactView(viewModel: viewModel)
                .opacity(richCompactReady ? 1 : 0)
                .scaleEffect(richCompactReady ? 1 : 1.012)
                .blur(radius: richCompactReady ? 0 : 1.4)
                .allowsHitTesting(richCompactReady)
        }
        .animation(startupTransition, value: richCompactReady)
        .onAppear {
            scheduleRichCompactMount()
        }
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

    private func scheduleRichCompactMount() {
        guard !scheduledRichCompactMount else { return }
        scheduledRichCompactMount = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(startupTransition) {
                richCompactReady = true
            }
        }
    }
}

private struct LuckyCatCompactStartupView: View {
    let statusTitle: String

    var body: some View {
        ZStack {
            startupGlow

            ZStack {
                startupShell
                startupEars
                startupBellyHalo
                startupFace
                startupWhiskers
                startupBell
            }
            .frame(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)
        }
        .frame(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)
        .compositingGroup()
    }

    private var startupGlow: some View {
        Circle()
            .fill(LuckyCatTokens.Palette.glassPrismRose.opacity(0.28))
            .frame(width: 180, height: 180)
            .blur(radius: 28)
            .offset(y: -6)
    }

    private var startupShell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.62),
                            LuckyCatTokens.Palette.glassRoseTint.opacity(0.84),
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.54)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                )

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            LuckyCatTokens.Palette.glassRoseTint.opacity(0.18),
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.26)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 176, height: 116)
                .offset(y: 34)
                .blur(radius: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: LuckyCatTokens.Palette.glassDeepShadow.opacity(0.28), radius: 12, x: 0, y: 8)
    }

    private var startupBellyHalo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        LuckyCatTokens.Palette.glassRoseTint.opacity(0.08),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 92
                )
            )
            .frame(width: 186, height: 186)
        .offset(y: 2)
    }

    private var startupEars: some View {
        HStack(spacing: 86) {
            StartupEarShape()
                .fill(startupEarFill)
                .frame(width: 58, height: 46)
            StartupEarShape()
                .fill(startupEarFill)
                .frame(width: 58, height: 46)
                .scaleEffect(x: -1, y: 1)
        }
        .offset(y: -84)
    }

    private var startupEarFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.54),
                LuckyCatTokens.Palette.glassRoseTint.opacity(0.88),
                LuckyCatTokens.Palette.glassRoseDepth.opacity(0.6)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var startupFace: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                LuckyCatTokens.Palette.glassRoseDepth.opacity(0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 142, height: 142)

                Text("66")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                LuckyCatTokens.Palette.glassPrismBlue.opacity(0.28),
                                LuckyCatTokens.Palette.cream.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.white.opacity(0.18), radius: 1, x: 0, y: -1)
            }
        }
        .offset(y: -16)
    }

    private var startupWhiskers: some View {
        VStack(spacing: 10) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.12),
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.4),
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.12)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 120, height: 3)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.1),
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.34),
                            LuckyCatTokens.Palette.glassRoseDepth.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 126, height: 3)
        }
        .offset(y: 58)
    }

    private var startupBell: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            LuckyCatTokens.Palette.gold.opacity(0.92),
                            LuckyCatTokens.Palette.goldDeep.opacity(0.86)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.white.opacity(0.44), lineWidth: 1))

            Text(statusGlyph)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.textPrimary.opacity(0.72))
                .offset(y: 0.5)
        }
        .offset(x: -6, y: 96)
        .shadow(color: LuckyCatTokens.Palette.goldDeep.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    private var statusGlyph: String {
        switch statusTitle.uppercased() {
        case "RUNNING":
            return "R"
        case "BLOCKED":
            return "B"
        case "DONE":
            return "D"
        case "PENDING":
            return "P"
        default:
            return "·"
        }
    }
}

private struct StartupEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06),
            control: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.26)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.22)
        )
        path.closeSubpath()
        return path
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
