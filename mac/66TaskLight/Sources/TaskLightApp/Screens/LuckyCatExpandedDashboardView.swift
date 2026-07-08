import SwiftUI
import TaskLightCore

struct LuckyCatExpandedDashboardView: View {
    fileprivate enum Section: String, CaseIterable {
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
    @State private var renderedSection: Section = .overview
    @State private var navigationSection: Section = .overview
    @State private var cacheKey = ""
    @State private var cachedManagedTasks: [TaskLightTaskSummary] = []
    @State private var cachedInvalidTasks: [TaskLightTaskSummary] = []
    @State private var cachedObservedThreads: [TaskLightObservationRecord] = []
    @State private var cachedEvents: [TaskLightEventRecord] = []
    @State private var cachedManagedTaskTotal = 0
    @State private var cachedInvalidTaskTotal = 0
    @State private var cachedObservedThreadTotal = 0
    @State private var cacheLoading = true
    @State private var overviewTaskVisibleLimit = TaskLightUIPerformanceBudget.expandedOverviewManagedTaskInitialRenderLimit
    @State private var taskPageVisibleLimit = TaskLightUIPerformanceBudget.expandedTaskInitialRenderLimit
    @State private var eventVisibleLimit = TaskLightUIPerformanceBudget.expandedRecentEventInitialRenderLimit
    @State private var lastSectionChangeAt = Date.distantPast
    @State private var cacheRefreshGeneration = 0
    @State private var sectionSwitchGeneration = 0
    @State private var managedTaskCacheLimit = TaskLightUIPerformanceBudget.expandedManagedTaskRenderLimit

    private enum TaskRowStyle {
        case card
        case compact
    }

    private static let cacheRefreshDeferralSeconds: TimeInterval = 0.24

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
                    .frame(height: LuckyCatLayout.expandedHeaderHeight)

                HStack(alignment: .top, spacing: 18) {
                    sidebar
                        .frame(width: LuckyCatLayout.expandedSidebarWidth)
                        .frame(height: LuckyCatLayout.expandedMainHeight, alignment: .top)
                        .clipped()

                    VStack(alignment: .leading, spacing: 14) {
                        summaryStrip
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        prewarmedContentDeck
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .frame(height: LuckyCatLayout.expandedContentScrollHeight, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: LuckyCatLayout.expandedMainHeight, alignment: .topLeading)
                }
                .frame(height: LuckyCatLayout.expandedMainHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: LuckyCatLayout.expandedWidth, height: LuckyCatLayout.expandedHeight)
        .onAppear {
            scheduleInitialContentCacheRefresh()
        }
        .onReceive(viewModel.$uiState) { _ in
            scheduleContentCacheRefresh()
        }
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
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            LuckyCatMascotView(status: status, large: true)
                .frame(
                    width: LuckyCatLayout.expandedSidebarMascotWidth,
                    height: LuckyCatLayout.expandedSidebarMascotHeight,
                    alignment: .center
                )
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("M\(viewModel.managedActiveCount()) · O\(viewModel.observedDisplayCount())")
                    .font(LuckyCatTokens.Typography.subtitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                Text(viewModel.luckyCatExpandedStatusText())
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(2)
            }
            .frame(height: LuckyCatLayout.expandedSidebarStatusHeight, alignment: .topLeading)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: LuckyCatLayout.expandedSidebarTabSpacing) {
                LuckyCatExpandedSidebarNavigation(
                    sections: Section.allCases,
                    initialSelection: navigationSection,
                    onSelect: selectSection
                )
            }
        }
        .frame(height: LuckyCatLayout.expandedMainHeight, alignment: .top)
    }

    private func selectSection(_ section: Section) {
        guard navigationSection != section || renderedSection != section else { return }
        lastSectionChangeAt = Date()
        var renderTransaction = Transaction()
        renderTransaction.disablesAnimations = true
        renderTransaction.animation = nil
        withTransaction(renderTransaction) {
            navigationSection = section
        }

        sectionSwitchGeneration += 1
        let generation = sectionSwitchGeneration
        DispatchQueue.main.async {
            guard sectionSwitchGeneration == generation else { return }
            var contentTransaction = Transaction()
            contentTransaction.disablesAnimations = true
            contentTransaction.animation = nil
            withTransaction(contentTransaction) {
                renderedSection = section
            }
        }
    }

    private var prewarmedContentDeck: some View {
        contentScrollPane(section: renderedSection)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func contentScrollPane(
        section: Section
    ) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 14) {
                dashboardContent(section: section)
            }
            .padding(.trailing, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: LuckyCatLayout.expandedContentScrollHeight, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    @ViewBuilder
    private func dashboardContent(
        section: Section
    ) -> some View {
        switch section {
        case .overview:
            LazyVStack(alignment: .leading, spacing: 14) {
                codexUsageSection
                managedTaskSection(
                    cachedManagedTasks,
                    totalCount: cachedManagedTaskTotal,
                    visibleLimit: $overviewTaskVisibleLimit,
                    maxLimit: min(cachedManagedTasks.count, TaskLightUIPerformanceBudget.expandedOverviewManagedTaskRenderLimit),
                    allowsPagination: false,
                    rowStyle: .card
                )
                invalidTaskSection(cachedInvalidTasks, totalCount: cachedInvalidTaskTotal, rowStyle: .card)
                observedThreadSection(cachedObservedThreads, totalCount: cachedObservedThreadTotal)
            }
        case .tasks:
            LazyVStack(alignment: .leading, spacing: 14) {
                managedTaskSection(
                    cachedManagedTasks,
                    totalCount: cachedManagedTaskTotal,
                    visibleLimit: $taskPageVisibleLimit,
                    maxLimit: cachedManagedTasks.count,
                    allowsPagination: true,
                    rowStyle: .compact
                )
                invalidTaskSection(cachedInvalidTasks, totalCount: cachedInvalidTaskTotal, rowStyle: .compact)
            }
        case .events:
            eventSection(cachedEvents, visibleLimit: $eventVisibleLimit)
        case .settings:
            settingsSection
        }
    }

    private func scheduleContentCacheRefresh() {
        let elapsed = Date().timeIntervalSince(lastSectionChangeAt)
        guard elapsed >= Self.cacheRefreshDeferralSeconds else {
            cacheRefreshGeneration += 1
            let generation = cacheRefreshGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.cacheRefreshDeferralSeconds) {
                guard cacheRefreshGeneration == generation else { return }
                refreshContentCache()
            }
            return
        }
        refreshContentCache()
    }

    private func scheduleInitialContentCacheRefresh() {
        cacheRefreshGeneration += 1
        let generation = cacheRefreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard cacheRefreshGeneration == generation else { return }
            refreshContentCache(force: true)
        }
    }

    private func refreshContentCache(force: Bool = false) {
        let nextKey = [
            viewModel.uiState.projector_generated_at,
            String(viewModel.uiState.tasks.count),
            String(viewModel.uiState.observations.count)
        ].joined(separator: "|")
        guard force || nextKey != cacheKey else { return }
        cacheKey = nextKey
        cacheLoading = true
        cacheRefreshGeneration += 1
        let generation = cacheRefreshGeneration
        let stateSnapshot = viewModel.uiState
        let eventsSnapshot = viewModel.recentEvents(limit: TaskLightUIPerformanceBudget.expandedRecentEventLimit)
        let managedLimitSnapshot = managedTaskCacheLimit
        DispatchQueue.global(qos: .userInitiated).async {
            let payload = LuckyCatExpandedDashboardCacheBuilder.build(
                state: stateSnapshot,
                events: eventsSnapshot,
                managedLimit: managedLimitSnapshot
            )
            DispatchQueue.main.async {
                guard cacheRefreshGeneration == generation else { return }
                cachedManagedTasks = payload.managedTasks
                cachedInvalidTasks = payload.invalidTasks
                cachedObservedThreads = payload.observedThreads
                cachedEvents = payload.events
                cachedManagedTaskTotal = payload.managedTaskTotal
                cachedInvalidTaskTotal = payload.invalidTaskTotal
                cachedObservedThreadTotal = payload.observedThreadTotal
                cacheLoading = false
            }
        }
    }

    private var codexUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Codex Usage", subtitle: viewModel.quotaStatusLabel())
            if let quota = viewModel.uiState.quota, quota.fresh {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remaining")
                                .font(LuckyCatTokens.Typography.statusPill)
                                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                            Text("⚡ \(percentText(quota.effective_remaining_percent))")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(quotaColor(quota.status))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(quota.status.uppercased())
                            .font(LuckyCatTokens.Typography.statusPill)
                            .foregroundStyle(quotaColor(quota.status))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(quotaColor(quota.status).opacity(0.16))
                            )
                    }

                    HStack(spacing: 10) {
                        quotaMetric(
                            title: quota.short_label ?? "短周期",
                            value: percentText(quota.short_percent),
                            detail: quotaWindowDetail(reset: quota.short_reset_label, bucketID: quota.short_bucket_id),
                            status: quota.status
                        )
                        quotaMetric(
                            title: quota.long_label ?? "长周期",
                            value: percentText(quota.long_percent),
                            detail: quotaWindowDetail(reset: quota.long_reset_label, bucketID: quota.long_bucket_id),
                            status: quota.status
                        )
                    }

                    HStack(spacing: 8) {
                        quotaInfoPill(
                            title: "Reset",
                            value: quota.manual_resets_available.map { "R\($0)" } ?? "not provided"
                        )
                        quotaInfoPill(title: "Source", value: quota.source ?? "unknown")
                    }

                    HStack(spacing: 8) {
                        quotaInfoPill(title: "Bucket", value: quota.bucket_id ?? quota.short_bucket_id ?? "unknown")
                        quotaInfoPill(title: "Probe", value: quota.probe_mode ?? "unknown")
                        quotaInfoPill(title: "Raw", value: quota.raw_window_count.map(String.init) ?? "unknown")
                    }

                    Text("Captured · \(quota.captured_at ?? "unknown") · \(quota.recommendation ?? "normal")")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .padding(12)
                .background(usageCardBackground)
            } else {
                HStack(spacing: 10) {
                    Text("⚡Q?")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quota missing or stale")
                            .font(LuckyCatTokens.Typography.taskTitle)
                            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                        Text("State projector will keep the main lamp unchanged.")
                            .font(LuckyCatTokens.Typography.taskMeta)
                            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(usageCardBackground)
            }
        }
    }

    private func quotaMetric(title: String, value: String, detail: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(LuckyCatTokens.Typography.statusPill)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(quotaColor(status))
                .lineLimit(1)
            Text(detail)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.44), lineWidth: 1)
        )
    }

    private func quotaWindowDetail(reset: String?, bucketID: String?) -> String {
        let resetPart = resetText(reset)
        if let bucketID, !bucketID.isEmpty {
            return "bucket \(bucketID) · \(resetPart)"
        }
        return resetPart
    }

    private func quotaInfoPill(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(LuckyCatTokens.Typography.statusPill)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            Text(value)
                .font(LuckyCatTokens.Typography.taskMeta.weight(.bold))
                .foregroundStyle(LuckyCatTokens.Palette.textPrimary.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.34))
        )
    }

    private var usageCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LuckyCatTokens.Palette.glass.opacity(0.58))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.44), lineWidth: 1)
            )
            .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.14), radius: 10, x: 0, y: 4)
    }

    private func percentText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)%"
    }

    private func resetText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "reset unknown" }
        return "\(value) reset"
    }

    private func quotaColor(_ status: String) -> Color {
        switch status {
        case "ok":
            return LuckyCatTokens.Palette.green
        case "watch":
            return LuckyCatTokens.Palette.amber
        case "low":
            return LuckyCatTokens.Palette.collarRed
        case "critical":
            return LuckyCatTokens.Palette.red
        default:
            return LuckyCatTokens.Palette.textSecondary
        }
    }

    @ViewBuilder
    private func managedTaskSection(
        _ managedTasks: [TaskLightTaskSummary],
        totalCount: Int,
        visibleLimit: Binding<Int>,
        maxLimit: Int,
        allowsPagination: Bool,
        rowStyle: TaskRowStyle
    ) -> some View {
        let cappedTotal = min(managedTasks.count, maxLimit)
        let renderedCount = min(visibleLimit.wrappedValue, cappedTotal)
        let visibleTasks = Array(managedTasks.prefix(renderedCount))
        sectionHeader("Managed Tasks", subtitle: cacheLoading ? "loading" : visibleCountSubtitle(rendered: visibleTasks.count, total: totalCount))
        if cacheLoading && managedTasks.isEmpty {
            emptyText("Loading managed tasks...")
        } else if managedTasks.isEmpty {
            emptyText("No managed tasks")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visibleTasks) { task in
                    switch rowStyle {
                    case .card:
                        LuckyCatTaskCard(task: task, scrollOptimized: TaskLightUIPerformanceBudget.expandedScrollUsesOptimizedCards)
                    case .compact:
                        LuckyCatTaskListRow(task: task)
                    }
                }
                virtualListSentinel(
                    rendered: renderedCount,
                    maxRender: cappedTotal,
                    total: totalCount,
                    noun: "tasks",
                    visibleLimit: visibleLimit,
                    onLoadNextPage: allowsPagination ? loadNextManagedTaskPage : nil
                )
            }
        }
    }

    @ViewBuilder
    private func invalidTaskSection(_ invalidTasks: [TaskLightTaskSummary], totalCount: Int, rowStyle: TaskRowStyle) -> some View {
        if !invalidTasks.isEmpty {
            let visibleTasks = Array(invalidTasks.prefix(TaskLightUIPerformanceBudget.expandedInvalidTaskRenderLimit))
            sectionHeader("Invalid Task JSON", subtitle: visibleCountSubtitle(rendered: visibleTasks.count, total: totalCount))
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visibleTasks) { task in
                    switch rowStyle {
                    case .card:
                        LuckyCatTaskCard(task: task, scrollOptimized: TaskLightUIPerformanceBudget.expandedScrollUsesOptimizedCards)
                    case .compact:
                        LuckyCatTaskListRow(task: task)
                    }
                }
                overflowHint(rendered: visibleTasks.count, total: totalCount, noun: "invalid tasks")
            }
        }
    }

    @ViewBuilder
    private func observedThreadSection(_ observedThreads: [TaskLightObservationRecord], totalCount: Int) -> some View {
        let visibleThreads = Array(observedThreads.prefix(TaskLightUIPerformanceBudget.expandedObservedThreadRenderLimit))
        sectionHeader("Live Observed Threads", subtitle: cacheLoading ? "loading" : visibleCountSubtitle(rendered: visibleThreads.count, total: totalCount))
        if cacheLoading && observedThreads.isEmpty {
            emptyText("Loading observed threads...")
        } else if observedThreads.isEmpty {
            emptyText("No live observed threads")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visibleThreads) { thread in
                    LuckyCatObservedThreadCard(thread: thread, scrollOptimized: TaskLightUIPerformanceBudget.expandedScrollUsesOptimizedCards)
                }
                overflowHint(rendered: visibleThreads.count, total: totalCount, noun: "observed threads")
            }
        }
    }

    @ViewBuilder
    private func eventSection(_ events: [TaskLightEventRecord], visibleLimit: Binding<Int>) -> some View {
        let renderedCount = min(visibleLimit.wrappedValue, events.count)
        let visibleEvents = Array(events.prefix(renderedCount))
        LazyVStack(alignment: .leading, spacing: 10) {
            sectionHeader("Events", subtitle: "\(events.count) recent")
            if events.isEmpty {
                emptyText("No events yet")
            } else {
                ForEach(visibleEvents, id: \.event_id) { event in
                    eventRow(event)
                }
                virtualListSentinel(
                    rendered: renderedCount,
                    maxRender: events.count,
                    total: events.count,
                    noun: "events",
                    visibleLimit: visibleLimit
                )
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

    private func visibleCountSubtitle(rendered: Int, total: Int) -> String {
        guard total > rendered else { return "\(total) visible" }
        return "\(rendered)/\(total) visible"
    }

    private func virtualListSentinel(
        rendered: Int,
        maxRender: Int,
        total: Int,
        noun: String,
        visibleLimit: Binding<Int>,
        onLoadNextPage: (() -> Void)? = nil
    ) -> some View {
        Group {
            if total > rendered && rendered < maxRender {
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    transaction.animation = nil
                    withTransaction(transaction) {
                        guard rendered < maxRender else { return }
                        let next = min(maxRender, rendered + TaskLightUIPerformanceBudget.expandedTaskRenderBatchSize)
                        if visibleLimit.wrappedValue != next {
                            visibleLimit.wrappedValue = next
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(virtualListHint(rendered: rendered, maxRender: maxRender, total: total, noun: noun))
                    }
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.28))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            } else if total > rendered, let onLoadNextPage {
                Button {
                    onLoadNextPage()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Load next \(noun) page · cached \(rendered)/\(total)")
                    }
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.28))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            } else if total > rendered {
                overflowHint(rendered: rendered, total: total, noun: noun)
            }
        }
    }

    private func loadNextManagedTaskPage() {
        let target = min(
            max(managedTaskCacheLimit + TaskLightUIPerformanceBudget.expandedManagedTaskCachePageSize, TaskLightUIPerformanceBudget.expandedManagedTaskRenderLimit),
            min(cachedManagedTaskTotal, TaskLightUIPerformanceBudget.expandedManagedTaskCacheHardLimit)
        )
        guard target > managedTaskCacheLimit else { return }
        managedTaskCacheLimit = target
        refreshContentCache(force: true)
    }

    private func virtualListHint(rendered: Int, maxRender: Int, total: Int, noun: String) -> String {
        if rendered < maxRender {
            return "Show more \(noun) · \(rendered)/\(total)"
        }
        if total > maxRender {
            return "Showing \(rendered) of \(total) \(noun). Use logs for full history."
        }
        return "Showing \(rendered) of \(total) \(noun)."
    }

    @ViewBuilder
    private func overflowHint(rendered: Int, total: Int, noun: String) -> some View {
        if total > rendered {
            Text("Showing first \(rendered) of \(total) \(noun). Use state filters or logs for the full history.")
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.78))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                )
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

private struct LuckyCatTaskListRow: View {
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

    private var detailText: String {
        if let phase = task.phase, !phase.isEmpty {
            return phase
        }
        if let summary = task.summary, !summary.isEmpty {
            return summary
        }
        if let message = task.message, !message.isEmpty {
            return message
        }
        return task.short_task_id
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(visualStatus.tint.opacity(0.88))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                Text(detailText)
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(statusLabel)
                    .font(LuckyCatTokens.Typography.statusPill)
                    .foregroundStyle(visualStatus.tint)
                    .lineLimit(1)
                if let timestamp = task.updated_at ?? task.started_at ?? task.created_at {
                    Text(timestamp)
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
    }
}

private struct LuckyCatExpandedSidebarNavigation: View {
    let sections: [LuckyCatExpandedDashboardView.Section]
    let initialSelection: LuckyCatExpandedDashboardView.Section
    let onSelect: (LuckyCatExpandedDashboardView.Section) -> Void

    @State private var selectedSection: LuckyCatExpandedDashboardView.Section

    init(
        sections: [LuckyCatExpandedDashboardView.Section],
        initialSelection: LuckyCatExpandedDashboardView.Section,
        onSelect: @escaping (LuckyCatExpandedDashboardView.Section) -> Void
    ) {
        self.sections = sections
        self.initialSelection = initialSelection
        self.onSelect = onSelect
        _selectedSection = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyCatLayout.expandedSidebarTabSpacing) {
            ForEach(sections, id: \.self) { section in
                tab(section)
            }
        }
        .onChange(of: initialSelection) { newValue in
            guard selectedSection != newValue else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                selectedSection = newValue
            }
        }
    }

    private func tab(_ section: LuckyCatExpandedDashboardView.Section) -> some View {
        let selected = selectedSection == section
        return Button {
            guard selectedSection != section else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                selectedSection = section
            }
            onSelect(section)
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
            .frame(height: LuckyCatLayout.expandedSidebarTabHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.55) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

private struct LuckyCatExpandedDashboardCachePayload {
    let managedTasks: [TaskLightTaskSummary]
    let invalidTasks: [TaskLightTaskSummary]
    let observedThreads: [TaskLightObservationRecord]
    let events: [TaskLightEventRecord]
    let managedTaskTotal: Int
    let invalidTaskTotal: Int
    let observedThreadTotal: Int
}

private enum LuckyCatExpandedDashboardCacheBuilder {
    static func build(
        state: TaskLightUIState,
        events: [TaskLightEventRecord],
        managedLimit: Int
    ) -> LuckyCatExpandedDashboardCachePayload {
        let invalidLimit = TaskLightUIPerformanceBudget.expandedInvalidTaskRenderLimit
        let observedLimit = TaskLightUIPerformanceBudget.expandedObservedThreadRenderLimit

        let sortedManaged = state.tasks
            .sorted(by: taskSort)
            .prefix(managedLimit)
            .map { $0.asTaskSummary() }

        let invalidTasks = state.tasks
            .filter { $0.display_scope == "invalid" }
            .map { $0.asTaskSummary() }
            .sorted { lhs, rhs in (lhs.title, lhs.task_id) < (rhs.title, rhs.task_id) }

        let visibleObserved = state.observations
            .filter { ["active_execution", "observed_active_high_confidence", "observed_only"].contains($0.display_scope) }
            .map { $0.asObservationRecord() }

        return LuckyCatExpandedDashboardCachePayload(
            managedTasks: Array(sortedManaged),
            invalidTasks: Array(invalidTasks.prefix(invalidLimit)),
            observedThreads: Array(visibleObserved.prefix(observedLimit)),
            events: events,
            managedTaskTotal: state.tasks.count,
            invalidTaskTotal: invalidTasks.count,
            observedThreadTotal: visibleObserved.count
        )
    }

    private static func taskSort(_ lhs: TaskLightUITask, _ rhs: TaskLightUITask) -> Bool {
        let lhsRank = taskSortRank(lhs.display_scope)
        let rhsRank = taskSortRank(rhs.display_scope)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.updated_at != rhs.updated_at {
            return (lhs.updated_at ?? "") > (rhs.updated_at ?? "")
        }
        return lhs.task_id < rhs.task_id
    }

    private static func taskSortRank(_ status: String) -> Int {
        switch status {
        case "open_blocker":
            return 0
        case "active_execution":
            return 1
        case "pending_verify":
            return 2
        case "recent_done":
            return 3
        case "stale_blocker":
            return 4
        case "resolved_blocker":
            return 5
        case "history":
            return 6
        case "released":
            return 7
        case "invalid":
            return 8
        case TaskLightStatus.blocked.rawValue:
            return 0
        case TaskLightStatus.running.rawValue:
            return 1
        case TaskLightStatus.done_unverified.rawValue:
            return 2
        case TaskLightStatus.done_verified.rawValue:
            return 3
        case TaskLightStatus.stale.rawValue:
            return 4
        case TaskLightStatus.cancelled.rawValue:
            return 5
        default:
            return 9
        }
    }
}
