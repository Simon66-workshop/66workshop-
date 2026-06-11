import SwiftUI

struct LuckyCatDashboardRootView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    var body: some View {
        Group {
            if viewModel.expanded {
                LuckyCatExpandedDashboardView(viewModel: viewModel)
            } else {
                LuckyCatCompactView(viewModel: viewModel)
            }
        }
    }
}
