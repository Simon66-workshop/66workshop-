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
    @State private var showsMatrix = true

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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MacOSKitGlass.textPrimary)
                    Text("正在载入状态预览")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MacOSKitGlass.textSecondary)
                }
                .padding(22)
                .macOSKitGlassCard(cornerRadius: 24)
            }
        }
        .frame(minWidth: 820, minHeight: 680)
    }
}

private struct LuckyCatVisualScenarioCard: View {
    let scenario: LuckyCatPreviewScenario
    private var presentation: LuckyCatVisualScenarioPresentation {
        LuckyCatVisualScenarioPresentation(uiState: scenario.uiState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(scenario.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(MacOSKitGlass.textPrimary)
                Spacer()
                Text(presentation.menuBarStatusTitle)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MacOSKitGlass.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(matrixChipBackground)
            }
            HStack(alignment: .center, spacing: 18) {
                previewSurface(title: "浅色", style: .light) {
                    LightweightLuckyCatPreview(presentation: presentation)
                        .frame(width: 132, height: 104)
                }
                previewSurface(title: "胶囊玻璃", style: .glassCapsule) {
                    LightweightEdgeRailPreview(presentation: presentation)
                        .frame(width: 58, height: 126)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.threadSummary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacOSKitGlass.textPrimary)
                    Text(presentation.quotaCompactText)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(presentation.quotaIsCritical ? LuckyCatTokens.Palette.red : MacOSKitGlass.textPrimary)
                    Text("Quota Pace: \(presentation.quotaPaceSummary)")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(MacOSKitGlass.textSecondary)
                    Text("Hooks Doctor: \(presentation.hooksDoctorBadge)")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(MacOSKitGlass.textSecondary)
                    Text(presentation.diagnosticSummary)
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(MacOSKitGlass.textSecondary)
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
        .background(matrixCardBackground)
    }

    private enum PreviewSurfaceStyle {
        case light
        case glassCapsule
    }

    private func previewSurface<Content: View>(title: String, style: PreviewSurfaceStyle, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MacOSKitGlass.textSecondary)
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
                .fill(Color.white.opacity(0.16))
        case .glassCapsule:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.18))
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
            .foregroundStyle(MacOSKitGlass.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(matrixChipBackground)
    }

    private var matrixCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.70),
                        Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.52),
                        Color.white.opacity(0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.76),
                            Color(red: 0.77, green: 0.86, blue: 0.94).opacity(0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            )
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.34)
                )
                .clipShape(shape)
            )
    }

    private var matrixChipBackground: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.56),
                        Color(red: 0.90, green: 0.96, blue: 1.0).opacity(0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.48), lineWidth: 0.7)
            )
    }
}

private struct LuckyCatVisualScenarioPresentation {
    let uiState: TaskLightUIState

    var running: Int {
        uiState.counts.running + uiState.counts.queued
    }

    var pending: Int {
        uiState.counts.pending_verify_count
    }

    var observed: Int {
        uiState.counts.observed_active
    }

    var statusTitle: String {
        let title = TaskLightProjectedPresentation.displayTitle(from: uiState)
        switch title.uppercased() {
        case "RUNNING": return "Running"
        case "BLOCKED": return "Blocked"
        case "PENDING": return "Pending"
        case "DONE": return "Done"
        case "IDLE": return "Idle"
        default:
            return title.prefix(1).uppercased() + title.dropFirst().lowercased()
        }
    }

    var shortStatusTitle: String {
        switch statusTitle {
        case "Running": return "Run"
        case "Pending": return "Pend"
        case "Blocked": return "Block"
        default: return statusTitle
        }
    }

    var visualStatus: LuckyCatVisualStatus {
        switch TaskLightProjectedPresentation.primaryStatus(from: uiState) {
        case "blocked", "stale":
            return .blocked
        case "running":
            return .running
        case "pending", "done_unverified":
            return .pending
        case "done_verified":
            return .done
        default:
            return observed > 0 ? .observed : .idle
        }
    }

    var statusColor: Color {
        switch visualStatus {
        case .running:
            return LuckyCatTokens.Palette.blue
        case .blocked:
            return LuckyCatTokens.Palette.red
        case .pending:
            return LuckyCatTokens.Palette.amber
        case .done:
            return LuckyCatTokens.Palette.green
        case .observed:
            return LuckyCatTokens.Palette.cyan
        case .idle:
            return LuckyCatTokens.Palette.idleGray
        }
    }

    var threadSummary: String {
        "运行 \(running) · 待验 \(pending) · 观察 \(observed)"
    }

    var menuBarStatusTitle: String {
        "● \(shortStatusTitle) \(running + pending + observed)  \(quotaCompactText)"
    }

    var quotaCompactText: String {
        guard let quota = uiState.quota, quota.fresh else {
            return "⚡Q?"
        }
        var parts: [String] = []
        var seenValues = Set<Int>()
        for value in [quota.short_percent, quota.long_percent, quota.effective_remaining_percent].compactMap({ $0 }) {
            guard seenValues.insert(value).inserted else { continue }
            parts.append("\(value)")
        }
        if let resets = quota.manual_resets_available {
            parts.append("R\(resets)")
        }
        return parts.isEmpty ? "⚡Q?" : "⚡" + parts.joined(separator: "·")
    }

    var quotaIsCritical: Bool {
        guard let quota = uiState.quota else { return false }
        let values = [quota.short_percent, quota.long_percent, quota.effective_remaining_percent].compactMap { $0 }
        guard let minimum = values.min() else { return false }
        return minimum < 20
    }

    var quotaPaceSummary: String {
        if quotaIsCritical {
            return "低额度红字"
        }
        guard uiState.quota?.fresh == true else {
            return "Quota 数据不足"
        }
        return "预览 · burn-rate fixture"
    }

    var hooksDoctorBadge: String {
        switch uiState.diagnostics.writer_status {
        case "ok":
            return "trusted"
        case "old_writer":
            return "old writer"
        case "multiple_writers":
            return "multiple projector"
        default:
            return uiState.diagnostics.writer_status ?? "no report"
        }
    }

    var diagnosticSummary: String {
        let writer = uiState.diagnostics.writer_status ?? "unknown"
        let hook = uiState.diagnostics.hook_bridge_status ?? "unknown"
        let signal = uiState.diagnostics.signal_bus_status ?? "unknown"
        return "Writer=\(writer) · Hook Bridge=\(hook) · Signal=\(signal)"
    }
}

private struct LightweightLuckyCatPreview: View {
    let presentation: LuckyCatVisualScenarioPresentation

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FAD7E5").opacity(0.74),
                            Color(hex: "#EFC2D8").opacity(0.42),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.44), lineWidth: 1)
                )

            HStack(spacing: 5) {
                ForEach(pawCounts, id: \.label) { item in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(item.color.opacity(item.count > 0 ? 0.70 : 0.24))
                            .frame(width: 17, height: 17)
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.7))
                        Text("\(item.count)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.92))
                        Text(item.label)
                            .font(.system(size: 5.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.74))
                    }
                    .frame(width: 20, height: 39)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                }
            }
            .padding(.bottom, 25)

            VStack(spacing: 2) {
                Text("66")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(presentation.statusTitle)
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(MacOSKitGlass.coldShadow.opacity(0.16)))
            }
            .padding(.bottom, 3)
        }
        .overlay(alignment: .topLeading) {
            Triangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 24, height: 22)
                .offset(x: 16, y: -3)
        }
        .overlay(alignment: .topTrailing) {
            Triangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 24, height: 22)
                .offset(x: -16, y: -3)
        }
    }

    private var pawCounts: [(label: String, count: Int, color: Color)] {
        [
            ("阻", uiStateBlocked, LuckyCatTokens.Palette.red),
            ("跑", presentation.running, LuckyCatTokens.Palette.blue),
            ("验", presentation.pending, LuckyCatTokens.Palette.amber),
            ("观", presentation.observed, LuckyCatTokens.Palette.cyan)
        ]
    }

    private var uiStateBlocked: Int {
        presentation.uiState.counts.blocked + presentation.uiState.counts.stale
    }
}

private struct LightweightEdgeRailPreview: View {
    let presentation: LuckyCatVisualScenarioPresentation

    var body: some View {
        VStack(spacing: 5) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            presentation.statusColor.opacity(0.74),
                            presentation.statusColor.opacity(0.34)
                        ],
                        center: UnitPoint(x: 0.30, y: 0.22),
                        startRadius: 2,
                        endRadius: 24
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Color.white.opacity(0.62), lineWidth: 1))
                .shadow(color: presentation.statusColor.opacity(0.20), radius: 5, y: 3)

            Text(presentation.statusTitle)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(presentation.statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            VStack(spacing: 1) {
                countLine("运", presentation.running)
                countLine("验", presentation.pending)
                countLine("观", presentation.observed)
            }
            .font(.system(size: 6.5, weight: .black))
            .foregroundStyle(MacOSKitGlass.textPrimary.opacity(0.78))

            Text(presentation.quotaCompactText)
                .font(.system(size: 7.2, weight: .black, design: .rounded))
                .foregroundStyle(presentation.quotaIsCritical ? LuckyCatTokens.Palette.red : MacOSKitGlass.textPrimary.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.30)))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 7)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            Color(hex: "#EAF6FF").opacity(0.30),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.58), lineWidth: 0.9))
        )
    }

    private func countLine(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
            Text("\(value)")
                .monospacedDigit()
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private var matrixBackground: some View {
    MacOSKitGlassBackground()
}
