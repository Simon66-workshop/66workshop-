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
    private var compactPanel: TaskLightPanel?
    private var expandedPanel: TaskLightPanel?
    private var cancellables = Set<AnyCancellable>()
    private var preExpandedCompactFrame: NSRect?
    private var isApplyingProgrammaticFrame = false
    private var programmaticFrameChangeID = 0

    init(viewModel: TaskLightViewModel) {
        self.viewModel = viewModel
        super.init()
        viewModel.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.transition(expanded: expanded)
            }
            .store(in: &cancellables)
    }

    func showPanel() {
        if compactPanel == nil {
            compactPanel = createPanel(displayMode: .compact)
        }
        if expandedPanel == nil {
            expandedPanel = createPanel(displayMode: .expanded)
        }
        guard let compactPanel, let expandedPanel else { return }
        applyPanelFrame(restoredCompactFrame(fallback: compactPanel.frame), to: compactPanel)
        if viewModel.expanded {
            preExpandedCompactFrame = compactPanel.frame
            applyPanelFrame(expandedFrame(from: compactPanel.frame), to: expandedPanel)
            compactPanel.orderOut(nil)
            expandedPanel.makeKeyAndOrderFront(nil)
            viewModel.setContentExpanded(true)
        } else {
            expandedPanel.orderOut(nil)
            compactPanel.makeKeyAndOrderFront(nil)
            viewModel.setContentExpanded(false)
        }
        NSApp.activate(ignoringOtherApps: true)
        viewModel.start()
    }

    func transition(expanded: Bool) {
        guard let compactPanel, let expandedPanel else { return }
        if expanded {
            let compactFrame = compactFrame(from: compactPanel.frame)
            preExpandedCompactFrame = compactFrame
            saveCompactFrame(compactFrame)
            applyPanelFrame(expandedFrame(from: compactFrame), to: expandedPanel)
            compactPanel.orderOut(nil)
            expandedPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            viewModel.setContentExpanded(true)
        } else {
            let targetFrame = TaskLightPanelGeometry.collapsedCompactFrame(
                storedCompactFrame: preExpandedCompactFrame ?? storedCompactFrame(),
                currentExpandedFrame: expandedPanel.frame,
                compactSize: compactSize,
                visibleFrames: visibleFrames()
            )
            applyPanelFrame(targetFrame, to: compactPanel)
            expandedPanel.orderOut(nil)
            compactPanel.makeKeyAndOrderFront(nil)
            preExpandedCompactFrame = nil
            viewModel.setContentExpanded(false)
        }
    }

    func windowDidMove(_ notification: Notification) {
        saveFrameIfCompact(window: notification.object as? NSWindow)
    }

    func windowDidResize(_ notification: Notification) {
        saveFrameIfCompact(window: notification.object as? NSWindow)
    }

    private func createPanel(displayMode: TaskLightPanelDisplayMode) -> TaskLightPanel {
        let size = panelSize(for: displayMode)
        let rootView = TaskLightRootView(viewModel: viewModel, displayMode: displayMode)
        let hosting = NSHostingController(rootView: rootView)
        let panel = TaskLightPanel(
            contentRect: NSRect(x: 120, y: 120, width: size.width, height: size.height),
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
        return panel
    }

    private func restoredCompactFrame(fallback: NSRect) -> NSRect {
        TaskLightPanelGeometry.restoredCompactFrame(
            storedFrame: storedCompactFrame(),
            fallbackFrame: fallback,
            compactSize: compactSize,
            visibleFrames: visibleFrames()
        )
    }

    private func storedCompactFrame() -> NSRect? {
        let defaults = UserDefaults.standard
        let keys = [TaskLightLedgerKeys.compactWindowFrame, TaskLightLedgerKeys.windowFrame]
        for key in keys {
            if let data = defaults.data(forKey: key),
               let value = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) {
                return value.rectValue
            }
        }
        return nil
    }

    private func saveFrameIfCompact(window: NSWindow?) {
        guard let compactPanel else { return }
        guard window === compactPanel else { return }
        guard !isApplyingProgrammaticFrame else { return }
        guard !viewModel.expanded else { return }
        saveCompactFrame(compactPanel.frame)
    }

    private func saveCompactFrame(_ frame: NSRect) {
        let compact = compactFrame(from: frame)
        let data = try? NSKeyedArchiver.archivedData(withRootObject: NSValue(rect: compact), requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.compactWindowFrame)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.windowFrame)
    }

    private func compactFrame(from frame: NSRect) -> NSRect {
        NSRect(origin: frame.origin, size: compactSize)
    }

    private func expandedFrame(from compactFrame: NSRect) -> NSRect {
        TaskLightPanelGeometry.expandedFrame(
            from: compactFrame,
            expandedSize: expandedSize,
            visibleFrames: visibleFrames()
        )
    }

    private func applyPanelFrame(_ frame: NSRect, to panel: TaskLightPanel, display: Bool = true) {
        isApplyingProgrammaticFrame = true
        programmaticFrameChangeID += 1
        let changeID = programmaticFrameChangeID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.setFrame(frame, display: display, animate: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard self?.programmaticFrameChangeID == changeID else { return }
            self?.isApplyingProgrammaticFrame = false
        }
    }

    private func panelSize(for displayMode: TaskLightPanelDisplayMode) -> NSSize {
        switch displayMode {
        case .compact:
            return compactSize
        case .expanded:
            return expandedSize
        }
    }

    private func visibleFrames() -> [NSRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    private var compactSize: NSSize {
        NSSize(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)
    }

    private var expandedSize: NSSize {
        NSSize(width: LuckyCatLayout.expandedWidth, height: LuckyCatLayout.expandedHeight)
    }
}
