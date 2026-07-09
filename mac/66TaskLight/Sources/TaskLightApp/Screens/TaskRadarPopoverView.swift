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
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("任务雷达")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                    Text("正在整理 Hooks Doctor 和状态回放")
                        .font(LuckyCatTokens.Typography.taskMeta)
                        .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.42), lineWidth: 1)
                        )
                )
            }
        }
        .frame(width: 420, height: 640, alignment: .center)
        .onAppear {
            guard !showsRadar else { return }
            DispatchQueue.main.async {
                showsRadar = true
            }
        }
    }

    private var radarHostBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.93, blue: 0.97).opacity(0.84),
                Color(red: 0.83, green: 0.94, blue: 1.0).opacity(0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                    quotaPaceSection
                    providerSection
                    hooksDoctorSection
                    statusReplaySection
                    interactionRulesSection
                    taskSection
                    observedSection
                    diagnosticsSection
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

    private var providerSection: some View {
        let providers = viewModel.usageProviderSnapshots()
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Usage Providers", subtitle: "\(providers.count)")
            ForEach(providers) { provider in
                HStack(alignment: .center, spacing: 9) {
                    Circle()
                        .fill(providerHealthColor(provider.health))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.display_name)
                            .font(LuckyCatTokens.Typography.taskTitle)
                            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                        Text(provider.health.rawValue)
                            .font(LuckyCatTokens.Typography.taskMeta)
                            .foregroundStyle(LuckyCatTokens.Palette.textSecondary)
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
            Text("Provider 数据只用于额度展示，不参与主灯判定；禁用 Provider 不联网、不读凭证。")
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

    private func shortTime(_ raw: String) -> String {
        guard let date = TaskLightTaskRecord.parseTimestamp(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

private extension View {
    func miniRadarButtonStyle() -> some View {
        self
            .font(LuckyCatTokens.Typography.statusPill)
            .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.34)))
    }
}
