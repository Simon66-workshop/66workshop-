import AppKit
import SwiftUI

@MainActor
final class TaskLightAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = TaskLightViewModel()
    private var panelController: TaskLightPanelController?
    private var menuBarController: TaskLightMenuBarController?
    private var initialPanelPresented = false
    private var edgeToggleSelfTestScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        appendStartupTrace("applicationDidFinishLaunching.begin")
        NSApp.setActivationPolicy(.regular)
        let controller = TaskLightPanelController(viewModel: viewModel)
        panelController = controller
        menuBarController = TaskLightMenuBarController(viewModel: viewModel, panelController: controller)
        NSApp.activate(ignoringOtherApps: true)
        appendStartupTrace("applicationDidFinishLaunching.activate")
        DispatchQueue.main.async { [weak self] in
            self?.presentInitialPanelIfNeeded(trigger: "launch.async")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.presentInitialPanelIfNeeded(trigger: "launch.retry")
            self?.panelController?.recoverVisibility(reason: "launch.retry")
        }
        appendStartupTrace("applicationDidFinishLaunching.end")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appendStartupTrace("applicationDidBecomeActive")
        presentInitialPanelIfNeeded(trigger: "didBecomeActive")
        panelController?.recoverVisibility(reason: "didBecomeActive")
        panelController?.handleActivationClickIfInsidePanel(reason: "applicationDidBecomeActive")
    }

    func applicationWillTerminate(_ notification: Notification) {
        appendStartupTrace("applicationWillTerminate.begin")
        menuBarController?.shutdown()
        panelController?.shutdown()
        viewModel.shutdown()
        appendStartupTrace("applicationWillTerminate.end")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func presentInitialPanelIfNeeded(trigger: String) {
        guard !initialPanelPresented else { return }
        guard let panelController else { return }
        appendStartupTrace("presentInitialPanelIfNeeded.\(trigger).begin")
        initialPanelPresented = true
        panelController.showPanel()
        scheduleEdgeToggleSelfTestIfNeeded()
        appendStartupTrace("presentInitialPanelIfNeeded.\(trigger).end")
    }

    private func scheduleEdgeToggleSelfTestIfNeeded() {
        guard !edgeToggleSelfTestScheduled else { return }
        guard ProcessInfo.processInfo.arguments.contains("--tasklight-edge-self-test") else { return }
        edgeToggleSelfTestScheduled = true
        appendStartupTrace("edgeToggleSelfTest.scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, let panelController = self.panelController else { return }
            panelController.runEdgeToggleSelfTest { passed in
                self.appendStartupTrace("edgeToggleSelfTest.completed.\(passed ? "ok" : "fail")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func appendStartupTrace(_ event: String) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("startup_trace.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) app_delegate \(event)\n"
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
