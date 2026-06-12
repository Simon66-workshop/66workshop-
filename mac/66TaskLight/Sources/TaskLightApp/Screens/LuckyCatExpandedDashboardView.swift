import SwiftUI
import TaskLightCore

struct LuckyCatExpandedDashboardView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    private var displayTitle: String {
        viewModel.luckyCatPresentationTitle()
    }

    var body: some View {
        LuckyCatGlassPanel(status: status) {
            VStack(alignment: .leading, spacing: 14) {
                headerBar

                HStack(alignment: .top, spacing: 18) {
                    sidebar
                        .frame(width: LuckyCatLayout.expandedSidebarWidth)

                    VStack(alignment: .leading, spacing: 14) {
                        summaryStrip

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                sectionHeader("Managed Tasks", subtitle: "\(viewModel.sortedManagedTasks().count) visible")
                                if viewModel.sortedManagedTasks().isEmpty {
                                    Text("No managed tasks")
                                        .font(LuckyCatTokens.Typography.taskMeta)
                                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                                        .padding(.top, 4)
                                } else {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(viewModel.sortedManagedTasks()) { task in
                                            LuckyCatTaskCard(task: task)
                                        }
                                    }
                                }

                                if !viewModel.invalidManagedTasks().isEmpty {
                                    sectionHeader("Invalid Task JSON", subtitle: "\(viewModel.invalidManagedTasks().count) isolated")
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(viewModel.invalidManagedTasks()) { task in
                                            LuckyCatTaskCard(task: task)
                                        }
                                    }
                                }

                                sectionHeader("Live Observed Threads", subtitle: "\(viewModel.visibleObservedThreads().count) active")
                                if viewModel.visibleObservedThreads().isEmpty {
                                    Text("No live observed threads")
                                        .font(LuckyCatTokens.Typography.taskMeta)
                                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                                        .padding(.top, 4)
                                } else {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(viewModel.visibleObservedThreads()) { thread in
                                            LuckyCatObservedThreadCard(thread: thread)
                                        }
                                    }
                                }
                            }
                            .padding(.trailing, 2)
                        }
                    }
                }
            }
        }
        .frame(width: LuckyCatLayout.expandedWidth, height: LuckyCatLayout.expandedHeight)
    }

    private var headerBar: some View {
        HStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LuckyCatTokens.Palette.goldDeep, LuckyCatTokens.Palette.gold],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)
                .overlay(
                    VStack(spacing: -2) {
                        Text("66")
                        Text("VS")
                    }
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                )

            Spacer()

            HStack(spacing: 14) {
                Image(systemName: "minus")
                Image(systemName: "xmark")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(LuckyCatTokens.Palette.textPrimary.opacity(0.82))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            LuckyCatMascotView(status: status, large: true)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(LuckyCatTokens.Typography.title)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                Text("M\(viewModel.managedActiveCount()) · O\(viewModel.observedDisplayCount())")
                    .font(LuckyCatTokens.Typography.subtitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                Text(viewModel.luckyCatExpandedStatusText())
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(3)
                Text(viewModel.stateSourceDiagnosticLabel())
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                    .lineLimit(4)
                Text(viewModel.currentThreadDiagnosticLabel())
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                    .lineLimit(3)
                Text(viewModel.bridgeHealthDiagnosticLabel())
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 10) {
                sidebarTab(icon: "house", title: "总览", selected: true)
                sidebarTab(icon: "checklist", title: "任务")
                sidebarTab(icon: "clock", title: "事件")
                sidebarTab(icon: "gearshape", title: "设置")
            }
            .padding(.top, 4)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 14) {
            LuckyCatSummaryBubble(status: .blocked, count: viewModel.blockedDisplayCount(), label: "阻塞")
            LuckyCatSummaryBubble(status: .running, count: viewModel.runningDisplayCount(), label: "运行")
            LuckyCatSummaryBubble(status: .done, count: viewModel.doneDisplayCount(), label: "完成")
            LuckyCatSummaryBubble(status: .pending, count: viewModel.pendingDisplayCount(), label: "待验收")
            LuckyCatSummaryBubble(status: .observed, count: viewModel.observedDisplayCount(), label: "观察")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.36))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.18), radius: 12, x: 0, y: 5)
        )
    }

    private func sidebarTab(icon: String, title: String, selected: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 16)
            Text(title)
        }
        .font(.system(size: 14, weight: selected ? .semibold : .regular, design: .rounded))
        .foregroundStyle(selected ? LuckyCatTokens.Palette.textPrimary : LuckyCatTokens.Palette.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.white.opacity(0.55) : Color.clear)
        )
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(LuckyCatTokens.Typography.sectionLabel)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            Spacer(minLength: 0)
            Text(subtitle)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
        }
    }
}

private struct LuckyCatSummaryBubble: View {
    let status: LuckyCatVisualStatus
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                status.tint.opacity(0.34),
                                status.tint.opacity(0.12)
                            ],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: 28
                        )
                    )
                    .frame(width: 50, height: 50)
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(status.tint)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}
