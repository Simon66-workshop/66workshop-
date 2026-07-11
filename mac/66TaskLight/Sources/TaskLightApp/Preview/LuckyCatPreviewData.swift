import TaskLightCore

@MainActor
enum LuckyCatPreviewData {
    static let visualMatrixScenarios: [LuckyCatPreviewScenario] = [
        LuckyCatPreviewScenario(id: "idle", title: "Idle", uiState: uiState(status: "idle", title: "IDLE")),
        LuckyCatPreviewScenario(id: "running", title: "Running", uiState: uiState(status: "running", title: "RUNNING", running: 3, observed: 1)),
        LuckyCatPreviewScenario(id: "pending", title: "Pending Verify", uiState: uiState(status: "done_unverified", title: "PENDING", pending: 2)),
        LuckyCatPreviewScenario(id: "blocked", title: "Blocked", uiState: uiState(status: "blocked", title: "BLOCKED", blocked: 1, running: 1)),
        LuckyCatPreviewScenario(id: "done", title: "Done", uiState: uiState(status: "done_verified", title: "DONE", done: 3)),
        LuckyCatPreviewScenario(id: "observed", title: "Observed Only", uiState: uiState(status: "idle", title: "IDLE", observed: 2, observedOnly: true)),
        LuckyCatPreviewScenario(id: "lowQuota", title: "Low Quota", uiState: uiState(status: "running", title: "RUNNING", running: 1, quotaShort: 12, quotaLong: 64, quotaStatus: "low")),
        LuckyCatPreviewScenario(id: "quotaUnknown", title: "Quota Unknown", uiState: uiState(status: "idle", title: "IDLE", quotaFresh: false)),
        LuckyCatPreviewScenario(id: "oldWriter", title: "Old Writer", uiState: uiState(status: "stale", title: "BLOCKED", stale: 1, writerStatus: "old_writer")),
        LuckyCatPreviewScenario(id: "multipleProjector", title: "Multiple Projector", uiState: uiState(status: "stale", title: "BLOCKED", stale: 1, writerStatus: "multiple_writers")),
        LuckyCatPreviewScenario(id: "processOnly", title: "Process Only", uiState: uiState(status: "idle", title: "IDLE", observed: 1, observedOnly: true))
    ]

    static let compactState = TaskLightAggregateState(
        lamp_status: TaskLightStatus.running.rawValue,
        global_status: TaskLightStatus.running.rawValue,
        counts: TaskLightCounts(
            blocked: 1,
            stale: 0,
            running: 2,
            queued: 1,
            done_verified: 1,
            done_unverified: 1,
            pending_verify_count: 1,
            active: 4,
            total: 5,
            red: 1,
            blue: 4,
            green: 1
        ),
        tasks: [
            TaskLightTaskSummary(
                task_id: "20260610-010101-ui-a1b2c3d4",
                short_task_id: "a1b2c3d4",
                title: "LuckyCat compact preview",
                slug: "luckycat-preview",
                status: TaskLightStatus.running.rawValue,
                raw_status: TaskLightStatus.running.rawValue,
                effective_status: TaskLightStatus.running.rawValue,
                phase: "layout",
                progress: 0.42,
                updated_at: TaskLightTaskRecord.nowString()
            )
        ],
        observations_state: TaskLightObservationsState(
            counts: TaskLightObservationCounts(active: 2, quiet: 0, attention: 0, disappeared: 0, linked_managed: 0, total: 2),
            observations: [
                TaskLightObservationRecord(
                    observation_id: "obs-preview",
                    pid: 1001,
                    ppid: 1000,
                    command: "python3 codex-observed-thread",
                    command_short: "codex-observed-thread",
                    title: "codex-observed-thread",
                    detected_at: TaskLightTaskRecord.nowString(),
                    last_seen_at: TaskLightTaskRecord.nowString(),
                    status: TaskLightObservationStatus.observed_active.rawValue,
                    confidence: 0.84
                )
            ]
        )
    )

    private static func uiState(
        status: String,
        title: String,
        blocked: Int = 0,
        stale: Int = 0,
        running: Int = 0,
        queued: Int = 0,
        pending: Int = 0,
        done: Int = 0,
        observed: Int = 0,
        observedOnly: Bool = false,
        quotaShort: Int? = 82,
        quotaLong: Int? = 61,
        quotaStatus: String = "ok",
        quotaFresh: Bool = true,
        writerStatus: String = "ok"
    ) -> TaskLightUIState {
        let managedActive = blocked + stale + running + queued + pending
        return TaskLightUIState(
            source: "state_projector",
            projector_version: "preview",
            global_status: status,
            lamp_status: status,
            global_display_title: title,
            counts: TaskLightUICounts(
                blocked: blocked,
                stale: stale,
                running: running,
                queued: queued,
                pending_verify_count: pending,
                done_verified_visible: done,
                observed_active: observed,
                appserver_active: running,
                process_observed: observedOnly ? observed : running + observed,
                managed_active: managedActive
            ),
            tasks: previewTasks(blocked: blocked, stale: stale, running: running, queued: queued, pending: pending, done: done),
            observations: previewObservations(count: observed),
            runtime_candidates: observedOnly ? [
                TaskLightRuntimeCandidate(
                    candidate_id: "preview-process-only",
                    kind: "process",
                    source_set: ["process_observer"],
                    display_scope: "ignored",
                    why_ignored: "process_only_not_authoritative"
                )
            ] : [],
            quota: quotaFresh ? CodexQuotaUIState(
                source: "preview",
                fresh: true,
                status: quotaStatus,
                effective_remaining_percent: quotaShort,
                short_percent: quotaShort,
                short_label: "short",
                long_percent: quotaLong,
                long_label: "weekly",
                manual_resets_available: 0
            ) : nil,
            diagnostics: TaskLightUIDiagnostics(
                writer_status: writerStatus,
                hook_bridge_status: "ok",
                signal_bus_status: "readable",
                latest_signal_age_sec: running > 0 ? 2 : 18,
                runtime_candidate_count: observedOnly ? 1 : managedActive,
                quota_status: quotaStatus,
                quota_fresh: quotaFresh,
                quota_source: quotaFresh ? "preview" : nil,
                quota_probe_status: quotaFresh ? "ok" : "unknown"
            )
        )
    }

    private static func previewTasks(
        blocked: Int,
        stale: Int,
        running: Int,
        queued: Int,
        pending: Int,
        done: Int
    ) -> [TaskLightUITask] {
        var output: [TaskLightUITask] = []
        output.append(contentsOf: makeTasks(count: blocked, status: TaskLightStatus.blocked.rawValue, scope: "open_blocker", title: "Blocked Codex task"))
        output.append(contentsOf: makeTasks(count: stale, status: TaskLightStatus.stale.rawValue, scope: "stale_blocker", title: "Stale projector task"))
        output.append(contentsOf: makeTasks(count: running, status: TaskLightStatus.running.rawValue, scope: "active_execution", title: "Running Codex task"))
        output.append(contentsOf: makeTasks(count: queued, status: TaskLightStatus.queued.rawValue, scope: "active_execution", title: "Queued Codex task"))
        output.append(contentsOf: makeTasks(count: pending, status: TaskLightStatus.done_unverified.rawValue, scope: "pending_verify", title: "Pending verification task"))
        output.append(contentsOf: makeTasks(count: done, status: TaskLightStatus.done_verified.rawValue, scope: "recent_done", title: "Verified task"))
        return output
    }

    private static func makeTasks(count: Int, status: String, scope: String, title: String) -> [TaskLightUITask] {
        guard count > 0 else { return [] }
        return (1...count).map { index in
            TaskLightUITask(
                task_id: "preview-\(status)-\(index)",
                short_task_id: "p\(index)",
                title: "\(title) \(index)",
                raw_status: status,
                effective_status: status,
                display_scope: scope,
                fresh: true,
                phase: "preview",
                progress: status == TaskLightStatus.done_verified.rawValue ? 1 : 0.54,
                message: "Visual matrix fixture",
                updated_at: TaskLightTaskRecord.nowString()
            )
        }
    }

    private static func previewObservations(count: Int) -> [TaskLightUIObservation] {
        guard count > 0 else { return [] }
        return (1...count).map { index in
            TaskLightUIObservation(
                observation_id: "preview-observed-\(index)",
                title: "Observed Codex thread \(index)",
                status: TaskLightObservationStatus.observed_active.rawValue,
                confidence: 0.82,
                display_scope: "observed_only",
                fresh: true,
                last_seen_age_sec: 4,
                pid: 4000 + index,
                command_short: "codex observed"
            )
        }
    }
}
