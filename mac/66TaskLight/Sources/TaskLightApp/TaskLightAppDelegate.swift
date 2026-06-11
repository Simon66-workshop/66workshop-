import AppKit
import SwiftUI

@MainActor
final class TaskLightAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = TaskLightViewModel()
    private var panelController: TaskLightPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let controller = TaskLightPanelController(viewModel: viewModel)
        panelController = controller
        controller.showPanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
