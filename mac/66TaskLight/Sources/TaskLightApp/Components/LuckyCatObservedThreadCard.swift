import SwiftUI
import TaskLightCore

struct LuckyCatObservedThreadCard: View {
    let thread: TaskLightObservationRecord
    var scrollOptimized: Bool = false

    private var visualStatus: LuckyCatVisualStatus {
        LuckyCatStatusStyle.observationStatus(from: thread)
    }

    private var statusText: String {
        switch TaskLightObservationStatus(rawValue: thread.status) {
        case .observed_attention:
            return "ATTENTION"
        case .observed_quiet:
            return "QUIET"
        case .observed_active:
            return "OBSERVED"
        default:
            return "OBSERVED"
        }
    }

    private var footerText: String {
        var parts: [String] = ["pid \(thread.pid)"]
        if let elapsed = thread.elapsedSeconds() {
            parts.append("elapsed \(elapsed)s")
        }
        if let lastSeen = thread.last_seen_at {
            parts.append("seen \(lastSeen)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                LuckyCatStatusOrb(
                    status: visualStatus,
                    size: 16,
                    pulsing: !scrollOptimized && visualStatus == .observed,
                    showsGlow: !scrollOptimized
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center) {
                        Text(thread.title)
                            .font(LuckyCatTokens.Typography.taskTitle)
                            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(statusText)
                            .font(LuckyCatTokens.Typography.statusPill)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule(style: .continuous).fill(visualStatus.tint.opacity(0.92)))
                    }
                    Text("未接管，仅显示活跃状态")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                }
            }

            HStack(alignment: .center) {
                Text(thread.command_short)
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(String(format: "confidence %.2f", thread.confidence))
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            }

            Text(footerText)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: LuckyCatLayout.observedCardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.52), lineWidth: 1)
        )
        .opacity(0.9)
    }

    private var cardBackground: some View {
        Group {
            if scrollOptimized {
                RoundedRectangle(cornerRadius: LuckyCatLayout.observedCardCornerRadius, style: .continuous)
                    .fill(LuckyCatTokens.Palette.glass.opacity(0.66))
            } else {
                RoundedRectangle(cornerRadius: LuckyCatLayout.observedCardCornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: LuckyCatLayout.observedCardCornerRadius, style: .continuous)
                .fill(visualStatus.tint.opacity(scrollOptimized ? 0.035 : 0.05))
        )
    }
}
