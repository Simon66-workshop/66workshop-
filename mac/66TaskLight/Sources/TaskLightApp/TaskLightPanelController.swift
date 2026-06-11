import AppKit
import Combine
import SwiftUI
import TaskLightCore

final class TaskLightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class TaskLightPanelController: NSObject, NSWindowDelegate {
    private let viewModel: TaskLightViewModel
    private var panel: TaskLightPanel?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: TaskLightViewModel) {
        self.viewModel = viewModel
        super.init()
        viewModel.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.resizePanel(expanded: expanded)
                self?.saveFrame()
            }
            .store(in: &cancellables)
    }

    func showPanel() {
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }
        restoreFrameIfNeeded()
        resizePanel(expanded: viewModel.expanded)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.start()
    }

    func resizePanel(expanded: Bool) {
        guard let panel else { return }
        let frame = panel.frame
        let size = expanded
            ? NSSize(width: LuckyCatLayout.expandedWidth, height: LuckyCatLayout.expandedHeight)
            : NSSize(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)
        panel.setFrame(NSRect(origin: frame.origin, size: size), display: true, animate: true)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    private func createPanel() {
        let rootView = TaskLightRootView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: rootView)
        let panel = TaskLightPanel(
            contentRect: NSRect(x: 120, y: 120, width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = hosting
        panel.delegate = self
        self.panel = panel
    }

    private func restoreFrameIfNeeded() {
        guard let panel else { return }
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: TaskLightLedgerKeys.windowFrame),
           let value = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) {
            panel.setFrame(clampedFrame(value.rectValue), display: true)
        }
    }

    private func saveFrame() {
        guard let panel else { return }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: NSValue(rect: panel.frame), requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.windowFrame)
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return frame
        }
        let visible = screen.visibleFrame
        var clamped = frame
        if clamped.width > visible.width {
            clamped.size.width = visible.width
        }
        if clamped.height > visible.height {
            clamped.size.height = visible.height
        }
        clamped.origin.x = min(max(clamped.origin.x, visible.minX), visible.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.origin.y, visible.minY), visible.maxY - clamped.height)
        return clamped
    }
}
