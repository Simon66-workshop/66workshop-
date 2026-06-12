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

    let a = store.loadFallbackDashboard()
    check(a.global_status == "idle", "empty dashboard idle")

    let uiNow = TaskLightTaskRecord.nowString()
	    let projectedUIState = TaskLightUIState(
	        projector_version: "M3.3",
	        projector_pid: Int(ProcessInfo.processInfo.processIdentifier),
	        projector_executable_path: "/tmp/state_projector.py",
	        projector_code_hash: "sha256:checks",
	        projector_launch_label: "com.66tasklight.state-projector",
	        projector_instance_id: "checks",
	        global_status: "running",
	        lamp_status: "running",
        global_display_title: "RUNNING",
        state_confidence: 0.95,
	        counts: TaskLightUICounts(running: 1, appserver_active: 1, process_observed: 1, managed_active: 1),
	        tasks: [
            TaskLightUITask(
                task_id: "20260609-120000-ui-99999999",
                short_task_id: "99999999",
                title: "UI projected task",
                source: "state_projector",
                raw_status: "running",
                effective_status: "running",
                display_scope: "active_execution",
                state_cause: "hook:item_started",
                fresh: true,
                phase: "tool_running",
                progress: 0.5,
                started_at: uiNow,
                updated_at: uiNow,
                confidence: 0.95
            )
	        ],
	        runtime_candidates: [
	            TaskLightRuntimeCandidate(
	                candidate_id: "turn:turn-1",
	                kind: "codex_turn",
	                task_id: "20260609-120000-ui-99999999",
	                thread_id: "thread-1",
	                turn_id: "turn-1",
	                source_set: ["codex_hook", "codex_appserver"],
	                last_signal_at: uiNow,
	                last_event_type: "item_started",
	                base_confidence: 0.95,
	                freshness_score: 1,
	                identity_score: 1,
	                consistency_score: 1,
	                runtime_score: 0.95,
	                display_scope: "active_execution",
	                state_cause: "codex_hook:item_started"
	            )
	        ],
	        diagnostics: TaskLightUIDiagnostics(
	            writer_status: "ok",
	            hook_bridge_status: "ok",
            signal_bus_status: "readable",
            signal_bus_record_count: 7,
            signal_bus_source_counts: ["codex_hook": 4, "current_thread_watcher": 2, "hook_bridge": 1],
            active_turn_bindings: 1,
            latest_signal_age_sec: 1,
            latest_hook_signal_age_sec: 0.7,
            latest_hook_bridge_signal_age_sec: 0.9,
            latest_process_observer_signal_age_sec: 2.4,
            latest_private_probe_signal_age_sec: 1.6,
            latest_private_probe_status: "active",
            latest_private_probe_quality: "thread_private_metadata",
            latest_private_probe_confidence: 0.78,
            current_thread_binding_status: "active",
            current_thread_binding_fresh: true,
            latest_current_thread_binding_age_sec: 0.8,
            latest_current_thread_signal_age_sec: 0.4,
            current_thread_task_identity: "thread-1:turn-1",
            current_thread_signal_source: "current_thread_watcher",
            current_thread_signal_quality: "thread_private_metadata",
            current_thread_signal_confidence: 0.78,
            current_thread_signal_status: "running",
            current_thread_fusion_decision: "refresh_managed_heartbeat",
            latest_turn_binding_status: "active",
            latest_turn_binding_age_sec: 0.6,
            latest_turn_binding_turn_id: "turn-1",
            latest_turn_binding_task_id: "20260609-120000-ui-99999999",
            latest_turn_binding_canonical_identity: "turn:turn-1",
            latest_turn_binding_aliases: ["hook:unknown:turn-1", "appserver:thread-1:turn-1"],
            latest_turn_signal_event: "item_started",
            latest_bridge_decision: "heartbeat",
	            state_dir: stateDirectory.path,
	            projector_reason: ["active_execution"],
	            binding_identity_count: 3,
	            runtime_candidate_count: 1,
	            top_runtime_candidates: [
	                TaskLightRuntimeCandidate(
	                    candidate_id: "turn:turn-1",
	                    source_set: ["codex_hook", "codex_appserver"],
	                    runtime_score: 0.95,
	                    display_scope: "active_execution"
	                )
	            ],
	            appserver_active_count: 1,
	            process_observed_count: 1
	        )
	    )
    try JSONEncoder().encode(projectedUIState).write(to: config.uiStateURL)
    let loadedUIState = store.loadProjectedUIState()
	    check(loadedUIState.source == "state_projector", "ui_state preferred when fresh")
	    check(loadedUIState.projector_version == "M3.3", "ui_state projector version decodes")
	    check(loadedUIState.global_display_title == "RUNNING", "ui_state title decodes")
	    check(loadedUIState.counts.running == 1, "ui_state counts decode")
	    check(loadedUIState.counts.appserver_active == 1, "ui_state appserver count decodes")
	    check(loadedUIState.counts.process_observed == 1, "ui_state process observed count decodes")
	    check(loadedUIState.runtime_candidates?.first?.display_scope == "active_execution", "ui_state runtime candidates decode")
	    check(loadedUIState.diagnostics.writer_status == "ok", "ui_state writer status decodes")
	    check(loadedUIState.diagnostics.signal_bus_status == "readable", "ui_state diagnostics decode signal bus status")
    check(loadedUIState.diagnostics.signal_bus_record_count == 7, "ui_state diagnostics decode signal bus record count")
    check(loadedUIState.diagnostics.signal_bus_source_counts?["codex_hook"] == 4, "ui_state diagnostics decode signal bus source counts")
    check(loadedUIState.diagnostics.latest_private_probe_status == "active", "ui_state diagnostics decode private probe status")
    check(loadedUIState.diagnostics.latest_private_probe_quality == "thread_private_metadata", "ui_state diagnostics decode private probe quality")
    check(loadedUIState.diagnostics.current_thread_binding_status == "active", "ui_state diagnostics decode current thread binding status")
    check(loadedUIState.diagnostics.current_thread_binding_fresh == true, "ui_state diagnostics decode current thread freshness")
    check(loadedUIState.diagnostics.current_thread_signal_source == "current_thread_watcher", "ui_state diagnostics decode current thread signal source")
    check(loadedUIState.diagnostics.latest_bridge_decision == "heartbeat", "ui_state diagnostics decode latest bridge decision")
    check(loadedUIState.diagnostics.latest_turn_binding_canonical_identity == "turn:turn-1", "ui_state diagnostics decode canonical turn identity")
	    check(loadedUIState.diagnostics.latest_turn_binding_aliases?.contains("appserver:thread-1:turn-1") == true, "ui_state diagnostics decode binding aliases")
	    check(loadedUIState.diagnostics.binding_identity_count == 3, "ui_state diagnostics decode binding identity count")
	    check(loadedUIState.diagnostics.runtime_candidate_count == 1, "ui_state diagnostics decode runtime candidate count")

    try "{broken".data(using: .utf8)!.write(to: config.uiStateURL)
    let fallbackUIState = store.loadProjectedUIState()
    check(fallbackUIState.source == "swift_fallback", "corrupt ui_state falls back")
    check(fallbackUIState.diagnostics.fallback_reason == "projector_unreadable", "fallback reason records unreadable projector")

    var staleProjectedUIState = projectedUIState
    staleProjectedUIState.projector_generated_at = "2020-01-01T00:00:00Z"
    try JSONEncoder().encode(staleProjectedUIState).write(to: config.uiStateURL)
    let staleFallbackUIState = store.loadProjectedUIState()
    check(staleFallbackUIState.source == "swift_fallback", "stale ui_state falls back")
    check(staleFallbackUIState.diagnostics.fallback_reason == "projector_stale", "fallback reason records stale projector")

    store.saveUIClientRecord(
        bundleID: "com.66tasklight.checks",
        bundlePath: "/tmp/66TaskLightChecks.app",
        executablePath: "/tmp/66TaskLightChecks",
        buildID: "checks"
    )
    let uiClientURL = config.uiClientsDirectoryURL.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier).json")
    check(FileManager.default.fileExists(atPath: uiClientURL.path), "ui client diagnostic writes")

    let taskOne = store.loadFallbackDashboard()
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

    let dashboard = store.loadFallbackDashboard()
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
    let loaded = store.loadFallbackDashboard()
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
    let pendingLoaded = store.loadFallbackDashboard()
    check(pendingLoaded.tasks.contains(where: { $0.task_id == pendingTask.task_id && $0.status == "stale" }), "verification timeout becomes stale")
    check(pendingLoaded.counts.pending_verify_count == 1, "expired pending verify no longer counts pending")

    let badURL = store.taskURL(taskID: "20260609-120004-bad-55555555")
    try "{\"broken\":".data(using: .utf8)!.write(to: badURL)
    let corrupted = store.loadFallbackDashboard()
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
    let combined = store.loadFallbackDashboard()
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
