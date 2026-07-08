import AppKit
import Combine
import CoreGraphics
import QuartzCore
import SwiftUI
import TaskLightCore

final class TaskLightPanel: NSPanel {
    var roundedHitTestRadius: CGFloat = 0
    var mouseDownInterceptor: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        guard !shouldDropMouseEvent(event) else { return }
        if event.isTaskLightMouseDown,
           mouseDownInterceptor?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        guard mouseDownInterceptor?(event) != true else { return }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard mouseDownInterceptor?(event) != true else { return }
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard mouseDownInterceptor?(event) != true else { return }
        super.otherMouseDown(with: event)
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

final class TaskLightClickShieldView: NSView {
    enum HitMode {
        case full
        case compactStatusOrb
    }

    var hitMode: HitMode = .full
    var onMouseDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        switch hitMode {
        case .full:
            return bounds.contains(point) ? self : nil
        case .compactStatusOrb:
            return taskLightCompactStatusOrbHit(point, panelSize: bounds.size) ? self : nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }
}

private extension NSEvent {
    var isTaskLightMouseDown: Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }
}

private func taskLightCompactStatusOrbHit(_ point: NSPoint, panelSize: NSSize) -> Bool {
    let orbCenter = compactStatusOrbCenter(panelSize: panelSize)
    let radius = max(LuckyCatLayout.compactBottomRingShadowSize / 2 + 12, 44)
    let dx = point.x - orbCenter.x
    let dy = point.y - orbCenter.y
    let bottomStatusSlot = NSRect(
        x: (panelSize.width / 2) - 72,
        y: 0,
        width: 144,
        height: min(panelSize.height, 78)
    )
    return (dx * dx + dy * dy) <= (radius * radius) || bottomStatusSlot.contains(point)
}

private func compactStatusOrbCenter(panelSize: NSSize) -> NSPoint {
    NSPoint(
        x: panelSize.width / 2,
        y: min(max(panelSize.height * 0.13, 18), 30)
    )
}

private let taskLightEdgeToggleDebounceSeconds: TimeInterval = 0.16
private let taskLightEdgeTransitionDuration: TimeInterval = 0.10
private let taskLightDragThreshold: CGFloat = 6
private let taskLightClickMaxDuration: TimeInterval = 0.16

private let taskLightMouseEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    switch type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        let controller = Unmanaged<TaskLightPanelController>.fromOpaque(userInfo).takeUnretainedValue()
        let eventLocation = event.location
        DispatchQueue.main.async {
            Task { @MainActor in
                controller.handleMouseEventTap(type: type, screenPoint: NSEvent.mouseLocation, eventLocation: eventLocation)
            }
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

private extension TaskLightPanelDisplayMode {
    var traceName: String {
        switch self {
        case .compact:
            return "compact"
        case .edgeRail:
            return "edgeRail"
        case .expanded:
            return "expanded"
        }
    }
}

private enum TaskLightPressTarget {
    case compact
    case edgeRail

    var traceName: String {
        switch self {
        case .compact:
            return "compact"
        case .edgeRail:
            return "edgeRail"
        }
    }
}

private struct TaskLightFallbackPress {
    let target: TaskLightPressTarget
    let startPoint: NSPoint
    let startFrame: NSRect
    let startedAt = Date()
    var didDrag = false
}

@MainActor
final class TaskLightPanelController: NSObject, NSWindowDelegate {
    private let viewModel: TaskLightViewModel
    private var compactPanel: TaskLightPanel?
    private var edgePanel: TaskLightPanel?
    private var expandedPanel: TaskLightPanel?
    private var cancellables = Set<AnyCancellable>()
    private var preExpandedCompactFrame: NSRect?
    private var isApplyingProgrammaticFrame = false
    private var programmaticFrameChangeID = 0
    private var startupVisibilityWorkItems: [DispatchWorkItem] = []
    private var lastEdgeToggleAt = Date.distantPast
    private var edgeTransitionLockedUntil = Date.distantPast
    private var mouseEventTap: CFMachPort?
    private var mouseEventTapSource: CFRunLoopSource?
    private var mouseButtonPollTimer: Timer?
    private var lastPolledLeftMouseDown = false
    private var isPanelPressTracking = false
    private var fallbackPress: TaskLightFallbackPress?
    private var lastKnownEdgeRailFrame: NSRect?
    private var edgeRailFramePersistWorkItem: DispatchWorkItem?

    init(viewModel: TaskLightViewModel) {
        self.viewModel = viewModel
        super.init()
        viewModel.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.transition(expanded: expanded)
            }
            .store(in: &cancellables)
        viewModel.$edgeCollapsed
            .removeDuplicates()
            .sink { [weak self] edgeCollapsed in
                self?.transition(edgeCollapsed: edgeCollapsed)
            }
            .store(in: &cancellables)
        viewModel.$edgeCollapseRequestID
            .dropFirst()
            .sink { [weak self] _ in
                self?.setEdgeCollapsedFromInteraction(true, source: "statusOrbClickCatcher.collapse")
            }
            .store(in: &cancellables)
        viewModel.$edgeRestoreRequestID
            .dropFirst()
            .sink { [weak self] _ in
                self?.forceRestoreFromEdgePanel(source: "edgeRailClickCatcher.restore")
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
        let warmedEdgePanel = ensureEdgePanel()
        applyPanelFrame(storedEdgeRailFrame() ?? edgeRailFrame(from: initialCompactFrame), to: warmedEdgePanel)
        warmedEdgePanel.alphaValue = 1
        warmedEdgePanel.ignoresMouseEvents = true
        warmedEdgePanel.orderOut(nil)
        appendStartupTrace("showPanel.warmedEdgePanel")
        if viewModel.expanded && !viewModel.edgeCollapsed {
            let expandedPanel = ensureExpandedPanel()
            preExpandedCompactFrame = compactPanel.frame
            applyPanelFrame(expandedFrame(from: compactPanel.frame), to: expandedPanel)
            compactPanel.orderOut(nil)
            expandedPanel.makeKeyAndOrderFront(nil)
            expandedPanel.orderFrontRegardless()
            viewModel.setContentExpanded(true)
            appendStartupTrace("showPanel.frontExpandedPanel")
        } else if viewModel.edgeCollapsed {
            let edgePanel = warmedEdgePanel
            applyPanelFrame(storedEdgeRailFrame() ?? edgeRailFrame(from: initialCompactFrame), to: edgePanel)
            compactPanel.ignoresMouseEvents = true
            compactPanel.orderOut(nil)
            expandedPanel?.orderOut(nil)
            edgePanel.ignoresMouseEvents = false
            edgePanel.makeKeyAndOrderFront(nil)
            edgePanel.orderFrontRegardless()
            viewModel.setContentExpanded(false)
            appendStartupTrace("showPanel.frontEdgePanel")
        } else {
            compactPanel.ignoresMouseEvents = false
            edgePanel?.orderOut(nil)
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
        installMouseEventTap()
        startMouseButtonPollingFallback()
        scheduleStartupVisibilityRecovery()
    }

    var anyTaskLightPanelVisible: Bool {
        compactPanel?.isVisible == true || edgePanel?.isVisible == true || expandedPanel?.isVisible == true
    }

    func togglePanelVisibilityFromMenuBar() {
        if anyTaskLightPanelVisible {
            compactPanel?.orderOut(nil)
            edgePanel?.orderOut(nil)
            expandedPanel?.orderOut(nil)
            appendStartupTrace("menuBar.toggleVisibility.hidden")
            return
        }
        showCurrentModeFromMenuBar(source: "menuBar.toggleVisibility.show")
    }

    func showCompactFromMenuBar() {
        if compactPanel == nil {
            viewModel.setEdgeCollapsed(false)
            viewModel.expanded = false
            showPanel()
            return
        }
        viewModel.setEdgeCollapsed(false)
        viewModel.expanded = false
        showCurrentModeFromMenuBar(source: "menuBar.showCompact")
    }

    func toggleEdgeRailFromMenuBar() {
        if compactPanel == nil {
            showPanel()
        }
        viewModel.setEdgeCollapsed(!viewModel.edgeCollapsed)
    }

    func openExpandedFromMenuBar() {
        if compactPanel == nil {
            showPanel()
        }
        if viewModel.edgeCollapsed {
            viewModel.setEdgeCollapsed(false)
        }
        if viewModel.expanded {
            showCurrentModeFromMenuBar(source: "menuBar.openExpanded.alreadyExpanded")
        } else {
            viewModel.expanded = true
        }
    }

    func transition(expanded: Bool) {
        guard let compactPanel else { return }
        guard !viewModel.edgeCollapsed else {
            viewModel.setContentExpanded(false)
            edgePanel?.orderFrontRegardless()
            return
        }
        if expanded {
            let expandedPanel = ensureExpandedPanel()
            let compactFrame = compactFrame(from: compactPanel.frame)
            preExpandedCompactFrame = compactFrame
            saveCompactFrame(compactFrame)
            applyPanelFrame(expandedFrame(from: compactFrame), to: expandedPanel)
            compactPanel.orderOut(nil)
            edgePanel?.orderOut(nil)
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
            edgePanel?.orderOut(nil)
            compactPanel.makeKeyAndOrderFront(nil)
            compactPanel.orderFrontRegardless()
            preExpandedCompactFrame = nil
            viewModel.setContentExpanded(false)
        }
    }

    func transition(edgeCollapsed: Bool) {
        guard let compactPanel else { return }
        lockEdgeTransition(source: "transition.edgeCollapsed.\(edgeCollapsed)")
        appendStartupTrace("transition.edgeCollapsed.\(edgeCollapsed).begin.frame.\(Int(compactPanel.frame.width))x\(Int(compactPanel.frame.height))")
        if edgeCollapsed {
            let edgePanel = ensureEdgePanel()
            compactPanel.ignoresMouseEvents = true
            compactPanel.acceptsMouseMovedEvents = true
            compactPanel.isMovableByWindowBackground = false
            let compactFrame = compactPanelIsVisuallyEdgeCollapsed(compactPanel)
                ? restoredCompactFrameFromEdgeRail(compactPanel.frame)
                : compactFrame(from: compactPanel.frame)
            let targetFrame = edgeRailFrame(from: compactFrame)
            saveCompactFrame(compactFrame)
            rememberEdgeRailFrame(targetFrame, source: "transition.collapse.anchor")
            expandedPanel?.orderOut(nil)
            preExpandedCompactFrame = nil
            viewModel.setContentExpanded(false)
            applyPanelFrame(targetFrame, to: edgePanel, animated: false)
            edgePanel.alphaValue = 1
            edgePanel.ignoresMouseEvents = false
            edgePanel.orderFrontRegardless()
            compactPanel.orderOut(nil)
            appendStartupTrace("transition.edgeCollapsed.true.end.frame.\(Int(targetFrame.width))x\(Int(targetFrame.height))")
        } else {
            compactPanel.ignoresMouseEvents = false
            compactPanel.acceptsMouseMovedEvents = true
            compactPanel.isMovableByWindowBackground = true
            let edgeFrame = currentEdgeRailFrame(fallback: compactPanel.frame)
            let restoringFromEdge = edgePanel?.isVisible == true || compactPanelIsVisuallyEdgeCollapsed(compactPanel)
            let targetFrame = restoringFromEdge
                ? restoredCompactFrameFromEdgeRail(edgeFrame)
                : restoredCompactFrame(fallback: compactFrame(from: compactPanel.frame))
            if restoringFromEdge {
                rememberEdgeRailFrame(edgeFrame, source: "transition.restore.edgeFrame")
            }
            if compactPanel.contentViewController == nil {
                refreshCompactRootView()
            }
            applyPanelFrame(targetFrame, to: compactPanel, animated: false)
            compactPanel.alphaValue = 1
            compactPanel.makeKeyAndOrderFront(nil)
            compactPanel.orderFrontRegardless()
            edgePanel?.ignoresMouseEvents = true
            edgePanel?.orderOut(nil)
            viewModel.setContentExpanded(false)
            appendStartupTrace("transition.edgeCollapsed.false.end.frame.\(Int(targetFrame.width))x\(Int(targetFrame.height))")
        }
    }

    func recoverVisibility(reason: String = "manual") {
        ensureVisibleOnActiveSpace()
        appendStartupTrace("recoverVisibility.\(reason)")
    }

    private func showCurrentModeFromMenuBar(source: String) {
        appendStartupTrace("\(source).begin")
        if compactPanel == nil {
            showPanel()
            return
        }
        if viewModel.edgeCollapsed {
            let panel = ensureEdgePanel()
            if let compactPanel {
                applyPanelFrame(storedEdgeRailFrame() ?? edgeRailFrame(from: compactPanel.frame), to: panel)
            }
            compactPanel?.orderOut(nil)
            expandedPanel?.orderOut(nil)
            panel.ignoresMouseEvents = false
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        } else if viewModel.expanded {
            guard let compactPanel else { return }
            let panel = ensureExpandedPanel()
            applyPanelFrame(expandedFrame(from: compactPanel.frame), to: panel)
            compactPanel.orderOut(nil)
            edgePanel?.orderOut(nil)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        } else {
            guard let compactPanel else { return }
            edgePanel?.orderOut(nil)
            expandedPanel?.orderOut(nil)
            compactPanel.ignoresMouseEvents = false
            compactPanel.makeKeyAndOrderFront(nil)
            compactPanel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        viewModel.start()
        installMouseEventTap()
        startMouseButtonPollingFallback()
        appendStartupTrace("\(source).end")
    }

    func handleActivationClickIfInsidePanel(reason: String) {
        let mouseButtonDown = CGEventSource.buttonState(.hidSystemState, button: .left)
            || CGEventSource.buttonState(.hidSystemState, button: .right)
        guard mouseButtonDown else { return }
        let screenPoint = normalizedPanelScreenPoint(NSEvent.mouseLocation)
        if let edgePanel, edgePanel.isVisible, edgePanel.frame.contains(screenPoint) {
            writeClickDiagnostic(source: "activation.\(reason).edgeRail", action: "observed_mouse_down", point: screenPoint)
            appendStartupTrace("activation.\(reason).edgeRail.observedMouseDown")
            return
        }
        guard let compactPanel, compactPanel.isVisible, !viewModel.expanded else { return }
        guard compactPanel.frame.contains(screenPoint) else { return }
        let panelPoint = NSPoint(
            x: screenPoint.x - compactPanel.frame.minX,
            y: screenPoint.y - compactPanel.frame.minY
        )
        let isStatusOrb = taskLightCompactStatusOrbHit(panelPoint, panelSize: compactPanel.frame.size)
        writeClickDiagnostic(
            source: "activation.\(reason).compact",
            action: isStatusOrb ? "observed_status_orb_mouse_down" : "observed_panel_mouse_down",
            point: panelPoint
        )
        appendStartupTrace("activation.\(reason).compact.observedMouseDown")
    }

    func runEdgeToggleSelfTest(completion: @escaping (Bool) -> Void) {
        guard compactPanel != nil else {
            writeEdgeToggleSelfTestResult([
                "status": "fail",
                "reason": "compact_panel_missing"
            ])
            completion(false)
            return
        }

        viewModel.setEdgeCollapsed(false)
        lastEdgeToggleAt = .distantPast
        edgeTransitionLockedUntil = .distantPast
        appendStartupTrace("edgeToggleSelfTest.begin")

        if let compactPanel {
            let visibleFrame = activeVisibleFrame() ?? visibleFrames().first ?? compactPanel.frame
            let testFrame = NSRect(
                x: visibleFrame.midX - compactSize.width / 2,
                y: visibleFrame.midY - compactSize.height / 2,
                width: compactSize.width,
                height: compactSize.height
            )
            applyPanelFrame(testFrame, to: compactPanel)
        }
        let warmedEdgePanel = ensureEdgePanel()
        applyPanelFrame(edgeRailFrame(from: compactPanel?.frame ?? .zero), to: warmedEdgePanel, animated: false)
        warmedEdgePanel.alphaValue = 1
        warmedEdgePanel.ignoresMouseEvents = true
        warmedEdgePanel.orderOut(nil)
        appendStartupTrace("edgeToggleSelfTest.warmedEdgePanel")

        let compactDragStartFrame = compactPanel?.frame ?? .zero
        if let compactPanel {
            movePanel(
                compactPanel,
                target: .compact,
                from: NSPoint(x: compactDragStartFrame.midX, y: compactDragStartFrame.midY),
                to: NSPoint(x: compactDragStartFrame.midX + 10, y: compactDragStartFrame.midY - 8)
            )
            finishPanelDrag(compactPanel, target: .compact, source: "selfTest.compactDrag")
        }
        let compactDragEndFrame = compactPanel?.frame ?? .zero
        let compactDragPass = viewModel.edgeCollapsed == false
            && compactPanel?.isVisible == true
            && abs(compactDragEndFrame.minX - compactDragStartFrame.minX) >= taskLightDragThreshold

        let bodyClickHandled = handleCompactPanelMouseDown(
            at: NSPoint(x: compactSize.width * 0.25, y: compactSize.height * 0.72),
            panelSize: compactSize,
            clickCount: 1,
            source: "selfTest.compactBodyClick"
        )
        let bodyClickPass = bodyClickHandled
            && viewModel.edgeCollapsed == false
            && compactPanel?.isVisible == true

        let compactStart = CACurrentMediaTime()
        let staleStoredEdgeFrame = NSRect(
            x: compactDragEndFrame.midX - edgeRailSize.width / 2,
            y: compactDragEndFrame.midY - edgeRailSize.height / 2,
            width: edgeRailSize.width,
            height: edgeRailSize.height
        )
        saveEdgeRailFrame(staleStoredEdgeFrame)
        let expectedCollapsedEdgeFrame = edgeRailFrame(from: compactDragEndFrame)
        let clickPathCollapsed = handleCompactPanelMouseDown(
            at: compactStatusOrbCenter(panelSize: compactSize),
            panelSize: compactSize,
            clickCount: 1,
            source: "selfTest.compactClick"
        )
        let collapseApplyMs = (CACurrentMediaTime() - compactStart) * 1000
        let collapsedPass = edgePanel?.isVisible == true
            && edgePanel.map { panelSizeMatches($0, edgeRailSize) } == true
            && compactPanel?.isVisible != true
        let collapsedAlphaPass = (edgePanel?.alphaValue ?? 0) >= 0.99
        let collapsedAnchoredFromCompactPass = edgePanel.map {
            abs($0.frame.minX - expectedCollapsedEdgeFrame.minX) <= 2
                && abs($0.frame.minY - expectedCollapsedEdgeFrame.minY) <= 2
        } == true

        if let edgePanel {
            let visibleFrame = activeVisibleFrame() ?? visibleFrames().first ?? edgePanel.frame
            let testFrame = NSRect(
                x: visibleFrame.midX - edgeRailSize.width / 2,
                y: visibleFrame.midY - edgeRailSize.height / 2,
                width: edgeRailSize.width,
                height: edgeRailSize.height
            )
            applyPanelFrame(testFrame, to: edgePanel)
        }

        let edgeDragStartFrame = edgePanel?.frame ?? .zero
        if let edgePanel {
            movePanel(
                edgePanel,
                target: .edgeRail,
                from: NSPoint(x: edgeDragStartFrame.midX, y: edgeDragStartFrame.midY),
                to: NSPoint(x: edgeDragStartFrame.midX + 12, y: edgeDragStartFrame.midY - 10)
            )
            finishPanelDrag(edgePanel, target: .edgeRail, source: "selfTest.edgeDrag")
        }
        let edgeDragEndFrame = edgePanel?.frame ?? .zero
        let edgeDragPass = viewModel.edgeCollapsed == true
            && edgePanel?.isVisible == true
            && compactPanel?.isVisible != true
            && abs(edgeDragEndFrame.minX - edgeDragStartFrame.minX) >= taskLightDragThreshold
            && abs(edgeDragEndFrame.minY - edgeDragStartFrame.minY) >= taskLightDragThreshold
        let expectedRestoredFrame = restoredCompactFrameFromEdgeRail(edgeDragEndFrame)

        edgeTransitionLockedUntil = .distantPast
        lastEdgeToggleAt = .distantPast
        let restoreStart = CACurrentMediaTime()
        handleEdgeRailMouseDown(source: "selfTest.edgeClick")
        let restoreApplyMs = (CACurrentMediaTime() - restoreStart) * 1000
        let restoredPass = compactPanel?.isVisible == true
            && compactPanel.map { panelSizeMatches($0, compactSize) } == true
            && edgePanel?.isVisible != true
        let restoredAlphaPass = (compactPanel?.alphaValue ?? 0) >= 0.99
        let restoredFromMovedEdgePass = compactPanel.map {
            abs($0.frame.minX - expectedRestoredFrame.minX) <= 2
                && abs($0.frame.minY - expectedRestoredFrame.minY) <= 2
        } == true

        let pass = compactDragPass
            && bodyClickPass
            && clickPathCollapsed
            && collapsedPass
            && collapsedAlphaPass
            && collapsedAnchoredFromCompactPass
            && edgeDragPass
            && restoredPass
            && restoredAlphaPass
            && restoredFromMovedEdgePass
        writeEdgeToggleSelfTestResult([
            "status": pass ? "ok" : "fail",
            "collapse_apply_ms": collapseApplyMs,
            "restore_apply_ms": restoreApplyMs,
            "transition_duration_ms": taskLightEdgeTransitionDuration * 1000,
            "compact_drag_pass": compactDragPass,
            "body_click_pass": bodyClickPass,
            "click_path_collapsed": clickPathCollapsed,
            "collapsed_pass": collapsedPass,
            "collapsed_alpha_pass": collapsedAlphaPass,
            "collapsed_anchored_from_compact_pass": collapsedAnchoredFromCompactPass,
            "stale_stored_edge_frame": framePayload(staleStoredEdgeFrame),
            "expected_collapsed_edge_frame": framePayload(expectedCollapsedEdgeFrame),
            "edge_drag_pass": edgeDragPass,
            "restored_pass": restoredPass,
            "restored_alpha_pass": restoredAlphaPass,
            "restored_from_moved_edge_pass": restoredFromMovedEdgePass,
            "compact_alpha": compactPanel?.alphaValue ?? -1,
            "edge_alpha": edgePanel?.alphaValue ?? -1,
            "compact_frame": framePayload(compactPanel?.frame),
            "edge_frame": framePayload(edgePanel?.frame),
            "expected_restored_frame": framePayload(expectedRestoredFrame),
            "compact_visible": compactPanel?.isVisible == true,
            "edge_visible": edgePanel?.isVisible == true
        ])
        appendStartupTrace("edgeToggleSelfTest.end.\(pass ? "ok" : "fail")")
        completion(pass)
    }

    func shutdown() {
        startupVisibilityWorkItems.forEach { $0.cancel() }
        startupVisibilityWorkItems.removeAll()
        edgeRailFramePersistWorkItem?.cancel()
        edgeRailFramePersistWorkItem = nil
        uninstallMouseEventTap()
        stopMouseButtonPollingFallback()
        compactPanel?.orderOut(nil)
        edgePanel?.orderOut(nil)
        expandedPanel?.orderOut(nil)
        compactPanel = nil
        edgePanel = nil
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

    private func ensureEdgePanel() -> TaskLightPanel {
        if let edgePanel {
            return edgePanel
        }
        let panel = createPanel(displayMode: .edgeRail)
        edgePanel = panel
        appendStartupTrace("panel.createdEdgeRailOnDemand")
        return panel
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let edgePanel, window === edgePanel {
            rememberEdgeRailFrame(edgePanel.frame, source: "windowDidMove.edgeRail", persistImmediately: false)
            return
        }
        saveFrameIfCompact(window: window)
    }

    func windowDidResize(_ notification: Notification) {
        saveFrameIfCompact(window: notification.object as? NSWindow)
    }

    private func installMouseEventTap() {
        guard mouseEventTap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: taskLightMouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            writeClickDiagnostic(source: "eventTap.install", action: "failed", point: nil)
            appendStartupTrace("mouseEventTap.installFailed")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            writeClickDiagnostic(source: "eventTap.install", action: "source_failed", point: nil)
            appendStartupTrace("mouseEventTap.sourceFailed")
            CFMachPortInvalidate(tap)
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        mouseEventTap = tap
        mouseEventTapSource = source
        writeClickDiagnostic(source: "eventTap.install", action: "ok", point: nil)
        appendStartupTrace("mouseEventTap.installed")
    }

    private func uninstallMouseEventTap() {
        if let mouseEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseEventTapSource, .commonModes)
            self.mouseEventTapSource = nil
        }
        if let mouseEventTap {
            CFMachPortInvalidate(mouseEventTap)
            self.mouseEventTap = nil
        }
    }

    private func startMouseButtonPollingFallback() {
        guard mouseButtonPollTimer == nil else { return }
        lastPolledLeftMouseDown = CGEventSource.buttonState(.hidSystemState, button: .left)
        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollMouseButtonFallback()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseButtonPollTimer = timer
        appendStartupTrace("mouseButtonPoll.installed")
    }

    private func stopMouseButtonPollingFallback() {
        mouseButtonPollTimer?.invalidate()
        mouseButtonPollTimer = nil
        lastPolledLeftMouseDown = false
    }

    private func pollMouseButtonFallback() {
        let leftMouseDown = CGEventSource.buttonState(.hidSystemState, button: .left)
        guard !isPanelPressTracking else {
            fallbackPress = nil
            lastPolledLeftMouseDown = leftMouseDown
            return
        }
        let point = currentDragScreenPoint()
        if leftMouseDown, !lastPolledLeftMouseDown {
            beginFallbackPress(at: point)
            lastPolledLeftMouseDown = leftMouseDown
            return
        }
        if leftMouseDown, let press = fallbackPress {
            updateFallbackPress(press, to: point)
            lastPolledLeftMouseDown = leftMouseDown
            return
        }
        if !leftMouseDown, lastPolledLeftMouseDown, let press = fallbackPress {
            finishFallbackPress(press, at: point)
        }
        lastPolledLeftMouseDown = leftMouseDown
    }

    @discardableResult
    private func handleCompactPanelMouseDown(at point: NSPoint, panelSize: NSSize, clickCount: Int, source: String) -> Bool {
        guard !viewModel.expanded else {
            writeClickDiagnostic(source: source, action: "ignored_expanded", point: point)
            appendStartupTrace("\(source).ignoredExpanded")
            return false
        }
        let isStatusOrb = taskLightCompactStatusOrbHit(point, panelSize: panelSize)
        guard isStatusOrb else {
            writeClickDiagnostic(
                source: source,
                action: "panel_click_no_toggle",
                point: point,
                extra: ["click_count": clickCount]
            )
            appendStartupTrace("\(source).panelClickNoToggle")
            return true
        }
        writeClickDiagnostic(
            source: source,
            action: "collapse_status_orb",
            point: point,
            extra: ["click_count": clickCount]
        )
        setEdgeCollapsedFromInteraction(true, source: "\(source).compactCollapse")
        return true
    }

    private func handleEdgeRailMouseDown(source: String) {
        writeClickDiagnostic(source: source, action: "restore", point: nil)
        if let edgePanel {
            rememberEdgeRailFrame(edgePanel.frame, source: "\(source).restoreAnchor")
        }
        forceRestoreFromEdgePanel(source: "\(source).edgeRestore")
    }

    @discardableResult
    private func trackPanelPress(on panel: TaskLightPanel, event: NSEvent, target: TaskLightPressTarget, source: String) -> Bool {
        guard event.type == .leftMouseDown else {
            if target == .compact {
                return handleCompactPanelMouseDown(
                    at: event.locationInWindow,
                    panelSize: panel.frame.size,
                    clickCount: event.clickCount,
                    source: source
                )
            }
            handleEdgeRailMouseDown(source: source)
            return true
        }

        isPanelPressTracking = true
        defer { isPanelPressTracking = false }
        fallbackPress = nil
        lastPolledLeftMouseDown = true

        let pressStartedAt = Date()
        let pressPoint = event.locationInWindow
        let startPoint = screenPoint(for: event, in: panel)
        let startFrame = panel.frame
        var didDrag = false
        var didEnd = false

        while !didEnd {
            guard let next = panel.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                break
            }

            switch next.type {
            case .leftMouseDragged:
                let currentPoint = screenPoint(for: next, in: panel)
                let totalDX = currentPoint.x - startPoint.x
                let totalDY = currentPoint.y - startPoint.y
                if !didDrag, hypot(totalDX, totalDY) >= taskLightDragThreshold {
                    didDrag = true
                    writeClickDiagnostic(source: source, action: "drag_begin", point: pressPoint)
                    appendStartupTrace("\(source).dragBegin")
                    if target == .edgeRail {
                        panel.performDrag(with: event)
                        didEnd = true
                        continue
                    }
                }
                if didDrag {
                    applyDraggedFrame(
                        panel,
                        target: target,
                        startFrame: startFrame,
                        deltaX: totalDX,
                        deltaY: totalDY
                    )
                }
            case .leftMouseUp:
                didEnd = true
            default:
                break
            }
        }

        if didDrag {
            finishPanelDrag(panel, target: target, source: source)
            return true
        }

        let pressDuration = Date().timeIntervalSince(pressStartedAt)
        if pressDuration >= taskLightClickMaxDuration {
            writeClickDiagnostic(
                source: source,
                action: "press_hold_no_toggle",
                point: pressPoint,
                extra: ["duration_ms": Int(pressDuration * 1000)]
            )
            appendStartupTrace("\(source).pressHoldNoToggle.\(Int(pressDuration * 1000))ms")
            return true
        }

        if target == .compact {
            return handleCompactPanelMouseDown(
                at: pressPoint,
                panelSize: panel.frame.size,
                clickCount: event.clickCount,
                source: source
            )
        }

        handleEdgeRailMouseDown(source: source)
        return true
    }

    func handleMouseEventTap(type: CGEventType, screenPoint: NSPoint, eventLocation: CGPoint) {
        writeClickDiagnostic(
            source: "eventTap.any",
            action: "observed",
            point: screenPoint,
            extra: [
                "event_type": type.rawValue,
                "event_location": ["x": eventLocation.x, "y": eventLocation.y]
            ]
        )
        appendStartupTrace("eventTap.any.observed.x\(Int(screenPoint.x)).y\(Int(screenPoint.y))")
    }

    private func handleMouseCoordinateInput(source: String, screenPoint: NSPoint, recordsAnyClick: Bool) {
        let normalizedPoint = normalizedPanelScreenPoint(screenPoint)
        if recordsAnyClick {
            writeClickDiagnostic(
                source: "\(source).any",
                action: "observed",
                point: normalizedPoint,
                extra: ["raw_point": ["x": screenPoint.x, "y": screenPoint.y]]
            )
            appendStartupTrace("\(source).any.observed.x\(Int(normalizedPoint.x)).y\(Int(normalizedPoint.y))")
        }
        if let edgePanel, edgePanel.isVisible, edgePanel.frame.contains(normalizedPoint) {
            writeClickDiagnostic(source: "\(source).edgeRail", action: "restore", point: nil)
            handleEdgeRailMouseDown(source: "\(source).edgeRail")
            return
        }

        guard let compactPanel, compactPanel.isVisible, !viewModel.expanded else { return }
        guard compactPanel.frame.contains(normalizedPoint) else { return }
        let panelPoint = NSPoint(
            x: normalizedPoint.x - compactPanel.frame.minX,
            y: normalizedPoint.y - compactPanel.frame.minY
        )
        let isStatusOrb = taskLightCompactStatusOrbHit(panelPoint, panelSize: compactPanel.frame.size)
        guard isStatusOrb else {
            writeClickDiagnostic(
                source: "\(source).compact",
                action: "panel_click_no_toggle",
                point: panelPoint
            )
            appendStartupTrace("\(source).compact.panelClickNoToggle")
            return
        }
        writeClickDiagnostic(
            source: "\(source).compact",
            action: "collapse_status_orb",
            point: panelPoint
        )
        setEdgeCollapsedFromInteraction(true, source: "\(source).compact.panelCollapse")
    }

    private func beginFallbackPress(at point: NSPoint) {
        if let edgePanel, edgePanel.isVisible, edgePanel.frame.contains(point) {
            fallbackPress = TaskLightFallbackPress(target: .edgeRail, startPoint: point, startFrame: edgePanel.frame)
            writeClickDiagnostic(source: "mousePoll.edgeRail", action: "press_begin", point: point)
            appendStartupTrace("mousePoll.edgeRail.pressBegin")
            return
        }
        if let compactPanel, compactPanel.isVisible, !viewModel.expanded, compactPanel.frame.contains(point) {
            fallbackPress = TaskLightFallbackPress(target: .compact, startPoint: point, startFrame: compactPanel.frame)
            writeClickDiagnostic(source: "mousePoll.compact", action: "press_begin", point: point)
            appendStartupTrace("mousePoll.compact.pressBegin")
        }
    }

    private func updateFallbackPress(_ press: TaskLightFallbackPress, to point: NSPoint) {
        var updated = press
        let dx = point.x - press.startPoint.x
        let dy = point.y - press.startPoint.y
        if !updated.didDrag, sqrt((dx * dx) + (dy * dy)) >= taskLightDragThreshold {
            updated.didDrag = true
            appendStartupTrace("mousePoll.\(press.target.traceName).dragBegan")
        }
        if updated.didDrag {
            if let panel = panel(for: press.target) {
                applyDraggedFrame(
                    panel,
                    target: press.target,
                    startFrame: press.startFrame,
                    deltaX: dx,
                    deltaY: dy
                )
            }
        }
        fallbackPress = updated
    }

    private func finishFallbackPress(_ press: TaskLightFallbackPress, at point: NSPoint) {
        fallbackPress = nil
        if press.didDrag {
            if let panel = panel(for: press.target) {
                finishPanelDrag(panel, target: press.target, source: "mousePoll.\(press.target.traceName)")
            }
            return
        }
        let pressDuration = Date().timeIntervalSince(press.startedAt)
        if pressDuration >= taskLightClickMaxDuration {
            writeClickDiagnostic(
                source: "mousePoll.\(press.target.traceName)",
                action: "press_hold_no_toggle",
                point: point,
                extra: ["duration_ms": Int(pressDuration * 1000)]
            )
            appendStartupTrace("mousePoll.\(press.target.traceName).pressHoldNoToggle.\(Int(pressDuration * 1000))ms")
            return
        }

        switch press.target {
        case .compact:
            guard let compactPanel else { return }
            let panelPoint = NSPoint(x: point.x - compactPanel.frame.minX, y: point.y - compactPanel.frame.minY)
            _ = handleCompactPanelMouseDown(
                at: panelPoint,
                panelSize: compactPanel.frame.size,
                clickCount: 1,
                source: "mousePoll.compact"
            )
        case .edgeRail:
            handleEdgeRailMouseDown(source: "mousePoll.edgeRail")
        }
    }

    private func panel(for target: TaskLightPressTarget) -> TaskLightPanel? {
        switch target {
        case .compact:
            return compactPanel
        case .edgeRail:
            return edgePanel
        }
    }

    private func movePanel(_ panel: TaskLightPanel, target: TaskLightPressTarget, from previousPoint: NSPoint, to currentPoint: NSPoint) {
        movePanel(
            panel,
            target: target,
            deltaX: currentPoint.x - previousPoint.x,
            deltaY: currentPoint.y - previousPoint.y
        )
    }

    private func movePanel(_ panel: TaskLightPanel, target: TaskLightPressTarget, deltaX: CGFloat, deltaY: CGFloat) {
        var frame = panel.frame
        switch target {
        case .compact:
            frame.origin.x += deltaX
            frame.origin.y += deltaY
        case .edgeRail:
            frame.origin.x += deltaX
            frame.origin.y += deltaY
        }
        let visibleFrame = visibleFrame(containing: NSPoint(x: frame.midX, y: frame.midY))
            ?? activeVisibleFrame()
            ?? visibleFrames().first
            ?? frame
        let clamped = TaskLightPanelGeometry.clampedFrame(frame, visibleFrame: visibleFrame)
        applyDragFrame(clamped, to: panel)
    }

    private func applyDraggedFrame(
        _ panel: TaskLightPanel,
        target: TaskLightPressTarget,
        startFrame: NSRect,
        deltaX: CGFloat,
        deltaY: CGFloat
    ) {
        var frame = startFrame
        switch target {
        case .compact:
            frame.origin.x += deltaX
            frame.origin.y += deltaY
        case .edgeRail:
            frame.origin.x += deltaX
            frame.origin.y += deltaY
        }
        let visibleFrame = visibleFrame(containing: NSPoint(x: frame.midX, y: frame.midY))
            ?? activeVisibleFrame()
            ?? visibleFrames().first
            ?? frame
        let clamped = TaskLightPanelGeometry.clampedFrame(frame, visibleFrame: visibleFrame)
        applyDragFrame(clamped, to: panel)
    }

    private func applyDragFrame(_ frame: NSRect, to panel: TaskLightPanel) {
        guard frame.size == panel.frame.size else {
            panel.setFrame(frame, display: false)
            if panel === edgePanel {
                rememberEdgeRailFrame(frame, source: "applyDragFrame.edgeRail")
            }
            return
        }
        panel.setFrameOrigin(frame.origin)
        if panel === edgePanel {
            rememberEdgeRailFrame(frame, source: "applyDragFrame.edgeRail")
        }
    }

    private func finishPanelDrag(_ panel: TaskLightPanel, target: TaskLightPressTarget, source: String) {
        switch target {
        case .compact:
            saveCompactFrame(panel.frame)
        case .edgeRail:
            rememberEdgeRailFrame(panel.frame, source: "\(source).dragEnd")
            saveCompactFrame(restoredCompactFrameFromEdgeRail(panel.frame))
        }
        writeClickDiagnostic(source: source, action: "drag_end", point: nil)
        appendStartupTrace("\(source).dragEnd")
    }

    private func normalizedPanelScreenPoint(_ point: NSPoint) -> NSPoint {
        let panelFrames = [compactPanel?.frame, edgePanel?.frame, expandedPanel?.frame].compactMap { $0 }
        if panelFrames.contains(where: { $0.contains(point) }) {
            return point
        }
        for screen in NSScreen.screens {
            let flipped = NSPoint(x: point.x, y: screen.frame.maxY - point.y + screen.frame.minY)
            if panelFrames.contains(where: { $0.contains(flipped) }) {
                return flipped
            }
        }
        return point
    }

    private func currentDragScreenPoint() -> NSPoint {
        NSEvent.mouseLocation
    }

    private func screenPoint(for event: NSEvent, in panel: TaskLightPanel) -> NSPoint {
        panel.convertPoint(toScreen: event.locationInWindow)
    }

    private func setEdgeCollapsedFromInteraction(_ value: Bool, source: String) {
        let now = Date()
        guard now >= edgeTransitionLockedUntil else {
            writeClickDiagnostic(source: source, action: "ignored_transition_lock", point: nil)
            appendStartupTrace("\(source).ignoredTransitionLock")
            return
        }
        guard now.timeIntervalSince(lastEdgeToggleAt) > taskLightEdgeToggleDebounceSeconds else {
            writeClickDiagnostic(source: source, action: "ignored_debounce", point: nil)
            appendStartupTrace("\(source).ignoredDebounce")
            return
        }
        lastEdgeToggleAt = now
        let visualState = compactPanel.map { compactPanelIsVisuallyEdgeCollapsed($0) } ?? false
        let edgeVisible = edgePanel?.isVisible == true
        appendStartupTrace("\(source).setEdgeCollapsed.\(value).model.\(viewModel.edgeCollapsed).visual.\(visualState).edgeVisible.\(edgeVisible)")
        if value {
            viewModel.expanded = false
        }
        if viewModel.edgeCollapsed == value {
            if visualState != value || edgeVisible != value {
                appendStartupTrace("\(source).reconcileVisual.\(value)")
                transition(edgeCollapsed: value)
            }
        } else {
            viewModel.setEdgeCollapsed(value)
        }
    }

    private func forceRestoreFromEdgePanel(source: String) {
        let now = Date()
        if now < edgeTransitionLockedUntil {
            writeClickDiagnostic(source: source, action: "restore_bypassed_transition_lock", point: nil)
            appendStartupTrace("\(source).restoreBypassedTransitionLock")
        }
        lastEdgeToggleAt = .distantPast
        let edgeVisible = edgePanel?.isVisible == true
        let visualState = compactPanel.map { compactPanelIsVisuallyEdgeCollapsed($0) } ?? false
        appendStartupTrace("\(source).forceRestore.model.\(viewModel.edgeCollapsed).visual.\(visualState).edgeVisible.\(edgeVisible)")
        guard viewModel.edgeCollapsed || edgeVisible || visualState else {
            writeClickDiagnostic(source: source, action: "ignored_already_restored", point: nil)
            appendStartupTrace("\(source).ignoredAlreadyRestored")
            return
        }
        viewModel.expanded = false
        if viewModel.edgeCollapsed {
            viewModel.setEdgeCollapsed(false)
            return
        }
        transition(edgeCollapsed: false)
    }

    private func compactPanelIsVisuallyEdgeCollapsed(_ panel: NSWindow) -> Bool {
        let widthDelta = abs(panel.frame.width - edgeRailSize.width)
        let heightDelta = abs(panel.frame.height - edgeRailSize.height)
        return widthDelta <= 8 && heightDelta <= 8
    }

    private func lockEdgeTransition(source: String) {
        edgeTransitionLockedUntil = Date().addingTimeInterval(taskLightEdgeTransitionDuration + 0.06)
        appendStartupTrace("\(source).transitionLocked")
    }

    private func restoredCompactFrameFromEdgeRail(_ edgeFrame: NSRect) -> NSRect {
        let visibleFrame = visibleFrame(containing: NSPoint(x: edgeFrame.midX, y: edgeFrame.midY))
            ?? activeVisibleFrame()
            ?? visibleFrames().first
            ?? edgeFrame
        let desired = NSRect(
            x: min(edgeFrame.maxX - compactSize.width, visibleFrame.maxX - compactSize.width - 18),
            y: edgeFrame.midY - compactSize.height / 2,
            width: compactSize.width,
            height: compactSize.height
        )
        return TaskLightPanelGeometry.clampedFrame(desired, visibleFrame: visibleFrame)
    }

    private func createPanel(displayMode: TaskLightPanelDisplayMode) -> TaskLightPanel {
        let size = panelSize(for: displayMode)
        appendStartupTrace("createPanel.\(displayMode.traceName).begin")
        let rootView = TaskLightRootView(viewModel: viewModel, displayMode: displayMode)
        appendStartupTrace("createPanel.\(displayMode.traceName).createdRootView")
        let hosting = NSHostingController(rootView: rootView)
        appendStartupTrace("createPanel.\(displayMode.traceName).createdHosting")
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        let styleMask: NSWindow.StyleMask = [.borderless, .fullSizeContentView]
        let panel = TaskLightPanel(
            contentRect: NSRect(x: 120, y: 120, width: size.width, height: size.height),
            styleMask: styleMask,
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
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.roundedHitTestRadius = displayMode == .expanded ? LuckyCatLayout.cornerRadius : 0
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        if displayMode == .edgeRail {
            panel.roundedHitTestRadius = 0
            panel.isMovableByWindowBackground = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.worksWhenModal = true
            panel.ignoresMouseEvents = false
            hosting.view.layer?.shouldRasterize = true
            hosting.view.layer?.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2
        }
        panel.contentViewController = hosting
        installClickShield(on: panel, displayMode: displayMode)
        panel.delegate = self
        if displayMode == .compact {
            panel.mouseDownInterceptor = { [weak self, weak panel] event in
                guard let self, let panel else { return false }
                return self.trackPanelPress(
                    on: panel,
                    event: event,
                    target: .compact,
                    source: "panelMouse.compact"
                )
            }
        } else if displayMode == .edgeRail {
            panel.mouseDownInterceptor = { [weak self, weak panel] event in
                guard let self, let panel else { return false }
                return self.trackPanelPress(
                    on: panel,
                    event: event,
                    target: .edgeRail,
                    source: "edgePanelMouse"
                )
            }
        }
        appendStartupTrace("createPanel.\(displayMode.traceName).end")
        return panel
    }

    private func installClickShield(on panel: TaskLightPanel, displayMode: TaskLightPanelDisplayMode) {
        guard displayMode == .compact || displayMode == .edgeRail else { return }
        guard let contentView = panel.contentView else { return }
        let shield = TaskLightClickShieldView(frame: contentView.bounds)
        shield.autoresizingMask = [.width, .height]
        shield.wantsLayer = true
        shield.layer?.backgroundColor = NSColor.clear.cgColor
        switch displayMode {
        case .compact:
            shield.hitMode = .full
            shield.onMouseDown = { [weak self] event in
                guard let self, let panel = event.window as? TaskLightPanel else { return }
                _ = self.trackPanelPress(
                    on: panel,
                    event: event,
                    target: .compact,
                    source: "nativeClickShield.compact"
                )
            }
            appendStartupTrace("clickShield.compact.installed")
        case .edgeRail:
            shield.hitMode = .full
            shield.onMouseDown = { [weak self] event in
                guard let self, let panel = event.window as? TaskLightPanel else { return }
                _ = self.trackPanelPress(
                    on: panel,
                    event: event,
                    target: .edgeRail,
                    source: "nativeClickShield.edgeRail"
                )
            }
            appendStartupTrace("clickShield.edgeRail.installed")
        case .expanded:
            return
        }
        contentView.addSubview(shield, positioned: .above, relativeTo: nil)
    }

    private func refreshCompactRootView() {
        guard let compactPanel else { return }
        if let hosting = compactPanel.contentViewController as? NSHostingController<TaskLightRootView> {
            hosting.rootView = TaskLightRootView(viewModel: viewModel, displayMode: .compact)
            hosting.view.needsLayout = true
            hosting.view.layoutSubtreeIfNeeded()
            return
        }
        compactPanel.contentViewController = NSHostingController(
            rootView: TaskLightRootView(viewModel: viewModel, displayMode: .compact)
        )
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
                let rect = value.rectValue
                if frameSizeMatches(rect.size, compactSize, tolerance: 10) {
                    return rect
                }
                if frameSizeMatches(rect.size, edgeRailSize, tolerance: 10) {
                    appendStartupTrace("storedCompactFrame.recoveredFromEdgeRail.\(key)")
                    return restoredCompactFrameFromEdgeRail(rect)
                }
                appendStartupTrace("storedCompactFrame.ignoredInvalid.\(key).\(Int(rect.width))x\(Int(rect.height))")
            }
        }
        return nil
    }

    private func storedEdgeRailFrame() -> NSRect? {
        if let lastKnownEdgeRailFrame {
            let visibleFrame = visibleFrame(containing: NSPoint(x: lastKnownEdgeRailFrame.midX, y: lastKnownEdgeRailFrame.midY))
                ?? activeVisibleFrame()
                ?? visibleFrames().first
                ?? lastKnownEdgeRailFrame
            return TaskLightPanelGeometry.clampedFrame(lastKnownEdgeRailFrame, visibleFrame: visibleFrame)
        }
        guard let data = UserDefaults.standard.data(forKey: TaskLightLedgerKeys.edgeRailWindowFrame),
              let value = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) else {
            return nil
        }
        let rect = value.rectValue
        guard frameSizeMatches(rect.size, edgeRailSize, tolerance: 10) else {
            appendStartupTrace("storedEdgeRailFrame.ignoredInvalid.\(Int(rect.width))x\(Int(rect.height))")
            return nil
        }
        let visibleFrame = visibleFrame(containing: NSPoint(x: rect.midX, y: rect.midY))
            ?? activeVisibleFrame()
            ?? visibleFrames().first
            ?? rect
        return TaskLightPanelGeometry.clampedFrame(rect, visibleFrame: visibleFrame)
    }

    private func currentEdgeRailFrame(fallback: NSRect) -> NSRect {
        if let edgePanel, frameSizeMatches(edgePanel.frame.size, edgeRailSize, tolerance: 10) {
            return edgePanel.frame
        }
        if let stored = storedEdgeRailFrame() {
            return stored
        }
        return NSRect(origin: fallback.origin, size: edgeRailSize)
    }

    private func saveFrameIfCompact(window: NSWindow?) {
        guard let compactPanel else { return }
        guard window === compactPanel else { return }
        guard !isApplyingProgrammaticFrame else { return }
        guard !viewModel.expanded else { return }
        guard !viewModel.edgeCollapsed else { return }
        guard !compactPanelIsVisuallyEdgeCollapsed(compactPanel) else { return }
        saveCompactFrame(compactPanel.frame)
    }

    private func saveCompactFrame(_ frame: NSRect) {
        let compact = compactFrame(from: frame)
        let data = try? NSKeyedArchiver.archivedData(withRootObject: NSValue(rect: compact), requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.compactWindowFrame)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.windowFrame)
    }

    private func saveEdgeRailFrame(_ frame: NSRect) {
        let edgeFrame = NSRect(origin: frame.origin, size: edgeRailSize)
        let data = try? NSKeyedArchiver.archivedData(withRootObject: NSValue(rect: edgeFrame), requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.edgeRailWindowFrame)
    }

    private func rememberEdgeRailFrame(_ frame: NSRect, source: String, persistImmediately: Bool = true) {
        let edgeFrame = NSRect(origin: frame.origin, size: edgeRailSize)
        lastKnownEdgeRailFrame = edgeFrame
        if persistImmediately {
            edgeRailFramePersistWorkItem?.cancel()
            edgeRailFramePersistWorkItem = nil
            saveEdgeRailFrame(edgeFrame)
            appendStartupTrace("\(source).rememberEdgeRailFrame.x\(Int(edgeFrame.minX)).y\(Int(edgeFrame.minY))")
            return
        }
        scheduleEdgeRailFramePersist(source: source)
    }

    private func scheduleEdgeRailFramePersist(source: String) {
        edgeRailFramePersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let edgeFrame = self.lastKnownEdgeRailFrame else { return }
                self.saveEdgeRailFrame(edgeFrame)
                self.appendStartupTrace("\(source).debouncedRememberEdgeRailFrame.x\(Int(edgeFrame.minX)).y\(Int(edgeFrame.minY))")
            }
        }
        edgeRailFramePersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: workItem)
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

    private func applyPanelFrame(_ frame: NSRect, to panel: TaskLightPanel, display: Bool = true, animated: Bool = false, duration: TimeInterval = 0.28) {
        isApplyingProgrammaticFrame = true
        programmaticFrameChangeID += 1
        let changeID = programmaticFrameChangeID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? duration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = animated
            panel.setFrame(frame, display: display, animate: animated)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? duration + 0.06 : 0.05)) { [weak self] in
            guard self?.programmaticFrameChangeID == changeID else { return }
            self?.isApplyingProgrammaticFrame = false
        }
    }

    private func animatePanelAlpha(_ panel: TaskLightPanel, to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            panel.alphaValue = alpha
            panel.displayIfNeeded()
        }
    }

    private func panelSizeMatches(_ panel: NSWindow, _ size: NSSize) -> Bool {
        frameSizeMatches(panel.frame.size, size, tolerance: 1)
    }

    private func frameSizeMatches(_ lhs: NSSize, _ rhs: NSSize, tolerance: CGFloat) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private func framePayload(_ frame: NSRect?) -> [String: Double] {
        guard let frame else { return [:] }
        return [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.width,
            "height": frame.height
        ]
    }

    private func writeEdgeToggleSelfTestResult(_ payload: [String: Any]) {
        let url = viewModel.config.stateDirectory.appendingPathComponent("edge_toggle_self_test.json")
        var output = payload
        output["generated_at"] = ISO8601DateFormatter().string(from: Date())
        do {
            try FileManager.default.createDirectory(at: viewModel.config.stateDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
        } catch {
            appendStartupTrace("edgeToggleSelfTest.writeFailed.\(error.localizedDescription)")
        }
    }

    private func writeClickDiagnostic(source: String, action: String, point: NSPoint?, extra: [String: Any] = [:]) {
        let url = viewModel.config.stateDirectory.appendingPathComponent("luckycat_click_diagnostics.json")
        let directory = viewModel.config.stateDirectory
        var output: [String: Any] = [
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "source": source,
            "action": action,
            "edge_collapsed": viewModel.edgeCollapsed,
            "expanded": viewModel.expanded,
            "compact_visible": compactPanel?.isVisible == true,
            "edge_visible": edgePanel?.isVisible == true,
            "compact_frame": framePayload(compactPanel?.frame),
            "edge_frame": framePayload(edgePanel?.frame)
        ]
        if let point {
            output["point"] = [
                "x": point.x,
                "y": point.y
            ]
        }
        for (key, value) in extra {
            output[key] = value
        }
        DispatchQueue.global(qos: .utility).async { [directory, url, output] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.appendStartupTrace("clickDiagnostic.writeFailed.\(error.localizedDescription)")
                }
            }
        }
    }

    private func panelSize(for displayMode: TaskLightPanelDisplayMode) -> NSSize {
        switch displayMode {
        case .compact:
            return compactSize
        case .edgeRail:
            return edgeRailSize
        case .expanded:
            return expandedSize
        }
    }

    private func visibleFrames() -> [NSRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    private func preferredStartupCompactFrame(fallback: NSRect) -> NSRect {
        let anchoredFrame = startupTopRightCompactFrame(fallback: fallback)
        appendStartupTrace("preferredStartupCompactFrame.topRightLaunch")
        return anchoredFrame
    }

    private func startupTopRightCompactFrame(fallback: NSRect) -> NSRect {
        let anchorFrame = activeVisibleFrame() ?? visibleFrames().first ?? fallback
        let anchoredFrame = NSRect(
            x: anchorFrame.maxX - compactSize.width - 18,
            y: anchorFrame.maxY - compactSize.height - 18,
            width: compactSize.width,
            height: compactSize.height
        )

        return TaskLightPanelGeometry.clampedFrame(anchoredFrame, visibleFrame: anchorFrame)
    }

    private func activeVisibleFrame() -> NSRect? {
        if let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return activeScreen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }

    private func visibleFrame(containing point: NSPoint) -> NSRect? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
    }

    private func edgeRailFrame(from anchorFrame: NSRect) -> NSRect {
        let visibleFrame = visibleFrame(containing: NSPoint(x: anchorFrame.midX, y: anchorFrame.midY))
            ?? activeVisibleFrame()
            ?? visibleFrames().first
            ?? anchorFrame
        let targetY = anchorFrame.midY - (edgeRailSize.height / 2)
        let minY = visibleFrame.minY + LuckyCatLayout.edgeRailVerticalMargin
        let maxY = visibleFrame.maxY - edgeRailSize.height - LuckyCatLayout.edgeRailVerticalMargin
        let clampedY = maxY >= minY
            ? min(max(targetY, minY), maxY)
            : visibleFrame.midY - (edgeRailSize.height / 2)
        return NSRect(
            x: visibleFrame.maxX - edgeRailSize.width - LuckyCatLayout.edgeRailRightMargin,
            y: clampedY,
            width: edgeRailSize.width,
            height: edgeRailSize.height
        )
    }

    private var compactSize: NSSize {
        NSSize(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)
    }

    private var edgeRailSize: NSSize {
        NSSize(width: LuckyCatLayout.edgeRailPanelWidth, height: LuckyCatLayout.edgeRailPanelHeight)
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
        } else if viewModel.edgeCollapsed {
            targetPanel = ensureEdgePanel()
        } else {
            targetPanel = compactPanel
        }
        let fallbackFrame = targetPanel.frame
        let recoveredFrame: NSRect
        if viewModel.expanded {
            recoveredFrame = expandedFrame(from: compactFrame(from: compactPanel.frame))
        } else if viewModel.edgeCollapsed {
            recoveredFrame = storedEdgeRailFrame() ?? edgeRailFrame(from: storedCompactFrame() ?? compactFrame(from: compactPanel.frame))
        } else {
            recoveredFrame = preferredStartupCompactFrame(fallback: fallbackFrame)
        }
        applyPanelFrame(recoveredFrame, to: targetPanel)
        targetPanel.ignoresMouseEvents = false
        targetPanel.makeKeyAndOrderFront(nil)
        targetPanel.orderFrontRegardless()
        if targetPanel === edgePanel {
            NSApp.activate(ignoringOtherApps: true)
            appendStartupTrace("ensureVisibleOnActiveSpace.edgePanelKey")
            return
        }
        targetPanel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        appendStartupTrace("ensureVisibleOnActiveSpace")
    }

    private func appendStartupTrace(_ event: String) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("startup_trace.log")
            let line = "\(ISO8601DateFormatter().string(from: Date())) panel_controller \(event)\n"
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path),
                   let handle = try? FileHandle(forWritingTo: url) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                } else {
                    try? data.write(to: url)
                }
            } else {
                return
            }
        }
    }
}
