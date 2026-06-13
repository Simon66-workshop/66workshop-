import SwiftUI

struct LuckyCatDashboardRootView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    var body: some View {
        Group {
            if viewModel.contentExpanded {
                LuckyCatExpandedDashboardView(viewModel: viewModel)
            } else {
                LuckyCatCompactView(viewModel: viewModel)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}
