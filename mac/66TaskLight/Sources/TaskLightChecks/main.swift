import Foundation
import TaskLightCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("TaskLightChecks failed: \(message)\n".utf8))
    exit(1)
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

func makeTempStateDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tasklight-checks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

do {
    let stateDirectory = try makeTempStateDirectory()
    defer { try? FileManager.default.removeItem(at: stateDirectory) }

    let config = TaskLightConfig(
        stateDirectory: stateDirectory,
        ttlSeconds: 1,
        verificationTTLSeconds: 1,
        refreshSeconds: 0.25,
        blockedSoundName: "Basso",
        doneSoundName: "Submarine",
        staleSoundName: "Funk"
    )

    let store = TaskLightStore(config: config)
    store.ensureLayout()

    let json = """
    {
      "schema_version": 2,
      "task_id": "20260609-120000-alpha-1234abcd",
      "short_task_id": "1234abcd",
      "title": "Alpha",
      "slug": "alpha",
      "status": "running",
      "raw_status": "running",
      "effective_status": "running",
      "heartbeat_at": "\(TaskLightTaskRecord.nowString())",
      "updated_at": "\(TaskLightTaskRecord.nowString())",
      "ttl_seconds": 300,
      "source": "tasklight"
    }
    """
    let decoded = try JSONDecoder().decode(TaskLightTaskRecord.self, from: Data(json.utf8))
    check(decoded.task_id == "20260609-120000-alpha-1234abcd", "task record decodes")
    check(decoded.liveStatus(ttlSeconds: 300, verificationTTLSeconds: 300) == .running, "live status is running")

    let first = TaskLightTaskSummary(
        schema_version: 2,
        task_id: "20260609-120000-alpha-1234abcd",
        short_task_id: "1234abcd",
        title: "Alpha",
        slug: "alpha",
        status: TaskLightStatus.blocked.rawValue,
        raw_status: TaskLightStatus.blocked.rawValue,
        effective_status: TaskLightStatus.blocked.rawValue,
        phase: "build",
        progress: 0.4,
        reason: "missing_input",
        message: "missing dependency",
        evidence: "tool unavailable",
        summary: nil,
        created_at: TaskLightTaskRecord.nowString(),
        started_at: TaskLightTaskRecord.nowString(),
        updated_at: TaskLightTaskRecord.nowString(),
        heartbeat_at: nil,
        done_at: nil,
        verified_at: nil,
        cancelled_at: nil,
        ttl_seconds: 300,
        last_error: nil,
        file_path: nil,
        alert_fingerprint: "fingerprint",
        sound_type: "blocked",
        is_invalid_json: false,
        invalid_json_error: nil
    )
    let second = first
    check(first.alert_fingerprint == second.alert_fingerprint, "blocked fingerprint stable")

    let a = store.loadDashboard()
    check(a.global_status == "idle", "empty dashboard idle")

    let taskOne = store.loadDashboard()
    check(taskOne.counts.gray >= 1, "gray count present for idle")

    let running = store.loadTask(taskID: "20260609-120000-alpha-1234abcd")
    check(running == nil, "missing task is nil")

    let now = TaskLightTaskRecord.nowString()
    let startA = TaskLightTaskRecord(
        task_id: "20260609-120000-alpha-11111111",
        title: "Alpha",
        slug: "alpha",
        status: "running",
        phase: "run",
        progress: 0.1,
        created_at: now,
        started_at: now,
        updated_at: now,
        heartbeat_at: now,
        ttl_seconds: 300
    )
    let startB = TaskLightTaskRecord(
        task_id: "20260609-120001-beta-22222222",
        title: "Beta",
        slug: "beta",
        status: "blocked",
        phase: "run",
        progress: 0.2,
        reason: "missing_input",
        message: "blocked",
        evidence: "evidence",
        created_at: now,
        started_at: now,
        updated_at: now,
        heartbeat_at: now,
        ttl_seconds: 300
    )
    let third = TaskLightTaskRecord(
        task_id: "20260609-120002-gamma-33333333",
        title: "Gamma",
        slug: "gamma",
        status: "done_unverified",
        phase: "finish",
        progress: 0.9,
        summary: "pending verification",
        created_at: now,
        started_at: now,
        updated_at: now,
        heartbeat_at: now,
        done_at: now,
        ttl_seconds: 300
    )
    try JSONEncoder().encode(startA).write(to: store.taskURL(taskID: startA.task_id))
    try JSONEncoder().encode(startB).write(to: store.taskURL(taskID: startB.task_id))
    try JSONEncoder().encode(third).write(to: store.taskURL(taskID: third.task_id))

    let dashboard = store.loadDashboard()
    check(dashboard.tasks.count == 3, "three tasks loaded")
    check(dashboard.tasks.first?.status == "blocked", "blocked sorts first")
    check(dashboard.tasks.last?.status == "done_unverified", "done_unverified sorts after running/queued")
    check(dashboard.counts.pending_verify_count == 1, "pending verify count increments")
    check(dashboard.global_status == "blocked", "blocked task forces global red")

    let staleTask = TaskLightTaskRecord(
        task_id: "20260609-120003-stale-44444444",
        title: "Stale",
        slug: "stale",
        status: "running",
        phase: "run",
        progress: 0.5,
        created_at: "2020-01-01T00:00:00Z",
        started_at: "2020-01-01T00:00:00Z",
        updated_at: "2020-01-01T00:00:00Z",
        heartbeat_at: "2020-01-01T00:00:00Z",
        ttl_seconds: 1
    )
    try JSONEncoder().encode(staleTask).write(to: store.taskURL(taskID: staleTask.task_id))
    let loaded = store.loadDashboard()
    check(loaded.tasks.contains(where: { $0.task_id == staleTask.task_id && $0.status == "stale" }), "stale task detected")

    let pendingTask = TaskLightTaskRecord(
        task_id: "20260609-120005-pending-66666666",
        title: "Pending",
        slug: "pending",
        status: "done_unverified",
        phase: "finish",
        progress: 0.9,
        summary: "awaiting acceptance",
        created_at: "2020-01-01T00:00:00Z",
        started_at: "2020-01-01T00:00:00Z",
        updated_at: "2020-01-01T00:00:00Z",
        done_at: "2020-01-01T00:00:00Z",
        ttl_seconds: 300
    )
    try JSONEncoder().encode(pendingTask).write(to: store.taskURL(taskID: pendingTask.task_id))
    let pendingLoaded = store.loadDashboard()
    check(pendingLoaded.tasks.contains(where: { $0.task_id == pendingTask.task_id && $0.status == "stale" }), "verification timeout becomes stale")
    check(pendingLoaded.counts.pending_verify_count == 1, "expired pending verify no longer counts pending")

    let badURL = store.taskURL(taskID: "20260609-120004-bad-55555555")
    try "{\"broken\":".data(using: .utf8)!.write(to: badURL)
    let corrupted = store.loadDashboard()
    check(corrupted.invalid_tasks.contains(where: { $0.task_id == "20260609-120004-bad-55555555" }), "invalid JSON isolated")

    let observation = TaskLightObservationRecord(
        observation_id: "4321-obs-abcd1234",
        pid: 4321,
        ppid: 1234,
        command: "python3 -c 'import time; time.sleep(10)' codex-observed-thread",
        command_short: "python3 -c 'import time; time.sleep(10)' codex-observed-thread",
        cwd: "/tmp/codex-observed",
        cwd_hash: "abcd1234",
        title: "codex-observed",
        detected_at: TaskLightTaskRecord.nowString(),
        last_seen_at: TaskLightTaskRecord.nowString(),
        status: TaskLightObservationStatus.observed_active.rawValue,
        confidence: 0.88
    )
    let observationState = TaskLightObservationsState(
        counts: TaskLightObservationCounts(active: 1, quiet: 0, attention: 0, disappeared: 0, linked_managed: 0, total: 1),
        observations: [observation]
    )
    try JSONEncoder().encode(observationState).write(to: config.observationsStateURL)
    let combined = store.loadDashboard()
    check(combined.observations_state?.counts.active == 1, "observations state merges into dashboard")
    check(combined.observations_state?.observations.first?.observation_id == observation.observation_id, "observation record decodes")

    var ledger = TaskLightPlayedEventsLedger()
    let event = TaskLightEventRecord(
        event_id: "evt-1",
        task_id: startB.task_id,
        from: "running",
        to: "blocked",
        created_at: TaskLightTaskRecord.nowString(),
        sound_type: "blocked"
    )
    ledger.played_event_ids.append(event.event_id)
    ledger.sound_windows["blocked"] = TaskLightSoundWindow(last_played_at: event.created_at, last_event_id: event.event_id)
    store.savePlayedLedger(ledger)
    let reloaded = store.loadPlayedLedger()
    check(reloaded.played_event_ids.contains("evt-1"), "played ledger persists")

    print("TaskLightChecks passed")
} catch {
    fail(error.localizedDescription)
}
