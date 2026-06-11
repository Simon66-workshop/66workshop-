import AppKit
import Combine
import Darwin
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
    @Published var uiState: TaskLightUIState
    @Published var expanded: Bool
    @Published var muted: Bool
    @Published var hookBridgeHealth: HookBridgeHealthDiagnostic?

    let config: TaskLightConfig
    let store: TaskLightStore

    private var timer: Timer?
    private var ledger: TaskLightPlayedEventsLedger
    private var stateDirectoryFileDescriptor: CInt?
    private var stateDirectorySource: DispatchSourceFileSystemObject?
    private var pendingStateFileRefresh: DispatchWorkItem?

    init(config: TaskLightConfig = .fromEnvironment(), store: TaskLightStore? = nil) {
        self.config = config
        self.store = store ?? TaskLightStore(config: config)
        self.store.ensureLayout()
        self.dashboard = self.store.loadDashboard()
        self.uiState = self.store.loadUIState()
        self.hookBridgeHealth = Self.loadHookBridgeHealth(from: self.config.hookBridgeHealthURL)
        let defaults = UserDefaults.standard
        self.expanded = defaults.object(forKey: TaskLightLedgerKeys.expanded) as? Bool ?? false
        self.ledger = self.store.loadPlayedLedger()
        self.muted = self.ledger.muted
    }

    func start() {
        refresh()
        startStateFileWatcher()
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
        uiState = store.loadUIState()
        hookBridgeHealth = Self.loadHookBridgeHealth(from: config.hookBridgeHealthURL)
        saveUIClientDiagnostic()
        handleAlertPlayback()
        persistUIState()
    }

    deinit {
        timer?.invalidate()
        pendingStateFileRefresh?.cancel()
        stateDirectorySource?.cancel()
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
        uiState.lamp_status
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

    func managedCount() -> Int {
        dashboard.counts.total
    }

    func sortedManagedTasks() -> [TaskLightTaskSummary] {
        uiState.tasks.map { $0.asTaskSummary() }.sorted { lhs, rhs in
            let lhsRank = taskSortRank(uiDisplayScope(for: lhs.task_id, fallback: lhs.effective_status))
            let rhsRank = taskSortRank(uiDisplayScope(for: rhs.task_id, fallback: rhs.effective_status))
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
        uiState.tasks.filter { $0.display_scope == "invalid" }.map { $0.asTaskSummary() }.sorted { lhs, rhs in
            (lhs.title, lhs.task_id) < (rhs.title, rhs.task_id)
        }
    }

    func visibleObservedThreads() -> [TaskLightObservationRecord] {
        uiState.observations
            .filter { $0.display_scope == "active_execution" }
            .map { $0.asObservationRecord() }
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
        uiState.global_display_title
    }

    func luckyCatPresentationStatus() -> LuckyCatVisualStatus {
        switch uiState.lamp_status {
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

    func signalDiagnosticLabel() -> String {
        guard let binding = latestThreadBindingDiagnostic() else {
            return "Signal: no current managed binding"
        }
        let source = binding.last_signal_source ?? "binding"
        let quality = binding.last_source_quality ?? binding.last_fusion_decision ?? "unknown"
        let confidence = binding.last_signal_confidence.map { String(format: "%.2f", $0) } ?? "--"
        let state = binding.last_inferred_status ?? binding.private_status ?? binding.status ?? "unknown"
        let decision = binding.last_fusion_decision ?? "none"
        return "Signal \(source) · \(quality) · c\(confidence) · \(state) · \(decision)"
    }

    func stateSourceDiagnosticLabel() -> String {
        let reason = uiState.diagnostics.projector_reason?.joined(separator: ",") ?? "none"
        let activeAge = secondsLabel(uiState.diagnostics.latest_active_turn_age_sec)
        let observedAge = secondsLabel(uiState.diagnostics.latest_observed_age_sec)
        let uiAge = secondsLabel(uiStateAgeSeconds())
        let fallback = uiState.diagnostics.fallback_reason ?? "none"
        let mismatch = (uiState.diagnostics.running_mismatch_warning ?? false) ? " mismatch" : ""
        return "State Source · \(uiState.source) · \(uiState.global_status) · reason \(reason) · activeAge \(activeAge) · observedAge \(observedAge) · uiAge \(uiAge) · fallback \(fallback)\(mismatch)"
    }

    func bridgeHealthDiagnosticLabel() -> String {
        let status = uiState.diagnostics.hook_bridge_status ?? hookBridgeHealth?.status ?? "unknown"
        let active = uiState.diagnostics.active_turn_bindings ?? hookBridgeHealth?.active_turn_bindings ?? 0
        let observedAge = secondsLabel(uiState.diagnostics.latest_observed_age_sec)
        let bundle = uiState.diagnostics.app_bundle_path ?? "no-client"
        return "Bridge Health · \(status) · active \(active) · obsAge \(observedAge) · \(bundle)"
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
        pendingStateFileRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        pendingStateFileRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private static func loadHookBridgeHealth(from url: URL) -> HookBridgeHealthDiagnostic? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(HookBridgeHealthDiagnostic.self, from: data)
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
        uiState.lamp_status
    }

    private func taskSortRank(_ status: String) -> Int {
        switch status {
        case "open_blocker":
            return 0
        case "active_execution":
            return 2
        case "pending_verify":
            return 4
        case "recent_done":
            return 5
        case "invalid":
            return 7
        case "history":
            return 8
        case "released":
            return 9
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

    private func uiDisplayScope(for taskID: String, fallback: String) -> String {
        uiState.tasks.first(where: { $0.task_id == taskID })?.display_scope ?? fallback
    }

    private func uiStateAgeSeconds() -> Double? {
        guard let generatedAt = TaskLightTaskRecord.parseTimestamp(uiState.projector_generated_at) else {
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

    private func persistUIState() {
        let defaults = UserDefaults.standard
        defaults.set(expanded, forKey: TaskLightLedgerKeys.expanded)
        defaults.set(muted, forKey: TaskLightLedgerKeys.muted)
    }

    private func saveUIClientDiagnostic() {
        let bundle = Bundle.main
        let bundleURL = bundle.bundleURL
        let executableURL = bundle.executableURL ?? URL(fileURLWithPath: "")
        let bundleID = bundle.bundleIdentifier ?? "com.local.66tasklight"
        let resourceDate = (try? bundleURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let buildID = resourceDate.map { String(Int($0.timeIntervalSince1970)) } ?? TaskLightTaskRecord.nowString()
        store.saveUIClientRecord(
            bundleID: bundleID,
            bundlePath: bundleURL.path,
            executablePath: executableURL.path,
            buildID: buildID
        )
    }

    private func compactReferenceTask() -> TaskLightTaskSummary? {
        let priority = ["open_blocker", "active_execution", "pending_verify", "recent_done"]
        for scope in priority {
            if let task = uiState.tasks.first(where: { $0.display_scope == scope }) {
                return task.asTaskSummary()
            }
        }
        return uiState.tasks.first?.asTaskSummary()
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

    private func latestThreadBindingDiagnostic() -> ThreadBindingDiagnostic? {
        let directory = config.stateDirectory.appendingPathComponent("thread_bindings")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        let bindings = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ThreadBindingDiagnostic? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ThreadBindingDiagnostic.self, from: data)
            }
        return bindings.sorted { lhs, rhs in
            if (lhs.status == "active") != (rhs.status == "active") {
                return lhs.status == "active"
            }
            let left = TaskLightTaskRecord.parseTimestamp(lhs.updated_at ?? lhs.created_at ?? "") ?? Date.distantPast
            let right = TaskLightTaskRecord.parseTimestamp(rhs.updated_at ?? rhs.created_at ?? "") ?? Date.distantPast
            return left > right
        }.first
    }

    private func latestTurnBindingDiagnostic() -> TurnBindingDiagnostic? {
        let directory = config.stateDirectory.appendingPathComponent("turn_bindings")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        let bindings = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> TurnBindingDiagnostic? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(TurnBindingDiagnostic.self, from: data)
            }
        return bindings.sorted { lhs, rhs in
            if (lhs.status == "active") != (rhs.status == "active") {
                return lhs.status == "active"
            }
            let left = TaskLightTaskRecord.parseTimestamp(lhs.updated_at ?? lhs.created_at ?? "") ?? Date.distantPast
            let right = TaskLightTaskRecord.parseTimestamp(rhs.updated_at ?? rhs.created_at ?? "") ?? Date.distantPast
            return left > right
        }.first
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

private struct ThreadBindingDiagnostic: Decodable {
    var thread_id: String?
    var task_id: String?
    var status: String?
    var created_at: String?
    var updated_at: String?
    var private_status: String?
    var last_fusion_decision: String?
    var last_signal_confidence: Double?
    var last_signal_source: String?
    var last_source_quality: String?
    var last_inferred_status: String?
    var task_identity: String?
}

private struct TurnBindingDiagnostic: Decodable {
    var task_id: String?
    var turn_id: String?
    var status: String?
    var created_at: String?
    var updated_at: String?
    var last_signal_at: String?
    var last_signal_event: String?
    var last_bridge_decision: String?
    var phase: String?
    var release_reason: String?
}

struct HookBridgeHealthDiagnostic: Decodable, Equatable {
    var status: String?
    var last_run_at: String?
    var last_seen_at: String?
    var processed_count: Int?
    var expired_count: Int?
    var superseded_count: Int?
    var active_turn_bindings: Int?
    var last_error: String?
    var updated_at: String?
}
