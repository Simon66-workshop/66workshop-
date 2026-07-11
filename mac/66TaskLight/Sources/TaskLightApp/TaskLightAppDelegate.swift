import AppKit
import SwiftUI

@MainActor
final class TaskLightAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = TaskLightViewModel()
    private var panelController: TaskLightPanelController?
    private var menuBarController: TaskLightMenuBarController?
    private var globalShortcutController: TaskLightGlobalShortcutController?
    private var initialPanelPresented = false
    private var edgeToggleSelfTestScheduled = false
    private var visualMatrixSelfTestScheduled = false
    private var menuBarSelfTestScheduled = false
    private var expandedPanelSelfTestScheduled = false
    private var interactionEventReplaySelfTestScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        appendStartupTrace("applicationDidFinishLaunching.begin")
        NSApp.setActivationPolicy(.regular)
        let controller = TaskLightPanelController(viewModel: viewModel)
        panelController = controller
        menuBarController = TaskLightMenuBarController(viewModel: viewModel, panelController: controller)
        globalShortcutController = TaskLightGlobalShortcutController(
            togglePanel: { [weak controller] in controller?.togglePanelVisibilityFromMenuBar() },
            toggleExpanded: { [weak controller] in controller?.toggleExpandedFromMenuBar() }
        )
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
        panelController?.handleActivationClickIfInsidePanel(reason: "applicationDidBecomeActive")
    }

    func applicationWillTerminate(_ notification: Notification) {
        appendStartupTrace("applicationWillTerminate.begin")
        menuBarController?.shutdown()
        globalShortcutController = nil
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
        scheduleVisualMatrixSelfTestIfNeeded()
        scheduleMenuBarSelfTestIfNeeded()
        scheduleExpandedPanelSelfTestIfNeeded()
        scheduleInteractionEventReplaySelfTestIfNeeded()
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

    private func scheduleVisualMatrixSelfTestIfNeeded() {
        guard !visualMatrixSelfTestScheduled else { return }
        guard ProcessInfo.processInfo.arguments.contains("--tasklight-visual-matrix-self-test") else { return }
        visualMatrixSelfTestScheduled = true
        appendStartupTrace("visualMatrixSelfTest.scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let menuBarController = self.menuBarController else { return }
            menuBarController.runVisualMatrixSelfTest { payload in
                self.writeVisualMatrixSelfTestResult(payload)
                self.appendStartupTrace("visualMatrixSelfTest.completed.\(payload["status"] ?? "unknown")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func scheduleMenuBarSelfTestIfNeeded() {
        guard !menuBarSelfTestScheduled else { return }
        guard ProcessInfo.processInfo.arguments.contains("--tasklight-menu-bar-self-test") else { return }
        menuBarSelfTestScheduled = true
        appendStartupTrace("menuBarSelfTest.scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let menuBarController = self.menuBarController else { return }
            menuBarController.runMenuBarSelfTest { payload in
                self.writeSelfTestResult(payload, fileName: "menu_bar_self_test.json")
                self.appendStartupTrace("menuBarSelfTest.completed.\(payload["status"] ?? "unknown")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func scheduleExpandedPanelSelfTestIfNeeded() {
        guard !expandedPanelSelfTestScheduled else { return }
        guard ProcessInfo.processInfo.arguments.contains("--tasklight-expanded-panel-self-test") else { return }
        expandedPanelSelfTestScheduled = true
        appendStartupTrace("expandedPanelSelfTest.scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let panelController = self.panelController else { return }
            panelController.runExpandedPanelSelfTest { payload in
                self.writeSelfTestResult(payload, fileName: "expanded_panel_self_test.json")
                self.appendStartupTrace("expandedPanelSelfTest.completed.\(payload["status"] ?? "unknown")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func scheduleInteractionEventReplaySelfTestIfNeeded() {
        guard !interactionEventReplaySelfTestScheduled else { return }
        guard ProcessInfo.processInfo.arguments.contains("--tasklight-interaction-event-replay-self-test") else { return }
        interactionEventReplaySelfTestScheduled = true
        appendStartupTrace("interactionEventReplaySelfTest.scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, let panelController = self.panelController else { return }
            panelController.runInteractionEventReplaySelfTest { payload in
                self.writeSelfTestResult(payload, fileName: "interaction_event_replay_self_test.json")
                self.appendStartupTrace("interactionEventReplaySelfTest.completed.\(payload["status"] ?? "unknown")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func writeVisualMatrixSelfTestResult(_ payload: [String: Any]) {
        writeSelfTestResult(payload, fileName: "visual_matrix_self_test.json")
    }

    private func writeSelfTestResult(_ payload: [String: Any], fileName: String) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent(fileName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var output = payload
        output["written_at"] = ISO8601DateFormatter().string(from: Date())
        guard JSONSerialization.isValidJSONObject(output),
              let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: url)
    }

    private func appendStartupTrace(_ event: String) {
        let directory = viewModel.config.stateDirectory
        let url = directory.appendingPathComponent("startup_trace.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) app_delegate \(event)\n"
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
