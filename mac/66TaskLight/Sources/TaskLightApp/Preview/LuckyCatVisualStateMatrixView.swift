import SwiftUI
import TaskLightCore

struct LuckyCatPreviewScenario: Identifiable {
    let id: String
    let title: String
    let uiState: TaskLightUIState
}

struct LuckyCatVisualStateMatrixView: View {
    let scenarios: [LuckyCatPreviewScenario]

    init(scenarios: [LuckyCatPreviewScenario] = LuckyCatPreviewData.visualMatrixScenarios) {
        self.scenarios = scenarios
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 390), spacing: 18)], spacing: 18) {
                ForEach(scenarios) { scenario in
                    LuckyCatVisualScenarioCard(scenario: scenario)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 820, minHeight: 680)
        .background(matrixBackground)
    }
}

struct LuckyCatVisualMatrixHostView: View {
    @State private var showsMatrix = false

    var body: some View {
        ZStack {
            matrixBackground
            if showsMatrix {
                LuckyCatVisualStateMatrixView()
                    .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                    Text("视觉矩阵")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    Text("正在载入状态预览")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.46), lineWidth: 1)
                        )
                )
            }
        }
        .frame(minWidth: 820, minHeight: 680)
        .onAppear {
            guard !showsMatrix else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                showsMatrix = true
            }
        }
    }
}

private struct LuckyCatVisualScenarioCard: View {
    let scenario: LuckyCatPreviewScenario
    @StateObject private var model: TaskLightViewModel

    init(scenario: LuckyCatPreviewScenario) {
        self.scenario = scenario
        _model = StateObject(wrappedValue: TaskLightViewModel(previewUIState: scenario.uiState))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(scenario.title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                Spacer()
                Text(model.menuBarStatusTitle())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.38)))
            }
            HStack(alignment: .center, spacing: 18) {
                LuckyCatCompactView(viewModel: model)
                    .scaleEffect(0.68)
                    .frame(width: LuckyCatLayout.compactWidth * 0.68, height: LuckyCatLayout.compactHeight * 0.68)
                LuckyCatEdgeRailView(viewModel: model)
                    .scaleEffect(0.72)
                    .frame(width: LuckyCatLayout.edgeRailPanelWidth * 0.72, height: LuckyCatLayout.edgeRailPanelHeight * 0.72)
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.edgeRailThreadSummary())
                        .font(LuckyCatTokens.Typography.taskTitle)
                        .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    Text(model.quotaCompactText())
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(model.quotaIsCritical() ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textPrimary)
                    Text(model.taskRadarDiagnosticRows().map { "\($0.label)=\($0.value)" }.joined(separator: " · "))
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.44), lineWidth: 1)
                )
        )
    }
}

private var matrixBackground: some View {
    LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.96, blue: 1),
            LuckyCatTokens.Palette.cream.opacity(0.86),
            Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.40)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
