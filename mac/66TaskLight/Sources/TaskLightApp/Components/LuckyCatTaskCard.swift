import SwiftUI
import TaskLightCore

struct LuckyCatTaskCard: View {
    let task: TaskLightTaskSummary

    private var visualStatus: LuckyCatVisualStatus {
        LuckyCatStatusStyle.taskStatus(from: task)
    }

    private var statusLabel: String {
        switch task.effective_status {
        case TaskLightStatus.blocked.rawValue:
            return "BLOCKED"
        case TaskLightStatus.stale.rawValue:
            return "STALE"
        case TaskLightStatus.running.rawValue:
            return "RUNNING"
        case TaskLightStatus.queued.rawValue:
            return "QUEUED"
        case TaskLightStatus.done_unverified.rawValue:
            return "待验收"
        case TaskLightStatus.done_verified.rawValue:
            return "DONE"
        case TaskLightStatus.cancelled.rawValue:
            return "CANCELLED"
        default:
            return task.effective_status.uppercased()
        }
    }

    private var detailLine: String {
        if let message = task.message, !message.isEmpty {
            return message
        }
        if let summary = task.summary, !summary.isEmpty {
            return summary
        }
        if let lastError = task.last_error, !lastError.isEmpty {
            return lastError
        }
        return task.phase ?? task.short_task_id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                LuckyCatStatusOrb(status: visualStatus, size: 16, pulsing: visualStatus == .running)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center) {
                        Text(task.title)
                            .font(LuckyCatTokens.Typography.taskTitle)
                            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        statusPill
                    }

                    Text(detailLine)
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                        .lineLimit(2)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                if let phase = task.phase, !phase.isEmpty {
                    Text(phase)
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                }
                if let progress = task.progress {
                    progressBar(value: progress)
                        .frame(width: 110)
                }
                Spacer(minLength: 0)
                Text(task.updated_at ?? task.started_at ?? task.created_at ?? "n/a")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: LuckyCatLayout.taskCardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.56), lineWidth: 1)
        )
    }

    private var statusPill: some View {
        Text(statusLabel)
            .font(LuckyCatTokens.Typography.statusPill)
            .foregroundStyle(visualStatus == .pending ? LuckyCatTokens.Palette.textPrimary : Color.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(visualStatus.tint.opacity(visualStatus == .pending ? 0.82 : 0.95))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: LuckyCatLayout.taskCardCornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: LuckyCatLayout.taskCardCornerRadius, style: .continuous)
                    .fill(visualStatus.tint.opacity(0.06))
            )
    }

    private func progressBar(value: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(height: 6)
            Capsule(style: .continuous)
                .fill(visualStatus.tint)
                .frame(width: max(6, min(110, value * 110)), height: 6)
        }
    }
}
