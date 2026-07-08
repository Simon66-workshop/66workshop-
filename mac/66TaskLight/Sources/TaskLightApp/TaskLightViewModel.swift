import AppKit
import Combine
import Darwin
import Foundation
import TaskLightCore

enum TaskRadarDiagnosticSeverity: String {
    case ok
    case warning
    case attention
    case unknown
}

struct TaskRadarDiagnosticRow: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let severity: TaskRadarDiagnosticSeverity

    init(label: String, value: String, severity: TaskRadarDiagnosticSeverity) {
        self.id = label
        self.label = label
        self.value = value
        self.severity = severity
    }
}

@MainActor
final class TaskLightViewModel: ObservableObject {
    enum CompactActivePaw {
        case problem
        case executing
        case complete
        case toVerify
        case recon
    }

    @Published var uiState: TaskLightUIState
    @Published var expanded: Bool
    @Published var edgeCollapsed: Bool
    @Published private(set) var edgeCollapseRequestID: Int
    @Published private(set) var edgeRestoreRequestID: Int
    @Published var contentExpanded: Bool
    @Published var muted: Bool
    @Published var workspaceCoveragePresentation: TaskLightWorkspaceCoveragePresentation?
    @Published private(set) var uiStateRevision: Int
    @Published private var recentEventSnapshot: [TaskLightEventRecord]

    let config: TaskLightConfig
    let store: TaskLightStore

    private var timer: Timer?
    private var ledger: TaskLightPlayedEventsLedger
    private var stateDirectoryFileDescriptor: CInt?
    private var stateDirectorySource: DispatchSourceFileSystemObject?
    private var uiPersistWorkItem: DispatchWorkItem?
    private var pendingStateFileRefresh: DispatchWorkItem?
    private var pendingWorkspaceCoverageRefreshes: [DispatchWorkItem] = []
    private var pendingWorkspaceCoverageHide: DispatchWorkItem?
    private var pendingInitialRefresh: DispatchWorkItem?
    private var recentEventsFingerprint: String?
    private var alertEventSnapshot: [TaskLightEventRecord]
    private var lastAlertPlaybackFingerprint: String?
    private var lastAlertPlaybackMuted: Bool?
    private var lastWatchedUIStateFileFingerprint: String?
    private var lastLoadedUIStateFileFingerprint: String?
    private var lastUIClientDiagnosticSignature: String?
    private var lastUIClientDiagnosticWriteAt: Date?
    private var lastUIEventFlowFingerprint: String?
    private var lastUIStateRefreshSignature: String?
    private var suppressCompactTapUntil: Date?

    init(config: TaskLightConfig = .fromEnvironment(), store: TaskLightStore? = nil) {
        self.config = config
        self.store = store ?? TaskLightStore(config: config)
        self.store.ensureLayout()
        let initialUIState = self.store.loadProjectedUIState()
        let defaults = UserDefaults.standard
        self.uiState = initialUIState
        self.expanded = false
        self.edgeCollapsed = false
        defaults.set(false, forKey: TaskLightLedgerKeys.edgeCollapsed)
        self.edgeCollapseRequestID = 0
        self.edgeRestoreRequestID = 0
        self.contentExpanded = false
        self.ledger = self.store.loadPlayedLedger()
        self.muted = self.ledger.muted
        self.recentEventSnapshot = []
        self.alertEventSnapshot = []
        self.uiStateRevision = 0
        self.lastUIStateRefreshSignature = Self.uiStateRefreshSignature(for: initialUIState, config: config)
    }

    init(previewUIState: TaskLightUIState) {
        let config = TaskLightConfig.fromEnvironment()
        self.config = config
        self.store = TaskLightStore(config: config)
        self.uiState = previewUIState
        self.expanded = false
        self.edgeCollapsed = false
        self.edgeCollapseRequestID = 0
        self.edgeRestoreRequestID = 0
        self.contentExpanded = false
        self.ledger = TaskLightPlayedEventsLedger()
        self.muted = false
        self.recentEventSnapshot = []
        self.alertEventSnapshot = []
        self.uiStateRevision = 0
        self.lastUIStateRefreshSignature = Self.uiStateRefreshSignature(for: previewUIState, config: config)
    }

    func start() {
        startStateFileWatcher()
        guard timer == nil else { return }
        pendingInitialRefresh?.cancel()
        timer?.invalidate()
        let timer = Timer(timeInterval: config.refreshSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        pendingInitialRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func refresh() {
        let uiStateFileFingerprint = Self.fileFingerprint(for: config.uiStateURL)
        if uiStateFileFingerprint != "missing",
           uiStateFileFingerprint == lastLoadedUIStateFileFingerprint {
            refreshRecentEventsIfNeeded()
            handleAlertPlayback()
            saveUIClientDiagnostic()
            return
        }
        lastLoadedUIStateFileFingerprint = uiStateFileFingerprint
        let previousState = uiState
        let nextState = store.loadProjectedUIState()
        let nextSignature = Self.uiStateRefreshSignature(for: nextState, config: config)
        if nextSignature != lastUIStateRefreshSignature || nextState != previousState {
            uiStateRevision += 1
        }
        lastUIStateRefreshSignature = nextSignature
        uiState = nextState
        recordUIEventFlow(previous: previousState, current: nextState)
        refreshRecentEventsIfNeeded()
        saveUIClientDiagnostic()
        handleAlertPlayback()
        persistUIState()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        uiPersistWorkItem?.cancel()
        uiPersistWorkItem = nil
        writeUIStateDefaults()
        pendingInitialRefresh?.cancel()
        pendingInitialRefresh = nil
        pendingStateFileRefresh?.cancel()
        pendingStateFileRefresh = nil
        pendingWorkspaceCoverageHide?.cancel()
        pendingWorkspaceCoverageHide = nil
        pendingWorkspaceCoverageRefreshes.forEach { $0.cancel() }
        pendingWorkspaceCoverageRefreshes.removeAll()
        stateDirectorySource?.cancel()
        stateDirectorySource = nil
        stateDirectoryFileDescriptor = nil
    }

    deinit {
        timer?.invalidate()
        pendingInitialRefresh?.cancel()
        pendingStateFileRefresh?.cancel()
        pendingWorkspaceCoverageHide?.cancel()
        pendingWorkspaceCoverageRefreshes.forEach { $0.cancel() }
        stateDirectorySource?.cancel()
    }

    func toggleExpanded() {
        if let suppressCompactTapUntil, Date() < suppressCompactTapUntil {
            return
        }
        if edgeCollapsed {
            setEdgeCollapsed(false)
            return
        }
        expanded.toggle()
        persistUIState()
    }

    func collapseExpanded() {
        guard expanded else { return }
        expanded = false
        persistUIState()
    }

    func toggleEdgeCollapsed() {
        setEdgeCollapsed(!edgeCollapsed)
    }

    func requestEdgeCollapseFromStatusOrb() {
        suppressCompactTapUntil = Date().addingTimeInterval(0.42)
        edgeCollapseRequestID += 1
    }

    func requestEdgeRestoreFromRail() {
        suppressCompactTapUntil = Date().addingTimeInterval(0.42)
        edgeRestoreRequestID += 1
    }

    func setEdgeCollapsed(_ value: Bool) {
        suppressCompactTapUntil = Date().addingTimeInterval(0.16)
        guard edgeCollapsed != value else {
            expanded = false
            contentExpanded = false
            persistUIState(deferred: true)
            return
        }
        expanded = false
        contentExpanded = false
        edgeCollapsed = value
        persistUIState(deferred: true)
    }

    func setContentExpanded(_ value: Bool) {
        guard contentExpanded != value else { return }
        contentExpanded = value
    }

    func toggleMute() {
        muted.toggle()
        ledger.muted = muted
        ledger.updated_at = TaskLightTaskRecord.nowString()
        store.savePlayedLedger(ledger)
        persistUIState()
    }

    func clearTask() {
        guard let taskID = primaryClearTaskID() else { return }
        store.clear(taskID: taskID)
        refresh()
    }

    func openLog() {
        NSWorkspace.shared.open(store.config.eventsURL)
    }

    func runWorkspaceCoverageReport() {
        workspaceCoveragePresentation = TaskLightWorkspaceCoveragePresentation(
            message: "正在检查 Codex 项目...",
            status: "running",
            reportURL: config.workspaceCoverageLatestMarkdownURL
        )
        store.runWorkspaceCoverageReport(openReport: true)
        scheduleWorkspaceCoverageRefreshes()
    }

    func openWorkspaceCoverageReport() {
        NSWorkspace.shared.open(config.workspaceCoverageLatestMarkdownURL)
    }

    func copyBlocker() {
        let projectedBlocker = uiState.tasks.first {
            $0.display_scope == "open_blocker" || $0.display_scope == "stale_blocker" || $0.display_scope == "invalid"
        }
        let lines: [String]
        if let target = projectedBlocker {
            lines = [
                "Task: \(target.task_id)",
                "Status: \(target.effective_status)",
                "Reason: \(target.reason ?? target.state_cause ?? "unknown")",
                "Message: \(target.message ?? target.summary ?? "unknown")",
                "Evidence: \(target.state_cause ?? "unknown")"
            ]
        } else {
            lines = [
                "Global status: \(uiState.lamp_status)",
                "Projector reason: \((uiState.diagnostics.projector_reason ?? ["none"]).joined(separator: ","))"
            ]
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func statusColor() -> NSColor {
        switch overallLampStatus() {
        case TaskLightStatus.running.rawValue:
            return .systemBlue
        case TaskLightStatus.blocked.rawValue:
            return .systemRed
        case TaskLightStatus.done_verified.rawValue:
            return .systemGreen
        case TaskLightStatus.stale.rawValue:
            return .systemRed
        default:
            return .tertiaryLabelColor
        }
    }

    func statusLabel() -> String {
        projectedPrimaryStatus()
    }

    func compactCountsLabel() -> String {
        "R \(blockedDisplayCount())  B \(runningDisplayCount())  G \(visibleDoneDisplayCount())  P \(pendingDisplayCount())  O \(observedDisplayCount())"
    }

    func managedActiveCount() -> Int {
        uiState.counts.managed_active
    }

    func observedCount() -> Int {
        observedDisplayCount()
    }

    func observedDisplayCount() -> Int {
        uiState.counts.observed_active
    }

    func blockedDisplayCount() -> Int {
        uiState.counts.blocked + uiState.counts.stale
    }

    func runningDisplayCount() -> Int {
        uiState.counts.running + uiState.counts.queued
    }

    func doneDisplayCount() -> Int {
        uiState.counts.done_verified_visible
    }

    func visibleDoneDisplayCount() -> Int {
        uiState.counts.done_verified_visible
    }

    func pendingDisplayCount() -> Int {
        uiState.counts.pending_verify_count
    }

    func compactStatusTitle() -> String {
        let displayTitle = luckyCatPresentationTitle()
        switch displayTitle.uppercased() {
        case "RUNNING":
            return "Running"
        case "BLOCKED":
            return "Blocked"
        case "PENDING":
            return "Pending"
        case "DONE":
            return "Done"
        case "IDLE":
            return "Idle"
        default:
            return displayTitle.prefix(1).uppercased() + displayTitle.dropFirst().lowercased()
        }
    }

    func edgeRailThreadSummary() -> String {
        "运行 \(runningDisplayCount()) · 待验 \(pendingDisplayCount()) · 观察 \(observedDisplayCount())"
    }

    func quotaIsCritical() -> Bool {
        guard let quota = uiState.quota else {
            return false
        }
        let candidates = [
            quota.short_percent,
            quota.long_percent,
            quota.effective_remaining_percent
        ].compactMap { $0 }
        guard let minimum = candidates.min() else {
            return false
        }
        return minimum < 20
    }

    func managedCount() -> Int {
        uiState.tasks.count
    }

    func sortedManagedTasks() -> [TaskLightTaskSummary] {
        uiState.tasks.sorted { lhs, rhs in
            let lhsRank = taskSortRank(lhs.display_scope)
            let rhsRank = taskSortRank(rhs.display_scope)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.updated_at != rhs.updated_at {
                return (lhs.updated_at ?? "") > (rhs.updated_at ?? "")
            }
            return lhs.task_id < rhs.task_id
        }.map { $0.asTaskSummary() }
    }

    func invalidManagedTasks() -> [TaskLightTaskSummary] {
        uiState.tasks.filter { $0.display_scope == "invalid" }.map { $0.asTaskSummary() }.sorted { lhs, rhs in
            (lhs.title, lhs.task_id) < (rhs.title, rhs.task_id)
        }
    }

    func visibleObservedThreads() -> [TaskLightObservationRecord] {
        uiState.observations
            .filter { ["active_execution", "observed_active_high_confidence", "observed_only"].contains($0.display_scope) }
            .map { $0.asObservationRecord() }
    }

    func recentEvents(limit: Int = 40) -> [TaskLightEventRecord] {
        Array(recentEventSnapshot.prefix(limit))
    }

    private func refreshRecentEventsIfNeeded() {
        let eventURL = store.config.eventsURL
        let attributes = try? FileManager.default.attributesOfItem(atPath: eventURL.path)
        let modifiedAt = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let fingerprint = "\(modifiedAt):\(fileSize)"
        guard fingerprint != recentEventsFingerprint else { return }
        recentEventsFingerprint = fingerprint
        let loadedEvents = store.loadRecentEvents()
        alertEventSnapshot = loadedEvents
        recentEventSnapshot = Array(
            loadedEvents
                .sorted { lhs, rhs in
                    if lhs.created_at != rhs.created_at {
                        return lhs.created_at > rhs.created_at
                    }
                    return lhs.event_id > rhs.event_id
                }
                .prefix(TaskLightUIPerformanceBudget.expandedRecentEventLimit)
        )
    }

    func luckyCatCompactStatusText() -> String {
        switch overallLampStatus() {
        case TaskLightStatus.blocked.rawValue:
            return "红色诊断优先，阻塞或陈旧任务会压过其他状态。"
        case TaskLightStatus.running.rawValue:
            return "蓝色表示正在执行、待验收，或仅有可见观察线程。"
        case TaskLightStatus.done_verified.rawValue:
            return "全部活跃任务结束后，验证通过才会进入绿色完成态。"
        default:
            return "当前没有活跃 managed task，也没有可见 observed thread。"
        }
    }

    func luckyCatExpandedStatusText() -> String {
        "Global \(statusLabel()) · blocked \(blockedDisplayCount()) · running \(runningDisplayCount()) · done \(doneDisplayCount()) · pending \(pendingDisplayCount()) · observed \(observedDisplayCount())"
    }

    func luckyCatPresentationTitle() -> String {
        TaskLightProjectedPresentation.displayTitle(from: uiState)
    }

    func luckyCatPresentationStatus() -> LuckyCatVisualStatus {
        switch projectedPrimaryStatus() {
        case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue:
            return .blocked
        case TaskLightStatus.running.rawValue:
            return .running
        case "pending", TaskLightStatus.done_unverified.rawValue:
            return .pending
        case TaskLightStatus.done_verified.rawValue:
            return .done
        default:
            return observedDisplayCount() > 0 ? .observed : .idle
        }
    }

    func weakRuntimeHintText() -> String? {
        guard projectedPrimaryStatus() == TaskLightStatus.idle.rawValue else {
            return nil
        }
        let candidates = uiState.runtime_candidates ?? []
        let liveSuspectCount = candidates.filter { candidate in
            guard candidate.display_scope == "ignored" else { return false }
            let sources = Set(candidate.source_set)
            let hasWeakRuntimeSource = sources.contains("codex_appserver") || sources.contains("codex_private_probe")
            let cause = candidate.state_cause ?? ""
            let ignoredReason = candidate.why_ignored ?? ""
            let isUnknownRuntime = cause.contains("codex_appserver:unknown")
                || cause.contains("private_active")
                || ignoredReason == "runtime_score_below_threshold"
            let freshness = candidate.freshness_score ?? 0
            return hasWeakRuntimeSource && isUnknownRuntime && freshness >= 0.5
        }.count
        if liveSuspectCount > 0 {
            return "疑似\(liveSuspectCount)"
        }
        let awaitingHookCount = candidates.filter { candidate in
            guard candidate.display_scope == "ignored" else { return false }
            let sources = Set(candidate.source_set)
            return sources.contains("codex_appserver") && candidate.why_ignored == "stale_appserver_signal"
        }.count
        guard awaitingHookCount > 0 else { return nil }
        return "待触发\(awaitingHookCount)"
    }

    func signalDiagnosticLabel() -> String {
        let source = uiState.diagnostics.current_thread_signal_source ?? "none"
        let quality = uiState.diagnostics.current_thread_signal_quality ?? "unknown"
        let confidence = uiState.diagnostics.current_thread_signal_confidence.map { String(format: "%.2f", $0) } ?? "--"
        let state = uiState.diagnostics.current_thread_signal_status ?? "unknown"
        let decision = uiState.diagnostics.current_thread_fusion_decision ?? uiState.diagnostics.latest_bridge_decision ?? "none"
        return "Signal \(source) · \(quality) · c\(confidence) · \(state) · \(decision)"
    }

    func stateSourceDiagnosticLabel() -> String {
        let reason = uiState.diagnostics.projector_reason?.joined(separator: ",") ?? "none"
        let signalBus = uiState.diagnostics.signal_bus_status ?? "unknown"
        let signalCount = uiState.diagnostics.signal_bus_record_count ?? 0
        let sourceCounts = (uiState.diagnostics.signal_bus_source_counts ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        let signalAge = secondsLabel(uiState.diagnostics.latest_signal_age_sec)
        let activeAge = secondsLabel(uiState.diagnostics.latest_active_turn_age_sec)
        let observedAge = secondsLabel(uiState.diagnostics.latest_observed_age_sec)
        let uiAge = secondsLabel(uiStateAgeSeconds())
        let fallback = uiState.diagnostics.fallback_reason ?? "none"
        let writer = uiState.diagnostics.writer_status ?? "unknown"
        let candidates = uiState.diagnostics.runtime_candidate_count ?? uiState.runtime_candidates?.count ?? 0
        let appserver = uiState.diagnostics.appserver_active_count ?? uiState.counts.appserver_active
        let process = uiState.diagnostics.process_observed_count ?? uiState.counts.process_observed
        let mismatch = (uiState.diagnostics.running_mismatch_warning ?? false) ? " mismatch" : ""
        return "State Source · \(uiState.source) \(uiState.projector_version ?? "legacy") · writer \(writer) · \(uiState.global_status) · signalBus \(signalBus) · \(signalCount) rec · \(sourceCounts.isEmpty ? "none" : sourceCounts) · candidates \(candidates) · appserver \(appserver) · process \(process) · signalAge \(signalAge) · reason \(reason) · activeAge \(activeAge) · observedAge \(observedAge) · uiAge \(uiAge) · fallback \(fallback)\(mismatch)"
    }

    func bridgeHealthDiagnosticLabel() -> String {
        let status = uiState.diagnostics.hook_bridge_status ?? "unknown"
        let active = uiState.diagnostics.active_turn_bindings ?? 0
        let latestEvent = uiState.diagnostics.latest_turn_signal_event ?? "none"
        let latestDecision = uiState.diagnostics.latest_bridge_decision ?? "none"
        let canonical = shortID(uiState.diagnostics.latest_turn_binding_canonical_identity ?? "none")
        let aliasCount = uiState.diagnostics.latest_turn_binding_aliases?.count ?? 0
        let observedAge = secondsLabel(uiState.diagnostics.latest_observed_age_sec)
        let privateAge = secondsLabel(uiState.diagnostics.latest_private_probe_signal_age_sec)
        let privateStatus = uiState.diagnostics.latest_private_probe_status ?? "none"
        let privateQuality = uiState.diagnostics.latest_private_probe_quality ?? "none"
        return "Bridge Health · \(status) · active \(active) · event \(latestEvent) · decision \(latestDecision) · id \(canonical) · aliases \(aliasCount) · private \(privateStatus) · \(privateQuality) · privateAge \(privateAge) · obsAge \(observedAge)"
    }

    func currentThreadDiagnosticLabel() -> String {
        let bindingStatus = uiState.diagnostics.current_thread_binding_status ?? "none"
        let bindingFresh = (uiState.diagnostics.current_thread_binding_fresh ?? false) ? "fresh" : "stale"
        let bindingAge = secondsLabel(uiState.diagnostics.latest_current_thread_binding_age_sec)
        let signalAge = secondsLabel(uiState.diagnostics.latest_current_thread_signal_age_sec)
        let identity = shortID(uiState.diagnostics.current_thread_task_identity ?? "none")
        return "Current Thread · \(bindingStatus) · \(bindingFresh) · bindAge \(bindingAge) · sigAge \(signalAge) · \(identity)"
    }

    func compactElapsedLabel() -> String {
        guard let task = compactReferenceTask() else {
            return "M0"
        }
        let reference = task.started_at ?? task.updated_at ?? task.created_at
        guard let started = TaskLightTaskRecord.parseTimestamp(reference) else {
            return "M0"
        }
        let elapsed = max(0, Int(Date().timeIntervalSince(started)))
        let minutes = elapsed / 60
        if minutes > 999 {
            return "M999+"
        }
        return "M\(minutes)"
    }

    func compactDataLabel() -> String {
        "M\(managedActiveCount()) O\(observedDisplayCount())"
    }

    func quotaCompactText() -> String {
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
        guard !parts.isEmpty else {
            return "⚡Q?"
        }
        return "⚡" + parts.joined(separator: "·")
    }

    func quotaStatusLabel() -> String {
        uiState.quota?.status.uppercased() ?? "UNKNOWN"
    }

    func menuBarStatusTitle() -> String {
        let activeCount = runningDisplayCount() + pendingDisplayCount() + observedDisplayCount()
        return "● \(menuBarShortStatusTitle()) \(activeCount)  \(quotaCompactText())"
    }

    func menuBarStatusAccessibilityLabel() -> String {
        "\(compactStatusTitle()), \(edgeRailThreadSummary()), quota \(quotaCompactText())"
    }

    func taskRadarActiveTasks() -> [TaskLightTaskSummary] {
        let activeScopes = Set(["open_blocker", "stale_blocker", "active_execution", "pending_verify"])
        let activeStatuses = Set([
            TaskLightStatus.blocked.rawValue,
            TaskLightStatus.stale.rawValue,
            TaskLightStatus.running.rawValue,
            TaskLightStatus.queued.rawValue,
            TaskLightStatus.done_unverified.rawValue,
            TaskLightStatus.invalid_json.rawValue
        ])
        return uiState.tasks
            .filter { task in
                activeScopes.contains(task.display_scope) || activeStatuses.contains(task.effective_status)
            }
            .sorted { lhs, rhs in
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
            .map { $0.asTaskSummary() }
    }

    func taskRadarObservedThreads() -> [TaskLightObservationRecord] {
        visibleObservedThreads()
    }

    func taskRadarDiagnosticRows() -> [TaskRadarDiagnosticRow] {
        let diagnostics = uiState.diagnostics
        return [
            TaskRadarDiagnosticRow(label: "Writer", value: diagnostics.writer_status ?? "unknown", severity: severityForHealthStatus(diagnostics.writer_status)),
            TaskRadarDiagnosticRow(label: "Hook Bridge", value: diagnostics.hook_bridge_status ?? "unknown", severity: severityForHealthStatus(diagnostics.hook_bridge_status)),
            TaskRadarDiagnosticRow(label: "Signal Bus", value: diagnostics.signal_bus_status ?? "unknown", severity: severityForHealthStatus(diagnostics.signal_bus_status)),
            TaskRadarDiagnosticRow(label: "Latest Signal", value: secondsLabel(diagnostics.latest_signal_age_sec), severity: severityForSignalAge(diagnostics.latest_signal_age_sec)),
            TaskRadarDiagnosticRow(label: "Candidates", value: "\(diagnostics.runtime_candidate_count ?? uiState.runtime_candidates?.count ?? 0)", severity: .unknown),
            TaskRadarDiagnosticRow(label: "Quota Probe", value: diagnostics.quota_probe_status ?? "unknown", severity: severityForHealthStatus(diagnostics.quota_probe_status))
        ]
    }

    func compactProgressValue() -> CGFloat {
        if let task = compactReferenceTask() {
            let fallback: CGFloat
            switch task.effective_status {
            case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue:
                fallback = 0.68
            case TaskLightStatus.done_unverified.rawValue:
                fallback = 0.88
            case TaskLightStatus.done_verified.rawValue:
                fallback = 1
            case TaskLightStatus.queued.rawValue:
                fallback = 0.08
            case TaskLightStatus.running.rawValue:
                fallback = 0.56
            default:
                fallback = 0
            }
            return clampedProgress(task.progress, fallback: fallback)
        }
        if hasObservedActivity() {
            return 0.22
        }
        return 0
    }

    func compactShowsAlertBell() -> Bool {
        blockedDisplayCount() > 0 || statusLabel() == TaskLightStatus.done_verified.rawValue
    }

    func compactActivePaw() -> CompactActivePaw? {
        if blockedDisplayCount() > 0 {
            return .problem
        }
        if pendingDisplayCount() > 0 && runningDisplayCount() == 0 {
            return .toVerify
        }
        if runningDisplayCount() > 0 {
            return .executing
        }
        if observedDisplayCount() > 0 {
            return .recon
        }
        if visibleDoneDisplayCount() > 0 {
            return .complete
        }
        return nil
    }

    private func doneVisibleWindowSeconds() -> TimeInterval {
        let raw = ProcessInfo.processInfo.environment["TASKLIGHT_DONE_VISIBLE_HOURS"]
        let hours = raw.flatMap(Double.init) ?? 24
        return max(0, hours) * 3600
    }

    private func startStateFileWatcher() {
        guard stateDirectorySource == nil else { return }
        let stateDirectory = config.stateURL.deletingLastPathComponent()
        let descriptor = open(stateDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleStateFileRefresh()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        stateDirectoryFileDescriptor = descriptor
        stateDirectorySource = source
        source.resume()
    }

    private func scheduleStateFileRefresh() {
        let fingerprint = Self.fileFingerprint(for: config.uiStateURL)
        guard fingerprint != lastWatchedUIStateFileFingerprint else { return }
        lastWatchedUIStateFileFingerprint = fingerprint
        pendingStateFileRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        pendingStateFileRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func scheduleWorkspaceCoverageRefreshes() {
        pendingWorkspaceCoverageRefreshes.forEach { $0.cancel() }
        pendingWorkspaceCoverageRefreshes = [1.0, 2.5, 4.0].map { delay in
            let workItem = DispatchWorkItem { [weak self] in
                self?.workspaceCoveragePresentation = self?.store.loadWorkspaceCoveragePresentation()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            return workItem
        }
        pendingWorkspaceCoverageHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in
            self?.workspaceCoveragePresentation = nil
        }
        pendingWorkspaceCoverageHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: hide)
    }

    func primaryClearTaskID() -> String? {
        let priorityScopes = ["open_blocker", "active_execution", "pending_verify", "recent_done", "stale_blocker", "resolved_blocker", "history", "released", "invalid"]
        for scope in priorityScopes {
            if let task = uiState.tasks.first(where: { $0.display_scope == scope }) {
                return task.task_id
            }
        }
        return nil
    }

    private func handleAlertPlayback() {
        guard recentEventsFingerprint != lastAlertPlaybackFingerprint || muted != lastAlertPlaybackMuted else {
            return
        }
        lastAlertPlaybackFingerprint = recentEventsFingerprint
        lastAlertPlaybackMuted = muted

        var ledger = self.ledger
        ledger.muted = muted

        let events = alertEventSnapshot
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.created_at != rhs.created_at {
                return lhs.created_at < rhs.created_at
            }
            return lhs.event_id < rhs.event_id
        }

        var ledgerChanged = false
        var playedEventIDs = Set(ledger.played_event_ids)
        for event in sortedEvents {
            guard !playedEventIDs.contains(event.event_id) else { continue }
            ledger.played_event_ids.append(event.event_id)
            playedEventIDs.insert(event.event_id)
            ledgerChanged = true

            guard event.sound_type == TaskLightStatus.blocked.rawValue || event.sound_type == TaskLightStatus.done_verified.rawValue else {
                continue
            }
            guard !ledger.muted else {
                continue
            }
            let window = ledger.sound_windows[event.sound_type] ?? TaskLightSoundWindow()
            let eventTime = TaskLightTaskRecord.parseTimestamp(event.created_at) ?? Date()
            let lastPlayed = TaskLightTaskRecord.parseTimestamp(window.last_played_at)
            if let lastPlayed, eventTime.timeIntervalSince(lastPlayed) < 5 {
                continue
            }
            playSound(for: event.sound_type)
            ledger.sound_windows[event.sound_type] = TaskLightSoundWindow(last_played_at: event.created_at, last_event_id: event.event_id)
            ledgerChanged = true
        }

        if ledger.muted != muted {
            ledger.muted = muted
            ledgerChanged = true
        }
        if ledgerChanged {
            ledger.updated_at = TaskLightTaskRecord.nowString()
            store.savePlayedLedger(ledger)
        }
        self.ledger = ledger
        self.muted = ledger.muted
    }

    private func overallLampStatus() -> String {
        projectedPrimaryStatus()
    }

    private func projectedPrimaryStatus() -> String {
        TaskLightProjectedPresentation.primaryStatus(from: uiState)
    }

    private func taskSortRank(_ status: String) -> Int {
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
        case TaskLightStatus.queued.rawValue:
            return 6
        case TaskLightStatus.invalid_json.rawValue:
            return 7
        default:
            return 8
        }
    }

    private func uiDisplayScope(for taskID: String, fallback: String) -> String {
        uiState.tasks.first(where: { $0.task_id == taskID })?.display_scope ?? fallback
    }

    private func uiStateAgeSeconds() -> Double? {
        uiStateAgeSeconds(for: uiState)
    }

    private func uiStateAgeSeconds(for state: TaskLightUIState) -> Double? {
        guard let generatedAt = TaskLightTaskRecord.parseTimestamp(state.projector_generated_at) else {
            return nil
        }
        return max(0, Date().timeIntervalSince(generatedAt))
    }

    private func secondsLabel(_ value: Double?) -> String {
        guard let value else {
            return "none"
        }
        return String(format: "%.1fs", value)
    }

    private func playSound(for soundType: String) {
        let soundName: String
        switch soundType {
        case TaskLightStatus.done_verified.rawValue:
            soundName = config.doneSoundName
        default:
            soundName = config.blockedSoundName
        }
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func persistUIState(deferred: Bool = false) {
        guard deferred else {
            writeUIStateDefaults()
            return
        }
        uiPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.writeUIStateDefaults()
            }
        }
        uiPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }

    private func writeUIStateDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(expanded, forKey: TaskLightLedgerKeys.expanded)
        defaults.set(edgeCollapsed, forKey: TaskLightLedgerKeys.edgeCollapsed)
        defaults.set(muted, forKey: TaskLightLedgerKeys.muted)
    }

    private func saveUIClientDiagnostic() {
        let bundle = Bundle.main
        let bundleURL = bundle.bundleURL
        let executableURL = bundle.executableURL ?? URL(fileURLWithPath: "")
        let bundleID = bundle.bundleIdentifier ?? "com.local.66tasklight"
        let resourceDate = (try? bundleURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let buildID = resourceDate.map { String(Int($0.timeIntervalSince1970)) } ?? TaskLightTaskRecord.nowString()
        let signature = [bundleID, bundleURL.path, executableURL.path, buildID, config.stateDirectory.path].joined(separator: "|")
        let now = Date()
        if signature == lastUIClientDiagnosticSignature,
           let lastWrite = lastUIClientDiagnosticWriteAt,
           now.timeIntervalSince(lastWrite) < 15 {
            return
        }
        lastUIClientDiagnosticSignature = signature
        lastUIClientDiagnosticWriteAt = now
        store.saveUIClientRecord(
            bundleID: bundleID,
            bundlePath: bundleURL.path,
            executablePath: executableURL.path,
            buildID: buildID
        )
    }

    private static func fileFingerprint(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "missing"
        }
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return "\(modifiedAt):\(fileSize)"
    }

    private func recordUIEventFlow(previous: TaskLightUIState, current: TaskLightUIState) {
        let reference = flowReferenceTask(in: current)
        let reason = current.diagnostics.projector_reason ?? []
        let fingerprintParts = [
            current.global_status,
            current.lamp_status,
            "\(current.counts.blocked)",
            "\(current.counts.stale)",
            "\(current.counts.running)",
            "\(current.counts.queued)",
            "\(current.counts.pending_verify_count)",
            "\(current.counts.observed_active)",
            reason.joined(separator: ","),
            reference?.task_id ?? "none",
            reference?.display_scope ?? "none",
            reference?.effective_status ?? "none",
            current.diagnostics.current_thread_signal_status ?? "none",
            current.diagnostics.current_thread_fusion_decision ?? "none"
        ]
        let fingerprint = fingerprintParts.joined(separator: "|")
        guard fingerprint != lastUIEventFlowFingerprint else { return }
        lastUIEventFlowFingerprint = fingerprint

        var payload: [String: Any] = [
            "schema_version": "0.1",
            "event_type": "ui_state_consumed",
            "recorded_at": TaskLightTaskRecord.nowString(),
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "source": current.source,
            "projector_version": current.projector_version ?? "unknown",
            "previous_global_status": previous.global_status,
            "previous_lamp_status": previous.lamp_status,
            "global_status": current.global_status,
            "lamp_status": current.lamp_status,
            "global_display_title": current.global_display_title,
            "counts": [
                "blocked": current.counts.blocked,
                "stale": current.counts.stale,
                "running": current.counts.running,
                "queued": current.counts.queued,
                "pending_verify_count": current.counts.pending_verify_count,
                "observed_active": current.counts.observed_active,
                "managed_active": current.counts.managed_active
            ],
            "projector_reason": reason,
            "fallback_reason": current.diagnostics.fallback_reason ?? "none",
            "writer_status": current.diagnostics.writer_status ?? "unknown",
            "hook_bridge_status": current.diagnostics.hook_bridge_status ?? "unknown",
            "current_thread_signal_status": current.diagnostics.current_thread_signal_status ?? "unknown",
            "current_thread_fusion_decision": current.diagnostics.current_thread_fusion_decision ?? "unknown",
            "ui_state_age_sec": uiStateAgeSeconds(for: current) ?? -1
        ]
        if let reference {
            payload["reference_task"] = [
                "task_id": reference.task_id,
                "title": reference.title,
                "effective_status": reference.effective_status,
                "display_scope": reference.display_scope,
                "state_cause": reference.state_cause ?? "unknown",
                "phase": reference.phase ?? "unknown",
                "turn_id": reference.turn_id ?? "none"
            ]
        }
        store.appendUIEventFlowRecord(payload)
    }

    private func compactReferenceTask() -> TaskLightTaskSummary? {
        flowReferenceTask(in: uiState)?.asTaskSummary()
    }

    private func flowReferenceTask(in state: TaskLightUIState) -> TaskLightUITask? {
        let priority = ["open_blocker", "active_execution", "pending_verify", "recent_done", "stale_blocker", "resolved_blocker"]
        for scope in priority {
            if let task = state.tasks.first(where: { $0.display_scope == scope }) {
                return task
            }
        }
        return state.tasks.first
    }

    private func isCompactPrimaryStatus(_ status: String) -> Bool {
        status == TaskLightStatus.blocked.rawValue
            || status == TaskLightStatus.stale.rawValue
            || status == TaskLightStatus.running.rawValue
            || status == TaskLightStatus.queued.rawValue
            || status == TaskLightStatus.done_unverified.rawValue
            || status == TaskLightStatus.done_verified.rawValue
    }

    private func hasObservedActivity() -> Bool {
        !visibleObservedThreads().isEmpty
    }

    private func hasHighConfidenceObservedAttention() -> Bool {
        visibleObservedThreads().contains {
            $0.status == TaskLightObservationStatus.observed_attention.rawValue && $0.confidence >= 0.75
        }
    }

    private func menuBarShortStatusTitle() -> String {
        switch compactStatusTitle() {
        case "Running":
            return "Run"
        case "Blocked":
            return "Block"
        case "Pending":
            return "Pend"
        case "Observed":
            return "Obs"
        default:
            return compactStatusTitle()
        }
    }

    private func severityForHealthStatus(_ status: String?) -> TaskRadarDiagnosticSeverity {
        switch status?.lowercased() {
        case "ok", "running", "readable", "healthy":
            return .ok
        case "stale", "warning", "watch":
            return .warning
        case "failed", "fail", "error", "blocked", "unreadable":
            return .attention
        default:
            return .unknown
        }
    }

    private func severityForSignalAge(_ value: Double?) -> TaskRadarDiagnosticSeverity {
        guard let value else { return .unknown }
        if value <= 15 { return .ok }
        if value <= 60 { return .warning }
        return .attention
    }

    private static func uiStateRefreshSignature(for state: TaskLightUIState, config: TaskLightConfig) -> String {
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: config.uiStateURL.path)
        let modifiedAt = (fileAttributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (fileAttributes?[.size] as? NSNumber)?.intValue ?? 0
        let reason = state.diagnostics.projector_reason?.joined(separator: ",") ?? "none"
        return [
            String(format: "%.6f", modifiedAt),
            "\(size)",
            state.source,
            state.projector_generated_at,
            state.global_status,
            state.lamp_status,
            TaskLightProjectedPresentation.displayTitle(from: state),
            "\(state.counts.blocked)",
            "\(state.counts.stale)",
            "\(state.counts.running)",
            "\(state.counts.queued)",
            "\(state.counts.pending_verify_count)",
            "\(state.counts.done_verified_visible)",
            "\(state.counts.observed_active)",
            reason
        ].joined(separator: "|")
    }

    private func clampedProgress(_ progress: Double?, fallback: CGFloat) -> CGFloat {
        guard let progress else {
            return fallback
        }
        return CGFloat(min(1, max(0, progress)))
    }

    private func shortID(_ value: String) -> String {
        if value == "none" || value == "unknown" {
            return value
        }
        return String(value.prefix(8))
    }

    private func ageLabel(since timestamp: String?) -> String {
        guard let date = TaskLightTaskRecord.parseTimestamp(timestamp) else {
            return "--"
        }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m"
    }
}
