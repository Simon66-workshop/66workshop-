import SwiftUI
import TaskLightCore

struct LuckyCatEdgeRailView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    var body: some View {
        LuckyCatEdgeRail3DChrome {
            readableContent
        }
        .frame(width: LuckyCatLayout.edgeRailPanelWidth, height: LuckyCatLayout.edgeRailPanelHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.compactStatusTitle()), \(viewModel.edgeRailThreadSummary()), \(viewModel.quotaCompactText())")
        .help("拖动移动，点击恢复小猫")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var readableContent: some View {
        VStack(spacing: 5) {
            EdgeRailGlassStatusOrb(
                status: status,
                size: EdgeRailLiquidGlassParameters.orbSize
            )
            .frame(width: 54, height: 52)
            .accessibilityHidden(true)

            statusTitle

            railDivider

            countStack

            edgeQuota
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .frame(width: LuckyCatLayout.edgeRailWidth, height: LuckyCatLayout.edgeRailHeight)
        .clipShape(Capsule(style: .continuous))
    }

    private var statusTitle: some View {
        Text(viewModel.compactStatusTitle())
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .kerning(-0.45)
            .foregroundStyle(statusTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(width: 66, height: 20)
            .background(statusTitleGlass)
            .overlay(statusTitleRim)
            .background(
                Text(viewModel.compactStatusTitle())
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .kerning(-0.45)
                    .foregroundStyle(statusTextColor.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(width: 66)
                    .blur(radius: 0.55)
            )
    }

    private var statusTitleGlass: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        statusTextColor.opacity(0.095),
                        Color.white.opacity(0.16),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .blendMode(.screen)
            )
    }

    private var statusTitleRim: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42),
                        statusTextColor.opacity(0.22),
                        Color.white.opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
    }

    private var countStack: some View {
        VStack(spacing: 4) {
            countRow(label: "运", value: viewModel.runningDisplayCount())
            countRow(label: "验", value: viewModel.pendingDisplayCount())
            countRow(label: "观", value: viewModel.observedDisplayCount())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: 60)
        .background(countGlassWell)
        .overlay(countGlassRim)
        .overlay(countGlassAirLayer)
    }

    private var countGlassWell: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(EdgeRailLiquidGlassParameters.infoPanelAlpha),
                        Color(hex: "#EBF7FF").opacity(0.086),
                        Color.white.opacity(0.050)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Capsule(style: .continuous)
                        .fill(EdgeRailGlassOptics.refractiveBlueGray.opacity(0.024))
                        .frame(height: 2.5)
                        .blur(radius: 1.2)
                        .padding(.horizontal, 7)
                        .padding(.bottom, 1)
                }
            )
    }

    private var countGlassRim: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.60),
                        Color.white.opacity(0.18),
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.042)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
    }

    private var countGlassAirLayer: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .inset(by: 1.2)
            .stroke(Color.white.opacity(0.20), lineWidth: 1)
            .blur(radius: 0.8)
    }

    private func countRow(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11.0, weight: .black, design: .rounded))
                .foregroundStyle(EdgeRailGlassText.countLabel)
                .frame(width: 15, alignment: .leading)
            Text("\(value)")
                .font(.system(size: 12.4, weight: .black, design: .rounded))
                .foregroundStyle(EdgeRailGlassText.countValue)
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)
        }
        .frame(width: 42, alignment: .center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var edgeQuota: some View {
        VStack(spacing: 3) {
            Text("⚡")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.quotaBolt)

            Text(String(viewModel.quotaCompactText().dropFirst()))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(viewModel.quotaIsCritical() ? LuckyCatTokens.Palette.red : EdgeRailGlassText.quotaNumber)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
                .frame(width: 46)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: 58)
        .background(quotaGlassGroove)
        .overlay(quotaGrooveRim)
    }

    @ViewBuilder
    private var quotaGlassGroove: some View {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.26))
                .glassEffect(.clear.interactive(false), in: Capsule(style: .continuous))
                .overlay(quotaGrooveDepth)
        } else {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                Color.white.opacity(0.22),
                                Color(hex: "#FFF7EA").opacity(0.095),
                                Color.white.opacity(0.055)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        )
                )
                .overlay(quotaGrooveDepth)
        }
    }

    private var quotaGrooveDepth: some View {
        Capsule(style: .continuous)
            .inset(by: 1)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.30),
                        Color(hex: "#E7DCCF").opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var quotaGrooveRim: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.44),
                        LuckyCatTokens.Palette.quotaDivider.opacity(0.92),
                        Color.white.opacity(0.24)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var railDivider: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.30))
            .frame(width: 34, height: 1)
    }

    private var statusTextColor: Color {
        switch status {
        case .blocked:
            return LuckyCatTokens.Palette.red
        case .running:
            return Color(hex: "#4BB6FF")
        case .pending:
            return Color(hex: "#B87916")
        case .done:
            return Color(hex: "#72DB93")
        case .observed:
            return Color(hex: "#33C0D8")
        case .idle:
            return Color(hex: "#4D5B66")
        }
    }
}
