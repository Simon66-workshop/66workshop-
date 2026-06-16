import AppKit
import Combine
import SwiftUI
import TaskLightCore

final class TaskLightPanel: NSPanel {
    var roundedHitTestRadius: CGFloat = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        guard !shouldDropMouseEvent(event) else { return }
        super.sendEvent(event)
    }

    private func shouldDropMouseEvent(_ event: NSEvent) -> Bool {
        guard roundedHitTestRadius > 0 else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel:
            let hitRect = NSRect(origin: .zero, size: frame.size)
            let hitPath = NSBezierPath(
                roundedRect: hitRect,
                xRadius: roundedHitTestRadius,
                yRadius: roundedHitTestRadius
            )
            return !hitPath.contains(event.locationInWindow)
        default:
            return false
        }
    }
}

private extension TaskLightPanelDisplayMode {
    var traceName: String {
        switch self {
        case .compact:
            return "compact"
        case .expanded:
            return "expanded"
        }
    }
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
    private var startupVisibilityWorkItems: [DispatchWorkItem] = []

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
        appendStartupTrace("showPanel.begin")
        if compactPanel == nil {
            compactPanel = createPanel(displayMode: .compact)
            appendStartupTrace("showPanel.createdCompactPanel")
        }
        guard let compactPanel else { return }
        let initialCompactFrame = preferredStartupCompactFrame(fallback: compactPanel.frame)
        applyPanelFrame(initialCompactFrame, to: compactPanel)
        appendStartupTrace("showPanel.appliedStartupCompactFrame")
        if viewModel.expanded {
            let expandedPanel = ensureExpandedPanel()
            preExpandedCompactFrame = compactPanel.frame
            applyPanelFrame(expandedFrame(from: compactPanel.frame), to: expandedPanel)
            compactPanel.orderOut(nil)
            expandedPanel.makeKeyAndOrderFront(nil)
            expandedPanel.orderFrontRegardless()
            viewModel.setContentExpanded(true)
            appendStartupTrace("showPanel.frontExpandedPanel")
        } else {
            expandedPanel?.orderOut(nil)
            compactPanel.makeKeyAndOrderFront(nil)
            compactPanel.orderFrontRegardless()
            viewModel.setContentExpanded(false)
            appendStartupTrace("showPanel.frontCompactPanel")
        }
        NSApp.activate(ignoringOtherApps: true)
        appendStartupTrace("showPanel.activateApp")
        viewModel.start()
        appendStartupTrace("showPanel.startedViewModel")
        scheduleStartupVisibilityRecovery()
    }

    func transition(expanded: Bool) {
        guard let compactPanel else { return }
        if expanded {
            let expandedPanel = ensureExpandedPanel()
            let compactFrame = compactFrame(from: compactPanel.frame)
            preExpandedCompactFrame = compactFrame
            saveCompactFrame(compactFrame)
            applyPanelFrame(expandedFrame(from: compactFrame), to: expandedPanel)
            compactPanel.orderOut(nil)
            expandedPanel.makeKeyAndOrderFront(nil)
            expandedPanel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            viewModel.setContentExpanded(true)
        } else {
            guard let expandedPanel else { return }
            let targetFrame = TaskLightPanelGeometry.collapsedCompactFrame(
                storedCompactFrame: preExpandedCompactFrame ?? storedCompactFrame(),
                currentExpandedFrame: expandedPanel.frame,
                compactSize: compactSize,
                visibleFrames: visibleFrames()
            )
            applyPanelFrame(targetFrame, to: compactPanel)
            expandedPanel.orderOut(nil)
            compactPanel.makeKeyAndOrderFront(nil)
            compactPanel.orderFrontRegardless()
            preExpandedCompactFrame = nil
            viewModel.setContentExpanded(false)
        }
    }

    func recoverVisibility(reason: String = "manual") {
        ensureVisibleOnActiveSpace()
        appendStartupTrace("recoverVisibility.\(reason)")
    }

    func shutdown() {
        startupVisibilityWorkItems.forEach { $0.cancel() }
        startupVisibilityWorkItems.removeAll()
        compactPanel?.orderOut(nil)
        expandedPanel?.orderOut(nil)
        compactPanel = nil
        expandedPanel = nil
        cancellables.removeAll()
    }

    private func ensureExpandedPanel() -> TaskLightPanel {
        if let expandedPanel {
            return expandedPanel
        }
        let panel = createPanel(displayMode: .expanded)
        expandedPanel = panel
        appendStartupTrace("panel.createdExpandedOnDemand")
        return panel
    }

    func windowDidMove(_ notification: Notification) {
        saveFrameIfCompact(window: notification.object as? NSWindow)
    }

    func windowDidResize(_ notification: Notification) {
        saveFrameIfCompact(window: notification.object as? NSWindow)
    }

    private func createPanel(displayMode: TaskLightPanelDisplayMode) -> TaskLightPanel {
        let size = panelSize(for: displayMode)
        appendStartupTrace("createPanel.\(displayMode.traceName).begin")
        let rootView = TaskLightRootView(viewModel: viewModel, displayMode: displayMode)
        appendStartupTrace("createPanel.\(displayMode.traceName).createdRootView")
        let hosting = NSHostingController(rootView: rootView)
        appendStartupTrace("createPanel.\(displayMode.traceName).createdHosting")
        let panel = TaskLightPanel(
            contentRect: NSRect(x: 120, y: 120, width: size.width, height: size.height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        appendStartupTrace("createPanel.\(displayMode.traceName).createdPanel")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.roundedHitTestRadius = displayMode == .expanded ? LuckyCatLayout.cornerRadius : 0
        panel.contentViewController = hosting
        panel.delegate = self
        appendStartupTrace("createPanel.\(displayMode.traceName).end")
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

    private func preferredStartupCompactFrame(fallback: NSRect) -> NSRect {
        let anchorFrame = activeVisibleFrame() ?? visibleFrames().first ?? fallback
        let anchoredFrame = NSRect(
            x: anchorFrame.maxX - compactSize.width - 18,
            y: anchorFrame.maxY - compactSize.height - 18,
            width: compactSize.width,
            height: compactSize.height
        )

        if let storedFrame = storedCompactFrame() {
            return TaskLightPanelGeometry.restoredCompactFrame(
                storedFrame: storedFrame,
                fallbackFrame: anchoredFrame,
                compactSize: compactSize,
                visibleFrames: [anchorFrame]
            )
        }

        return TaskLightPanelGeometry.clampedFrame(anchoredFrame, visibleFrame: anchorFrame)
    }

    private func activeVisibleFrame() -> NSRect? {
        if let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return activeScreen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }

    private var compactSize: NSSize {
        NSSize(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)
    }

    private var expandedSize: NSSize {
        NSSize(width: LuckyCatLayout.expandedWidth, height: LuckyCatLayout.expandedHeight)
    }

    private func scheduleStartupVisibilityRecovery() {
        startupVisibilityWorkItems.forEach { $0.cancel() }
        startupVisibilityWorkItems.removeAll()

        for delay in [0.2, 1.0, 3.0] {
            let workItem = DispatchWorkItem { [weak self] in
                self?.ensureVisibleOnActiveSpace()
            }
            startupVisibilityWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func ensureVisibleOnActiveSpace() {
        guard let compactPanel else { return }
        let targetPanel: TaskLightPanel
        if viewModel.expanded {
            targetPanel = ensureExpandedPanel()
        } else {
            targetPanel = compactPanel
        }
        let fallbackFrame = targetPanel.frame
        let recoveredFrame = viewModel.expanded
            ? expandedFrame(from: compactFrame(from: compactPanel.frame))
            : preferredStartupCompactFrame(fallback: fallbackFrame)
        applyPanelFrame(recoveredFrame, to: targetPanel)
        targetPanel.orderFrontRegardless()
        targetPanel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        appendStartupTrace("ensureVisibleOnActiveSpace")
    }

    private func appendStartupTrace(_ event: String) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("startup_trace.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) panel_controller \(event)\n"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
