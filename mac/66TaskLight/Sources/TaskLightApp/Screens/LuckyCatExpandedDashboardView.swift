import SwiftUI
import TaskLightCore

struct LuckyCatExpandedDashboardView: View {
    private enum Section: String, CaseIterable {
        case overview = "总览"
        case tasks = "任务"
        case events = "事件"
        case settings = "设置"

        var icon: String {
            switch self {
            case .overview: return "house"
            case .tasks: return "checklist"
            case .events: return "clock"
            case .settings: return "gearshape"
            }
        }
    }

    @ObservedObject var viewModel: TaskLightViewModel
    @State private var selectedSection: Section = .overview

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    private var displayTitle: String {
        viewModel.luckyCatPresentationTitle()
    }

    var body: some View {
        let managedTasks = viewModel.sortedManagedTasks()
        let invalidTasks = viewModel.invalidManagedTasks()
        let observedThreads = viewModel.visibleObservedThreads()

        LuckyCatGlassPanel(status: status) {
            VStack(alignment: .leading, spacing: 14) {
                headerBar

                HStack(alignment: .top, spacing: 18) {
                    sidebar
                        .frame(width: LuckyCatLayout.expandedSidebarWidth)

                    VStack(alignment: .leading, spacing: 14) {
                        summaryStrip

                        ScrollView(.vertical, showsIndicators: false) {
                            dashboardContent(managedTasks: managedTasks, invalidTasks: invalidTasks, observedThreads: observedThreads)
                            .padding(.trailing, 2)
                            .transaction { transaction in
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
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
                ForEach(Section.allCases, id: \.self) { section in
                    sidebarTab(section)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func dashboardContent(
        managedTasks: [TaskLightTaskSummary],
        invalidTasks: [TaskLightTaskSummary],
        observedThreads: [TaskLightObservationRecord]
    ) -> some View {
        switch selectedSection {
        case .overview:
            LazyVStack(alignment: .leading, spacing: 14) {
                managedTaskSection(managedTasks)
                invalidTaskSection(invalidTasks)
                observedThreadSection(observedThreads)
            }
        case .tasks:
            LazyVStack(alignment: .leading, spacing: 14) {
                managedTaskSection(managedTasks)
                invalidTaskSection(invalidTasks)
            }
        case .events:
            eventSection(viewModel.recentEvents(limit: TaskLightUIPerformanceBudget.expandedRecentEventLimit))
        case .settings:
            settingsSection
        }
    }

    @ViewBuilder
    private func managedTaskSection(_ managedTasks: [TaskLightTaskSummary]) -> some View {
        sectionHeader("Managed Tasks", subtitle: "\(managedTasks.count) visible")
        if managedTasks.isEmpty {
            emptyText("No managed tasks")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(managedTasks) { task in
                    LuckyCatTaskCard(task: task, scrollOptimized: TaskLightUIPerformanceBudget.expandedScrollUsesOptimizedCards)
                }
            }
        }
    }

    @ViewBuilder
    private func invalidTaskSection(_ invalidTasks: [TaskLightTaskSummary]) -> some View {
        if !invalidTasks.isEmpty {
            sectionHeader("Invalid Task JSON", subtitle: "\(invalidTasks.count) isolated")
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(invalidTasks) { task in
                    LuckyCatTaskCard(task: task, scrollOptimized: TaskLightUIPerformanceBudget.expandedScrollUsesOptimizedCards)
                }
            }
        }
    }

    @ViewBuilder
    private func observedThreadSection(_ observedThreads: [TaskLightObservationRecord]) -> some View {
        sectionHeader("Live Observed Threads", subtitle: "\(observedThreads.count) active")
        if observedThreads.isEmpty {
            emptyText("No live observed threads")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(observedThreads) { thread in
                    LuckyCatObservedThreadCard(thread: thread, scrollOptimized: TaskLightUIPerformanceBudget.expandedScrollUsesOptimizedCards)
                }
            }
        }
    }

    @ViewBuilder
    private func eventSection(_ events: [TaskLightEventRecord]) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            sectionHeader("Events", subtitle: "\(events.count) recent")
            if events.isEmpty {
                emptyText("No events yet")
            } else {
                ForEach(events, id: \.event_id) { event in
                    eventRow(event)
                }
            }
        }
    }

    private var settingsSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            sectionHeader("Settings", subtitle: "local actions")
            settingsButton(title: viewModel.muted ? "恢复声音" : "静音", icon: viewModel.muted ? "speaker.wave.2" : "speaker.slash") {
                viewModel.toggleMute()
            }
            settingsButton(title: "打开事件日志", icon: "doc.text") {
                viewModel.openLog()
            }
            settingsButton(title: "复制阻塞信息", icon: "doc.on.doc") {
                viewModel.copyBlocker()
            }
            settingsButton(title: "运行 workspace 巡检", icon: "magnifyingglass") {
                viewModel.runWorkspaceCoverageReport()
            }
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

    private func sidebarTab(_ section: Section) -> some View {
        let selected = selectedSection == section
        return Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .frame(width: 16)
                Text(section.rawValue)
                Spacer(minLength: 0)
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
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
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

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(LuckyCatTokens.Typography.taskMeta)
            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            .padding(.top, 4)
    }

    private func eventRow(_ event: TaskLightEventRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("\(event.from) -> \(event.to)")
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                Spacer(minLength: 8)
                Text(event.sound_type)
                    .font(LuckyCatTokens.Typography.statusPill)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            }
            Text(event.title ?? event.task_id)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                .lineLimit(1)
            Text(event.created_at)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LuckyCatTokens.Palette.glass.opacity(0.64))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    private func settingsButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.48))
            )
        }
        .buttonStyle(.plain)
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
