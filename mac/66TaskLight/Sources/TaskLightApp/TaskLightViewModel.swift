import AppKit
import Combine
import Foundation
import TaskLightCore

@MainActor
final class TaskLightViewModel: ObservableObject {
    enum CompactActivePaw {
        case problem
        case executing
        case complete
        case toVerify
        case recon
    }

    @Published var dashboard: TaskLightAggregateState
    @Published var expanded: Bool
    @Published var muted: Bool

    let config: TaskLightConfig
    let store: TaskLightStore

    private var timer: Timer?
    private var ledger: TaskLightPlayedEventsLedger

    init(config: TaskLightConfig = .fromEnvironment(), store: TaskLightStore? = nil) {
        self.config = config
        self.store = store ?? TaskLightStore(config: config)
        self.store.ensureLayout()
        self.dashboard = self.store.loadDashboard()
        let defaults = UserDefaults.standard
        self.expanded = defaults.object(forKey: TaskLightLedgerKeys.expanded) as? Bool ?? false
        self.ledger = self.store.loadPlayedLedger()
        self.muted = self.ledger.muted
    }

    func start() {
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: config.refreshSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        dashboard = store.loadDashboard()
        handleAlertPlayback()
        persistUIState()
    }

    func toggleExpanded() {
        expanded.toggle()
        persistUIState()
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

    func copyBlocker() {
        let target = dashboard.tasks.first(where: { $0.status == TaskLightStatus.blocked.rawValue || $0.status == TaskLightStatus.stale.rawValue }) ?? dashboard.invalid_tasks.first
        let lines: [String]
        if let target {
            lines = [
                "Task: \(target.task_id)",
                "Status: \(target.status)",
                "Reason: \(target.reason ?? target.last_error ?? target.invalid_json_error ?? "unknown")",
                "Message: \(target.message ?? target.last_error ?? "unknown")",
                "Evidence: \(target.evidence ?? "unknown")"
            ]
        } else {
            lines = [
                "Global status: \(dashboard.lamp_status)",
                "State health: \(dashboard.source_health)"
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
        if dashboard.source_health == TaskLightSourceHealth.corrupt_state.rawValue {
            return "stale"
        }
        return overallLampStatus()
    }

    func compactCountsLabel() -> String {
        let observedCount = dashboard.observations_state?.counts.active ?? 0
        return "R \(dashboard.counts.blocked + dashboard.counts.stale)  B \(dashboard.counts.running + dashboard.counts.queued + dashboard.counts.done_unverified)  G \(dashboard.counts.done_verified)  P \(dashboard.counts.pending_verify_count)  O \(observedCount)"
    }

    func managedActiveCount() -> Int {
        dashboard.counts.blocked + dashboard.counts.stale + dashboard.counts.running + dashboard.counts.queued + dashboard.counts.done_unverified
    }

    func observedCount() -> Int {
        observedDisplayCount()
    }

    func observedDisplayCount() -> Int {
        visibleObservedThreads().count
    }

    func blockedDisplayCount() -> Int {
        dashboard.counts.blocked + dashboard.counts.stale
    }

    func runningDisplayCount() -> Int {
        dashboard.counts.running + dashboard.counts.queued
    }

    func doneDisplayCount() -> Int {
        dashboard.counts.done_verified
    }

    func pendingDisplayCount() -> Int {
        dashboard.counts.pending_verify_count
    }

    func managedCount() -> Int {
        dashboard.counts.total
    }

    func sortedManagedTasks() -> [TaskLightTaskSummary] {
        dashboard.tasks.sorted { lhs, rhs in
            let lhsRank = taskSortRank(lhs.effective_status)
            let rhsRank = taskSortRank(rhs.effective_status)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.updated_at != rhs.updated_at {
                return (lhs.updated_at ?? "") > (rhs.updated_at ?? "")
            }
            return lhs.task_id < rhs.task_id
        }
    }

    func invalidManagedTasks() -> [TaskLightTaskSummary] {
        dashboard.invalid_tasks.sorted { lhs, rhs in
            (lhs.title, lhs.task_id) < (rhs.title, rhs.task_id)
        }
    }

    func visibleObservedThreads() -> [TaskLightObservationRecord] {
        (dashboard.observations_state?.observations ?? [])
            .filter { $0.isActive && $0.managed_task_id == nil }
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
        if doneDisplayCount() > 0 {
            return .complete
        }
        return nil
    }

    func primaryClearTaskID() -> String? {
        if let current = dashboard.current_task_id {
            return current
        }
        if let active = dashboard.tasks.first(where: { $0.status == TaskLightStatus.blocked.rawValue || $0.status == TaskLightStatus.stale.rawValue || $0.status == TaskLightStatus.running.rawValue || $0.status == TaskLightStatus.queued.rawValue || $0.status == TaskLightStatus.done_unverified.rawValue }) {
            return active.task_id
        }
        return dashboard.tasks.first?.task_id ?? dashboard.invalid_tasks.first?.task_id
    }

    private func handleAlertPlayback() {
        var ledger = store.loadPlayedLedger()
        ledger.muted = muted

        let events = store.loadEvents()
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.created_at != rhs.created_at {
                return lhs.created_at < rhs.created_at
            }
            return lhs.event_id < rhs.event_id
        }

        var ledgerChanged = false
        for event in sortedEvents {
            guard !ledger.played_event_ids.contains(event.event_id) else { continue }
            ledger.played_event_ids.append(event.event_id)
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
        if dashboard.source_health == TaskLightSourceHealth.corrupt_state.rawValue {
            return TaskLightStatus.stale.rawValue
        }
        if dashboard.counts.blocked > 0 || dashboard.counts.stale > 0 {
            return TaskLightStatus.blocked.rawValue
        }
        if hasHighConfidenceObservedAttention() {
            return TaskLightStatus.blocked.rawValue
        }
        if dashboard.counts.running > 0 || dashboard.counts.queued > 0 || dashboard.counts.done_unverified > 0 {
            return TaskLightStatus.running.rawValue
        }
        if hasObservedActivity() {
            return TaskLightStatus.running.rawValue
        }
        if dashboard.last_verified_at != nil {
            return TaskLightStatus.done_verified.rawValue
        }
        return TaskLightStatus.idle.rawValue
    }

    private func taskSortRank(_ status: String) -> Int {
        switch status {
        case TaskLightStatus.blocked.rawValue:
            return 0
        case TaskLightStatus.stale.rawValue:
            return 1
        case TaskLightStatus.running.rawValue:
            return 2
        case TaskLightStatus.queued.rawValue:
            return 3
        case TaskLightStatus.done_unverified.rawValue:
            return 4
        case TaskLightStatus.done_verified.rawValue:
            return 5
        case TaskLightStatus.cancelled.rawValue:
            return 6
        case TaskLightStatus.invalid_json.rawValue:
            return 7
        default:
            return 8
        }
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

    private func persistUIState() {
        let defaults = UserDefaults.standard
        defaults.set(expanded, forKey: TaskLightLedgerKeys.expanded)
        defaults.set(muted, forKey: TaskLightLedgerKeys.muted)
    }

    private func compactReferenceTask() -> TaskLightTaskSummary? {
        if let current = dashboard.current_task_id,
           let currentTask = dashboard.tasks.first(where: { $0.task_id == current }),
           isCompactPrimaryStatus(currentTask.effective_status) {
            return currentTask
        }

        let priority = [
            TaskLightStatus.blocked.rawValue,
            TaskLightStatus.stale.rawValue,
            TaskLightStatus.running.rawValue,
            TaskLightStatus.queued.rawValue,
            TaskLightStatus.done_unverified.rawValue,
            TaskLightStatus.done_verified.rawValue
        ]
        for status in priority {
            if let task = dashboard.tasks.first(where: { $0.effective_status == status }) {
                return task
            }
        }
        return nil
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

    private func clampedProgress(_ progress: Double?, fallback: CGFloat) -> CGFloat {
        guard let progress else {
            return fallback
        }
        return CGFloat(min(1, max(0, progress)))
    }
}
