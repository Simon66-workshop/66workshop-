import SwiftUI
import TaskLightCore

struct TaskRadarWindowHostView: View {
    @ObservedObject var viewModel: TaskLightViewModel
    let onOpenVisualMatrix: (() -> Void)?
    @State private var showsRadar = false

    var body: some View {
        ZStack {
            radarHostBackground
            if showsRadar {
                TaskRadarPopoverView(viewModel: viewModel, onOpenVisualMatrix: onOpenVisualMatrix)
                    .transition(.opacity)
            } else {
                radarSkeleton
            }
        }
        .frame(width: 420, height: 640, alignment: .center)
        .onAppear {
            guard !showsRadar else { return }
            // Render the bounded summary shell first; defer the diagnostic
            // tree by one run-loop beat so opening the radar never competes
            // with native menu teardown.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                showsRadar = true
            }
        }
    }

    private var radarSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LuckyCatStatusOrb(status: viewModel.luckyCatPresentationStatus(), size: 34, pulsing: false, showsGlow: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.compactStatusTitle())
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MacOSKitGlass.textPrimary)
                    Text(viewModel.edgeRailThreadSummary())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacOSKitGlass.textSecondary)
                }
                Spacer(minLength: 0)
                Text(viewModel.menuBarStatusTitle())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MacOSKitGlass.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .macOSKitGlassChip()
            }
            HStack(spacing: 10) {
                Text(viewModel.quotaCompactText())
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(viewModel.quotaIsCritical() ? LuckyCatTokens.Palette.red : MacOSKitGlass.textPrimary)
                    .monospacedDigit()
                Text("正在展开诊断细节")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(MacOSKitGlass.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .macOSKitGlassCard(cornerRadius: 18)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 420, height: 640, alignment: .topLeading)
    }

    private var radarHostBackground: some View {
        MacOSKitGlassBackground()
        .ignoresSafeArea()
    }
}

struct TaskRadarPopoverView: View {
    @ObservedObject var viewModel: TaskLightViewModel
    let onOpenVisualMatrix: (() -> Void)?
    @State private var selectedHookWorkspaces: Set<String> = []
    @State private var pendingHookInstallRequest: WorkspaceHookInstallRequest?
    @State private var showsHookInstallConfirm = false

    init(viewModel: TaskLightViewModel, onOpenVisualMatrix: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenVisualMatrix = onOpenVisualMatrix
    }

    private var activeTasks: [TaskLightTaskSummary] {
        viewModel.taskRadarActiveTasks(limit: 6)
    }

    private var observedThreads: [TaskLightObservationRecord] {
        viewModel.taskRadarObservedThreads(limit: 4)
    }

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quotaCard
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    taskSection
                    observedSection
                    diagnosticsSection
                    quotaPaceSection
                    quotaResetSection
                    quotaCalendarSection
                    providerSection
                    hooksDoctorSection
                    workspaceRepairQueueSection
                    statusReplaySection
                    statusExplanationSection
                    interactionRulesSection
                }
                .padding(.trailing, 4)
            }
        }
        .padding(16)
        .frame(width: 420, height: 640, alignment: .topLeading)
        .background(radarBackground)
        .confirmationDialog(
            "安装选中的 workspace hooks？",
            isPresented: $showsHookInstallConfirm,
            presenting: pendingHookInstallRequest
        ) { request in
            Button("确认安装 hooks", role: .none) {
                viewModel.installWorkspaceHooks(request: request, confirmed: true)
            }
            Button("取消", role: .cancel) {}
        } message: { request in
            Text("将安装 \(request.workspaces.count) 个 workspace 的 hooks。\n\(request.risk_summary)\n\(request.post_install_next_action)\n\(request.command_preview)")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            LuckyCatStatusOrb(status: status, size: 34, pulsing: status == .running, showsGlow: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.compactStatusTitle())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MacOSKitGlass.textPrimary)
                Text(viewModel.edgeRailThreadSummary())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacOSKitGlass.textSecondary)
            }
            Spacer(minLength: 0)
            if let onOpenVisualMatrix {
                Button(action: onOpenVisualMatrix) {
                    Label("矩阵", systemImage: "square.grid.2x2")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .macOSKitGlassChip(prominent: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacOSKitGlass.textPrimary)
                .help("打开视觉状态矩阵")
            }
            Text(viewModel.menuBarStatusTitle())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(MacOSKitGlass.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .macOSKitGlassChip()
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacOSKitGlass.textPrimary)
                Text("Quota is diagnostic only; main lamp remains ui_state driven.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(MacOSKitGlass.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(viewModel.quotaStatusLabel())
                .font(LuckyCatTokens.Typography.statusPill)
                .foregroundStyle(viewModel.quotaIsCritical() ? LuckyCatTokens.Palette.red : MacOSKitGlass.textSecondary)
        }
        .padding(12)
        .background(glassCard(cornerRadius: 18))
    }

    private var quotaPaceSection: some View {
        let snapshot = viewModel.quotaBurnRateSnapshot()
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Quota Pace", subtitle: snapshot.status)
            Text(snapshot.summary)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(snapshot.is_low_quota ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textSecondary)
            if snapshot.windows.isEmpty {
                emptyRow("Quota history is still warming up")
            } else {
                ForEach(snapshot.windows.prefix(3)) { window in
                    quotaPaceRow(window)
                }
            }
        }
    }

    private var quotaResetSection: some View {
        let snapshot = viewModel.quotaResetSnapshot()
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Codex Reset", subtitle: snapshot.status)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LuckyCatTokens.Palette.amber)
                    .frame(width: 24, height: 24)
                    .macOSKitGlassChip(prominent: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.manual_resets_label)
                        .font(LuckyCatTokens.Typography.taskTitle)
                        .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    Text(resetCreditSummaryText(snapshot))
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(glassCard(cornerRadius: 14))

            if snapshot.windows.isEmpty {
                emptyRow("Reset window validity is not available yet")
            } else {
                ForEach(snapshot.windows.prefix(3)) { window in
                    quotaResetRow(window)
                }
            }
            if !snapshot.credits.isEmpty {
                ForEach(snapshot.credits.prefix(3)) { credit in
                    quotaResetCreditRow(credit)
                }
            }
            Text("Reset 次数和有效期只用于额度诊断，不参与主灯状态。")
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
        }
    }

    private var providerSection: some View {
        let providers = viewModel.usageProviderSnapshots()
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Usage Providers", subtitle: "\(providers.count)")
            ForEach(providers) { provider in
                let sourceLabel = provider.source_label ?? "local presentation"
                let freshnessLabel = provider.freshness_label ?? "unknown freshness"
                HStack(alignment: .center, spacing: 9) {
                    Circle()
                        .fill(providerHealthColor(provider.health))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.display_name)
                            .font(LuckyCatTokens.Typography.taskTitle)
                            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                        Text("\(sourceLabel) · \(freshnessLabel)")
                            .font(LuckyCatTokens.Typography.taskMeta)
                            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                            .lineLimit(1)
                        if let conflict = provider.conflict_label {
                            Text(conflict)
                                .font(LuckyCatTokens.Typography.statusPill)
                                .foregroundStyle(LuckyCatTokens.Palette.amber)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(provider.quota_text)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(provider.is_low_quota ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textPrimary)
                        .monospacedDigit()
                }
                .padding(10)
                .background(glassCard(cornerRadius: 14))
            }
            Text("Provider 数据只用于额度展示，不参与主灯判定；外部 Provider 必须由用户显式 opt-in，默认不联网、不读凭证。")
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
        }
    }

    private var quotaCalendarSection: some View {
        let entries = viewModel.quotaCalendarEntries(limit: 6)
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Quota Calendar", subtitle: entries.contains { $0.severity == "attention" } ? "attention" : "upcoming")
            if entries.isEmpty {
                emptyRow("No reset or credit expiry time is available yet")
            } else {
                ForEach(entries) { entry in
                    quotaCalendarRow(entry)
                }
            }
            Text("Reset 和 expiry 只用于额度预警，不参与主灯状态。")
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
        }
    }

    private var hooksDoctorSection: some View {
        let rows = viewModel.workspaceDoctorRows()
        let installableRows = rows.filter(workspaceDoctorInstallable)
        let selectedCount = rows.filter { selectedHookWorkspaces.contains($0.workspace) }.count
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Hooks Doctor", subtitle: rows.isEmpty ? "no report" : "\(rows.count)")
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Button("巡检") {
                        viewModel.runWorkspaceCoverageReport()
                    }
                    .buttonStyle(.plain)
                    .miniRadarButtonStyle()
                    Button("报告") {
                        viewModel.openWorkspaceCoverageReport()
                    }
                    .buttonStyle(.plain)
                    .miniRadarButtonStyle()
                    Button("安装说明") {
                        viewModel.openWorkspaceHooksGuide()
                    }
                    .buttonStyle(.plain)
                    .miniRadarButtonStyle()
                    Spacer(minLength: 0)
                }
                HStack(spacing: 7) {
                    Button("选需处理") {
                        selectedHookWorkspaces = Set(installableRows.map(\.workspace))
                    }
                    .disabled(installableRows.isEmpty)
                    .buttonStyle(.plain)
                    .miniRadarButtonStyle()
                    Button("清空") {
                        selectedHookWorkspaces.removeAll()
                        pendingHookInstallRequest = nil
                    }
                    .disabled(selectedHookWorkspaces.isEmpty)
                    .buttonStyle(.plain)
                    .miniRadarButtonStyle()
                    Button("安装选中") {
                        pendingHookInstallRequest = viewModel.workspaceHookInstallRequest(for: selectedHookWorkspaces)
                        showsHookInstallConfirm = pendingHookInstallRequest != nil
                    }
                    .disabled(selectedCount == 0)
                    .buttonStyle(.plain)
                    .miniRadarButtonStyle()
                    Text("已选 \(selectedCount)")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            .accessibilityLabel("Hooks Doctor actions")
            if rows.isEmpty {
                emptyRow("Run Workspace 巡检 to build doctor report")
            } else {
                if let request = viewModel.workspaceHookInstallRequest(for: selectedHookWorkspaces) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("安装预览 · \(request.workspaces.count) 个 workspace")
                            .font(LuckyCatTokens.Typography.taskTitle)
                            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                        Text(request.command_preview)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        Text("\(request.risk_summary) · \(request.post_install_next_action)")
                            .font(LuckyCatTokens.Typography.taskMeta)
                            .foregroundStyle(LuckyCatTokens.Palette.amber)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(glassCard(cornerRadius: 14))
                }
                ForEach(rows.prefix(5)) { row in
                    workspaceDoctorRow(row)
                }
                if let result = viewModel.workspaceHookInstallResult {
                    Text("\(result.status): \(result.message)")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(result.status == "success" ? LuckyCatTokens.Palette.green : LuckyCatTokens.Palette.amber)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(glassCard(cornerRadius: 14))
                }
                Text("可按安装说明手动安装 hooks；安装后仍必须在 Codex UI 手动 Trust。这里不会自动 trust，也不会自动修改任务状态。")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            }
        }
    }

    private var statusReplaySection: some View {
        let records = viewModel.statusReplayRecords(hours: 24, limit: 8)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("24h Status Replay")
                    .font(LuckyCatTokens.Typography.sectionLabel)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                Spacer()
                Text("\(records.count)")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                Button("复制证据") {
                    viewModel.copyStatusReplayEvidence()
                }
                .buttonStyle(.plain)
                .miniRadarButtonStyle()
            }
            if records.isEmpty {
                emptyRow("No state transition evidence in the last 24h")
            } else {
                ForEach(records.prefix(5)) { record in
                    statusReplayRow(record)
                }
            }
        }
    }

    private var workspaceRepairQueueSection: some View {
        let queue = viewModel.workspaceRepairQueue(limit: 4)
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Repair Queue", subtitle: queue.isEmpty ? "clear" : "\(queue.count)")
            if queue.isEmpty {
                emptyRow("No workspace repair action is waiting")
            } else {
                ForEach(queue) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name)
                                .font(LuckyCatTokens.Typography.taskTitle)
                                .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                            Spacer(minLength: 0)
                            Text(item.manualTrustRequired ? "Manual Trust" : item.requiresUserConfirmation ? "Confirm install" : "Refresh")
                                .font(LuckyCatTokens.Typography.statusPill)
                                .foregroundStyle(workspaceSeverityColor(item.severity))
                        }
                        Text(item.action)
                            .font(LuckyCatTokens.Typography.taskMeta)
                            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(glassCard(cornerRadius: 14))
                }
            }
        }
    }

    private var statusExplanationSection: some View {
        let explanations = viewModel.statusExplanations(limit: 4)
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Why This Status", subtitle: explanations.isEmpty ? "stable" : "evidence")
            if explanations.isEmpty {
                emptyRow("No current status anomaly needs explanation")
            } else {
                ForEach(explanations) { explanation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(explanation.title)
                            .font(LuckyCatTokens.Typography.taskTitle)
                            .foregroundStyle(severityColorForInsight(explanation.severity))
                        Text(explanation.detail)
                            .font(LuckyCatTokens.Typography.taskMeta)
                            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                            .lineLimit(2)
                        Text(explanation.recommendedAction)
                            .font(LuckyCatTokens.Typography.statusPill)
                            .foregroundStyle(LuckyCatTokens.Palette.amber)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(glassCard(cornerRadius: 14))
                }
            }
        }
    }

    private var interactionRulesSection: some View {
        let rules = viewModel.interactionRulesSummary()
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Interaction Rules", subtitle: "\(Int(rules.threshold_points))pt / \(rules.long_press_ms)ms")
            Text("单击切换 · 拖动只拖动 · 长按不切换 · 双击打开诊断")
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(glassCard(cornerRadius: 14))
        }
    }

    private var taskSection: some View {
        let tasks = activeTasks
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Active Managed Tasks", subtitle: "\(tasks.count)")
            if tasks.isEmpty {
                emptyRow("No active managed task")
            } else {
                ForEach(tasks) { task in
                    radarTaskRow(task)
                }
            }
        }
    }

    private var observedSection: some View {
        let threads = observedThreads
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Observed Threads", subtitle: "\(threads.count)")
            if threads.isEmpty {
                emptyRow("No visible observed thread")
            } else {
                Text("Observed threads are diagnostics only; they do not prove managed RUNNING by themselves.")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                ForEach(threads) { thread in
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

    private func quotaPaceRow(_ window: QuotaBurnRateWindow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(window.label)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                Text("reset \(window.reset_label ?? "--") · samples \(window.samples)")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                Text("\(window.confidence.rawValue) · \(window.data_status)")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(window.confidence == .stable ? LuckyCatTokens.Palette.green : LuckyCatTokens.Palette.amber)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(window.remaining_percent.map { "\($0)%" } ?? "Q?")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(window.warning == "low_quota" ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textPrimary)
                    .monospacedDigit()
                Text(window.burn_percent_per_hour.map { String(format: "%.1f%%/h", $0) } ?? "warming")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                Text(window.estimated_empty_at.map { "empty \(shortTime($0))" } ?? "no ETA")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
            }
        }
        .padding(10)
        .background(glassCard(cornerRadius: 14))
    }

    private func quotaResetRow(_ window: CodexQuotaResetWindow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(window.label)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                Text(window.validity_label)
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                if let resetAt = window.reset_at {
                    Text("reset_at \(shortTime(resetAt))")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary.opacity(0.82))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(window.remaining_percent.map { "\($0)%" } ?? "Q?")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle((window.remaining_percent ?? 100) < 20 ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.textPrimary)
                    .monospacedDigit()
                Text("重置 \(window.reset_label ?? "--")")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            }
        }
        .padding(10)
        .background(glassCard(cornerRadius: 14))
    }

    private func quotaResetCreditRow(_ credit: CodexQuotaResetCreditUIState) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text((credit.status ?? "unknown").capitalized)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(credit.redeemed == true ? LuckyCatTokens.Palette.textSecondary : LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                Text("最迟有效期 \(resetCreditExpiryText(credit))")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(credit.redeemed == true ? "已用" : "可用")
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(credit.redeemed == true ? LuckyCatTokens.Palette.red : LuckyCatTokens.Palette.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .macOSKitGlassChip()
        }
        .padding(10)
        .background(glassCard(cornerRadius: 14))
    }

    private func quotaCalendarRow(_ entry: QuotaCalendarEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: entry.kind == "credit_expiry" ? "hourglass" : "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(severityColorForInsight(entry.severity))
                .frame(width: 24, height: 24)
                .macOSKitGlassChip()
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                Text(entry.detail)
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entry.dueAt.map { resetExpiryDisplay($0) } ?? "--")
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(severityColorForInsight(entry.severity))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(10)
        .background(glassCard(cornerRadius: 14))
    }

    private func workspaceDoctorRow(_ row: WorkspaceDoctorRow) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if workspaceDoctorInstallable(row) {
                Toggle("", isOn: Binding(
                    get: { selectedHookWorkspaces.contains(row.workspace) },
                    set: { isSelected in
                        if isSelected {
                            selectedHookWorkspaces.insert(row.workspace)
                        } else {
                            selectedHookWorkspaces.remove(row.workspace)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .padding(.top, 1)
            }
            Circle()
                .fill(workspaceSeverityColor(row.severity))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    .lineLimit(1)
                Text("\(row.coverage_status) · \(row.reason)")
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if row.preferred {
                Text("常用")
                    .font(LuckyCatTokens.Typography.statusPill)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            }
        }
        .padding(10)
        .background(glassCard(cornerRadius: 14))
    }

    private func statusReplayRow(_ record: StatusReplayRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(record.from_status) → \(record.to_status)")
                    .font(LuckyCatTokens.Typography.taskTitle)
                    .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                Spacer()
                Text(shortTime(record.recorded_at))
                    .font(LuckyCatTokens.Typography.statusPill)
                    .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            }
            Text(record.counts_summary)
                .font(LuckyCatTokens.Typography.taskMeta)
                .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
            if !record.markers.isEmpty {
                Text(record.markers.joined(separator: " · "))
                    .font(LuckyCatTokens.Typography.taskMeta)
                    .foregroundStyle(LuckyCatTokens.Palette.amber)
                    .lineLimit(1)
            }
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

    private func workspaceSeverityColor(_ severity: String) -> Color {
        switch severity {
        case "ok":
            return LuckyCatTokens.Palette.green
        case "warning", "needs_review":
            return LuckyCatTokens.Palette.amber
        case "attention":
            return LuckyCatTokens.Palette.red
        default:
            return LuckyCatTokens.Palette.textSecondary.opacity(0.7)
        }
    }

    private func severityColorForInsight(_ severity: String) -> Color {
        switch severity {
        case "attention":
            return LuckyCatTokens.Palette.red
        case "warning", "needs_review":
            return LuckyCatTokens.Palette.amber
        case "ok":
            return LuckyCatTokens.Palette.green
        default:
            return LuckyCatTokens.Palette.textSecondary
        }
    }

    private func providerHealthColor(_ health: ProviderHealth) -> Color {
        switch health {
        case .ok:
            return LuckyCatTokens.Palette.green
        case .warning:
            return LuckyCatTokens.Palette.amber
        case .disabled:
            return LuckyCatTokens.Palette.textSecondary.opacity(0.46)
        case .unavailable:
            return LuckyCatTokens.Palette.red.opacity(0.76)
        }
    }

    private func workspaceDoctorInstallable(_ row: WorkspaceDoctorRow) -> Bool {
        ["attention", "warning", "needs_review"].contains(row.severity)
    }

    private func resetCreditSummaryText(_ snapshot: CodexQuotaResetSnapshot) -> String {
        if !snapshot.credits.isEmpty {
            let next = snapshot.next_expiry.map { " · 最近到期 \(resetExpiryDisplay($0))" } ?? ""
            let used = snapshot.manual_resets_used_count.map { " · 已用 \($0)" } ?? ""
            let expired = snapshot.manual_resets_expired_count.map { " · 过期 \($0)" } ?? ""
            return "每次 reset 的最迟有效期如下\(next)\(used)\(expired)"
        }
        if let available = snapshot.manual_resets_available {
            return "可用 \(available) 次；等待每次 reset 的到期明细"
        }
        return "等待 reset credit 明细"
    }

    private func resetCreditExpiryText(_ credit: CodexQuotaResetCreditUIState) -> String {
        resetExpiryDisplay(credit.expires_at ?? credit.expiry_date)
    }

    private func resetExpiryDisplay(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "--" }
        if let date = TaskLightTaskRecord.parseTimestamp(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: date)
        }
        if let date = Self.resetDateOnlyFormatter.date(from: raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日"
            return formatter.string(from: date)
        }
        return raw
    }

    private func shortTime(_ raw: String) -> String {
        guard let date = TaskLightTaskRecord.parseTimestamp(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func glassCard(cornerRadius: CGFloat) -> some View {
        MacOSKitGlassSurface(cornerRadius: cornerRadius, shadow: cornerRadius >= 18)
    }

private var radarBackground: some View {
        MacOSKitGlassBackground()
            .overlay(.ultraThinMaterial.opacity(0.36))
    }
}

private extension View {
    func miniRadarButtonStyle() -> some View {
        self
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MacOSKitGlass.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .macOSKitGlassChip()
    }
}

private extension TaskRadarPopoverView {
    static let resetDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
