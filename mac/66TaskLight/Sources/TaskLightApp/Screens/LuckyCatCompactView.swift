import SwiftUI
import TaskLightCore

struct LuckyCatCompactView: View {
    @ObservedObject var viewModel: TaskLightViewModel
    @State private var entranceVisible = false

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    var body: some View {
        ZStack {
            LuckyCatCompactShell(
                status: status,
                progress: viewModel.compactProgressValue(),
                highlightsBell: viewModel.compactShowsAlertBell(),
                statusTitle: viewModel.compactStatusTitle(),
                elapsedLabel: quotaPresentation.fullLabel,
                elapsedLeadingSymbol: quotaPresentation.leadingSymbol,
                elapsedValueText: quotaPresentation.valueText,
                elapsedLabelColor: quotaPresentation.textColor,
                elapsedStatusDotColor: quotaFreshnessDotColor,
                weakRuntimeHint: viewModel.weakRuntimeHintText(),
                onNoseTripleTap: {
                    viewModel.runWorkspaceCoverageReport()
                }
            ) {
                ZStack {
                    HStack(spacing: 8) {
                        CompactPhasePaw(
                            label: "阻塞",
                            status: .blocked,
                            count: viewModel.blockedDisplayCount(),
                            isPrimary: viewModel.compactActivePaw() == .problem
                        )
                        CompactPhasePaw(
                            label: "运行",
                            status: .running,
                            count: viewModel.runningDisplayCount(),
                            isPrimary: viewModel.compactActivePaw() == .executing
                        )
                        CompactPhasePaw(
                            label: "完成",
                            status: .done,
                            count: viewModel.visibleDoneDisplayCount(),
                            isPrimary: viewModel.compactActivePaw() == .complete
                        )
                        CompactPhasePaw(
                            label: "待验",
                            status: .pending,
                            count: viewModel.pendingDisplayCount(),
                            isPrimary: viewModel.compactActivePaw() == .toVerify
                        )
                        CompactPhasePaw(
                            label: "观察",
                            status: .observed,
                            count: viewModel.observedDisplayCount(),
                            isPrimary: viewModel.compactActivePaw() == .recon
                        )
                    }
                    .frame(width: 286, height: 106)
                    .position(x: 182, y: 176)
                }
            }
            .frame(width: LuckyCatLayout.compactCanvasWidth, height: LuckyCatLayout.compactCanvasHeight)
            .scaleEffect(LuckyCatLayout.compactScale, anchor: .center)
            .frame(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)

            if let coverage = viewModel.workspaceCoveragePresentation {
                LuckyCatReportBubbleView(presentation: coverage) {
                    viewModel.openWorkspaceCoverageReport()
                }
                .transition(AnyTransition.scale(scale: 0.92).combined(with: AnyTransition.opacity))
                .position(x: LuckyCatLayout.compactWidth / 2, y: LuckyCatLayout.compactHeight - 18)
                .zIndex(20)
            }
        }
        .frame(width: LuckyCatLayout.compactWidth, height: LuckyCatLayout.compactHeight)
        .opacity(entranceVisible ? 1 : 0.96)
        .scaleEffect(entranceVisible ? 1 : 0.985, anchor: .center)
        .animation(.easeInOut(duration: 0.18), value: viewModel.workspaceCoveragePresentation?.message)
        .onAppear {
            entranceVisible = false
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.10)) {
                    entranceVisible = true
                }
            }
        }
    }

    private var quotaPresentation: QuotaCompactPresentation {
        QuotaCompactPresentation(
            fullLabel: viewModel.quotaCompactText(),
            isCritical: viewModel.quotaIsCritical()
        )
    }

    private var quotaFreshnessDotColor: Color {
        guard let quota = viewModel.uiState.quota else {
            return LuckyCatTokens.Palette.textSecondary.opacity(0.52)
        }
        return quota.fresh ? LuckyCatTokens.Palette.green.opacity(0.92) : LuckyCatTokens.Palette.textSecondary.opacity(0.52)
    }

}

private struct QuotaCompactPresentation {
    let fullLabel: String
    let isCritical: Bool

    var leadingSymbol: String {
        fullLabel.hasPrefix("⚡") ? "⚡" : ""
    }

    var valueText: String {
        guard fullLabel.hasPrefix("⚡") else {
            return fullLabel
        }
        return String(fullLabel.dropFirst())
    }

    var textColor: Color {
        isCritical ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.quotaNumberLight
    }
}

private struct LuckyCatReportBubbleView: View {
    let presentation: TaskLightWorkspaceCoveragePresentation
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(presentation.isError ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.gold)
                .frame(width: 7, height: 7)

            Text(presentation.message)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("报告")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.goldDeep)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(maxWidth: 238)
        .background(
            BubbleShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            LuckyCatTokens.Palette.cream.opacity(0.93),
                            LuckyCatTokens.Palette.creamDeep.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.22), radius: 8, x: 0, y: 4)
        )
        .overlay(
            BubbleShape()
                .stroke(Color.white.opacity(0.66), lineWidth: 1)
        )
        .contentShape(BubbleShape())
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    onTap()
                }
        )
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bubbleRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 5)
        path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: 13, height: 13))
        path.move(to: CGPoint(x: rect.midX - 8, y: bubbleRect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + 8, y: bubbleRect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

private struct BeaconHousing: View {
    let status: LuckyCatVisualStatus

    var body: some View {
        ZStack {
            housingSinkShadow
            housingBase
                .overlay(housingOuterStroke)
                .overlay(housingGlow)
                .overlay(housingInsetRim)
                .overlay(housingInnerSoftEdge)
                .overlay(housingInnerWarmDepth)
                .overlay(housingInnerShadow)
                .overlay(housingSheen)
                .overlay(housingSpecular)
                .overlay(housingFinalRim)

            HStack(spacing: 5) {
                Capsule().fill(LuckyCatTokens.Palette.red.opacity(0.84)).frame(width: 12, height: 3).rotationEffect(.degrees(-16))
                Capsule().fill(LuckyCatTokens.Palette.red.opacity(0.84)).frame(width: 14, height: 3)
                Capsule().fill(LuckyCatTokens.Palette.red.opacity(0.84)).frame(width: 12, height: 3).rotationEffect(.degrees(16))
            }
            .rotationEffect(.degrees(-90))
            .offset(x: -55, y: 18)
        }
        .shadow(color: status.glow.opacity(0.18), radius: 14, x: 0, y: 0)
    }

    private var housingBase: some View {
        BeaconHousingShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        LuckyCatTokens.Palette.cream.opacity(0.9),
                        LuckyCatTokens.Palette.creamDeep.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 116, height: 100)
    }

    private var housingSinkShadow: some View {
        BeaconHousingShape()
            .fill(
                LinearGradient(
                    colors: [
                        LuckyCatTokens.Palette.shadow.opacity(0.24),
                        LuckyCatTokens.Palette.shadow.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
            )
            .frame(width: 122, height: 106)
            .blur(radius: 7)
            .offset(x: -2, y: 4)
    }

    private var housingOuterStroke: some View {
        BeaconHousingShape()
            .stroke(Color.white.opacity(0.68), lineWidth: 1)
    }

    private var housingGlow: some View {
        BeaconHousingShape()
            .stroke(status.glow.opacity(0.18), lineWidth: 8)
            .blur(radius: 8)
    }

    private var housingInsetRim: some View {
        BeaconHousingShape()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.82),
                        LuckyCatTokens.Palette.creamDeep.opacity(0.62),
                        status.glow.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 6
            )
            .padding(7)
            .blur(radius: 0.4)
    }

    private var housingInnerSoftEdge: some View {
        BeaconHousingShape()
            .stroke(Color.white.opacity(0.40), lineWidth: 9)
            .padding(15)
            .blur(radius: 0.9)
    }

    private var housingInnerWarmDepth: some View {
        BeaconHousingShape()
            .stroke(LuckyCatTokens.Palette.creamDeep.opacity(0.38), lineWidth: 12)
            .padding(18)
            .blur(radius: 2.4)
    }

    private var housingInnerShadow: some View {
        BeaconHousingShape()
            .stroke(LuckyCatTokens.Palette.shadow.opacity(0.26), lineWidth: 15)
            .padding(20)
            .blur(radius: 4.6)
            .blendMode(.multiply)
    }

    private var housingSheen: some View {
        BeaconHousingShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(18)
    }

    private var housingSpecular: some View {
        BeaconHousingShape()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 2,
                    endRadius: 38
                )
            )
            .padding(20)
    }

    private var housingFinalRim: some View {
        BeaconHousingShape()
            .stroke(Color.white.opacity(0.24), lineWidth: 5)
            .padding(23)
            .blur(radius: 0.8)
    }
}

private struct BeaconHousingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX + 7
        let right = rect.maxX - 7
        let top = rect.minY + 27
        let bottom = rect.maxY - 4
        let leftEarBase = CGPoint(x: rect.minX + 26, y: top + 1)
        let leftEarPeak = CGPoint(x: rect.minX + 34, y: rect.minY + 7)
        let rightEarPeak = CGPoint(x: rect.maxX - 34, y: rect.minY + 7)
        let rightEarBase = CGPoint(x: rect.maxX - 26, y: top + 1)

        path.move(to: CGPoint(x: left + 10, y: bottom))
        path.addCurve(
            to: CGPoint(x: left, y: rect.midY + 8),
            control1: CGPoint(x: left - 6, y: bottom - 8),
            control2: CGPoint(x: left - 1, y: rect.maxY - 24)
        )
        path.addCurve(
            to: leftEarBase,
            control1: CGPoint(x: left + 1, y: rect.midY - 14),
            control2: CGPoint(x: rect.minX + 14, y: top + 10)
        )
        path.addCurve(
            to: leftEarPeak,
            control1: CGPoint(x: rect.minX + 25, y: top - 9),
            control2: CGPoint(x: rect.minX + 29, y: rect.minY + 8)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: top),
            control1: CGPoint(x: rect.minX + 40, y: rect.minY + 4),
            control2: CGPoint(x: rect.midX - 20, y: rect.minY + 12)
        )
        path.addCurve(
            to: rightEarPeak,
            control1: CGPoint(x: rect.midX + 20, y: rect.minY + 12),
            control2: CGPoint(x: rect.maxX - 40, y: rect.minY + 4)
        )
        path.addCurve(
            to: rightEarBase,
            control1: CGPoint(x: rect.maxX - 29, y: rect.minY + 8),
            control2: CGPoint(x: rect.maxX - 25, y: top - 9)
        )
        path.addCurve(
            to: CGPoint(x: right, y: rect.midY + 8),
            control1: CGPoint(x: rect.maxX - 14, y: top + 10),
            control2: CGPoint(x: right - 1, y: rect.midY - 14)
        )
        path.addCurve(
            to: CGPoint(x: right - 10, y: bottom),
            control1: CGPoint(x: right + 2, y: rect.maxY - 21),
            control2: CGPoint(x: right + 7, y: bottom - 7)
        )
        path.addCurve(
            to: CGPoint(x: left + 10, y: bottom),
            control1: CGPoint(x: rect.midX + 20, y: rect.maxY + 5),
            control2: CGPoint(x: rect.midX - 20, y: rect.maxY + 5)
        )
        path.closeSubpath()
        return path
    }
}

private struct CompactPhasePaw: View {
    let label: String
    let status: LuckyCatVisualStatus
    let count: Int
    let isPrimary: Bool

    var body: some View {
        let hasCount = count > 0
        LuckyCatPawCounterChip(
            status: status,
            count: count,
            label: label,
            isActive: isPrimary
        )
        .scaleEffect(isPrimary ? 1.01 : (hasCount ? 0.98 : 0.94))
        .shadow(
            color: status.tint.opacity(isPrimary ? 0.26 : (hasCount ? 0.16 : 0.06)),
            radius: isPrimary ? 12 : 6,
            x: 0,
            y: 6
        )
    }
}
