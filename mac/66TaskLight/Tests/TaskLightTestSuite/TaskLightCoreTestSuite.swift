import Foundation
import Testing
import TaskLightCore

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
        var first: TaskLightRenderSnapshot?
        coordinator.refresh {
            first = $0
            semaphore.signal()
        }
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        #expect(first != nil)
        #expect(first?.recentEvents.count ?? 0 <= TaskLightUIPerformanceBudget.expandedRecentEventLimit)
        #expect(first?.statusReplay.count ?? 0 <= TaskLightUIPerformanceBudget.statusReplayRenderLimit)
        #expect(first?.workspaceDoctorRows.count ?? 0 <= TaskLightUIPerformanceBudget.workspaceDoctorRenderLimit)
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
