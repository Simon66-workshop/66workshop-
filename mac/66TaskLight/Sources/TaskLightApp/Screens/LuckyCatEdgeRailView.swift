import SwiftUI
import TaskLightCore

struct LuckyCatEdgeRailView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    var body: some View {
        VStack(spacing: 5) {
            LuckyCatStatusOrb(
                status: status,
                size: 31,
                pulsing: false,
                showsGlow: false,
                style: .embedded
            )
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            Text(viewModel.compactStatusTitle())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(statusTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .frame(width: 48)

            railDivider

            countStack

            edgeQuota
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: LuckyCatLayout.edgeRailWidth, height: LuckyCatLayout.edgeRailHeight)
        .background(railBackground)
        .overlay(railHairline)
        .clipShape(RoundedRectangle(cornerRadius: LuckyCatLayout.edgeRailCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: LuckyCatLayout.edgeRailCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.compactStatusTitle()), \(viewModel.edgeRailThreadSummary()), \(viewModel.quotaCompactText())")
        .help("拖动移动，点击恢复小猫")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var countStack: some View {
        VStack(spacing: 3) {
            countRow(label: "运", value: viewModel.runningDisplayCount())
            countRow(label: "验", value: viewModel.pendingDisplayCount())
            countRow(label: "观", value: viewModel.observedDisplayCount())
        }
        .frame(width: 46)
    }

    private func countRow(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.quotaNumberLight.opacity(0.62))
                .frame(width: 10, alignment: .trailing)
            Text("\(value)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.quotaNumberLight.opacity(0.92))
                .monospacedDigit()
                .frame(width: 18, alignment: .leading)
        }
        .frame(width: 34, alignment: .center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var edgeQuota: some View {
        VStack(spacing: 1) {
            Text("⚡")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.quotaBolt)

            Text(String(viewModel.quotaCompactText().dropFirst()))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(viewModel.quotaIsCritical() ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.quotaNumberLight)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .monospacedDigit()
                .frame(width: 34)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(width: 46)
        .background(
            Capsule(style: .continuous)
                .fill(LuckyCatTokens.Palette.quotaChipFill.opacity(0.84))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(LuckyCatTokens.Palette.quotaDivider, lineWidth: 1)
        )
    }

    private var railDivider: some View {
        Capsule(style: .continuous)
            .fill(LuckyCatTokens.Palette.quotaDivider)
            .frame(width: 30, height: 1)
    }

    private var railBackground: some View {
        RoundedRectangle(cornerRadius: LuckyCatLayout.edgeRailCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: LuckyCatLayout.edgeRailCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                LuckyCatTokens.Palette.glassRoseCore.opacity(0.72),
                                LuckyCatTokens.Palette.glassRoseDepth.opacity(0.56),
                                Color(hex: "#2D1521").opacity(0.58)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuckyCatLayout.edgeRailCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .blendMode(.screen)
            )
    }

    private var railHairline: some View {
        RoundedRectangle(cornerRadius: LuckyCatLayout.edgeRailCornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.48),
                        LuckyCatTokens.Palette.glassPrismRose.opacity(0.30),
                        Color.white.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var statusTextColor: Color {
        switch status {
        case .blocked:
            return LuckyCatTokens.Palette.red
        case .running:
            return LuckyCatTokens.Palette.blue
        case .pending:
            return LuckyCatTokens.Palette.amber
        case .done:
            return LuckyCatTokens.Palette.green
        case .observed:
            return LuckyCatTokens.Palette.cyan
        case .idle:
            return LuckyCatTokens.Palette.quotaNumberLight.opacity(0.88)
        }
    }
}
