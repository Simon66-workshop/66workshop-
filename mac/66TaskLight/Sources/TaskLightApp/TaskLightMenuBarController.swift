import AppKit
import Combine
import SwiftUI

@MainActor
final class TaskLightMenuBarController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let viewModel: TaskLightViewModel
    private weak var panelController: TaskLightPanelController?
    private let statusItem: NSStatusItem
    private let statusMenu: NSMenu
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var visualMatrixWindowController: NSWindowController?
    private var isStatusMenuOpen = false
    private var statusNeedsRefreshAfterMenuClose = false

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.prepareVisualMatrixController()
        }
    }

    func shutdown() {
        popover.close()
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
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 540)
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
        rebuildStatusMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isStatusMenuOpen = false
        if statusNeedsRefreshAfterMenuClose {
            statusNeedsRefreshAfterMenuClose = false
            DispatchQueue.main.async { [weak self] in
                self?.updateStatusItem()
            }
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
        statusMenu.removeAllItems()
        popover.close()
        let visibilityTitle = panelController?.anyTaskLightPanelVisible == true ? "隐藏小猫" : "显示小猫"
        let expandedPanelTitle = viewModel.expanded ? "关闭完整面板" : "打开完整面板"
        let visualMatrixTitle = isVisualMatrixVisible ? "关闭视觉矩阵" : "打开视觉矩阵"
        statusMenu.addItem(NSMenuItem(title: "打开任务雷达", action: #selector(openTaskRadar), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: visibilityTitle, action: #selector(toggleCatVisibility), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: viewModel.edgeCollapsed ? "恢复完整小猫" : "切换胶囊态", action: #selector(toggleEdgeRail), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: expandedPanelTitle, action: #selector(toggleExpandedPanel), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: visualMatrixTitle, action: #selector(toggleVisualMatrix), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "运行 Workspace 巡检", action: #selector(runWorkspaceCoverage), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "退出 66TaskLight", action: #selector(quitApp), keyEquivalent: "q"))
        for item in statusMenu.items {
            item.target = self
        }
    }

    @objc private func openTaskRadar() {
        let startedAt = CACurrentMediaTime()
        guard let button = statusItem.button else { return }
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button else { return }
            self.togglePopover(button)
            self.writeManualLatency(source: "menu", action: "openTaskRadar", startedAt: startedAt)
        }
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
        completion([
            "status": hasMenu && hasPopoverContent && openExpandedReady && closeExpandedReady && expandedToggleClosed && matrixOpenTitleReady && matrixCloseTitleReady && matrixWindowVisible && matrixToggleClosed ? "ok" : "not_ready",
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
            "open_apply_ms": (CFAbsoluteTimeGetCurrent() - started) * 1000,
            "menu_title": viewModel.menuBarStatusTitle()
        ])
    }

    private var isVisualMatrixVisible: Bool {
        visualMatrixWindowController?.window?.isVisible == true
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
