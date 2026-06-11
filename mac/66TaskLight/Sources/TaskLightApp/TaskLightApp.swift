import SwiftUI

@main
struct TaskLightAppMain: App {
    @NSApplicationDelegateAdaptor(TaskLightAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

