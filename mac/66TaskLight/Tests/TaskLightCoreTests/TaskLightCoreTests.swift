import XCTest
@testable import TaskLightCore

final class TaskLightCoreTests: XCTestCase {
    func testSnapshotDecodingAndEffectiveStatus() throws {
        let json = """
        {
          "schema_version": 1,
          "status": "running",
          "task_id": "abc",
          "title": "Sample",
          "heartbeat_at": "2026-06-09T00:00:00Z",
          "updated_at": "2026-06-09T00:00:00Z",
          "ttl_seconds": 300,
          "source": "tasklight"
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(TaskLightSnapshot.self, from: json)
        XCTAssertEqual(snapshot.task_id, "abc")
        XCTAssertEqual(snapshot.effectiveStatus(ttlSeconds: 300), .running)
    }

    func testAlertLedgerDeduplicatesRepeatedBlockedStates() {
        var ledger = TaskLightAlertLedger()
        let snapshot = TaskLightSnapshot.blocked(
            task_id: "abc",
            title: "Sample",
            phase: "build",
            progress: 0.5,
            reason: "deps_missing",
            message: "missing dependency",
            evidence: "tool unavailable",
            ttl_seconds: 300
        )

        XCTAssertTrue(ledger.shouldAnnounce(snapshot: snapshot))
        XCTAssertFalse(ledger.shouldAnnounce(snapshot: snapshot))
    }
}

