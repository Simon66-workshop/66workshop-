import Foundation
import Testing
import TaskLightCore

private final class SnapshotResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TaskLightRenderSnapshot?

    func set(_ snapshot: TaskLightRenderSnapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    func get() -> TaskLightRenderSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("TaskLightCore")
public struct TaskLightCoreTestSuite {
    @Test("Snapshot decoding preserves a fresh running status")
    public func snapshotDecodingAndEffectiveStatus() throws {
        let now = TaskLightTaskRecord.nowString()
        let record = TaskLightTaskRecord(
            task_id: "abc",
            title: "Sample",
            slug: "sample",
            status: TaskLightStatus.running.rawValue,
            updated_at: now,
            heartbeat_at: now,
            ttl_seconds: 300
        )
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TaskLightTaskRecord.self, from: encoded)

        #expect(decoded.task_id == "abc")
        #expect(decoded.liveStatus(ttlSeconds: 300, verificationTTLSeconds: 300) == .running)
    }

    @Test("Played event ledger starts with bounded sound windows")
    public func playedEventLedgerDefaults() {
        let ledger = TaskLightPlayedEventsLedger()

        #expect(ledger.played_event_ids.isEmpty)
        #expect(ledger.sound_windows.keys.sorted() == ["blocked", "done_verified"])
    }

    @Test("Projector freshness expires within the ten second acceptance window")
    public func projectorFreshnessExpires() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = TaskLightTaskRecord.nowString(from: now.addingTimeInterval(-4.9))
        let stale = TaskLightTaskRecord.nowString(from: now.addingTimeInterval(-5.1))

        #expect(TaskLightStore.isProjectorTimestampFresh(fresh, maxAgeSeconds: 5, now: now))
        #expect(!TaskLightStore.isProjectorTimestampFresh(stale, maxAgeSeconds: 5, now: now))
    }

    @Test("Reliability and UI latency budgets stay inside acceptance bounds")
    public func reliabilityBudgets() {
        #expect(TaskLightUIPerformanceBudget.projectorFreshnessMaxSeconds + 5 <= 10)
        #expect(TaskLightUIPerformanceBudget.duplicateSignalRateMax <= 0.01)
        #expect(TaskLightUIPerformanceBudget.menuOpenMaxMilliseconds <= 450)
        #expect(TaskLightUIPerformanceBudget.radarOpenMaxMilliseconds <= 180)
        #expect(TaskLightUIPerformanceBudget.expandedApplyMaxMilliseconds <= 650)
        #expect(TaskLightUIPerformanceBudget.renderSnapshotLoadMaxMilliseconds <= 160)
    }

    @Test("Render snapshots coalesce local read-model data off the UI surface")
    public func renderSnapshotCoordinatorLoadsBoundedPayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tasklight-render-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = TaskLightConfig(
            stateDirectory: root,
            ttlSeconds: 300,
            verificationTTLSeconds: 900,
            refreshSeconds: 5,
            blockedSoundName: "Basso",
            doneSoundName: "Submarine",
            staleSoundName: "Funk"
        )
        let store = TaskLightStore(config: config)
        store.ensureLayout()
        let coordinator = TaskLightRenderSnapshotCoordinator(config: config)
        let semaphore = DispatchSemaphore(value: 0)
        let first = SnapshotResultBox()
        coordinator.refresh {
            first.set($0)
            semaphore.signal()
        }
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        #expect(first.get() != nil)
        #expect(first.get()?.recentEvents.count ?? 0 <= TaskLightUIPerformanceBudget.expandedRecentEventLimit)
        #expect(first.get()?.statusReplay.count ?? 0 <= TaskLightUIPerformanceBudget.statusReplayRenderLimit)
        #expect(first.get()?.workspaceDoctorRows.count ?? 0 <= TaskLightUIPerformanceBudget.workspaceDoctorRenderLimit)
    }

    @Test("Operational insights keep quota and workspace repair display-only")
    public func operationalInsightContracts() {
        let row = WorkspaceDoctorRow(
            workspace: "/tmp/needs-hooks",
            name: "Needs Hooks",
            group: "test",
            coverage_status: "missing",
            hook_status: "missing",
            reason: "hooks missing",
            recommended_action: "install",
            severity: "attention",
            preferred: false
        )
        let queue = TaskLightOperationalInsights.workspaceRepairQueue(rows: [row])
        #expect(queue.first?.requiresUserConfirmation == true)
        #expect(queue.first?.manualTrustRequired == false)

        let reset = CodexQuotaResetSnapshot(
            status: "ok",
            manual_resets_label: "可用重置 1 次",
            credits: [CodexQuotaResetCreditUIState(id: "credit-1", status: "available", expires_at: "2026-12-31T23:00:00Z", redeemed: false)],
            summary: "test"
        )
        let calendar = TaskLightOperationalInsights.quotaCalendar(reset: reset, now: Date(timeIntervalSince1970: 0))
        #expect(calendar.contains(where: { $0.kind == "credit_expiry" }))

        let optIn = TaskLightProviderOptIn(explicit_user_opt_in: true, provider_ids: ["sample"])
        #expect(optIn.allows("sample"))
        #expect(!optIn.allows("codex"))
    }

    @Test("Quota compact text retains the last valid local values during a stale probe")
    public func quotaCompactTextFallback() {
        let staleQuota = CodexQuotaUIState(
            source: "codex_appserver_cached",
            fresh: false,
            status: "error",
            effective_remaining_percent: 57,
            short_percent: 57,
            long_percent: 93,
            manual_resets_available: 3
        )

        #expect(TaskLightQuotaPresentation.compactText(for: staleQuota) == "⚡57·93·R3")
        #expect(TaskLightQuotaPresentation.compactText(for: nil) == "⚡Q?")
    }

    @Test("Projected empty quota adopts a fresh local snapshot without changing the lamp")
    public func projectedQuotaUsesFreshLocalFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tasklight-quota-fallback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = TaskLightConfig(
            stateDirectory: root,
            ttlSeconds: 300,
            verificationTTLSeconds: 900,
            refreshSeconds: 5,
            blockedSoundName: "Basso",
            doneSoundName: "Submarine",
            staleSoundName: "Funk"
        )
        let store = TaskLightStore(config: config)
        store.ensureLayout()
        let projected = TaskLightUIState(
            projector_version: "M3.8",
            projector_generated_at: TaskLightTaskRecord.nowString(),
            global_status: TaskLightStatus.running.rawValue,
            lamp_status: TaskLightStatus.running.rawValue,
            global_display_title: "RUNNING",
            quota: CodexQuotaUIState(source: "state_projector", fresh: false, status: "unknown")
        )
        try JSONEncoder().encode(projected).write(to: config.uiStateURL)

        let coordinator = TaskLightRenderSnapshotCoordinator(config: config)
        let firstResult = SnapshotResultBox()
        let firstReady = DispatchSemaphore(value: 0)
        coordinator.refresh {
            firstResult.set($0)
            firstReady.signal()
        }
        #expect(firstReady.wait(timeout: .now() + 2) == .success)
        #expect(firstResult.get()?.uiState.quota?.effective_remaining_percent == nil)

        let quotaState: [String: Any] = [
            "source": "codex_appserver",
            "fresh": true,
            "quota_status": "ok",
            "effective_remaining_percent": 92,
            "captured_at": TaskLightTaskRecord.nowString(),
            "display_windows": [
                ["id": "short", "label": "5小时", "bucket_id": "codex", "remaining_percent": 92, "window_duration_mins": 300],
                ["id": "long", "label": "1周", "bucket_id": "codex", "remaining_percent": 99, "window_duration_mins": 10_080]
            ]
        ]
        try JSONSerialization.data(withJSONObject: quotaState).write(
            to: root.appendingPathComponent("quota_state.json")
        )

        let secondResult = SnapshotResultBox()
        let secondReady = DispatchSemaphore(value: 0)
        coordinator.refresh {
            secondResult.set($0)
            secondReady.signal()
        }
        #expect(secondReady.wait(timeout: .now() + 2) == .success)
        #expect(secondResult.get()?.uiState.quota?.short_percent == 92)
        #expect(secondResult.get()?.uiState.quota?.long_percent == 99)
        #expect(secondResult.get()?.uiState.global_status == TaskLightStatus.running.rawValue)
        #expect(secondResult.get()?.uiState.lamp_status == TaskLightStatus.running.rawValue)
    }

    @Test("Interaction state machine keeps tap, double tap, drag, and long press distinct")
    public func interactionStateMachineContracts() {
        var stateMachine = TaskLightInteractionStateMachine(doubleTapInterval: 0.30)

        _ = stateMachine.begin(target: .compact, x: 0, y: 0, at: 1.0)
        #expect(stateMachine.end(x: 0, y: 0, at: 1.05) == .singleTap(.compact))
        _ = stateMachine.begin(target: .edgeRail, x: 0, y: 0, at: 1.20)
        #expect(stateMachine.end(x: 0, y: 0, at: 1.24) == .doubleTap)

        _ = stateMachine.begin(target: .compact, x: 0, y: 0, at: 2.0)
        #expect(stateMachine.move(x: 6, y: 0) == .dragStarted(.compact))
        #expect(stateMachine.end(x: 6, y: 0, at: 2.05) == .dragEnded(.compact))

        _ = stateMachine.begin(target: .edgeRail, x: 0, y: 0, at: 3.0)
        #expect(stateMachine.end(x: 0, y: 0, at: 3.46) == .longPress(.edgeRail))
    }

    @Test("Event and UI flow logs rotate into bounded archives")
    public func logRotation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tasklight-log-rotation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = TaskLightConfig(
            stateDirectory: root,
            ttlSeconds: 300,
            verificationTTLSeconds: 900,
            refreshSeconds: 5,
            blockedSoundName: "Basso",
            doneSoundName: "Submarine",
            staleSoundName: "Funk"
        )
        let store = TaskLightStore(config: config)
        store.ensureLayout()
        try Data(repeating: 0x78, count: TaskLightUIPerformanceBudget.eventLogMaxBytes + 1).write(to: config.eventsURL)
        store.appendEvent(TaskLightEventRecord(
            event_id: "rotation",
            task_id: "rotation",
            from: "running",
            to: "done_verified",
            created_at: TaskLightTaskRecord.nowString(),
            sound_type: "done_verified"
        ))
        try Data(repeating: 0x78, count: TaskLightUIPerformanceBudget.uiEventFlowLogMaxBytes + 1).write(to: config.uiEventFlowURL)
        store.appendUIEventFlowRecord(["event_id": "rotation", "recorded_at": TaskLightTaskRecord.nowString()])

        #expect(FileManager.default.fileExists(atPath: config.eventsURL.path + ".1"))
        #expect(FileManager.default.fileExists(atPath: config.uiEventFlowURL.path + ".1"))
    }
}
