import TaskLightCore

enum LuckyCatPreviewData {
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
}
