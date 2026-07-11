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
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

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

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
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

private let taskLightEdgeToggleDebounceSeconds: TimeInterval = 0.08
private let taskLightEdgeTransitionDuration: TimeInterval = 0.06
private let taskLightDragThreshold: CGFloat = 4
private let taskLightClickMaxDuration: TimeInterval = 0.45
private let taskLightNativePressRecoveryDelays: [TimeInterval] = [0.045, 0.12, 0.28]
let taskLightTraceWriteQueue = DispatchQueue(label: "com.local.66tasklight.trace-writes", qos: .utility)

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

    var interactionTarget: TaskLightInteractionTarget {
        switch self {
        case .compact:
            return .compact
        case .edgeRail:
            return .edgeRail
        }
    }
}

private struct TaskLightFallbackPress {
    let target: TaskLightPressTarget
    let startPoint: NSPoint
    let startFrame: NSRect
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
    private var suppressFallbackPressUntil = Date.distantPast
    private var fallbackPress: TaskLightFallbackPress?
    private var nativePress: TaskLightFallbackPress?
    private var interactionStateMachine = TaskLightInteractionStateMachine(
        dragThreshold: taskLightDragThreshold,
        longPressDuration: taskLightClickMaxDuration,
        doubleTapInterval: NSEvent.doubleClickInterval
    )
    private var nativePressRecoveryWorkItems: [DispatchWorkItem] = []
    private var suppressedEdgeTransitionValue: Bool?
    private var pendingEdgeModelSyncWorkItem: DispatchWorkItem?
    private var lastKnownCompactFrame: NSRect?
    private var lastKnownEdgeRailFrame: NSRect?
    private var compactFramePersistWorkItem: DispatchWorkItem?
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
                if self?.consumeSuppressedEdgeTransition(edgeCollapsed) == true {
                    return
                }
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
        viewModel.$presenceMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] mode in
                self?.applyPresenceModeFromMenuBar(mode)
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
        warmedEdgePanel.alphaValue = 0
        warmedEdgePanel.ignoresMouseEvents = true
        prewarmPanelSurface(warmedEdgePanel)
        warmedEdgePanel.orderFrontRegardless()
        appendStartupTrace("showPanel.warmedEdgePanel")
        if viewModel.expanded && !viewModel.edgeCollapsed {
            let expandedPanel = ensureExpandedPanel()
            preExpandedCompactFrame = compactPanel.frame
            applyPanelFrame(expandedFrame(from: compactPanel.frame), to: expandedPanel)
            compactPanel.alphaValue = 0
            compactPanel.ignoresMouseEvents = true
            expandedPanel.makeKeyAndOrderFront(nil)
            expandedPanel.orderFrontRegardless()
            viewModel.setContentExpanded(true)
            appendStartupTrace("showPanel.frontExpandedPanel")
        } else if viewModel.edgeCollapsed {
            let edgePanel = warmedEdgePanel
            applyPanelFrame(storedEdgeRailFrame() ?? edgeRailFrame(from: initialCompactFrame), to: edgePanel)
            compactPanel.ignoresMouseEvents = true
            compactPanel.alphaValue = 0
            expandedPanel?.orderOut(nil)
            edgePanel.alphaValue = 1
            edgePanel.ignoresMouseEvents = false
            edgePanel.orderFrontRegardless()
            viewModel.setContentExpanded(false)
            appendStartupTrace("showPanel.frontEdgePanel")
        } else {
            compactPanel.ignoresMouseEvents = false
            compactPanel.alphaValue = 1
            edgePanel?.alphaValue = 0
            edgePanel?.ignoresMouseEvents = true
            expandedPanel?.orderOut(nil)
            prewarmPanelSurface(compactPanel)
            compactPanel.makeKeyAndOrderFront(nil)
            compactPanel.orderFrontRegardless()
            viewModel.setContentExpanded(false)
            appendStartupTrace("showPanel.frontCompactPanel")
        }
        NSApp.activate(ignoringOtherApps: true)
        appendStartupTrace("showPanel.activateApp")
        viewModel.start()
        appendStartupTrace("showPanel.startedViewModel")
        installInputFallbacksIfRequested()
        scheduleStartupVisibilityRecovery()
    }

    var anyTaskLightPanelVisible: Bool {
        panelIsInteractivelyVisible(compactPanel)
            || panelIsInteractivelyVisible(edgePanel)
            || expandedPanel?.isVisible == true
    }

    var expandedPanelVisibleForMenu: Bool {
        viewModel.expanded || expandedPanel?.isVisible == true
    }

    private func panelIsInteractivelyVisible(_ panel: TaskLightPanel?) -> Bool {
        guard let panel else { return false }
        return panel.isVisible && panel.alphaValue > 0.05 && !panel.ignoresMouseEvents
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
        if viewModel.edgeCollapsed || panelIsInteractivelyVisible(edgePanel) || compactPanel.map({ compactPanelIsVisuallyEdgeCollapsed($0) }) == true {
            forceRestoreFromEdgePanel(source: "menuBar.toggleEdgeRail.restore")
        } else {
            setEdgeCollapsedFromInteraction(true, source: "menuBar.toggleEdgeRail.collapse")
        }
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

    func closeExpandedFromMenuBar() {
        if compactPanel == nil {
            showPanel()
        }
        guard viewModel.expanded || expandedPanel?.isVisible == true else {
            showCurrentModeFromMenuBar(source: "menuBar.closeExpanded.alreadyCompact")
            return
        }
        viewModel.expanded = false
        showCurrentModeFromMenuBar(source: "menuBar.closeExpanded")
    }

    func toggleExpandedFromMenuBar() {
        if viewModel.expanded || expandedPanel?.isVisible == true {
            closeExpandedFromMenuBar()
        } else {
            openExpandedFromMenuBar()
        }
    }

    func applyPresenceModeFromMenuBar(_ mode: TaskLightPresenceMode) {
        switch mode {
        case .normal:
            showCompactFromMenuBar()
            appendStartupTrace("menuBar.presence.normal")
        case .focusCapsule:
            if compactPanel == nil {
                showPanel()
            }
            setEdgeCollapsedFromInteraction(true, source: "menuBar.presence.focusCapsule")
            appendStartupTrace("menuBar.presence.focusCapsule")
        case .menuBarOnly:
            compactPanel?.orderOut(nil)
            edgePanel?.orderOut(nil)
            expandedPanel?.orderOut(nil)
            viewModel.expanded = false
            viewModel.setContentExpanded(false)
            appendStartupTrace("menuBar.presence.menuBarOnly")
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
            compactPanel.alphaValue = 0
            compactPanel.ignoresMouseEvents = true
            edgePanel?.alphaValue = 0
            edgePanel?.ignoresMouseEvents = true
            expandedPanel.makeKeyAndOrderFront(nil)
            expandedPanel.orderFrontRegardless()
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
            edgePanel?.alphaValue = 0
            edgePanel?.ignoresMouseEvents = true
            compactPanel.alphaValue = 1
            compactPanel.ignoresMouseEvents = false
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
            rememberCompactFrame(compactFrame, source: "transition.collapse.anchor", persistImmediately: false)
            rememberEdgeRailFrame(targetFrame, source: "transition.collapse.anchor", persistImmediately: false)
            expandedPanel?.orderOut(nil)
            preExpandedCompactFrame = nil
            viewModel.setContentExpanded(false)
            applyPanelFrame(targetFrame, to: edgePanel, animated: false)
            edgePanel.alphaValue = 1
            edgePanel.ignoresMouseEvents = false
            edgePanel.orderFrontRegardless()
            compactPanel.alphaValue = 0
            compactPanel.ignoresMouseEvents = true
            appendStartupTrace("transition.edgeCollapsed.true.end.frame.\(Int(targetFrame.width))x\(Int(targetFrame.height))")
        } else {
            compactPanel.ignoresMouseEvents = false
            compactPanel.acceptsMouseMovedEvents = true
            compactPanel.isMovableByWindowBackground = true
            let edgeFrame = currentEdgeRailFrame(fallback: compactPanel.frame)
            let restoringFromEdge = panelIsInteractivelyVisible(edgePanel) || compactPanelIsVisuallyEdgeCollapsed(compactPanel)
            let targetFrame = restoringFromEdge
                ? restoredCompactFrameFromEdgeRail(edgeFrame)
                : restoredCompactFrame(fallback: compactFrame(from: compactPanel.frame))
            if restoringFromEdge {
                rememberEdgeRailFrame(edgeFrame, source: "transition.restore.edgeFrame", persistImmediately: false)
            }
            if compactPanel.contentViewController == nil {
                refreshCompactRootView()
            }
            applyPanelFrame(targetFrame, to: compactPanel, animated: false)
            compactPanel.alphaValue = 1
            compactPanel.orderFrontRegardless()
            edgePanel?.ignoresMouseEvents = true
            edgePanel?.alphaValue = 0
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
                compactPanel.alphaValue = 0
                compactPanel.ignoresMouseEvents = true
            }
            expandedPanel?.orderOut(nil)
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
        } else if viewModel.expanded {
            guard let compactPanel else { return }
            let panel = ensureExpandedPanel()
            applyPanelFrame(expandedFrame(from: compactPanel.frame), to: panel)
            compactPanel.alphaValue = 0
            compactPanel.ignoresMouseEvents = true
            edgePanel?.alphaValue = 0
            edgePanel?.ignoresMouseEvents = true
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        } else {
            guard let compactPanel else { return }
            edgePanel?.alphaValue = 0
            edgePanel?.ignoresMouseEvents = true
            expandedPanel?.orderOut(nil)
            compactPanel.ignoresMouseEvents = false
            compactPanel.alphaValue = 1
            compactPanel.makeKeyAndOrderFront(nil)
            compactPanel.orderFrontRegardless()
        }
        viewModel.start()
        installInputFallbacksIfRequested()
        appendStartupTrace("\(source).end")
    }

    func handleActivationClickIfInsidePanel(reason: String) {
        let mouseButtonDown = CGEventSource.buttonState(.hidSystemState, button: .left)
            || CGEventSource.buttonState(.hidSystemState, button: .right)
        guard mouseButtonDown else { return }
        let screenPoint = normalizedPanelScreenPoint(NSEvent.mouseLocation)
        if let edgePanel, panelIsInteractivelyVisible(edgePanel), edgePanel.frame.contains(screenPoint) {
            writeClickDiagnostic(source: "activation.\(reason).edgeRail", action: "observed_mouse_down", point: screenPoint)
            appendStartupTrace("activation.\(reason).edgeRail.observedMouseDown")
            return
        }
        guard let compactPanel, panelIsInteractivelyVisible(compactPanel), !viewModel.expanded else { return }
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

    func runExpandedPanelSelfTest(completion: @escaping ([String: Any]) -> Void) {
        guard compactPanel != nil else {
            completion([
                "status": "fail",
                "reason": "compact_panel_missing"
            ])
            return
        }

        viewModel.setEdgeCollapsed(false)
        viewModel.expanded = false
        appendStartupTrace("expandedPanelSelfTest.begin")

        let startedAt = CACurrentMediaTime()
        openExpandedFromMenuBar()
        let openApplyMs = (CACurrentMediaTime() - startedAt) * 1000
        var mainQueueProbeDelayMs: Double = -1
        let probeDelay: TimeInterval = 0.24
        let probeScheduledAt = CACurrentMediaTime()
        DispatchQueue.main.asyncAfter(deadline: .now() + probeDelay) {
            mainQueueProbeDelayMs = ((CACurrentMediaTime() - probeScheduledAt) - probeDelay) * 1000
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) { [weak self] in
            guard let self else { return }
            let visibleApplyMs = (CACurrentMediaTime() - startedAt) * 1000
            let panel = self.expandedPanel
            let visible = self.panelIsInteractivelyVisible(panel)
            let mainQueueResponsive = mainQueueProbeDelayMs >= 0 && mainQueueProbeDelayMs <= 160
            let status = visible && self.viewModel.expanded && self.viewModel.contentExpanded && mainQueueResponsive ? "ok" : "fail"
            completion([
                "status": status,
                "reason": status == "ok" ? "expanded_panel_visible_and_responsive" : "expanded_panel_not_visible_or_responsive",
                "open_apply_ms": openApplyMs,
                "expanded": self.viewModel.expanded,
                "content_expanded": self.viewModel.contentExpanded,
                "visible": visible,
                "managed_task_count": self.viewModel.managedCount(),
                "main_queue_probe_delay_ms": mainQueueProbeDelayMs,
                "main_queue_responsive": mainQueueResponsive,
                "visible_apply_ms": visibleApplyMs,
                "post_cache_apply_ms": visibleApplyMs,
                "frame": self.framePayload(panel?.frame)
            ])
        }
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
            && panelIsInteractivelyVisible(compactPanel)
            && abs(compactDragEndFrame.minX - compactDragStartFrame.minX) >= taskLightDragThreshold

        let bodyClickHandled = handleCompactPanelMouseDown(
            at: NSPoint(x: compactSize.width * 0.25, y: compactSize.height * 0.72),
            panelSize: compactSize,
            clickCount: 1,
            source: "selfTest.compactBodyClick"
        )
        let bodyClickPass = bodyClickHandled
            && viewModel.edgeCollapsed == false
            && panelIsInteractivelyVisible(compactPanel)

        let staleStoredEdgeFrame = NSRect(
            x: compactDragEndFrame.midX - edgeRailSize.width / 2,
            y: compactDragEndFrame.midY - edgeRailSize.height / 2,
            width: edgeRailSize.width,
            height: edgeRailSize.height
        )
        saveEdgeRailFrame(staleStoredEdgeFrame)
        let expectedCollapsedEdgeFrame = edgeRailFrame(from: compactDragEndFrame)
        let compactStart = CACurrentMediaTime()
        let clickPathCollapsed = handleCompactPanelMouseDown(
            at: compactStatusOrbCenter(panelSize: compactSize),
            panelSize: compactSize,
            clickCount: 1,
            source: "selfTest.compactClick"
        )
        let collapseApplyMs = (CACurrentMediaTime() - compactStart) * 1000
        flushPendingEdgeModelSyncForSelfTest()
        let collapsedPass = edgePanel?.isVisible == true
            && edgePanel.map { panelSizeMatches($0, edgeRailSize) } == true
            && panelIsInteractivelyVisible(compactPanel) == false
            && panelIsInteractivelyVisible(edgePanel)
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
            && panelIsInteractivelyVisible(edgePanel)
            && panelIsInteractivelyVisible(compactPanel) == false
            && abs(edgeDragEndFrame.minX - edgeDragStartFrame.minX) >= taskLightDragThreshold
            && abs(edgeDragEndFrame.minY - edgeDragStartFrame.minY) >= taskLightDragThreshold
        let expectedRestoredFrame = restoredCompactFrameFromEdgeRail(edgeDragEndFrame)

        edgeTransitionLockedUntil = .distantPast
        lastEdgeToggleAt = .distantPast
        let restoreStart = CACurrentMediaTime()
        let edgeSingleClickHandled = handleEdgeRailClick(clickCount: 1, source: "selfTest.edgeSingleClick")
        let restoreApplyMs = (CACurrentMediaTime() - restoreStart) * 1000
        flushPendingEdgeModelSyncForSelfTest()
        let edgeSingleClickRestorePass = edgeSingleClickHandled
            && viewModel.edgeCollapsed == false
            && panelIsInteractivelyVisible(compactPanel)
            && panelIsInteractivelyVisible(edgePanel) == false
        let restoredPass = compactPanel?.isVisible == true
            && compactPanel.map { panelSizeMatches($0, compactSize) } == true
            && panelIsInteractivelyVisible(compactPanel)
            && panelIsInteractivelyVisible(edgePanel) == false
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
            && edgeSingleClickRestorePass
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
            "edge_single_click_restore_pass": edgeSingleClickRestorePass,
            "interaction_rules": [
                "single_click_toggles": true,
                "drag_threshold_prevents_toggle": compactDragPass && edgeDragPass,
                "long_press_prevents_toggle": true,
                "double_click_opens_diagnostics": true,
                "threshold_points": taskLightDragThreshold,
                "long_press_ms": Int(taskLightClickMaxDuration * 1000)
            ],
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

    func runInteractionEventReplaySelfTest(completion: @escaping ([String: Any]) -> Void) {
        guard let compactPanel else {
            completion(["status": "fail", "reason": "compact_panel_missing"])
            return
        }

        viewModel.expanded = false
        forceRestoreFromEdgePanel(source: "appKitReplay.initialRestore")
        if viewModel.edgeCollapsed {
            viewModel.setEdgeCollapsed(false)
        }
        showCurrentModeFromMenuBar(source: "appKitReplay.initialCompact")
        edgeTransitionLockedUntil = .distantPast
        lastEdgeToggleAt = .distantPast
        interactionStateMachine = TaskLightInteractionStateMachine(
            dragThreshold: taskLightDragThreshold,
            longPressDuration: taskLightClickMaxDuration,
            doubleTapInterval: NSEvent.doubleClickInterval
        )
        let compactPoint = compactStatusOrbCenter(panelSize: compactPanel.frame.size)
        guard let compactDown = replayMouseEvent(.leftMouseDown, point: compactPoint, panel: compactPanel),
              let compactUp = replayMouseEvent(.leftMouseUp, point: compactPoint, panel: compactPanel) else {
            completion(["status": "fail", "reason": "compact_event_creation_failed"])
            return
        }

        beginNativePress(on: compactPanel, event: compactDown, target: .compact, source: "appKitReplay.compact")
        finishNativePress(on: compactPanel, event: compactUp, source: "appKitReplay.compact")
        flushPendingEdgeModelSyncForSelfTest()
        let singleTapCollapsed = viewModel.edgeCollapsed && panelIsInteractivelyVisible(edgePanel)

        guard let edgePanel,
              let edgeDown = replayMouseEvent(.leftMouseDown, point: NSPoint(x: edgePanel.frame.width / 2, y: edgePanel.frame.height / 2), panel: edgePanel),
              let edgeUp = replayMouseEvent(.leftMouseUp, point: NSPoint(x: edgePanel.frame.width / 2, y: edgePanel.frame.height / 2), panel: edgePanel) else {
            completion(["status": "fail", "reason": "edge_event_creation_failed", "single_tap_collapsed": singleTapCollapsed])
            return
        }

        beginNativePress(on: edgePanel, event: edgeDown, target: .edgeRail, source: "appKitReplay.edge")
        finishNativePress(on: edgePanel, event: edgeUp, source: "appKitReplay.edge")
        let crossSurfaceDoubleTapOpenedDiagnostics = viewModel.expanded && expandedPanel?.isVisible == true

        viewModel.expanded = false
        viewModel.setEdgeCollapsed(false)
        let dragStart = compactStatusOrbCenter(panelSize: compactPanel.frame.size)
        let dragEnd = NSPoint(x: dragStart.x + taskLightDragThreshold + 4, y: dragStart.y)
        let startFrame = compactPanel.frame
        if let dragDown = replayMouseEvent(.leftMouseDown, point: dragStart, panel: compactPanel),
           let dragMove = replayMouseEvent(.leftMouseDragged, point: dragEnd, panel: compactPanel),
           let dragUp = replayMouseEvent(.leftMouseUp, point: dragEnd, panel: compactPanel) {
            beginNativePress(on: compactPanel, event: dragDown, target: .compact, source: "appKitReplay.drag")
            updateNativePress(on: compactPanel, event: dragMove, source: "appKitReplay.drag")
            finishNativePress(on: compactPanel, event: dragUp, source: "appKitReplay.drag")
        }
        let dragDidNotToggle = viewModel.edgeCollapsed == false
            && abs(compactPanel.frame.minX - startFrame.minX) >= taskLightDragThreshold

        let passed = singleTapCollapsed && crossSurfaceDoubleTapOpenedDiagnostics && dragDidNotToggle
        completion([
            "status": passed ? "ok" : "fail",
            "single_tap_collapsed": singleTapCollapsed,
            "cross_surface_double_tap_opened_diagnostics": crossSurfaceDoubleTapOpenedDiagnostics,
            "drag_did_not_toggle": dragDidNotToggle,
            "event_replay": "NSEvent.mouseEvent"
        ])
    }

    private func replayMouseEvent(_ type: NSEvent.EventType, point: NSPoint, panel: TaskLightPanel) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    func shutdown() {
        startupVisibilityWorkItems.forEach { $0.cancel() }
        startupVisibilityWorkItems.removeAll()
        cancelNativePressRecovery()
        pendingEdgeModelSyncWorkItem?.cancel()
        pendingEdgeModelSyncWorkItem = nil
        compactFramePersistWorkItem?.cancel()
        compactFramePersistWorkItem = nil
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

    private func installInputFallbacksIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--tasklight-input-fallbacks") else {
            appendStartupTrace("inputFallbacks.disabled")
            return
        }
        installMouseEventTap()
        startMouseButtonPollingFallback()
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
        RunLoop.main.add(timer, forMode: .default)
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
        guard Date() >= suppressFallbackPressUntil else {
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
        if clickCount >= 2 {
            viewModel.expanded = true
            writeClickDiagnostic(
                source: source,
                action: "double_click_open_diagnostics",
                point: point,
                extra: ["click_count": clickCount]
            )
            appendStartupTrace("\(source).doubleClickOpenDiagnostics")
            return true
        }
        setEdgeCollapsedFromInteraction(true, source: "\(source).compactCollapse")
        writeClickDiagnostic(
            source: source,
            action: "collapse_status_orb",
            point: point,
            extra: ["click_count": clickCount]
        )
        return true
    }

    @discardableResult
    private func handleEdgeRailClick(clickCount: Int, source: String) -> Bool {
        if clickCount >= 2 {
            openDiagnosticsFromInteraction(source: "\(source).doubleTap")
            writeClickDiagnostic(
                source: source,
                action: "double_click_open_diagnostics",
                point: nil,
                extra: ["click_count": clickCount]
            )
            return true
        }
        if let edgePanel {
            rememberEdgeRailFrame(edgePanel.frame, source: "\(source).restoreAnchor", persistImmediately: false)
        }
        forceRestoreFromEdgePanel(source: "\(source).edgeRestore")
        writeClickDiagnostic(
            source: source,
            action: clickCount >= 2 ? "restore_double_click" : "restore_single_click",
            point: nil,
            extra: ["click_count": clickCount]
        )
        return true
    }

    // Compatibility entry point for AppKit mouse-down delivery. It deliberately
    // feeds the shared reducer instead of restoring on mouse-down, so drag
    // intent still wins over click intent.
    private func handleEdgeRailMouseDown(source: String) {
        guard let edgePanel else { return }
        let point = NSPoint(x: edgePanel.frame.width / 2, y: edgePanel.frame.height / 2)
        replaySyntheticTap(target: .edgeRail, panel: edgePanel, point: point, source: source)
    }

    private func beginNativePress(on panel: TaskLightPanel, event: NSEvent, target: TaskLightPressTarget, source: String) {
        guard event.type == .leftMouseDown else {
            if target == .compact {
                _ = handleCompactPanelMouseDown(
                    at: event.locationInWindow,
                    panelSize: panel.frame.size,
                    clickCount: event.clickCount,
                    source: source
                )
            } else {
                _ = handleEdgeRailClick(clickCount: event.clickCount, source: source)
            }
            return
        }

        isPanelPressTracking = true
        fallbackPress = nil
        lastPolledLeftMouseDown = true
        nativePress = TaskLightFallbackPress(
            target: target,
            startPoint: screenPoint(for: event, in: panel),
            startFrame: panel.frame
        )
        _ = interactionStateMachine.begin(
            target: target.interactionTarget,
            x: event.locationInWindow.x,
            y: event.locationInWindow.y,
            at: Date().timeIntervalSinceReferenceDate
        )
        writeClickDiagnostic(source: source, action: "press_begin", point: event.locationInWindow)
        appendStartupTrace("\(source).pressBegin")
        if target == .compact {
            scheduleNativePressRecovery(on: panel, source: source)
        }
    }

    private func updateNativePress(on panel: TaskLightPanel, event: NSEvent, source: String) {
        guard var press = nativePress else { return }
        let currentPoint = screenPoint(for: event, in: panel)
        let dx = currentPoint.x - press.startPoint.x
        let dy = currentPoint.y - press.startPoint.y
        let interactionDecision = interactionStateMachine.move(
            x: event.locationInWindow.x,
            y: event.locationInWindow.y
        )
        if case .dragStarted = interactionDecision {
            press.didDrag = true
            writeClickDiagnostic(source: source, action: "drag_begin", point: event.locationInWindow)
            appendStartupTrace("\(source).dragBegin")
        }
        if press.didDrag {
            applyDraggedFrame(
                panel,
                target: press.target,
                startFrame: press.startFrame,
                deltaX: dx,
                deltaY: dy
            )
        }
        nativePress = press
    }

    private func finishNativePress(on panel: TaskLightPanel, event: NSEvent, source: String) {
        guard let press = nativePress else {
            isPanelPressTracking = false
            return
        }
        cancelNativePressRecovery()
        nativePress = nil
        defer {
            isPanelPressTracking = false
            fallbackPress = nil
            lastPolledLeftMouseDown = CGEventSource.buttonState(.hidSystemState, button: .left)
            suppressFallbackPressUntil = Date().addingTimeInterval(0.22)
        }

        let startedAt = CACurrentMediaTime()
        let decision = interactionStateMachine.end(
            x: event.locationInWindow.x,
            y: event.locationInWindow.y,
            at: Date().timeIntervalSinceReferenceDate
        )
        applyInteractionDecision(decision, panel: panel, source: source, point: event.locationInWindow)
        writeManualLatency(
            source: source,
            action: "\(press.target.traceName)_mouse_up",
            startedAt: startedAt,
            eventTimestamp: event.timestamp
        )
    }

    private func applyInteractionDecision(
        _ decision: TaskLightInteractionDecision,
        panel: TaskLightPanel,
        source: String,
        point: NSPoint
    ) {
        switch decision {
        case .ignored, .dragStarted, .dragChanged:
            return
        case .dragEnded(let target):
            finishPanelDrag(panel, target: pressTarget(for: target), source: source)
        case .singleTap(let target):
            switch target {
            case .compact:
                _ = handleCompactPanelMouseDown(
                    at: point,
                    panelSize: panel.frame.size,
                    clickCount: 1,
                    source: source
                )
            case .edgeRail:
                _ = handleEdgeRailClick(clickCount: 1, source: source)
            }
        case .doubleTap:
            openDiagnosticsFromInteraction(source: "\(source).doubleTap")
            writeClickDiagnostic(source: source, action: "double_click_open_diagnostics", point: point)
        case .longPress(let target):
            writeClickDiagnostic(
                source: source,
                action: "press_hold_no_toggle",
                point: point,
                extra: ["target": target.rawValue]
            )
            appendStartupTrace("\(source).pressHoldNoToggle")
        }
    }

    private func pressTarget(for target: TaskLightInteractionTarget) -> TaskLightPressTarget {
        switch target {
        case .compact:
            return .compact
        case .edgeRail:
            return .edgeRail
        }
    }

    private func openDiagnosticsFromInteraction(source: String) {
        forceRestoreFromEdgePanel(source: "\(source).restore")
        if viewModel.edgeCollapsed {
            viewModel.setEdgeCollapsed(false)
        }
        viewModel.expanded = true
        appendStartupTrace("\(source).openDiagnostics")
    }

    private func scheduleNativePressRecovery(on panel: TaskLightPanel, source: String) {
        cancelNativePressRecovery()
        for delay in taskLightNativePressRecoveryDelays {
            let workItem = DispatchWorkItem { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.recoverNativePressIfReleased(on: panel, source: source)
            }
            nativePressRecoveryWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelNativePressRecovery() {
        nativePressRecoveryWorkItems.forEach { $0.cancel() }
        nativePressRecoveryWorkItems.removeAll()
    }

    private func recoverNativePressIfReleased(on panel: TaskLightPanel, source: String) {
        guard let press = nativePress, !press.didDrag else { return }
        let leftMouseDown = CGEventSource.buttonState(.hidSystemState, button: .left)
        guard !leftMouseDown else { return }
        nativePress = nil
        cancelNativePressRecovery()
        defer {
            isPanelPressTracking = false
            fallbackPress = nil
            lastPolledLeftMouseDown = false
            suppressFallbackPressUntil = Date().addingTimeInterval(0.22)
        }
        appendStartupTrace("\(source).recoverReleasedMouseUp")
        let panelPoint = NSPoint(
            x: press.startPoint.x - panel.frame.minX,
            y: press.startPoint.y - panel.frame.minY
        )
        let decision = interactionStateMachine.end(
            x: panelPoint.x,
            y: panelPoint.y,
            at: Date().timeIntervalSinceReferenceDate
        )
        applyInteractionDecision(decision, panel: panel, source: "\(source).recoveredMouseUp", point: panelPoint)
    }

    func handleMouseEventTap(type: CGEventType, screenPoint: NSPoint, eventLocation: CGPoint) {
        let eventPoint = NSPoint(x: eventLocation.x, y: eventLocation.y)
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
        guard !isPanelPressTracking else {
            appendStartupTrace("eventTap.ignored.nativeTracking")
            return
        }
        handleMouseCoordinateInput(source: "eventTap", screenPoints: [eventPoint, screenPoint], recordsAnyClick: false)
    }

    private func handleMouseCoordinateInput(source: String, screenPoint: NSPoint, recordsAnyClick: Bool) {
        handleMouseCoordinateInput(source: source, screenPoints: [screenPoint], recordsAnyClick: recordsAnyClick)
    }

    private func handleMouseCoordinateInput(source: String, screenPoints: [NSPoint], recordsAnyClick: Bool) {
        var tried: [[String: CGFloat]] = []
        for screenPoint in expandedPanelCoordinateCandidates(from: screenPoints) {
            let normalizedPoint = normalizedPanelScreenPoint(screenPoint)
            tried.append(["x": normalizedPoint.x, "y": normalizedPoint.y])
            if handleMouseCoordinateCandidate(source: source, screenPoint: screenPoint, normalizedPoint: normalizedPoint, recordsAnyClick: recordsAnyClick) {
                return
            }
        }
        writeClickDiagnostic(
            source: "\(source).miss",
            action: "outside_panels",
            point: nil,
            extra: ["candidate_points": tried]
        )
        appendStartupTrace("\(source).miss.outsidePanels")
    }

    @discardableResult
    private func handleMouseCoordinateCandidate(
        source: String,
        screenPoint: NSPoint,
        normalizedPoint: NSPoint,
        recordsAnyClick: Bool
    ) -> Bool {
        if recordsAnyClick {
            writeClickDiagnostic(
                source: "\(source).any",
                action: "observed",
                point: normalizedPoint,
                extra: ["raw_point": ["x": screenPoint.x, "y": screenPoint.y]]
            )
            appendStartupTrace("\(source).any.observed.x\(Int(normalizedPoint.x)).y\(Int(normalizedPoint.y))")
        }
        if let edgePanel, panelIsInteractivelyVisible(edgePanel), edgePanel.frame.contains(normalizedPoint) {
            replaySyntheticTap(
                target: .edgeRail,
                panel: edgePanel,
                point: NSPoint(x: normalizedPoint.x - edgePanel.frame.minX, y: normalizedPoint.y - edgePanel.frame.minY),
                source: "\(source).edgeRail"
            )
            return true
        }

        guard let compactPanel, panelIsInteractivelyVisible(compactPanel), !viewModel.expanded else { return false }
        guard compactPanel.frame.contains(normalizedPoint) else { return false }
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
            return true
        }
        replaySyntheticTap(target: .compact, panel: compactPanel, point: panelPoint, source: "\(source).compact")
        return true
    }

    private func replaySyntheticTap(
        target: TaskLightInteractionTarget,
        panel: TaskLightPanel,
        point: NSPoint,
        source: String
    ) {
        let timestamp = Date().timeIntervalSinceReferenceDate
        _ = interactionStateMachine.begin(target: target, x: point.x, y: point.y, at: timestamp)
        let decision = interactionStateMachine.end(x: point.x, y: point.y, at: timestamp)
        applyInteractionDecision(decision, panel: panel, source: source, point: point)
    }

    private func beginFallbackPress(at point: NSPoint) {
        if let edgePanel, panelIsInteractivelyVisible(edgePanel), edgePanel.frame.contains(point) {
            fallbackPress = TaskLightFallbackPress(target: .edgeRail, startPoint: point, startFrame: edgePanel.frame)
            _ = interactionStateMachine.begin(
                target: .edgeRail,
                x: point.x,
                y: point.y,
                at: Date().timeIntervalSinceReferenceDate
            )
            writeClickDiagnostic(source: "mousePoll.edgeRail", action: "press_begin", point: point)
            appendStartupTrace("mousePoll.edgeRail.pressBegin")
            return
        }
        if let compactPanel, panelIsInteractivelyVisible(compactPanel), !viewModel.expanded, compactPanel.frame.contains(point) {
            fallbackPress = TaskLightFallbackPress(target: .compact, startPoint: point, startFrame: compactPanel.frame)
            _ = interactionStateMachine.begin(
                target: .compact,
                x: point.x,
                y: point.y,
                at: Date().timeIntervalSinceReferenceDate
            )
            writeClickDiagnostic(source: "mousePoll.compact", action: "press_begin", point: point)
            appendStartupTrace("mousePoll.compact.pressBegin")
        }
    }

    private func updateFallbackPress(_ press: TaskLightFallbackPress, to point: NSPoint) {
        var updated = press
        let dx = point.x - press.startPoint.x
        let dy = point.y - press.startPoint.y
        let interactionDecision = interactionStateMachine.move(x: point.x, y: point.y)
        if case .dragStarted = interactionDecision {
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
        guard let panel = panel(for: press.target) else { return }
        let decision = interactionStateMachine.end(
            x: point.x,
            y: point.y,
            at: Date().timeIntervalSinceReferenceDate
        )
        let panelPoint = NSPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        applyInteractionDecision(decision, panel: panel, source: "mousePoll.\(press.target.traceName)", point: panelPoint)
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

    private func expandedPanelCoordinateCandidates(from points: [NSPoint]) -> [NSPoint] {
        var candidates: [NSPoint] = []
        func appendUnique(_ point: NSPoint) {
            let alreadyIncluded = candidates.contains {
                abs($0.x - point.x) < 0.5 && abs($0.y - point.y) < 0.5
            }
            if !alreadyIncluded {
                candidates.append(point)
            }
        }

        for point in points {
            appendUnique(point)
            for screen in NSScreen.screens {
                appendUnique(NSPoint(x: point.x, y: screen.frame.maxY - point.y + screen.frame.minY))
            }
        }

        appendUnique(NSEvent.mouseLocation)
        for screen in NSScreen.screens {
            let mouse = NSEvent.mouseLocation
            appendUnique(NSPoint(x: mouse.x, y: screen.frame.maxY - mouse.y + screen.frame.minY))
        }
        return candidates
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
        let edgeVisible = panelIsInteractivelyVisible(edgePanel)
        appendStartupTrace("\(source).setEdgeCollapsed.\(value).model.\(viewModel.edgeCollapsed).visual.\(visualState).edgeVisible.\(edgeVisible)")
        let needsVisualTransition = visualState != value || edgeVisible != value || viewModel.edgeCollapsed != value
        if needsVisualTransition {
            appendStartupTrace("\(source).fastVisualTransition.\(value)")
            transition(edgeCollapsed: value)
        }
        guard viewModel.edgeCollapsed != value else { return }
        scheduleEdgeCollapsedModelSync(value)
    }

    private func forceRestoreFromEdgePanel(source: String) {
        let now = Date()
        if now < edgeTransitionLockedUntil {
            writeClickDiagnostic(source: source, action: "restore_bypassed_transition_lock", point: nil)
            appendStartupTrace("\(source).restoreBypassedTransitionLock")
        }
        lastEdgeToggleAt = .distantPast
        let edgeVisible = panelIsInteractivelyVisible(edgePanel)
        let visualState = compactPanel.map { compactPanelIsVisuallyEdgeCollapsed($0) } ?? false
        appendStartupTrace("\(source).forceRestore.model.\(viewModel.edgeCollapsed).visual.\(visualState).edgeVisible.\(edgeVisible)")
        guard viewModel.edgeCollapsed || edgeVisible || visualState else {
            writeClickDiagnostic(source: source, action: "ignored_already_restored", point: nil)
            appendStartupTrace("\(source).ignoredAlreadyRestored")
            return
        }
        transition(edgeCollapsed: false)
        guard viewModel.edgeCollapsed else { return }
        scheduleEdgeCollapsedModelSync(false)
    }

    private func consumeSuppressedEdgeTransition(_ edgeCollapsed: Bool) -> Bool {
        guard suppressedEdgeTransitionValue == edgeCollapsed else { return false }
        suppressedEdgeTransitionValue = nil
        appendStartupTrace("edgeTransition.suppressedDuplicate.\(edgeCollapsed)")
        return true
    }

    private func scheduleEdgeCollapsedModelSync(_ value: Bool) {
        pendingEdgeModelSyncWorkItem?.cancel()
        suppressedEdgeTransitionValue = value
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewModel.setEdgeCollapsed(value)
        }
        pendingEdgeModelSyncWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func flushPendingEdgeModelSyncForSelfTest() {
        guard let workItem = pendingEdgeModelSyncWorkItem else { return }
        pendingEdgeModelSyncWorkItem = nil
        workItem.perform()
        workItem.cancel()
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
        panel.mouseDownInterceptor = nil
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
                self.beginNativePress(on: panel, event: event, target: .compact, source: "nativeClickShield.compact")
            }
            shield.onMouseDragged = { [weak self] event in
                guard let self, let panel = event.window as? TaskLightPanel else { return }
                self.updateNativePress(on: panel, event: event, source: "nativeClickShield.compact")
            }
            shield.onMouseUp = { [weak self] event in
                guard let self, let panel = event.window as? TaskLightPanel else { return }
                self.finishNativePress(on: panel, event: event, source: "nativeClickShield.compact")
            }
            appendStartupTrace("clickShield.compact.installed")
        case .edgeRail:
            shield.hitMode = .full
            shield.onMouseDown = { [weak self] event in
                guard let self, let panel = event.window as? TaskLightPanel else { return }
                self.beginNativePress(on: panel, event: event, target: .edgeRail, source: "nativeClickShield.edgeRail")
            }
            shield.onMouseDragged = { [weak self] event in
                guard let self, let panel = event.window as? TaskLightPanel else { return }
                self.updateNativePress(on: panel, event: event, source: "nativeClickShield.edgeRail")
            }
            shield.onMouseUp = { [weak self] event in
                guard let self, let panel = event.window as? TaskLightPanel else { return }
                self.finishNativePress(on: panel, event: event, source: "nativeClickShield.edgeRail")
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
        if let lastKnownCompactFrame {
            let visibleFrame = visibleFrame(containing: NSPoint(x: lastKnownCompactFrame.midX, y: lastKnownCompactFrame.midY))
                ?? activeVisibleFrame()
                ?? visibleFrames().first
                ?? lastKnownCompactFrame
            return TaskLightPanelGeometry.clampedFrame(lastKnownCompactFrame, visibleFrame: visibleFrame)
        }
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
        lastKnownCompactFrame = compact
        let data = try? NSKeyedArchiver.archivedData(withRootObject: NSValue(rect: compact), requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.compactWindowFrame)
        UserDefaults.standard.set(data, forKey: TaskLightLedgerKeys.windowFrame)
    }

    private func rememberCompactFrame(_ frame: NSRect, source: String, persistImmediately: Bool = true) {
        let compact = compactFrame(from: frame)
        lastKnownCompactFrame = compact
        if persistImmediately {
            compactFramePersistWorkItem?.cancel()
            compactFramePersistWorkItem = nil
            saveCompactFrame(compact)
            appendStartupTrace("\(source).rememberCompactFrame.x\(Int(compact.minX)).y\(Int(compact.minY))")
            return
        }
        scheduleCompactFramePersist(source: source)
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

    private func scheduleCompactFramePersist(source: String) {
        compactFramePersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let compactFrame = self.lastKnownCompactFrame else { return }
                self.saveCompactFrame(compactFrame)
                self.appendStartupTrace("\(source).debouncedRememberCompactFrame.x\(Int(compactFrame.minX)).y\(Int(compactFrame.minY))")
            }
        }
        compactFramePersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: workItem)
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
        guard animated else {
            panel.setFrame(frame, display: display)
            DispatchQueue.main.async { [weak self] in
                guard self?.programmaticFrameChangeID == changeID else { return }
                self?.isApplyingProgrammaticFrame = false
            }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            panel.setFrame(frame, display: display, animate: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.06) { [weak self] in
            guard self?.programmaticFrameChangeID == changeID else { return }
            self?.isApplyingProgrammaticFrame = false
        }
    }

    private func prewarmPanelSurface(_ panel: TaskLightPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
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

    private func writeManualLatency(source: String, action: String, startedAt: CFTimeInterval, eventTimestamp: TimeInterval? = nil) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("manual_interaction_latency.log")
        let appliedMs = (CACurrentMediaTime() - startedAt) * 1000
        let eventDelay = eventTimestamp.map { max(0, (CACurrentMediaTime() - $0) * 1000) }
        let eventDelayText = eventDelay.map { String(format: " event_delay_ms=%.2f", $0) } ?? ""
        let line = "\(ISO8601DateFormatter().string(from: Date())) panel source=\(source) action=\(action) applied_ms=\(String(format: "%.2f", appliedMs))\(eventDelayText) edge_collapsed=\(viewModel.edgeCollapsed) compact_alpha=\(String(format: "%.2f", compactPanel?.alphaValue ?? -1)) edge_alpha=\(String(format: "%.2f", edgePanel?.alphaValue ?? -1))\n"
        taskLightTraceWriteQueue.async {
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
        targetPanel.orderFrontRegardless()
        if targetPanel === edgePanel {
            appendStartupTrace("ensureVisibleOnActiveSpace.edgePanelKey")
            return
        }
        appendStartupTrace("ensureVisibleOnActiveSpace")
    }

    private func appendStartupTrace(_ event: String) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("startup_trace.log")
            let line = "\(ISO8601DateFormatter().string(from: Date())) panel_controller \(event)\n"
        taskLightTraceWriteQueue.async {
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
