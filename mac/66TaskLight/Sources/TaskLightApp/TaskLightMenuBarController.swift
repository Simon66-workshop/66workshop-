import AppKit
import Combine
import SwiftUI

@MainActor
final class TaskLightMenuBarController: NSObject, NSPopoverDelegate {
    private let viewModel: TaskLightViewModel
    private weak var panelController: TaskLightPanelController?
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: TaskLightViewModel, panelController: TaskLightPanelController) {
        self.viewModel = viewModel
        self.panelController = panelController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
        bindViewModel()
        updateStatusItem()
    }

    func shutdown() {
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
        cancellables.removeAll()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = viewModel.menuBarStatusAccessibilityLabel()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 540)
        popover.contentViewController = NSHostingController(
            rootView: TaskRadarPopoverView(viewModel: viewModel)
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
        guard let button = statusItem.button else { return }
        button.attributedTitle = menuBarAttributedTitle()
        button.toolTip = viewModel.menuBarStatusAccessibilityLabel()
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

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }
        switch event.type {
        case .rightMouseUp, .rightMouseDown:
            showContextMenu(sender)
        default:
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        popover.close()
        let menu = NSMenu()
        let visibilityTitle = panelController?.anyTaskLightPanelVisible == true ? "隐藏小猫" : "显示小猫"
        menu.addItem(NSMenuItem(title: visibilityTitle, action: #selector(toggleCatVisibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: viewModel.edgeCollapsed ? "恢复完整小猫" : "切换胶囊态", action: #selector(toggleEdgeRail), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开完整面板", action: #selector(openExpandedPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "运行 Workspace 巡检", action: #selector(runWorkspaceCoverage), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 66TaskLight", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleCatVisibility() {
        panelController?.togglePanelVisibilityFromMenuBar()
    }

    @objc private func toggleEdgeRail() {
        panelController?.toggleEdgeRailFromMenuBar()
    }

    @objc private func openExpandedPanel() {
        panelController?.openExpandedFromMenuBar()
    }

    @objc private func runWorkspaceCoverage() {
        viewModel.runWorkspaceCoverageReport()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
