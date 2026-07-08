import AppKit
import Combine
import SwiftUI
import TaskLightCore

@MainActor
final class TaskLightMenuBarController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let viewModel: TaskLightViewModel
    private weak var panelController: TaskLightPanelController?
    private let statusItem: NSStatusItem
    private let statusMenu: NSMenu
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var radarWindowController: NSWindowController?
    private var visualMatrixWindowController: NSWindowController?
    private var isStatusMenuOpen = false
    private var statusNeedsRefreshAfterMenuClose = false
    private var pendingMenuCloseAction: (() -> Void)?
    private var visibilityMenuItem: NSMenuItem?
    private var edgeRailMenuItem: NSMenuItem?
    private var expandedPanelMenuItem: NSMenuItem?
    private var visualMatrixMenuItem: NSMenuItem?
    private var focusMenuItem: NSMenuItem?
    private var menuBarOnlyMenuItem: NSMenuItem?
    private var autoMeetingMenuItem: NSMenuItem?
    private var lastTaskRadarOpenMetrics: [String: Double] = [:]
    private var cachedTaskRadarVisibleFrame: NSRect?

    init(viewModel: TaskLightViewModel, panelController: TaskLightPanelController) {
        self.viewModel = viewModel
        self.panelController = panelController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusMenu = NSMenu()
        self.popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
        bindViewModel()
        updateStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.prepareTaskRadarController()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.prepareVisualMatrixController()
        }
    }

    func shutdown() {
        popover.close()
        radarWindowController?.close()
        visualMatrixWindowController?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
        cancellables.removeAll()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.toolTip = viewModel.menuBarStatusAccessibilityLabel()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildStatusMenu()
    }

    private func configurePopover() {
        popover.behavior = .semitransient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: TaskRadarPopoverView(viewModel: viewModel) { [weak self] in
                self?.openVisualMatrixFromRadar()
            }
        )
    }

    private func bindViewModel() {
        viewModel.$uiState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        viewModel.$edgeCollapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard !isStatusMenuOpen else {
            statusNeedsRefreshAfterMenuClose = true
            return
        }
        guard let button = statusItem.button else { return }
        button.attributedTitle = menuBarAttributedTitle()
        button.toolTip = viewModel.menuBarStatusAccessibilityLabel()
        rebuildStatusMenu()
    }

    private func menuBarAttributedTitle() -> NSAttributedString {
        let title = viewModel.menuBarStatusTitle()
        let output = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        if title.hasPrefix("●") {
            output.addAttribute(.foregroundColor, value: viewModel.statusColor(), range: NSRange(location: 0, length: 1))
        }
        return output
    }

    func menuWillOpen(_ menu: NSMenu) {
        isStatusMenuOpen = true
        statusNeedsRefreshAfterMenuClose = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        updateStatusMenuTitles()
    }

    func menuDidClose(_ menu: NSMenu) {
        isStatusMenuOpen = false
        let pendingAction = pendingMenuCloseAction
        pendingMenuCloseAction = nil
        if let pendingAction {
            pendingAction()
        }
        if statusNeedsRefreshAfterMenuClose {
            statusNeedsRefreshAfterMenuClose = false
            updateStatusItem()
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    private func rebuildStatusMenu() {
        guard statusMenu.items.isEmpty else {
            updateStatusMenuTitles()
            return
        }
        statusMenu.addItem(NSMenuItem(title: "打开任务雷达", action: #selector(openTaskRadar), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        let visibilityItem = NSMenuItem(title: "", action: #selector(toggleCatVisibility), keyEquivalent: "")
        let edgeItem = NSMenuItem(title: "", action: #selector(toggleEdgeRail), keyEquivalent: "")
        let expandedItem = NSMenuItem(title: "", action: #selector(toggleExpandedPanel), keyEquivalent: "")
        let matrixItem = NSMenuItem(title: "", action: #selector(toggleVisualMatrix), keyEquivalent: "")
        let focusItem = NSMenuItem(title: "", action: #selector(toggleFocusMode), keyEquivalent: "")
        let menuOnlyItem = NSMenuItem(title: "", action: #selector(toggleMenuBarOnlyMode), keyEquivalent: "")
        let autoMeetingItem = NSMenuItem(title: "", action: #selector(toggleAutoMeetingMode), keyEquivalent: "")
        statusMenu.addItem(visibilityItem)
        statusMenu.addItem(edgeItem)
        statusMenu.addItem(expandedItem)
        statusMenu.addItem(matrixItem)
        statusMenu.addItem(focusItem)
        statusMenu.addItem(menuOnlyItem)
        statusMenu.addItem(autoMeetingItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "打开 Hooks Doctor", action: #selector(openHooksDoctor), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "运行 Workspace 巡检", action: #selector(runWorkspaceCoverage), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "退出 66TaskLight", action: #selector(quitApp), keyEquivalent: "q"))
        visibilityMenuItem = visibilityItem
        edgeRailMenuItem = edgeItem
        expandedPanelMenuItem = expandedItem
        visualMatrixMenuItem = matrixItem
        focusMenuItem = focusItem
        menuBarOnlyMenuItem = menuOnlyItem
        autoMeetingMenuItem = autoMeetingItem
        for item in statusMenu.items {
            item.target = self
        }
        updateStatusMenuTitles()
    }

    private func updateStatusMenuTitles() {
        let visibilityTitle = panelController?.anyTaskLightPanelVisible == true ? "隐藏小猫" : "显示小猫"
        let expandedPanelTitle = viewModel.expanded ? "关闭完整面板" : "打开完整面板"
        let visualMatrixTitle = isVisualMatrixVisible ? "关闭视觉矩阵" : "打开视觉矩阵"
        let focusTitle = viewModel.presenceMode == .focusCapsule ? "退出 Focus 模式" : "Focus 模式"
        let menuOnlyTitle = viewModel.presenceMode == .menuBarOnly ? "退出菜单栏 Only" : "只留菜单栏"
        let autoMeetingTitle = viewModel.autoMeetingModeEnabled ? "关闭会议自动降存在感" : "开启会议自动降存在感"
        visibilityMenuItem?.title = visibilityTitle
        edgeRailMenuItem?.title = viewModel.edgeCollapsed ? "恢复完整小猫" : "切换胶囊态"
        expandedPanelMenuItem?.title = expandedPanelTitle
        visualMatrixMenuItem?.title = visualMatrixTitle
        focusMenuItem?.title = focusTitle
        menuBarOnlyMenuItem?.title = menuOnlyTitle
        autoMeetingMenuItem?.title = autoMeetingTitle
    }

    @objc private func openTaskRadar() {
        let startedAt = CACurrentMediaTime()
        schedulePopoverOpen(action: "openTaskRadar", startedAt: startedAt)
    }

    @objc private func toggleCatVisibility() {
        let startedAt = CACurrentMediaTime()
        appendMenuTrace("action.toggleCatVisibility.begin")
        panelController?.togglePanelVisibilityFromMenuBar()
        appendMenuTrace("action.toggleCatVisibility.end")
        writeManualLatency(source: "menu", action: "toggleCatVisibility", startedAt: startedAt)
    }

    @objc private func toggleEdgeRail() {
        let startedAt = CACurrentMediaTime()
        appendMenuTrace("action.toggleEdgeRail.begin")
        panelController?.toggleEdgeRailFromMenuBar()
        appendMenuTrace("action.toggleEdgeRail.end")
        writeManualLatency(source: "menu", action: "toggleEdgeRail", startedAt: startedAt)
    }

    @objc private func toggleExpandedPanel() {
        let startedAt = CACurrentMediaTime()
        appendMenuTrace("action.toggleExpanded.begin")
        panelController?.toggleExpandedFromMenuBar()
        appendMenuTrace("action.toggleExpanded.end")
        writeManualLatency(source: "menu", action: "toggleExpandedPanel", startedAt: startedAt)
    }

    @objc private func runWorkspaceCoverage() {
        viewModel.runWorkspaceCoverageReport()
    }

    @objc private func openHooksDoctor() {
        let startedAt = CACurrentMediaTime()
        schedulePopoverOpen(action: "openHooksDoctor", startedAt: startedAt)
    }

    private func schedulePopoverOpen(action: String, startedAt: CFTimeInterval) {
        appendMenuTrace("action.\(action).scheduled")
        let openAction: () -> Void = { [weak self] in
            guard let self else { return }
            self.presentTaskRadarWindow(source: action)
            let isShown = self.radarWindowController?.window?.isVisible == true
            self.appendMenuTrace("action.\(action).shown=\(isShown)")
            self.writeManualLatency(source: "menu", action: action, startedAt: startedAt)
        }
        if isStatusMenuOpen {
            pendingMenuCloseAction = openAction
        } else {
            DispatchQueue.main.async {
                openAction()
            }
        }
    }

    @objc private func toggleFocusMode() {
        let next: TaskLightPresenceMode = viewModel.presenceMode == .focusCapsule ? .normal : .focusCapsule
        viewModel.setPresenceMode(next)
    }

    @objc private func toggleMenuBarOnlyMode() {
        let next: TaskLightPresenceMode = viewModel.presenceMode == .menuBarOnly ? .normal : .menuBarOnly
        viewModel.setPresenceMode(next)
    }

    @objc private func toggleAutoMeetingMode() {
        viewModel.setAutoMeetingModeEnabled(!viewModel.autoMeetingModeEnabled)
    }

    @objc private func toggleVisualMatrix() {
        let startedAt = CACurrentMediaTime()
        appendMenuTrace("action.toggleVisualMatrix.begin")
        if isVisualMatrixVisible {
            closeVisualMatrixWindow(source: "menu")
        } else {
            presentVisualMatrixWindow(source: "menu")
        }
        appendMenuTrace("action.toggleVisualMatrix.end")
        writeManualLatency(source: "menu", action: "toggleVisualMatrix", startedAt: startedAt)
    }

    private func openVisualMatrixFromRadar() {
        popover.close()
        radarWindowController?.close()
        presentVisualMatrixWindow(source: "radar")
    }

    func runVisualMatrixSelfTest(completion: @escaping ([String: Any]) -> Void) {
        let started = CFAbsoluteTimeGetCurrent()
        presentVisualMatrixWindow(source: "self_test")
        guard let window = visualMatrixWindowController?.window else {
            completion([
                "status": "missing_window",
                "visible": false
            ])
            return
        }
        completion([
            "status": window.isVisible ? "ok" : "not_visible",
            "visible": window.isVisible,
            "key": window.isKeyWindow,
            "title": window.title,
            "open_apply_ms": (CFAbsoluteTimeGetCurrent() - started) * 1000,
            "frame": [
                "x": window.frame.origin.x,
                "y": window.frame.origin.y,
                "width": window.frame.width,
                "height": window.frame.height
            ]
        ])
    }

    func runMenuBarSelfTest(completion: @escaping ([String: Any]) -> Void) {
        guard statusItem.button != nil else {
            completion([
                "status": "missing_status_button",
                "status_button_ready": false
            ])
            return
        }
        let started = CFAbsoluteTimeGetCurrent()
        let hasMenu = statusItem.menu === statusMenu && !statusMenu.items.isEmpty
        let hasPopoverContent = popover.contentViewController != nil
        popover.close()
        radarWindowController?.close()
        menuWillOpen(statusMenu)
        let hooksDoctorStarted = CFAbsoluteTimeGetCurrent()
        openHooksDoctor()
        let hooksDoctorDeferred = pendingMenuCloseAction != nil
        statusNeedsRefreshAfterMenuClose = true
        menuDidClose(statusMenu)
        let hooksDoctorShownAfterMenuClose = radarWindowController?.window?.isVisible == true
        updateStatusItem()
        let hooksDoctorSurvivesStatusRefresh = radarWindowController?.window?.isVisible == true
        let hooksDoctorApplyMS = (CFAbsoluteTimeGetCurrent() - hooksDoctorStarted) * 1000
        radarWindowController?.close()
        popover.close()
        viewModel.expanded = false
        rebuildStatusMenu()
        let openExpandedItem = statusMenu.items.first { $0.title == "打开完整面板" }
        let openExpandedReady = openExpandedItem?.target === self && openExpandedItem?.action == #selector(toggleExpandedPanel)
        viewModel.expanded = true
        rebuildStatusMenu()
        let closeExpandedItem = statusMenu.items.first { $0.title == "关闭完整面板" }
        let closeExpandedReady = closeExpandedItem?.target === self && closeExpandedItem?.action == #selector(toggleExpandedPanel)
        if closeExpandedReady, let closeExpandedItem {
            NSApp.sendAction(closeExpandedItem.action!, to: closeExpandedItem.target, from: closeExpandedItem)
        }
        let expandedToggleClosed = viewModel.expanded == false
        rebuildStatusMenu()
        closeVisualMatrixWindow(source: "self_test.reset")
        rebuildStatusMenu()
        let openMatrixItem = statusMenu.items.first { $0.title == "打开视觉矩阵" }
        let matrixOpenTitleReady = openMatrixItem?.target === self && openMatrixItem?.action == #selector(toggleVisualMatrix)
        if matrixOpenTitleReady, let openMatrixItem, let action = openMatrixItem.action {
            NSApp.sendAction(action, to: openMatrixItem.target, from: openMatrixItem)
        }
        let matrixWindowVisible = visualMatrixWindowController?.window?.isVisible == true
        rebuildStatusMenu()
        let closeMatrixItem = statusMenu.items.first { $0.title == "关闭视觉矩阵" }
        let matrixCloseTitleReady = closeMatrixItem?.target === self && closeMatrixItem?.action == #selector(toggleVisualMatrix)
        if matrixCloseTitleReady, let closeMatrixItem, let action = closeMatrixItem.action {
            NSApp.sendAction(action, to: closeMatrixItem.target, from: closeMatrixItem)
        }
        let matrixToggleClosed = visualMatrixWindowController?.window?.isVisible != true
        let baselineOK = hasMenu
            && hasPopoverContent
            && openExpandedReady
            && closeExpandedReady
            && expandedToggleClosed
            && matrixOpenTitleReady
            && matrixCloseTitleReady
            && matrixWindowVisible
            && matrixToggleClosed
        completion([
            "status": baselineOK && hooksDoctorDeferred && hooksDoctorShownAfterMenuClose && hooksDoctorSurvivesStatusRefresh ? "ok" : "not_ready",
            "status_button_ready": hasMenu,
            "popover_content_ready": hasPopoverContent,
            "expanded_open_title_ready": openExpandedReady,
            "expanded_close_title_ready": closeExpandedReady,
            "expanded_toggle_closed": expandedToggleClosed,
            "matrix_menu_action_ready": matrixOpenTitleReady,
            "matrix_open_title_ready": matrixOpenTitleReady,
            "matrix_close_title_ready": matrixCloseTitleReady,
            "matrix_menu_action_visible": matrixWindowVisible,
            "matrix_toggle_closed": matrixToggleClosed,
            "hooks_doctor_deferred_after_menu": hooksDoctorDeferred,
            "hooks_doctor_shown_after_menu_close": hooksDoctorShownAfterMenuClose,
            "hooks_doctor_survives_status_refresh": hooksDoctorSurvivesStatusRefresh,
            "hooks_doctor_apply_ms": hooksDoctorApplyMS,
            "task_radar_controller_ms": lastTaskRadarOpenMetrics["controller_ms"] ?? -1,
            "task_radar_frame_ms": lastTaskRadarOpenMetrics["frame_ms"] ?? -1,
            "task_radar_show_ms": lastTaskRadarOpenMetrics["show_ms"] ?? -1,
            "task_radar_order_ms": lastTaskRadarOpenMetrics["order_ms"] ?? -1,
            "task_radar_total_ms": lastTaskRadarOpenMetrics["total_ms"] ?? -1,
            "open_apply_ms": (CFAbsoluteTimeGetCurrent() - started) * 1000,
            "menu_title": viewModel.menuBarStatusTitle()
        ])
    }

    private var isVisualMatrixVisible: Bool {
        visualMatrixWindowController?.window?.isVisible == true
    }

    private func presentTaskRadarWindow(source: String) {
        let started = CFAbsoluteTimeGetCurrent()
        let hadPreparedController = radarWindowController != nil
        let controller = radarWindowController ?? makeTaskRadarWindowController()
        radarWindowController = controller
        let controllerMS = (CFAbsoluteTimeGetCurrent() - started) * 1000
        guard let window = controller.window else { return }
        if !hadPreparedController {
            applyTaskRadarFrame(to: window)
        }
        let frameMS = (CFAbsoluteTimeGetCurrent() - started) * 1000
        window.deminiaturize(nil)
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        controller.showWindow(nil)
        let showMS = (CFAbsoluteTimeGetCurrent() - started) * 1000
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.orderFrontRegardless()
        let orderMS = (CFAbsoluteTimeGetCurrent() - started) * 1000
        lastTaskRadarOpenMetrics = [
            "controller_ms": controllerMS,
            "frame_ms": frameMS,
            "show_ms": showMS,
            "order_ms": orderMS,
            "total_ms": orderMS
        ]
        appendMenuTrace("taskRadar.open.\(source).visible=\(window.isVisible)")
    }

    private func prepareTaskRadarController() {
        guard radarWindowController == nil else { return }
        cachedTaskRadarVisibleFrame = NSScreen.main?.visibleFrame
        let controller = makeTaskRadarWindowController()
        radarWindowController = controller
        controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func makeTaskRadarWindowController() -> NSWindowController {
        let hosting = NSHostingController(
            rootView: TaskRadarWindowHostView(viewModel: viewModel) { [weak self] in
                self?.openVisualMatrixFromRadar()
            }
        )
        let window = NSPanel(
            contentRect: defaultTaskRadarFrame(),
            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "66TaskLight 任务雷达"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 420, height: 560)
        window.contentViewController = hosting
        return NSWindowController(window: window)
    }

    private func defaultTaskRadarFrame() -> NSRect {
        let visible = cachedTaskRadarVisibleFrame ?? NSRect(x: 80, y: 80, width: 1200, height: 820)
        let width: CGFloat = 420
        let height = min(max(visible.height * 0.72, 560), 640)
        let x = visible.maxX - width - 12
        let y = visible.maxY - height - 12
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func applyTaskRadarFrame(to window: NSWindow) {
        let frame = defaultTaskRadarFrame()
        guard !framesApproximatelyEqual(window.frame, frame) else { return }
        window.setFrame(frame, display: false)
    }

    private func framesApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func presentVisualMatrixWindow(source: String) {
        let controller = visualMatrixWindowController ?? makeVisualMatrixWindowController()
        visualMatrixWindowController = controller
        guard let window = controller.window else { return }
        if !window.isVisible, !isFrameMostlyVisible(window.frame) {
            applyDefaultVisualMatrixFrame(to: window)
        }
        if window.frame.width < 820 || window.frame.height < 640 {
            applyDefaultVisualMatrixFrame(to: window)
        }
        window.deminiaturize(nil)
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        appendMenuTrace("visualMatrix.open.\(source).visible=\(window.isVisible)")
    }

    private func closeVisualMatrixWindow(source: String) {
        guard let window = visualMatrixWindowController?.window else { return }
        window.close()
        appendMenuTrace("visualMatrix.close.\(source).visible=\(window.isVisible)")
    }

    private func prepareVisualMatrixController() {
        guard visualMatrixWindowController == nil else { return }
        visualMatrixWindowController = makeVisualMatrixWindowController()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func makeVisualMatrixWindowController() -> NSWindowController {
        let hosting = NSHostingController(rootView: LuckyCatVisualMatrixHostView())
        let window = NSWindow(
            contentRect: defaultVisualMatrixFrame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "66TaskLight 视觉状态矩阵"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 680)
        window.contentViewController = hosting
        applyDefaultVisualMatrixFrame(to: window)
        return NSWindowController(window: window)
    }

    private func defaultVisualMatrixFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1200, height: 820)
        let width = min(max(visible.width * 0.52, 820), 980)
        let height = min(max(visible.height * 0.72, 680), 760)
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func applyDefaultVisualMatrixFrame(to window: NSWindow) {
        let frame = defaultVisualMatrixFrame()
        window.setFrame(frame, display: false)
    }

    private func isFrameMostlyVisible(_ frame: NSRect) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) else {
            return false
        }
        let intersection = screen.visibleFrame.intersection(frame)
        return intersection.width >= min(240, frame.width * 0.35)
            && intersection.height >= min(220, frame.height * 0.35)
    }

    private func appendMenuTrace(_ event: String) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("menu_bar_actions.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) menu_bar \(event)\n"
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

    private func writeManualLatency(source: String, action: String, startedAt: CFTimeInterval) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("manual_interaction_latency.log")
        let appliedMs = (CACurrentMediaTime() - startedAt) * 1000
        let line = "\(ISO8601DateFormatter().string(from: Date())) menu source=\(source) action=\(action) applied_ms=\(String(format: "%.2f", appliedMs)) edge_collapsed=\(viewModel.edgeCollapsed) menu_open=\(isStatusMenuOpen)\n"
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
}
