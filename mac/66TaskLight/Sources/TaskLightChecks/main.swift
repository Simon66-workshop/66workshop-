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

func checkNear(_ lhs: CGFloat, _ rhs: CGFloat, _ message: String, tolerance: CGFloat = 0.01) {
    if abs(lhs - rhs) > tolerance {
        fail("\(message): \(lhs) != \(rhs)")
    }
}

func makeTempStateDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tasklight-checks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

if let expectedFallback = ProcessInfo.processInfo.environment["TASKLIGHT_CHECK_EXPECTED_FALLBACK"] {
    let store = TaskLightStore(config: .fromEnvironment())
    let state = store.loadProjectedUIState()
    let fallback = state.diagnostics.fallback_reason ?? "none"
    print("projected_source=\(state.source)")
    print("fallback_reason=\(fallback)")
    exit(state.source == "swift_fallback" && fallback == expectedFallback ? 0 : 1)
}

if let uiStatePath = ProcessInfo.processInfo.environment["TASKLIGHT_CHECK_UI_STATE_PATH"] {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: uiStatePath))
        _ = try JSONDecoder().decode(TaskLightUIState.self, from: data)
        print("ui_state_decode=ok")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("ui_state_decode=failed \(error)\n".utf8))
        exit(1)
    }
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
	        projector_version: "M3.7",
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
	                state_cause: "codex_hook:item_started",
	                why_ignored: nil
	            )
	        ],
	        quota: CodexQuotaUIState(
	            source: "clipboard_import",
	            fresh: true,
	            status: "watch",
	            effective_remaining_percent: 42,
	            display_windows: [
	                CodexQuotaWindowUIState(
	                    id: "short",
	                    label: "5小时",
	                    bucket_id: "manual",
	                    remaining_percent: 93,
	                    reset_label: "11:44",
	                    reset_at: "2026-06-18T11:44:00+08:00",
	                    window_duration_mins: 300,
	                    health: "ok",
	                    selection_reason: "selected_manual_or_unknown_bucket_from_1_candidate"
	                ),
	                CodexQuotaWindowUIState(
	                    id: "long",
	                    label: "1周",
	                    bucket_id: "manual",
	                    remaining_percent: 42,
	                    reset_label: "6月18日",
	                    reset_at: "2026-06-18T00:00:00+08:00",
	                    window_duration_mins: 10080,
	                    health: "watch",
	                    selection_reason: "selected_manual_or_unknown_bucket_from_1_candidate"
	                )
	            ],
	            raw_window_count: 2,
	            captured_age_sec: 1,
	            probe_mode: "manual",
	            bucket_id: "manual",
	            warnings: [],
	            short_percent: 93,
	            short_label: "5小时",
	            short_reset_label: "11:44",
	            short_bucket_id: "manual",
	            long_percent: 42,
	            long_label: "1周",
	            long_reset_label: "6月18日",
	            long_bucket_id: "manual",
	            manual_resets_available: 1,
	            manual_resets_total_count: 3,
	            manual_resets_used_count: 0,
	            manual_resets_expired_count: 0,
	            manual_resets_next_expiry: "2026-07-18",
	            manual_reset_credits: [
	                CodexQuotaResetCreditUIState(id: "reset_credit_1", status: "available", issued_at: "2026-06-18T08:28:29+08:00", issued_date: "2026-06-18", expires_at: "2026-07-18T08:28:29+08:00", expiry_date: "2026-07-18", redeemed: false),
	                CodexQuotaResetCreditUIState(id: "reset_credit_2", status: "available", issued_at: "2026-06-27T07:12:43+08:00", issued_date: "2026-06-26", expires_at: "2026-07-27T07:12:43+08:00", expiry_date: "2026-07-26", redeemed: false),
	                CodexQuotaResetCreditUIState(id: "reset_credit_3", status: "available", issued_at: "2026-07-02T03:46:38+08:00", issued_date: "2026-07-01", expires_at: "2026-08-01T03:46:38+08:00", expiry_date: "2026-07-31", redeemed: false)
	            ],
	            captured_at: uiNow,
	            recommendation: "watch_usage"
	        ),
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
	                    display_scope: "ignored",
	                    why_ignored: "runtime_score_below_threshold"
	                )
	            ],
	            appserver_active_count: 1,
	            process_observed_count: 1,
	            quota_status: "watch",
	            quota_fresh: true,
	            quota_source: "clipboard_import",
	            quota_state_path: config.stateDirectory.appendingPathComponent("quota_state.json").path,
	            quota_probe_status: "ok",
	            quota_probe_health_path: config.stateDirectory.appendingPathComponent("quota_probe_health.json").path,
	            quota_warning_count: 0
	        )
	    )
    try JSONEncoder().encode(projectedUIState).write(to: config.uiStateURL)
    let loadedUIState = store.loadProjectedUIState()
	    check(loadedUIState.source == "state_projector", "ui_state preferred when fresh")
	    check(loadedUIState.projector_version == "M3.7", "ui_state projector version decodes")
	    check(loadedUIState.global_display_title == "RUNNING", "ui_state title decodes")
	    check(TaskLightProjectedPresentation.displayTitle(from: loadedUIState) == "RUNNING", "ui_state presentation title follows projected running status")
	    check(loadedUIState.counts.running == 1, "ui_state counts decode")
	    check(loadedUIState.counts.appserver_active == 1, "ui_state appserver count decodes")
	    check(loadedUIState.counts.process_observed == 1, "ui_state process observed count decodes")
	    check(loadedUIState.runtime_candidates?.first?.display_scope == "active_execution", "ui_state runtime candidates decode")
	    check(loadedUIState.runtime_candidates?.first?.why_ignored == nil, "ui_state runtime candidates decode ignored reason")
	    check(loadedUIState.diagnostics.writer_status == "ok", "ui_state writer status decodes")
	    check(loadedUIState.quota?.status == "watch", "ui_state quota status decodes")
	    check(loadedUIState.quota?.short_percent == 93, "ui_state quota short percent decodes")
	    check(loadedUIState.quota?.long_percent == 42, "ui_state quota long percent decodes")
	    check(loadedUIState.quota?.manual_resets_available == 1, "ui_state quota reset count decodes")
	    check(loadedUIState.quota?.manual_resets_total_count == 3, "ui_state quota reset total decodes")
	    check(loadedUIState.quota?.manual_resets_next_expiry == "2026-07-18", "ui_state quota reset next expiry decodes")
	    check(loadedUIState.quota?.manual_reset_credits?.count == 3, "ui_state quota reset credits decode")
	    check(loadedUIState.quota?.manual_reset_credits?.first?.expires_at == "2026-07-18T08:28:29+08:00", "ui_state quota reset precise expiry decodes")
	    check(loadedUIState.quota?.display_windows?.count == 2, "ui_state quota display windows decode")
	    check(loadedUIState.quota?.display_windows?.first?.reset_at == "2026-06-18T11:44:00+08:00", "ui_state quota reset_at decodes")
	    check(loadedUIState.quota?.raw_window_count == 2, "ui_state quota raw window count decodes")
	    check(loadedUIState.quota?.bucket_id == "manual", "ui_state quota bucket id decodes")
	    check(loadedUIState.diagnostics.quota_status == "watch", "ui_state diagnostics decode quota status")
	    check(loadedUIState.diagnostics.quota_probe_status == "ok", "ui_state diagnostics decode quota probe status")
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
	    check(loadedUIState.diagnostics.top_runtime_candidates?.first?.why_ignored == "runtime_score_below_threshold", "ui_state diagnostics decode runtime ignored reason")

        var appServerQuotaUIState = loadedUIState
        appServerQuotaUIState.quota?.source = "codex_appserver"
        appServerQuotaUIState.quota?.captured_age_sec = 3
        let providerSnapshot = CodexUsageProviderAdapter().snapshot(from: appServerQuotaUIState)
        check(providerSnapshot.source_label == "ChatGPT Work local app-server", "provider exposes local ChatGPT Work source")
        check(providerSnapshot.freshness_label == "fresh 3s", "provider exposes quota freshness")
        check(providerSnapshot.conflict_label == nil, "provider has no synthetic source conflict")
        var cachedProviderUIState = appServerQuotaUIState
        cachedProviderUIState.quota?.source = "codex_appserver_cached"
        cachedProviderUIState.quota?.fresh = false
        cachedProviderUIState.quota?.warnings = ["appserver_schema_changed"]
        let cachedProviderSnapshot = CodexUsageProviderAdapter().snapshot(from: cachedProviderUIState)
        check(cachedProviderSnapshot.source_label == "Last valid ChatGPT Work snapshot", "provider labels cached app-server data")
        check(cachedProviderSnapshot.freshness_label == "stale", "provider marks cached app-server data stale")
        check(cachedProviderSnapshot.conflict_label == "Source changed; using the last valid local snapshot", "provider exposes schema defense")
        let legacyProviderJSON = """
        {"id":"codex","display_name":"Codex","health":"ok","quota_text":"⚡42·93","remaining_percent":42,"is_low_quota":false,"updated_at":"2026-07-10T00:00:00Z","diagnostic_only":true}
        """
        let legacyProvider = try JSONDecoder().decode(UsageProviderSnapshot.self, from: Data(legacyProviderJSON.utf8))
        check(legacyProvider.source_label == nil && legacyProvider.freshness_label == nil, "legacy provider snapshots remain decodable")

    var mismatchedTitleUIState = projectedUIState
    mismatchedTitleUIState.global_status = "running"
    mismatchedTitleUIState.lamp_status = "running"
    mismatchedTitleUIState.global_display_title = "DONE"
    check(TaskLightProjectedPresentation.displayTitle(from: mismatchedTitleUIState) == "RUNNING", "ui_state presentation guards stale Done title during projected running")
    check(TaskLightProjectedPresentation.primaryStatus(from: mismatchedTitleUIState) == "running", "ui_state presentation primary status follows projected running")

    var unresolvedStaleUIState = TaskLightUIState()
    unresolvedStaleUIState.counts.stale = 1
    check(TaskLightProjectedPresentation.primaryStatus(from: unresolvedStaleUIState) == "idle", "unresolved stale presentation does not promote the primary lamp")
    check(TaskLightProjectedPresentation.menuBarStatusLabel(from: unresolvedStaleUIState) == "Stale", "menu bar exposes unresolved stale work instead of clean Idle")
    check(TaskLightProjectedPresentation.menuBarActivityCount(from: unresolvedStaleUIState) == 1, "menu bar counts unresolved stale work")

    let cleanIdleUIState = TaskLightUIState()
    check(TaskLightProjectedPresentation.menuBarStatusLabel(from: cleanIdleUIState) == "Idle", "clean idle remains Idle")
    check(TaskLightProjectedPresentation.menuBarActivityCount(from: cleanIdleUIState) == 0, "clean idle remains zero")

    var weakObservedUIState = TaskLightUIState()
    weakObservedUIState.runtime_candidates = [
        TaskLightRuntimeCandidate(
            candidate_id: "turn:weak-observed",
            source_set: ["codex_hook"],
            freshness_score: 0.5,
            display_scope: "observed_only",
            state_cause: "codex_hook:item_started"
        )
    ]
    check(TaskLightProjectedPresentation.primaryStatus(from: weakObservedUIState) == "idle", "weak observed work does not promote the primary lamp")
    check(TaskLightProjectedPresentation.menuBarStatusLabel(from: weakObservedUIState) == "Watch", "menu bar exposes weak observed work instead of clean Idle")
    check(TaskLightProjectedPresentation.menuBarActivityCount(from: weakObservedUIState) == 1, "menu bar counts fresh weak observed work")

    var hookRunningUIState = TaskLightUIState(global_status: "running", lamp_status: "running", global_display_title: "RUNNING")
    hookRunningUIState.runtime_candidates = [
        TaskLightRuntimeCandidate(
            candidate_id: "turn:authoritative-running",
            source_set: ["codex_hook"],
            freshness_score: 1,
            display_scope: "active_execution",
            state_cause: "codex_hook:item_started"
        )
    ]
    check(TaskLightProjectedPresentation.menuBarActivityCount(from: hookRunningUIState) == 1, "menu bar counts authoritative active hook turns when managed task counts are empty")

    var processOnlyUIState = TaskLightUIState()
    processOnlyUIState.runtime_candidates = [
        TaskLightRuntimeCandidate(
            candidate_id: "process:diagnostic-only",
            source_set: ["process_observer"],
            freshness_score: 1,
            display_scope: "ignored",
            state_cause: "process_observer:running",
            why_ignored: "process_only_not_authoritative"
        )
    ]
    check(TaskLightProjectedPresentation.menuBarStatusLabel(from: processOnlyUIState) == "Idle", "process-only evidence does not change the menu status")
    check(TaskLightProjectedPresentation.menuBarActivityCount(from: processOnlyUIState) == 0, "process-only evidence does not increase the running count")

    try "{broken".data(using: .utf8)!.write(to: config.uiStateURL)
    let fallbackUIState = store.loadProjectedUIState()
    check(fallbackUIState.source == "swift_fallback", "corrupt ui_state falls back")
    check(fallbackUIState.diagnostics.fallback_reason == "projector_unreadable", "fallback reason records unreadable projector")

    var staleProjectedUIState = projectedUIState
    staleProjectedUIState.projector_generated_at = "2020-01-01T00:00:00Z"
    try JSONEncoder().encode(staleProjectedUIState).write(to: config.uiStateURL)
    let staleLoadedUIState = store.loadProjectedUIState()
    check(staleLoadedUIState.source == "swift_fallback", "readable stale ui_state stops driving the UI")
    check(staleLoadedUIState.diagnostics.fallback_reason == "projector_stale", "stale projector reason is explicit")

    let fallbackQuotaJSON = """
    {
      "schema_version": "0.2",
      "source": "codex_appserver",
      "fresh": true,
      "quota_status": "watch",
      "effective_remaining_percent": 41,
      "captured_at": "\(uiNow)",
      "recommendation": "watch_usage",
      "manual_resets": {
        "available_count": 3,
        "total_count": 3,
        "used_count": 0,
        "expired_count": 0,
        "next_expiry": "2026-07-18",
        "credits": [
          { "id": "reset_credit_1", "status": "available", "issued_date": "2026-06-18", "expiry_date": "2026-07-18", "redeemed": false },
          { "id": "reset_credit_2", "status": "available", "issued_date": "2026-06-26", "expiry_date": "2026-07-26", "redeemed": false },
          { "id": "reset_credit_3", "status": "available", "issued_date": "2026-07-01", "expiry_date": "2026-07-31", "redeemed": false }
        ]
      },
      "raw_windows": [
        {
          "bucket_id": "codex_bengalfox",
          "label": "5小时",
          "remaining_percent": 97,
          "reset_label": "15:18",
          "reset_at": "2026-06-18T15:18:00+08:00",
          "window_duration_mins": 300,
          "selection_reason": "raw_model_specific_codex_bucket"
        },
        {
          "bucket_id": "codex",
          "label": "5小时",
          "remaining_percent": 98,
          "reset_label": "16:45",
          "reset_at": "2026-06-18T16:45:00+08:00",
          "window_duration_mins": 300,
          "selection_reason": "raw_account_codex_bucket"
        },
        {
          "bucket_id": "codex_bengalfox",
          "label": "1周",
          "remaining_percent": 43,
          "reset_label": "6月18日",
          "reset_at": "2026-06-18T00:00:00+08:00",
          "window_duration_mins": 10080,
          "selection_reason": "raw_model_specific_codex_bucket"
        },
        {
          "bucket_id": "codex",
          "label": "1周",
          "remaining_percent": 40,
          "reset_label": "6月18日",
          "reset_at": "2026-06-18T00:00:00+08:00",
          "window_duration_mins": 10080,
          "selection_reason": "raw_account_codex_bucket"
        }
      ],
      "display_windows": [
        {
          "id": "short",
          "bucket_id": "codex",
          "label": "5小时",
          "remaining_percent": 98,
          "reset_label": "16:45",
          "reset_at": "2026-06-18T16:45:00+08:00",
          "window_duration_mins": 300,
          "selection_reason": "selected_account_codex_bucket_from_2_candidates"
        },
        {
          "id": "long",
          "bucket_id": "codex",
          "label": "1周",
          "remaining_percent": 40,
          "reset_label": "6月18日",
          "reset_at": "2026-06-18T00:00:00+08:00",
          "window_duration_mins": 10080,
          "selection_reason": "selected_account_codex_bucket_from_2_candidates"
        }
      ],
      "windows": [
        {
          "bucket_id": "codex_bengalfox",
          "label": "5小时",
          "remaining_percent": 97,
          "reset_label": "15:18",
          "reset_at": "2026-06-18T15:18:00+08:00",
          "window_duration_mins": 300
        },
        {
          "bucket_id": "codex",
          "label": "5小时",
          "remaining_percent": 98,
          "reset_label": "16:45",
          "reset_at": "2026-06-18T16:45:00+08:00",
          "window_duration_mins": 300
        },
        {
          "bucket_id": "codex_bengalfox",
          "label": "1周",
          "remaining_percent": 43,
          "reset_label": "6月18日",
          "reset_at": "2026-06-18T00:00:00+08:00",
          "window_duration_mins": 10080
        },
        {
          "bucket_id": "codex",
          "label": "1周",
          "remaining_percent": 40,
          "reset_label": "6月18日",
          "reset_at": "2026-06-18T00:00:00+08:00",
          "window_duration_mins": 10080
        }
      ]
    }
    """
    try fallbackQuotaJSON.data(using: .utf8)!.write(to: config.stateDirectory.appendingPathComponent("quota_state.json"))
    try "{broken".data(using: .utf8)!.write(to: config.uiStateURL)
    let quotaFallbackUIState = store.loadProjectedUIState()
    check(quotaFallbackUIState.source == "swift_fallback", "corrupt ui_state still enters fallback")
    check(quotaFallbackUIState.quota?.source == "codex_appserver", "fallback ui_state loads quota_state source")
    check(quotaFallbackUIState.quota?.short_percent == 98, "fallback ui_state prefers account-level short quota bucket")
    check(quotaFallbackUIState.quota?.long_percent == 40, "fallback ui_state prefers account-level long quota bucket")
    check(quotaFallbackUIState.quota?.raw_window_count == 4, "fallback ui_state records raw quota window count")
    check(quotaFallbackUIState.quota?.display_windows?.first?.reset_at == "2026-06-18T16:45:00+08:00", "fallback ui_state exposes quota reset_at")
    check(quotaFallbackUIState.quota?.manual_resets_available == 3, "fallback ui_state exposes reset credit available count")
    check(quotaFallbackUIState.quota?.manual_resets_next_expiry == "2026-07-18", "fallback ui_state exposes reset credit next expiry")
    check(quotaFallbackUIState.quota?.manual_reset_credits?.count == 3, "fallback ui_state exposes sanitized reset credits")
    check(quotaFallbackUIState.quota?.short_bucket_id == "codex", "fallback ui_state exposes short quota bucket")
    check(quotaFallbackUIState.diagnostics.quota_status == "watch", "fallback diagnostics records quota status")

    store.saveUIClientRecord(
        bundleID: "com.66tasklight.checks",
        bundlePath: "/tmp/66TaskLightChecks.app",
        executablePath: "/tmp/66TaskLightChecks",
        buildID: "checks"
    )
    let uiClientURL = config.uiClientsDirectoryURL.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier).json")
    check(FileManager.default.fileExists(atPath: uiClientURL.path), "ui client diagnostic writes")

    let coverageStatus = TaskLightWorkspaceCoverageRunStatus(
        status: "ok",
        message: "发现 2 个项目需要 Trust",
        updated_at: TaskLightTaskRecord.nowString(),
        latest_json_path: config.workspaceCoverageLatestJSONURL.path,
        report_path: config.workspaceCoverageLatestMarkdownURL.path
    )
    try JSONEncoder().encode(coverageStatus).write(to: config.workspaceCoverageRunStatusURL)
    let coverageReport = """
    {
      "schema_version": "0.1",
      "status": "needs_trust",
        "summary": {
        "workspace_count": 3,
        "preferred_workspace_count": 2,
        "trusted": 1,
        "preferred_trusted": 0,
        "installed_needs_trust": 2,
        "preferred_installed_needs_trust": 2,
        "missing_hooks": 0,
        "invalid_hooks": 0
        }
    }
    """
    try Data(coverageReport.utf8).write(to: config.workspaceCoverageLatestJSONURL)
    let coverage = store.loadWorkspaceCoveragePresentation()
    check(coverage?.message == "常用项目 2 个需要 Trust", "workspace coverage presentation prefers preferred summary")
    check(coverage?.isError == false, "workspace coverage presentation does not mark trust as error")

    let taskOne = store.loadFallbackDashboard()
    check(taskOne.counts.gray >= 1, "gray count present for idle")

    let compactSize = CGSize(width: 234.9, height: 181.395)
    let expandedSize = CGSize(width: 680, height: 500)
    let mainVisible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let sideVisible = CGRect(x: 1440, y: 0, width: 1280, height: 800)
    let edgeCompactFrame = CGRect(x: 1190, y: 690, width: compactSize.width, height: compactSize.height)
    let expandedFrame = TaskLightPanelGeometry.expandedFrame(
        from: edgeCompactFrame,
        expandedSize: expandedSize,
        visibleFrames: [mainVisible, sideVisible]
    )
    checkNear(expandedFrame.midX, mainVisible.midX, "expanded frame centers on compact screen x")
    checkNear(expandedFrame.midY, mainVisible.midY, "expanded frame centers on compact screen y")
    check(expandedFrame.width == expandedSize.width, "expanded frame uses expanded width")
    check(expandedFrame.height == expandedSize.height, "expanded frame uses expanded height")

    let sideCompactFrame = CGRect(x: 1500, y: 540, width: compactSize.width, height: compactSize.height)
    let sideExpandedFrame = TaskLightPanelGeometry.expandedFrame(
        from: sideCompactFrame,
        expandedSize: expandedSize,
        visibleFrames: [mainVisible, sideVisible]
    )
    checkNear(sideExpandedFrame.midX, sideVisible.midX, "expanded frame centers on external screen x")
    checkNear(sideExpandedFrame.midY, sideVisible.midY, "expanded frame centers on external screen y")

    let movedExpandedFrame = CGRect(x: 200, y: 120, width: expandedSize.width, height: expandedSize.height)
    let collapsedFrame = TaskLightPanelGeometry.collapsedCompactFrame(
        storedCompactFrame: edgeCompactFrame,
        currentExpandedFrame: movedExpandedFrame,
        compactSize: compactSize,
        visibleFrames: [mainVisible, sideVisible]
    )
    checkNear(collapsedFrame.origin.x, edgeCompactFrame.origin.x, "collapse restores pre-expanded compact x")
    checkNear(collapsedFrame.origin.y, edgeCompactFrame.origin.y, "collapse restores pre-expanded compact y")
    checkNear(collapsedFrame.width, compactSize.width, "collapse restores compact width")
    checkNear(collapsedFrame.height, compactSize.height, "collapse restores compact height")

    let offscreenCompact = CGRect(x: -500, y: -200, width: compactSize.width, height: compactSize.height)
    let restoredClampedCompact = TaskLightPanelGeometry.restoredCompactFrame(
        storedFrame: offscreenCompact,
        fallbackFrame: edgeCompactFrame,
        compactSize: compactSize,
        visibleFrames: [mainVisible]
    )
    check(restoredClampedCompact.minX >= mainVisible.minX, "restored compact clamps x into screen")
    check(restoredClampedCompact.minY >= mainVisible.minY, "restored compact clamps y into screen")
    check(TaskLightPanelGeometry.usesAnimatedWindowFrameChanges == false, "panel frame transitions are non-animated")
    check(TaskLightPanelGeometry.usesDualWindowSwap == true, "panel transitions use separate compact and expanded windows")
    check(TaskLightPanelGeometry.usesHiddenAtomicContentSwap == false, "dual-window transitions do not need hidden same-window frame swaps")
    check(TaskLightPanelGeometry.targetTransitionLatencyMilliseconds <= 50, "panel transition target is millisecond-level")
    let transitionScore = TaskLightPanelGeometry.transitionScore(
        expandsToCenter: true,
        restoresCompactOrigin: true,
        protectsCompactFrameDuringExpandedMove: true,
        usesHiddenAtomicContentSwap: TaskLightPanelGeometry.usesHiddenAtomicContentSwap,
        usesDualWindowSwap: TaskLightPanelGeometry.usesDualWindowSwap,
        transitionLatencyMilliseconds: 16,
        usesAnimation: TaskLightPanelGeometry.usesAnimatedWindowFrameChanges
    )
    check(transitionScore >= 95, "panel transition algorithm score is acceptable")
    let renderingScore = TaskLightUIPerformanceBudget.renderingScore(
        bellUsesCompositedAnimation: true,
        scrollUsesOptimizedCards: TaskLightUIPerformanceBudget.expandedScrollUsesOptimizedCards,
        scrollDisablesCardPulseAnimations: TaskLightUIPerformanceBudget.expandedScrollDisablesCardPulseAnimations,
        scrollAvoidsPerCardMaterial: TaskLightUIPerformanceBudget.expandedScrollAvoidsPerCardMaterial
    )
    check(TaskLightUIPerformanceBudget.compactBellSwingDurationSeconds >= 1.5, "bell swing is low-frequency enough to avoid jitter")
    check(renderingScore >= 95, "LuckyCat rendering performance score is acceptable")

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

    let replayTime = TaskLightTaskRecord.nowString()
    store.appendUIEventFlowRecord([
        "recorded_at": replayTime,
        "previous_global_status": "idle",
        "global_status": "running",
        "lamp_status": "running",
        "counts": ["running": 1, "pending_verify_count": 0, "blocked": 0, "observed_active": 0],
        "projector_reason": ["active_execution"],
        "writer_status": "ok",
        "hook_bridge_status": "ok",
        "current_thread_signal_status": "running",
        "current_thread_fusion_decision": "refresh_managed_heartbeat"
    ])
    let replaySince = Date().addingTimeInterval(-60)
    let firstReplayRead = store.loadStatusReplayRecords(since: replaySince, limit: 8)
    let secondReplayRead = store.loadStatusReplayRecords(since: replaySince, limit: 8)
    check(firstReplayRead.contains(where: { $0.to_status == "running" }), "status replay reads recent bounded event tail")
    check(firstReplayRead == secondReplayRead, "status replay reuses unchanged event-flow cache")

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
