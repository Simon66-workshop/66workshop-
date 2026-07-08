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
                previewSurface(title: "浅色", style: .light) {
                    LuckyCatCompactView(viewModel: model)
                        .scaleEffect(0.58)
                        .frame(width: LuckyCatLayout.compactWidth * 0.58, height: LuckyCatLayout.compactHeight * 0.58)
                }
                previewSurface(title: "胶囊玻璃", style: .glassCapsule) {
                    LuckyCatEdgeRailView(viewModel: model)
                        .scaleEffect(0.66)
                        .frame(width: LuckyCatLayout.edgeRailPanelWidth * 0.66, height: LuckyCatLayout.edgeRailPanelHeight * 0.66)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.edgeRailThreadSummary())
                        .font(LuckyCatTokens.Typography.taskTitle)
                        .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    Text(model.quotaCompactText())
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(model.quotaIsCritical() ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textPrimary)
                    Text("Quota Pace: \(model.quotaBurnRateSnapshot().summary)")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    Text("Hooks Doctor: \(model.workspaceDoctorRows(limit: 1).first?.coverage_status ?? "no report")")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    Text(model.taskRadarDiagnosticRows().map { "\($0.label)=\($0.value)" }.joined(separator: " · "))
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                readabilityChip("浅背景")
                readabilityChip("暗背景可读性")
                readabilityChip("复杂网页背景")
                readabilityChip("低 quota 红字")
                readabilityChip("Pending 黄球")
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

    private enum PreviewSurfaceStyle {
        case light
        case glassCapsule
    }

    private func previewSurface<Content: View>(title: String, style: PreviewSurfaceStyle, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
            Text(title)
                .font(LuckyCatTokens.Typography.statusPill)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(previewSurfaceFill(style))
                .background(previewSurfaceEnvironment(style))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(previewSurfaceStroke(style), lineWidth: 1)
                )
        )
    }

    private func previewSurfaceFill(_ style: PreviewSurfaceStyle) -> LinearGradient {
        switch style {
        case .light:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.48),
                    Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.34),
                    Color.white.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .glassCapsule:
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.995, blue: 1.0).opacity(0.66),
                    Color(red: 0.88, green: 0.95, blue: 1.0).opacity(0.38),
                    Color(red: 0.97, green: 0.93, blue: 0.98).opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private func previewSurfaceEnvironment(_ style: PreviewSurfaceStyle) -> some View {
        switch style {
        case .light:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        case .glassCapsule:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.54),
                            Color(red: 0.70, green: 0.86, blue: 1.0).opacity(0.20),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.28, y: 0.18),
                        startRadius: 4,
                        endRadius: 96
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.52, green: 0.66, blue: 0.78).opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private func previewSurfaceStroke(_ style: PreviewSurfaceStyle) -> LinearGradient {
        switch style {
        case .light:
            return LinearGradient(
                colors: [Color.white.opacity(0.44), Color.white.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .glassCapsule:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.72),
                    Color(red: 0.78, green: 0.90, blue: 1.0).opacity(0.34),
                    Color.white.opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func readabilityChip(_ title: String) -> some View {
        Text(title)
            .font(LuckyCatTokens.Typography.statusPill)
            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.28)))
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
