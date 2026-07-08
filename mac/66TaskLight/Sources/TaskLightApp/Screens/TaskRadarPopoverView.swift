import SwiftUI
import TaskLightCore

struct TaskRadarPopoverView: View {
    @ObservedObject var viewModel: TaskLightViewModel
    let onOpenVisualMatrix: (() -> Void)?

    init(viewModel: TaskLightViewModel, onOpenVisualMatrix: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenVisualMatrix = onOpenVisualMatrix
    }

    private var activeTasks: [TaskLightTaskSummary] {
        viewModel.taskRadarActiveTasks()
    }

    private var observedThreads: [TaskLightObservationRecord] {
        viewModel.taskRadarObservedThreads()
    }

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quotaCard
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    taskSection
                    observedSection
                    diagnosticsSection
                }
                .padding(.trailing, 4)
            }
        }
        .padding(16)
        .frame(width: 390, height: 540, alignment: .topLeading)
        .background(radarBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            LuckyCatStatusOrb(status: status, size: 34, pulsing: status == .running, showsGlow: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.compactStatusTitle())
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                Text(viewModel.edgeRailThreadSummary())
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            }
            Spacer(minLength: 0)
            if let onOpenVisualMatrix {
                Button(action: onOpenVisualMatrix) {
                    Label("矩阵", systemImage: "square.grid.2x2")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.36)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                .help("打开视觉状态矩阵")
            }
            Text(viewModel.menuBarStatusTitle())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.38)))
        }
    }

    private var quotaCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(viewModel.quotaCompactText())
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(viewModel.quotaIsCritical() ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textPrimary)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Usage")
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                Text("Quota is diagnostic only; main lamp remains ui_state driven.")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(viewModel.quotaStatusLabel())
                .font(LuckyCatTokens.Typography.statusPill)
                .foregroundStyle(viewModel.quotaIsCritical() ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textSecondary)
        }
        .padding(12)
        .background(glassCard(cornerRadius: 18))
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Active Managed Tasks", subtitle: "\(activeTasks.count)")
            if activeTasks.isEmpty {
                emptyRow("No active managed task")
            } else {
                ForEach(Array(activeTasks.prefix(6))) { task in
                    radarTaskRow(task)
                }
            }
        }
    }

    private var observedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Observed Threads", subtitle: "\(observedThreads.count)")
            if observedThreads.isEmpty {
                emptyRow("No visible observed thread")
            } else {
                Text("Observed threads are diagnostics only; they do not prove managed RUNNING by themselves.")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                ForEach(Array(observedThreads.prefix(4))) { thread in
                    radarObservedRow(thread)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Diagnostics", subtitle: viewModel.uiState.source)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(viewModel.taskRadarDiagnosticRows()) { row in
                    diagnosticPill(row)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(LuckyCatTokens.Typography.sectionLabel)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            Spacer()
            Text(subtitle)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
        }
    }

    private func radarTaskRow(_ task: TaskLightTaskSummary) -> some View {
        HStack(alignment: .top, spacing: 9) {
            LuckyCatStatusOrb(status: LuckyCatStatusStyle.taskStatus(from: task), size: 14, pulsing: false, showsGlow: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                Text([task.effective_status, task.phase, task.message ?? task.summary].compactMap { $0 }.joined(separator: " · "))
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(glassCard(cornerRadius: 14))
    }

    private func radarObservedRow(_ thread: TaskLightObservationRecord) -> some View {
        HStack(alignment: .top, spacing: 9) {
            LuckyCatStatusOrb(status: LuckyCatStatusStyle.observationStatus(from: thread), size: 14, pulsing: false, showsGlow: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                Text("\(thread.command_short) · confidence \(String(format: "%.2f", thread.confidence))")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(glassCard(cornerRadius: 14))
    }

    private func diagnosticPill(_ row: TaskRadarDiagnosticRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.label.uppercased())
                .font(LuckyCatTokens.Typography.statusPill)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            Text(row.value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(severityColor(row.severity))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassCard(cornerRadius: 13))
    }

    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .font(LuckyCatTokens.Typography.taskMeta)
            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(glassCard(cornerRadius: 14))
    }

    private func severityColor(_ severity: TaskRadarDiagnosticSeverity) -> Color {
        switch severity {
        case .ok:
            return LuckyCatTokens.Palette.green
        case .warning:
            return LuckyCatTokens.Palette.amber
        case .attention:
            return LuckyCatTokens.Palette.red
        case .unknown:
            return LuckyCatTokens.Palette.textPrimary.opacity(0.74)
        }
    }

    private func glassCard(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.44), lineWidth: 1)
            )
    }

    private var radarBackground: some View {
        LinearGradient(
            colors: [
                LuckyCatTokens.Palette.cream.opacity(0.82),
                Color(red: 0.88, green: 0.95, blue: 1.0).opacity(0.68),
                LuckyCatTokens.Palette.glassRoseTint.opacity(0.36)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(.ultraThinMaterial.opacity(0.64))
    }
}
