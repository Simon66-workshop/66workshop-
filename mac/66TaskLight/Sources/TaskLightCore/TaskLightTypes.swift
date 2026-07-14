import Foundation
import CryptoKit

public enum TaskLightStatus: String, Codable, CaseIterable {
    case idle
    case queued
    case running
    case blocked
    case done_unverified
    case done_verified
    case stale
    case cancelled
    case invalid_json
}

public enum TaskLightSourceHealth: String, Codable {
    case healthy
    case corrupt_state
    case reconstructed
}

public struct TaskLightConfig: Sendable {
    public var stateDirectory: URL
    public var stateURL: URL
    public var tasksDirectoryURL: URL
    public var currentURL: URL
    public var observationsDirectoryURL: URL
    public var observationsStateURL: URL
    public var hookBridgeHealthURL: URL
    public var uiStateURL: URL
    public var uiEventFlowURL: URL
    public var quotaHistoryURL: URL
    public var renderTelemetryURL: URL
    public var widgetSnapshotURL: URL
    public var uiClientsDirectoryURL: URL
    public var workspaceCoverageDirectoryURL: URL
    public var providersDirectoryURL: URL
    public var workspaceCoverageRunStatusURL: URL
    public var workspaceCoverageLatestJSONURL: URL
    public var workspaceCoverageLatestMarkdownURL: URL
    public var eventsURL: URL
    public var playedEventsURL: URL
    public var lockURL: URL
    public var ttlSeconds: TimeInterval
    public var verificationTTLSeconds: TimeInterval
    public var refreshSeconds: TimeInterval
    public var projectorMaxAgeSeconds: TimeInterval
    public var blockedSoundName: String
    public var doneSoundName: String
    public var staleSoundName: String

    public init(
        stateDirectory: URL,
        ttlSeconds: TimeInterval,
        verificationTTLSeconds: TimeInterval,
        refreshSeconds: TimeInterval,
        blockedSoundName: String,
        doneSoundName: String,
        staleSoundName: String,
        projectorMaxAgeSeconds: TimeInterval = 5,
        observationsDirectoryURL: URL? = nil,
        observationsStateURL: URL? = nil,
        hookBridgeHealthURL: URL? = nil,
        uiStateURL: URL? = nil,
        uiEventFlowURL: URL? = nil,
        quotaHistoryURL: URL? = nil,
        renderTelemetryURL: URL? = nil,
        widgetSnapshotURL: URL? = nil,
        uiClientsDirectoryURL: URL? = nil,
        workspaceCoverageDirectoryURL: URL? = nil,
        providersDirectoryURL: URL? = nil
    ) {
        self.stateDirectory = stateDirectory
        self.stateURL = stateDirectory.appendingPathComponent("state.json")
        self.tasksDirectoryURL = stateDirectory.appendingPathComponent("tasks")
        self.currentURL = stateDirectory.appendingPathComponent("current.json")
        self.observationsDirectoryURL = observationsDirectoryURL ?? stateDirectory.appendingPathComponent("observations")
        self.observationsStateURL = observationsStateURL ?? stateDirectory.appendingPathComponent("observations_state.json")
        self.hookBridgeHealthURL = hookBridgeHealthURL ?? stateDirectory.appendingPathComponent("hook_bridge_health.json")
        self.uiStateURL = uiStateURL ?? stateDirectory.appendingPathComponent("ui_state.json")
        self.uiEventFlowURL = uiEventFlowURL ?? stateDirectory.appendingPathComponent("ui_event_flow.jsonl")
        self.quotaHistoryURL = quotaHistoryURL ?? stateDirectory.appendingPathComponent("quota_history.jsonl")
        self.renderTelemetryURL = renderTelemetryURL ?? stateDirectory.appendingPathComponent("render_telemetry.jsonl")
        self.widgetSnapshotURL = widgetSnapshotURL ?? stateDirectory.appendingPathComponent("widget_snapshot.json")
        self.uiClientsDirectoryURL = uiClientsDirectoryURL ?? stateDirectory.appendingPathComponent("ui_clients")
        self.workspaceCoverageDirectoryURL = workspaceCoverageDirectoryURL ?? stateDirectory.appendingPathComponent("workspace_coverage")
        self.providersDirectoryURL = providersDirectoryURL ?? stateDirectory.appendingPathComponent("providers")
        self.workspaceCoverageRunStatusURL = self.workspaceCoverageDirectoryURL.appendingPathComponent("run_status.json")
        self.workspaceCoverageLatestJSONURL = self.workspaceCoverageDirectoryURL.appendingPathComponent("latest.json")
        self.workspaceCoverageLatestMarkdownURL = self.workspaceCoverageDirectoryURL.appendingPathComponent("latest.md")
        self.eventsURL = stateDirectory.appendingPathComponent("events.jsonl")
        self.playedEventsURL = stateDirectory.appendingPathComponent("played_events.json")
        self.lockURL = stateDirectory.appendingPathComponent(".lock")
        self.ttlSeconds = ttlSeconds
        self.verificationTTLSeconds = verificationTTLSeconds
        self.refreshSeconds = refreshSeconds
        self.projectorMaxAgeSeconds = projectorMaxAgeSeconds
        self.blockedSoundName = blockedSoundName
        self.doneSoundName = doneSoundName
        self.staleSoundName = staleSoundName
    }

    public static func fromEnvironment() -> TaskLightConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let stateDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TASKLIGHT_STATE_DIR"] ?? home.appendingPathComponent(".66tasklight").path)
        let ttlSeconds = TimeInterval(ProcessInfo.processInfo.environment["TASKLIGHT_TTL_SECONDS"].flatMap(Double.init) ?? 300)
        let verificationTTLSeconds = TimeInterval(ProcessInfo.processInfo.environment["TASKLIGHT_VERIFICATION_TTL_SECONDS"].flatMap(Double.init) ?? 900)
        let refreshSeconds = TimeInterval(ProcessInfo.processInfo.environment["TASKLIGHT_REFRESH_SECONDS"].flatMap(Double.init) ?? 5)
        let projectorMaxAgeSeconds = TimeInterval(ProcessInfo.processInfo.environment["TASKLIGHT_PROJECTOR_MAX_AGE_SECONDS"].flatMap(Double.init) ?? 5)
        let blockedSoundName = ProcessInfo.processInfo.environment["TASKLIGHT_BLOCKED_SOUND"] ?? "Basso"
        let doneSoundName = ProcessInfo.processInfo.environment["TASKLIGHT_DONE_SOUND"] ?? "Submarine"
        let staleSoundName = ProcessInfo.processInfo.environment["TASKLIGHT_STALE_SOUND"] ?? "Funk"
        let observationsDirectoryURL = ProcessInfo.processInfo.environment["TASKLIGHT_OBSERVATIONS_DIR"].map { URL(fileURLWithPath: $0) }
        let observationsStateURL = ProcessInfo.processInfo.environment["TASKLIGHT_OBSERVATIONS_STATE_PATH"].map { URL(fileURLWithPath: $0) }
        let hookBridgeHealthURL = ProcessInfo.processInfo.environment["TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH"].map { URL(fileURLWithPath: $0) }
        let uiStateURL = ProcessInfo.processInfo.environment["TASKLIGHT_UI_STATE_PATH"].map { URL(fileURLWithPath: $0) }
        let uiEventFlowURL = ProcessInfo.processInfo.environment["TASKLIGHT_UI_EVENT_FLOW_PATH"].map { URL(fileURLWithPath: $0) }
        let quotaHistoryURL = ProcessInfo.processInfo.environment["TASKLIGHT_QUOTA_HISTORY_PATH"].map { URL(fileURLWithPath: $0) }
        let renderTelemetryURL = ProcessInfo.processInfo.environment["TASKLIGHT_RENDER_TELEMETRY_PATH"].map { URL(fileURLWithPath: $0) }
        let widgetSnapshotURL = ProcessInfo.processInfo.environment["TASKLIGHT_WIDGET_SNAPSHOT_PATH"].map { URL(fileURLWithPath: $0) }
        let uiClientsDirectoryURL = ProcessInfo.processInfo.environment["TASKLIGHT_UI_CLIENTS_DIR"].map { URL(fileURLWithPath: $0) }
        let workspaceCoverageDirectoryURL = ProcessInfo.processInfo.environment["TASKLIGHT_WORKSPACE_COVERAGE_DIR"].map { URL(fileURLWithPath: $0) }
        let providersDirectoryURL = ProcessInfo.processInfo.environment["TASKLIGHT_PROVIDER_PLUGIN_DIR"].map { URL(fileURLWithPath: $0) }
        return TaskLightConfig(
            stateDirectory: stateDirectory,
            ttlSeconds: ttlSeconds,
            verificationTTLSeconds: verificationTTLSeconds,
            refreshSeconds: refreshSeconds,
            blockedSoundName: blockedSoundName,
            doneSoundName: doneSoundName,
            staleSoundName: staleSoundName,
            projectorMaxAgeSeconds: projectorMaxAgeSeconds,
            observationsDirectoryURL: observationsDirectoryURL,
            observationsStateURL: observationsStateURL,
            hookBridgeHealthURL: hookBridgeHealthURL,
            uiStateURL: uiStateURL,
            uiEventFlowURL: uiEventFlowURL,
            quotaHistoryURL: quotaHistoryURL,
            renderTelemetryURL: renderTelemetryURL,
            widgetSnapshotURL: widgetSnapshotURL,
            uiClientsDirectoryURL: uiClientsDirectoryURL,
            workspaceCoverageDirectoryURL: workspaceCoverageDirectoryURL,
            providersDirectoryURL: providersDirectoryURL
        )
    }
}

public struct TaskLightTaskRecord: Codable, Equatable, Identifiable {
    public var schema_version: Int
    public var task_id: String
    public var short_task_id: String?
    public var title: String
    public var slug: String
    public var status: String
    public var raw_status: String?
    public var effective_status: String?
    public var phase: String?
    public var progress: Double?
    public var reason: String?
    public var message: String?
    public var evidence: String?
    public var summary: String?
    public var created_at: String?
    public var started_at: String?
    public var updated_at: String?
    public var heartbeat_at: String?
    public var done_at: String?
    public var verified_at: String?
    public var cancelled_at: String?
    public var ttl_seconds: Int?
    public var source: String?
    public var last_error: String?
    public var current_event_id: String?
    public var file_path: String?
    public var alert_fingerprint: String?
    public var sound_type: String?
    public var is_invalid_json: Bool?
    public var invalid_json_error: String?

    public var id: String { task_id }

    public init(
        schema_version: Int = 3,
        task_id: String,
        short_task_id: String? = nil,
        title: String,
        slug: String,
        status: String,
        raw_status: String? = nil,
        effective_status: String? = nil,
        phase: String? = nil,
        progress: Double? = nil,
        reason: String? = nil,
        message: String? = nil,
        evidence: String? = nil,
        summary: String? = nil,
        created_at: String? = nil,
        started_at: String? = nil,
        updated_at: String? = nil,
        heartbeat_at: String? = nil,
        done_at: String? = nil,
        verified_at: String? = nil,
        cancelled_at: String? = nil,
        ttl_seconds: Int? = nil,
        source: String? = "tasklight",
        last_error: String? = nil,
        current_event_id: String? = nil,
        file_path: String? = nil,
        alert_fingerprint: String? = nil,
        sound_type: String? = nil,
        is_invalid_json: Bool? = nil,
        invalid_json_error: String? = nil
    ) {
        self.schema_version = schema_version
        self.task_id = task_id
        self.short_task_id = short_task_id
        self.title = title
        self.slug = slug
        self.status = status
        self.raw_status = raw_status
        self.effective_status = effective_status
        self.phase = phase
        self.progress = progress
        self.reason = reason
        self.message = message
        self.evidence = evidence
        self.summary = summary
        self.created_at = created_at
        self.started_at = started_at
        self.updated_at = updated_at
        self.heartbeat_at = heartbeat_at
        self.done_at = done_at
        self.verified_at = verified_at
        self.cancelled_at = cancelled_at
        self.ttl_seconds = ttl_seconds
        self.source = source
        self.last_error = last_error
        self.current_event_id = current_event_id
        self.file_path = file_path
        self.alert_fingerprint = alert_fingerprint
        self.sound_type = sound_type
        self.is_invalid_json = is_invalid_json
        self.invalid_json_error = invalid_json_error
    }

    public var shortTaskID: String {
        if let short_task_id, !short_task_id.isEmpty {
            return short_task_id
        }
        return task_id.components(separatedBy: "-").last ?? task_id
    }

    public func liveStatus(ttlSeconds: TimeInterval, verificationTTLSeconds: TimeInterval) -> TaskLightStatus {
        if is_invalid_json == true {
            return .invalid_json
        }
        let raw = TaskLightStatus(rawValue: raw_status ?? status) ?? .idle
        if raw == .stale {
            return .stale
        }
        if raw == .done_unverified {
            if TaskLightStatus(rawValue: effective_status ?? "") == .stale {
                return .stale
            }
            let doneAt = Self.parseTimestamp(done_at ?? updated_at ?? started_at ?? created_at)
            guard let doneAt else {
                return .stale
            }
            if Date().timeIntervalSince(doneAt) > verificationTTLSeconds {
                return .stale
            }
            return .done_unverified
        }
        guard raw == .running else {
            return raw
        }
        let heartbeat = Self.parseTimestamp(heartbeat_at ?? updated_at ?? started_at ?? created_at)
        guard let heartbeat else {
            return .stale
        }
        if Date().timeIntervalSince(heartbeat) > ttlSeconds {
            return .stale
        }
        return .running
    }

    public func withLiveStatus(ttlSeconds: TimeInterval, verificationTTLSeconds: TimeInterval) -> TaskLightTaskRecord {
        let live = liveStatus(ttlSeconds: ttlSeconds, verificationTTLSeconds: verificationTTLSeconds)
        guard live.rawValue != status else {
            return self
        }
        var copy = self
        copy.status = live.rawValue
        copy.effective_status = live.rawValue
        if live == .stale {
            copy.last_error = (raw_status == TaskLightStatus.done_unverified.rawValue) ? "acceptance gate expired" : "heartbeat expired"
            copy.sound_type = nil
        }
        return copy
    }

    public func alertFingerprint(effectiveStatus: TaskLightStatus? = nil) -> String {
        let statusToUse = effectiveStatus ?? TaskLightStatus(rawValue: effective_status ?? status) ?? .idle
        let payload: [String: Any?]
        switch statusToUse {
        case .blocked:
            payload = [
                "status": statusToUse.rawValue,
                "task_id": task_id,
                "title": title,
                "phase": phase,
                "reason": reason,
                "message": message,
                "evidence": evidence
            ]
        case .done_verified:
            payload = [
                "status": statusToUse.rawValue,
                "task_id": task_id,
                "title": title,
                "summary": summary
            ]
        default:
            payload = [
                "status": statusToUse.rawValue,
                "task_id": task_id,
                "title": title
            ]
        }
        let normalized = payload.mapValues { value -> String in
            if let value {
                return String(describing: value)
            }
            return ""
        }
        let encoded = (try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])) ?? Data()
        return SHA256.hexDigest(data: encoded)
    }

    public static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: value) {
            return parsed
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct TaskLightTaskSummary: Codable, Equatable, Identifiable {
    public var schema_version: Int
    public var task_id: String
    public var short_task_id: String
    public var title: String
    public var slug: String
    public var status: String
    public var raw_status: String
    public var effective_status: String
    public var phase: String?
    public var progress: Double?
    public var reason: String?
    public var message: String?
    public var evidence: String?
    public var summary: String?
    public var created_at: String?
    public var started_at: String?
    public var updated_at: String?
    public var heartbeat_at: String?
    public var done_at: String?
    public var verified_at: String?
    public var cancelled_at: String?
    public var ttl_seconds: Int?
    public var last_error: String?
    public var file_path: String?
    public var alert_fingerprint: String?
    public var sound_type: String?
    public var is_invalid_json: Bool
    public var invalid_json_error: String?

    public var id: String { task_id }

    public init(
        schema_version: Int = 3,
        task_id: String,
        short_task_id: String,
        title: String,
        slug: String,
        status: String,
        raw_status: String,
        effective_status: String,
        phase: String? = nil,
        progress: Double? = nil,
        reason: String? = nil,
        message: String? = nil,
        evidence: String? = nil,
        summary: String? = nil,
        created_at: String? = nil,
        started_at: String? = nil,
        updated_at: String? = nil,
        heartbeat_at: String? = nil,
        done_at: String? = nil,
        verified_at: String? = nil,
        cancelled_at: String? = nil,
        ttl_seconds: Int? = nil,
        last_error: String? = nil,
        file_path: String? = nil,
        alert_fingerprint: String? = nil,
        sound_type: String? = nil,
        is_invalid_json: Bool = false,
        invalid_json_error: String? = nil
    ) {
        self.schema_version = schema_version
        self.task_id = task_id
        self.short_task_id = short_task_id
        self.title = title
        self.slug = slug
        self.status = status
        self.raw_status = raw_status
        self.effective_status = effective_status
        self.phase = phase
        self.progress = progress
        self.reason = reason
        self.message = message
        self.evidence = evidence
        self.summary = summary
        self.created_at = created_at
        self.started_at = started_at
        self.updated_at = updated_at
        self.heartbeat_at = heartbeat_at
        self.done_at = done_at
        self.verified_at = verified_at
        self.cancelled_at = cancelled_at
        self.ttl_seconds = ttl_seconds
        self.last_error = last_error
        self.file_path = file_path
        self.alert_fingerprint = alert_fingerprint
        self.sound_type = sound_type
        self.is_invalid_json = is_invalid_json
        self.invalid_json_error = invalid_json_error
    }

    public func liveStatus(ttlSeconds: TimeInterval, verificationTTLSeconds: TimeInterval) -> TaskLightStatus {
        if is_invalid_json {
            return .invalid_json
        }
        let raw = TaskLightStatus(rawValue: raw_status) ?? .idle
        if raw == .stale {
            return .stale
        }
        if raw == .done_unverified {
            if TaskLightStatus(rawValue: effective_status) == .stale {
                return .stale
            }
            let doneAt = TaskLightTaskRecord.parseTimestamp(done_at ?? updated_at ?? started_at ?? created_at)
            guard let doneAt else {
                return .stale
            }
            if Date().timeIntervalSince(doneAt) > verificationTTLSeconds {
                return .stale
            }
            return .done_unverified
        }
        guard raw == .running else {
            return TaskLightStatus(rawValue: effective_status) ?? .idle
        }
        let heartbeat = TaskLightTaskRecord.parseTimestamp(heartbeat_at ?? updated_at ?? started_at ?? created_at)
        guard let heartbeat else {
            return .stale
        }
        if Date().timeIntervalSince(heartbeat) > ttlSeconds {
            return .stale
        }
        return .running
    }
}

public struct TaskLightCounts: Codable, Equatable {
    public var blocked: Int
    public var stale: Int
    public var running: Int
    public var queued: Int
    public var done_verified: Int
    public var done_unverified: Int
    public var pending_verify_count: Int
    public var cancelled: Int
    public var invalid_json: Int
    public var active: Int
    public var total: Int
    public var red: Int
    public var blue: Int
    public var green: Int
    public var gray: Int

    public init(
        blocked: Int = 0,
        stale: Int = 0,
        running: Int = 0,
        queued: Int = 0,
        done_verified: Int = 0,
        done_unverified: Int = 0,
        pending_verify_count: Int = 0,
        cancelled: Int = 0,
        invalid_json: Int = 0,
        active: Int = 0,
        total: Int = 0,
        red: Int = 0,
        blue: Int = 0,
        green: Int = 0,
        gray: Int = 0
    ) {
        self.blocked = blocked
        self.stale = stale
        self.running = running
        self.queued = queued
        self.done_verified = done_verified
        self.done_unverified = done_unverified
        self.pending_verify_count = pending_verify_count
        self.cancelled = cancelled
        self.invalid_json = invalid_json
        self.active = active
        self.total = total
        self.red = red
        self.blue = blue
        self.green = green
        self.gray = gray
    }

    private enum CodingKeys: String, CodingKey {
        case blocked
        case stale
        case running
        case queued
        case done_verified
        case done_unverified
        case pending_verify_count
        case cancelled
        case invalid_json
        case active
        case total
        case red
        case blue
        case green
        case gray
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.blocked = try container.decodeIfPresent(Int.self, forKey: .blocked) ?? 0
        self.stale = try container.decodeIfPresent(Int.self, forKey: .stale) ?? 0
        self.running = try container.decodeIfPresent(Int.self, forKey: .running) ?? 0
        self.queued = try container.decodeIfPresent(Int.self, forKey: .queued) ?? 0
        self.done_verified = try container.decodeIfPresent(Int.self, forKey: .done_verified) ?? 0
        self.done_unverified = try container.decodeIfPresent(Int.self, forKey: .done_unverified) ?? 0
        self.pending_verify_count = try container.decodeIfPresent(Int.self, forKey: .pending_verify_count) ?? 0
        self.cancelled = try container.decodeIfPresent(Int.self, forKey: .cancelled) ?? 0
        self.invalid_json = try container.decodeIfPresent(Int.self, forKey: .invalid_json) ?? 0
        self.active = try container.decodeIfPresent(Int.self, forKey: .active) ?? 0
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.red = try container.decodeIfPresent(Int.self, forKey: .red) ?? 0
        self.blue = try container.decodeIfPresent(Int.self, forKey: .blue) ?? 0
        self.green = try container.decodeIfPresent(Int.self, forKey: .green) ?? 0
        self.gray = try container.decodeIfPresent(Int.self, forKey: .gray) ?? 0
    }
}

public enum TaskLightObservationStatus: String, Codable, CaseIterable {
    case observed_active
    case observed_quiet
    case observed_attention
    case observed_disappeared
}

public struct TaskLightObservationRecord: Codable, Equatable, Identifiable {
    public var schema_version: Int
    public var observation_id: String
    public var pid: Int
    public var ppid: Int
    public var command: String
    public var command_short: String
    public var cwd: String?
    public var cwd_hash: String?
    public var title: String
    public var detected_at: String?
    public var last_seen_at: String?
    public var status: String
    public var confidence: Double
    public var managed_task_id: String?
    public var missed_scans: Int
    public var removed_at: String?
    public var last_error: String?
    public var file_path: String?

    public var id: String { observation_id }

    public init(
        schema_version: Int = 3,
        observation_id: String,
        pid: Int,
        ppid: Int,
        command: String,
        command_short: String,
        cwd: String? = nil,
        cwd_hash: String? = nil,
        title: String,
        detected_at: String? = nil,
        last_seen_at: String? = nil,
        status: String,
        confidence: Double,
        managed_task_id: String? = nil,
        missed_scans: Int = 0,
        removed_at: String? = nil,
        last_error: String? = nil,
        file_path: String? = nil
    ) {
        self.schema_version = schema_version
        self.observation_id = observation_id
        self.pid = pid
        self.ppid = ppid
        self.command = command
        self.command_short = command_short
        self.cwd = cwd
        self.cwd_hash = cwd_hash
        self.title = title
        self.detected_at = detected_at
        self.last_seen_at = last_seen_at
        self.status = status
        self.confidence = confidence
        self.managed_task_id = managed_task_id
        self.missed_scans = missed_scans
        self.removed_at = removed_at
        self.last_error = last_error
        self.file_path = file_path
    }

    public var isActive: Bool {
        guard let status = TaskLightObservationStatus(rawValue: status) else { return false }
        switch status {
        case .observed_active, .observed_quiet, .observed_attention:
            return true
        case .observed_disappeared:
            return false
        }
    }

    public func elapsedSeconds() -> Int? {
        guard let start = TaskLightTaskRecord.parseTimestamp(detected_at) else { return nil }
        return max(0, Int(Date().timeIntervalSince(start)))
    }
}

public struct TaskLightObservationCounts: Codable, Equatable {
    public var active: Int
    public var quiet: Int
    public var attention: Int
    public var disappeared: Int
    public var linked_managed: Int
    public var total: Int

    public init(
        active: Int = 0,
        quiet: Int = 0,
        attention: Int = 0,
        disappeared: Int = 0,
        linked_managed: Int = 0,
        total: Int = 0
    ) {
        self.active = active
        self.quiet = quiet
        self.attention = attention
        self.disappeared = disappeared
        self.linked_managed = linked_managed
        self.total = total
    }
}

public struct TaskLightObservationsState: Codable, Equatable {
    public var schema_version: Int
    public var source: String
    public var source_health: String
    public var lamp_status: String
    public var global_status: String
    public var generated_at: String
    public var updated_at: String
    public var counts: TaskLightObservationCounts
    public var observations: [TaskLightObservationRecord]

    public init(
        schema_version: Int = 3,
        source: String = "tasklight",
        source_health: String = TaskLightSourceHealth.healthy.rawValue,
        lamp_status: String = "idle",
        global_status: String = "idle",
        generated_at: String = TaskLightTaskRecord.nowString(),
        updated_at: String = TaskLightTaskRecord.nowString(),
        counts: TaskLightObservationCounts = TaskLightObservationCounts(),
        observations: [TaskLightObservationRecord] = []
    ) {
        self.schema_version = schema_version
        self.source = source
        self.source_health = source_health
        self.lamp_status = lamp_status
        self.global_status = global_status
        self.generated_at = generated_at
        self.updated_at = updated_at
        self.counts = counts
        self.observations = observations
    }
}

public struct TaskLightAggregateState: Codable, Equatable {
    public var schema_version: Int
    public var source: String
    public var source_health: String
    public var lamp_status: String
    public var global_status: String
    public var generated_at: String
    public var updated_at: String
    public var current_task_id: String?
    public var last_verified_at: String?
    public var last_event_at: String?
    public var counts: TaskLightCounts
    public var tasks: [TaskLightTaskSummary]
    public var invalid_tasks: [TaskLightTaskSummary]
    public var observations_state: TaskLightObservationsState?

    public init(
        schema_version: Int = 3,
        source: String = "tasklight",
        source_health: String = TaskLightSourceHealth.healthy.rawValue,
        lamp_status: String = "idle",
        global_status: String = "idle",
        generated_at: String = TaskLightTaskRecord.nowString(),
        updated_at: String = TaskLightTaskRecord.nowString(),
        current_task_id: String? = nil,
        last_verified_at: String? = nil,
        last_event_at: String? = nil,
        counts: TaskLightCounts = TaskLightCounts(),
        tasks: [TaskLightTaskSummary] = [],
        invalid_tasks: [TaskLightTaskSummary] = [],
        observations_state: TaskLightObservationsState? = nil
    ) {
        self.schema_version = schema_version
        self.source = source
        self.source_health = source_health
        self.lamp_status = lamp_status
        self.global_status = global_status
        self.generated_at = generated_at
        self.updated_at = updated_at
        self.current_task_id = current_task_id
        self.last_verified_at = last_verified_at
        self.last_event_at = last_event_at
        self.counts = counts
        self.tasks = tasks
        self.invalid_tasks = invalid_tasks
        self.observations_state = observations_state
    }
}

public struct TaskLightUICounts: Codable, Equatable {
    public var blocked: Int
    public var stale: Int
    public var running: Int
    public var queued: Int
    public var pending_verify_count: Int
    public var done_verified_visible: Int
    public var observed_active: Int
    public var appserver_active: Int
    public var process_observed: Int
    public var managed_active: Int

    public init(
        blocked: Int = 0,
        stale: Int = 0,
        running: Int = 0,
        queued: Int = 0,
        pending_verify_count: Int = 0,
        done_verified_visible: Int = 0,
        observed_active: Int = 0,
        appserver_active: Int = 0,
        process_observed: Int = 0,
        managed_active: Int = 0
    ) {
        self.blocked = blocked
        self.stale = stale
        self.running = running
        self.queued = queued
        self.pending_verify_count = pending_verify_count
        self.done_verified_visible = done_verified_visible
        self.observed_active = observed_active
        self.appserver_active = appserver_active
        self.process_observed = process_observed
        self.managed_active = managed_active
    }

    private enum CodingKeys: String, CodingKey {
        case blocked
        case stale
        case running
        case queued
        case pending_verify_count
        case done_verified_visible
        case observed_active
        case appserver_active
        case process_observed
        case managed_active
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.blocked = try container.decodeIfPresent(Int.self, forKey: .blocked) ?? 0
        self.stale = try container.decodeIfPresent(Int.self, forKey: .stale) ?? 0
        self.running = try container.decodeIfPresent(Int.self, forKey: .running) ?? 0
        self.queued = try container.decodeIfPresent(Int.self, forKey: .queued) ?? 0
        self.pending_verify_count = try container.decodeIfPresent(Int.self, forKey: .pending_verify_count) ?? 0
        self.done_verified_visible = try container.decodeIfPresent(Int.self, forKey: .done_verified_visible) ?? 0
        self.observed_active = try container.decodeIfPresent(Int.self, forKey: .observed_active) ?? 0
        self.appserver_active = try container.decodeIfPresent(Int.self, forKey: .appserver_active) ?? 0
        self.process_observed = try container.decodeIfPresent(Int.self, forKey: .process_observed) ?? 0
        self.managed_active = try container.decodeIfPresent(Int.self, forKey: .managed_active) ?? 0
    }
}

public struct TaskLightRuntimeCandidate: Codable, Equatable, Identifiable {
    public var candidate_id: String
    public var kind: String?
    public var task_id: String?
    public var thread_id: String?
    public var turn_id: String?
    public var pid: Int?
    public var source_set: [String]
    public var last_signal_at: String?
    public var last_event_type: String?
    public var base_confidence: Double?
    public var freshness_score: Double?
    public var identity_score: Double?
    public var consistency_score: Double?
    public var runtime_score: Double?
    public var display_scope: String
    public var state_cause: String?
    public var why_ignored: String?
    public var reason: String?
    public var message: String?

    public var id: String { candidate_id }

    private enum CodingKeys: String, CodingKey {
        case candidate_id
        case kind
        case task_id
        case thread_id
        case turn_id
        case pid
        case source_set
        case last_signal_at
        case last_event_type
        case base_confidence
        case freshness_score
        case identity_score
        case consistency_score
        case runtime_score
        case display_scope
        case state_cause
        case why_ignored
        case reason
        case message
    }

    public init(
        candidate_id: String,
        kind: String? = nil,
        task_id: String? = nil,
        thread_id: String? = nil,
        turn_id: String? = nil,
        pid: Int? = nil,
        source_set: [String] = [],
        last_signal_at: String? = nil,
        last_event_type: String? = nil,
        base_confidence: Double? = nil,
        freshness_score: Double? = nil,
        identity_score: Double? = nil,
        consistency_score: Double? = nil,
        runtime_score: Double? = nil,
        display_scope: String = "ignored",
        state_cause: String? = nil,
        why_ignored: String? = nil,
        reason: String? = nil,
        message: String? = nil
    ) {
        self.candidate_id = candidate_id
        self.kind = kind
        self.task_id = task_id
        self.thread_id = thread_id
        self.turn_id = turn_id
        self.pid = pid
        self.source_set = source_set
        self.last_signal_at = last_signal_at
        self.last_event_type = last_event_type
        self.base_confidence = base_confidence
        self.freshness_score = freshness_score
        self.identity_score = identity_score
        self.consistency_score = consistency_score
        self.runtime_score = runtime_score
        self.display_scope = display_scope
        self.state_cause = state_cause
        self.why_ignored = why_ignored
        self.reason = reason
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.candidate_id = try container.decode(String.self, forKey: .candidate_id)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind)
        self.task_id = try container.decodeIfPresent(String.self, forKey: .task_id)
        self.thread_id = try container.decodeIfPresent(String.self, forKey: .thread_id)
        self.turn_id = try container.decodeIfPresent(String.self, forKey: .turn_id)
        self.pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        self.source_set = try container.decodeIfPresent([String].self, forKey: .source_set) ?? []
        self.last_signal_at = try Self.decodeLossyString(container, forKey: .last_signal_at)
        self.last_event_type = try container.decodeIfPresent(String.self, forKey: .last_event_type)
        self.base_confidence = try container.decodeIfPresent(Double.self, forKey: .base_confidence)
        self.freshness_score = try container.decodeIfPresent(Double.self, forKey: .freshness_score)
        self.identity_score = try container.decodeIfPresent(Double.self, forKey: .identity_score)
        self.consistency_score = try container.decodeIfPresent(Double.self, forKey: .consistency_score)
        self.runtime_score = try container.decodeIfPresent(Double.self, forKey: .runtime_score)
        self.display_scope = try container.decodeIfPresent(String.self, forKey: .display_scope) ?? "ignored"
        self.state_cause = try container.decodeIfPresent(String.self, forKey: .state_cause)
        self.why_ignored = try container.decodeIfPresent(String.self, forKey: .why_ignored)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    private static func decodeLossyString<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

public struct TaskLightUITask: Codable, Equatable, Identifiable {
    public var task_id: String
    public var short_task_id: String?
    public var title: String
    public var turn_id: String?
    public var canonical_identity: String?
    public var binding_aliases: [String]?
    public var source: String?
    public var raw_status: String
    public var effective_status: String
    public var display_scope: String
    public var last_signal_age_sec: Double?
    public var state_cause: String?
    public var fresh: Bool
    public var phase: String?
    public var progress: Double?
    public var reason: String?
    public var message: String?
    public var summary: String?
    public var started_at: String?
    public var updated_at: String?
    public var done_at: String?
    public var verified_at: String?
    public var file_path: String?
    public var confidence: Double?

    public var id: String { task_id }

    enum CodingKeys: String, CodingKey {
        case task_id
        case short_task_id
        case title
        case turn_id
        case canonical_identity
        case binding_aliases
        case source
        case raw_status
        case effective_status
        case display_scope
        case last_signal_age_sec
        case state_cause
        case fresh
        case phase
        case progress
        case reason
        case message
        case summary
        case started_at
        case updated_at
        case done_at
        case verified_at
        case file_path
        case confidence
    }

    public init(
        task_id: String,
        short_task_id: String? = nil,
        title: String,
        turn_id: String? = nil,
        canonical_identity: String? = nil,
        binding_aliases: [String]? = nil,
        source: String? = nil,
        raw_status: String = "idle",
        effective_status: String = "idle",
        display_scope: String = "history",
        last_signal_age_sec: Double? = nil,
        state_cause: String? = nil,
        fresh: Bool = false,
        phase: String? = nil,
        progress: Double? = nil,
        reason: String? = nil,
        message: String? = nil,
        summary: String? = nil,
        started_at: String? = nil,
        updated_at: String? = nil,
        done_at: String? = nil,
        verified_at: String? = nil,
        file_path: String? = nil,
        confidence: Double? = nil
    ) {
        self.task_id = task_id
        self.short_task_id = short_task_id
        self.title = title
        self.turn_id = turn_id
        self.canonical_identity = canonical_identity
        self.binding_aliases = binding_aliases
        self.source = source
        self.raw_status = raw_status
        self.effective_status = effective_status
        self.display_scope = display_scope
        self.last_signal_age_sec = last_signal_age_sec
        self.state_cause = state_cause
        self.fresh = fresh
        self.phase = phase
        self.progress = progress
        self.reason = reason
        self.message = message
        self.summary = summary
        self.started_at = started_at
        self.updated_at = updated_at
        self.done_at = done_at
        self.verified_at = verified_at
        self.file_path = file_path
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTaskID = try Self.decodeLossyString(container, forKey: .task_id) ?? ""
        self.task_id = decodedTaskID
        self.short_task_id = try Self.decodeLossyString(container, forKey: .short_task_id)
        self.title = try Self.decodeLossyString(container, forKey: .title) ?? decodedTaskID
        self.turn_id = try Self.decodeLossyString(container, forKey: .turn_id)
        self.canonical_identity = try Self.decodeLossyString(container, forKey: .canonical_identity)
        self.binding_aliases = try container.decodeIfPresent([String].self, forKey: .binding_aliases)
        self.source = try Self.decodeLossyString(container, forKey: .source)
        self.raw_status = try Self.decodeLossyString(container, forKey: .raw_status) ?? "idle"
        self.effective_status = try Self.decodeLossyString(container, forKey: .effective_status) ?? raw_status
        self.display_scope = try Self.decodeLossyString(container, forKey: .display_scope) ?? "history"
        self.last_signal_age_sec = try container.decodeIfPresent(Double.self, forKey: .last_signal_age_sec)
        self.state_cause = try Self.decodeLossyString(container, forKey: .state_cause)
        self.fresh = (try? container.decode(Bool.self, forKey: .fresh)) ?? false
        self.phase = try Self.decodeLossyString(container, forKey: .phase)
        self.progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        self.reason = try Self.decodeLossyString(container, forKey: .reason)
        self.message = try Self.decodeLossyString(container, forKey: .message)
        self.summary = try Self.decodeLossyString(container, forKey: .summary)
        self.started_at = try Self.decodeLossyString(container, forKey: .started_at)
        self.updated_at = try Self.decodeLossyString(container, forKey: .updated_at)
        self.done_at = try Self.decodeLossyString(container, forKey: .done_at)
        self.verified_at = try Self.decodeLossyString(container, forKey: .verified_at)
        self.file_path = try Self.decodeLossyString(container, forKey: .file_path)
        self.confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
    }

    private static func decodeLossyString(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    public func asTaskSummary() -> TaskLightTaskSummary {
        TaskLightTaskSummary(
            task_id: task_id,
            short_task_id: short_task_id ?? String(task_id.suffix(8)),
            title: title,
            slug: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            status: effective_status,
            raw_status: raw_status,
            effective_status: effective_status,
            phase: phase,
            progress: progress,
            reason: reason,
            message: message,
            evidence: state_cause,
            summary: summary,
            created_at: started_at ?? updated_at,
            started_at: started_at,
            updated_at: updated_at,
            done_at: done_at,
            verified_at: verified_at,
            file_path: file_path,
            is_invalid_json: effective_status == TaskLightStatus.invalid_json.rawValue,
            invalid_json_error: effective_status == TaskLightStatus.invalid_json.rawValue ? state_cause : nil
        )
    }
}

public struct TaskLightUIObservation: Codable, Equatable, Identifiable {
    public var observation_id: String
    public var title: String
    public var status: String
    public var confidence: Double
    public var display_scope: String
    public var fresh: Bool
    public var last_seen_age_sec: Double?
    public var pid: Int?
    public var command_short: String?
    public var cwd: String?
    public var last_seen_at: String?

    public var id: String { observation_id }

    private enum CodingKeys: String, CodingKey {
        case observation_id
        case title
        case status
        case confidence
        case display_scope
        case fresh
        case last_seen_age_sec
        case pid
        case command_short
        case cwd
        case last_seen_at
    }

    public init(
        observation_id: String,
        title: String,
        status: String = TaskLightObservationStatus.observed_quiet.rawValue,
        confidence: Double = 0,
        display_scope: String = "history",
        fresh: Bool = false,
        last_seen_age_sec: Double? = nil,
        pid: Int? = nil,
        command_short: String? = nil,
        cwd: String? = nil,
        last_seen_at: String? = nil
    ) {
        self.observation_id = observation_id
        self.title = title
        self.status = status
        self.confidence = confidence
        self.display_scope = display_scope
        self.fresh = fresh
        self.last_seen_age_sec = last_seen_age_sec
        self.pid = pid
        self.command_short = command_short
        self.cwd = cwd
        self.last_seen_at = last_seen_at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.observation_id = try container.decode(String.self, forKey: .observation_id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? observation_id
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? TaskLightObservationStatus.observed_quiet.rawValue
        self.confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        self.display_scope = try container.decodeIfPresent(String.self, forKey: .display_scope) ?? "history"
        self.fresh = try container.decodeIfPresent(Bool.self, forKey: .fresh) ?? false
        self.last_seen_age_sec = try container.decodeIfPresent(Double.self, forKey: .last_seen_age_sec)
        self.pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        self.command_short = try container.decodeIfPresent(String.self, forKey: .command_short)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        self.last_seen_at = try Self.decodeLossyString(container, forKey: .last_seen_at)
    }

    private static func decodeLossyString<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    public func asObservationRecord() -> TaskLightObservationRecord {
        TaskLightObservationRecord(
            observation_id: observation_id,
            pid: pid ?? 0,
            ppid: 0,
            command: command_short ?? title,
            command_short: command_short ?? title,
            cwd: cwd,
            title: title,
            detected_at: nil,
            last_seen_at: last_seen_at,
            status: status,
            confidence: confidence
        )
    }
}

public struct TaskLightUIDiagnostics: Codable, Equatable {
    public var writer_status: String?
    public var hook_bridge_status: String?
    public var signal_bus_status: String?
    public var signal_bus_record_count: Int?
    public var signal_bus_source_counts: [String: Int]?
    public var active_turn_bindings: Int?
    public var latest_signal_age_sec: Double?
    public var latest_hook_signal_age_sec: Double?
    public var latest_hook_bridge_signal_age_sec: Double?
    public var latest_process_observer_signal_age_sec: Double?
    public var latest_private_probe_signal_age_sec: Double?
    public var latest_active_turn_age_sec: Double?
    public var latest_observed_age_sec: Double?
    public var latest_private_probe_status: String?
    public var latest_private_probe_quality: String?
    public var latest_private_probe_confidence: Double?
    public var current_thread_binding_status: String?
    public var current_thread_binding_fresh: Bool?
    public var latest_current_thread_binding_age_sec: Double?
    public var latest_current_thread_signal_age_sec: Double?
    public var current_thread_task_identity: String?
    public var current_thread_signal_source: String?
    public var current_thread_signal_quality: String?
    public var current_thread_signal_confidence: Double?
    public var current_thread_signal_status: String?
    public var current_thread_fusion_decision: String?
    public var latest_turn_binding_status: String?
    public var latest_turn_binding_age_sec: Double?
    public var latest_turn_binding_turn_id: String?
    public var latest_turn_binding_task_id: String?
    public var latest_turn_binding_canonical_identity: String?
    public var latest_turn_binding_aliases: [String]?
    public var latest_turn_signal_event: String?
    public var latest_bridge_decision: String?
    public var running_mismatch_warning: Bool?
    public var state_dir: String?
    public var app_bundle_path: String?
    public var build_id: String?
    public var projector_reason: [String]?
    public var observed_false_positive_count: Int?
    public var binding_identity_count: Int?
    public var runtime_candidate_count: Int?
    public var top_runtime_candidates: [TaskLightRuntimeCandidate]?
    public var appserver_active_count: Int?
    public var process_observed_count: Int?
    public var fallback_reason: String?
    public var quota_status: String?
    public var quota_fresh: Bool?
    public var quota_source: String?
    public var quota_state_path: String?
    public var quota_probe_status: String?
    public var quota_probe_health_path: String?
    public var quota_warning_count: Int?
    public var history_index_status: String?
    public var history_row_count: Int?
    public var duplicate_signal_rate: Double?
    public var status_transition_count_1h: Int?
    public var anomaly_count: Int?

    public init(
        writer_status: String? = nil,
        hook_bridge_status: String? = nil,
        signal_bus_status: String? = nil,
        signal_bus_record_count: Int? = nil,
        signal_bus_source_counts: [String: Int]? = nil,
        active_turn_bindings: Int? = nil,
        latest_signal_age_sec: Double? = nil,
        latest_hook_signal_age_sec: Double? = nil,
        latest_hook_bridge_signal_age_sec: Double? = nil,
        latest_process_observer_signal_age_sec: Double? = nil,
        latest_private_probe_signal_age_sec: Double? = nil,
        latest_active_turn_age_sec: Double? = nil,
        latest_observed_age_sec: Double? = nil,
        latest_private_probe_status: String? = nil,
        latest_private_probe_quality: String? = nil,
        latest_private_probe_confidence: Double? = nil,
        current_thread_binding_status: String? = nil,
        current_thread_binding_fresh: Bool? = nil,
        latest_current_thread_binding_age_sec: Double? = nil,
        latest_current_thread_signal_age_sec: Double? = nil,
        current_thread_task_identity: String? = nil,
        current_thread_signal_source: String? = nil,
        current_thread_signal_quality: String? = nil,
        current_thread_signal_confidence: Double? = nil,
        current_thread_signal_status: String? = nil,
        current_thread_fusion_decision: String? = nil,
        latest_turn_binding_status: String? = nil,
        latest_turn_binding_age_sec: Double? = nil,
        latest_turn_binding_turn_id: String? = nil,
        latest_turn_binding_task_id: String? = nil,
        latest_turn_binding_canonical_identity: String? = nil,
        latest_turn_binding_aliases: [String]? = nil,
        latest_turn_signal_event: String? = nil,
        latest_bridge_decision: String? = nil,
        running_mismatch_warning: Bool? = nil,
        state_dir: String? = nil,
        app_bundle_path: String? = nil,
        build_id: String? = nil,
        projector_reason: [String]? = nil,
        observed_false_positive_count: Int? = nil,
        binding_identity_count: Int? = nil,
        runtime_candidate_count: Int? = nil,
        top_runtime_candidates: [TaskLightRuntimeCandidate]? = nil,
        appserver_active_count: Int? = nil,
        process_observed_count: Int? = nil,
        fallback_reason: String? = nil,
        quota_status: String? = nil,
        quota_fresh: Bool? = nil,
        quota_source: String? = nil,
        quota_state_path: String? = nil,
        quota_probe_status: String? = nil,
        quota_probe_health_path: String? = nil,
        quota_warning_count: Int? = nil,
        history_index_status: String? = nil,
        history_row_count: Int? = nil,
        duplicate_signal_rate: Double? = nil,
        status_transition_count_1h: Int? = nil,
        anomaly_count: Int? = nil
    ) {
        self.writer_status = writer_status
        self.hook_bridge_status = hook_bridge_status
        self.signal_bus_status = signal_bus_status
        self.signal_bus_record_count = signal_bus_record_count
        self.signal_bus_source_counts = signal_bus_source_counts
        self.active_turn_bindings = active_turn_bindings
        self.latest_signal_age_sec = latest_signal_age_sec
        self.latest_hook_signal_age_sec = latest_hook_signal_age_sec
        self.latest_hook_bridge_signal_age_sec = latest_hook_bridge_signal_age_sec
        self.latest_process_observer_signal_age_sec = latest_process_observer_signal_age_sec
        self.latest_private_probe_signal_age_sec = latest_private_probe_signal_age_sec
        self.latest_active_turn_age_sec = latest_active_turn_age_sec
        self.latest_observed_age_sec = latest_observed_age_sec
        self.latest_private_probe_status = latest_private_probe_status
        self.latest_private_probe_quality = latest_private_probe_quality
        self.latest_private_probe_confidence = latest_private_probe_confidence
        self.current_thread_binding_status = current_thread_binding_status
        self.current_thread_binding_fresh = current_thread_binding_fresh
        self.latest_current_thread_binding_age_sec = latest_current_thread_binding_age_sec
        self.latest_current_thread_signal_age_sec = latest_current_thread_signal_age_sec
        self.current_thread_task_identity = current_thread_task_identity
        self.current_thread_signal_source = current_thread_signal_source
        self.current_thread_signal_quality = current_thread_signal_quality
        self.current_thread_signal_confidence = current_thread_signal_confidence
        self.current_thread_signal_status = current_thread_signal_status
        self.current_thread_fusion_decision = current_thread_fusion_decision
        self.latest_turn_binding_status = latest_turn_binding_status
        self.latest_turn_binding_age_sec = latest_turn_binding_age_sec
        self.latest_turn_binding_turn_id = latest_turn_binding_turn_id
        self.latest_turn_binding_task_id = latest_turn_binding_task_id
        self.latest_turn_binding_canonical_identity = latest_turn_binding_canonical_identity
        self.latest_turn_binding_aliases = latest_turn_binding_aliases
        self.latest_turn_signal_event = latest_turn_signal_event
        self.latest_bridge_decision = latest_bridge_decision
        self.running_mismatch_warning = running_mismatch_warning
        self.state_dir = state_dir
        self.app_bundle_path = app_bundle_path
        self.build_id = build_id
        self.projector_reason = projector_reason
        self.observed_false_positive_count = observed_false_positive_count
        self.binding_identity_count = binding_identity_count
        self.runtime_candidate_count = runtime_candidate_count
        self.top_runtime_candidates = top_runtime_candidates
        self.appserver_active_count = appserver_active_count
        self.process_observed_count = process_observed_count
        self.fallback_reason = fallback_reason
        self.quota_status = quota_status
        self.quota_fresh = quota_fresh
        self.quota_source = quota_source
        self.quota_state_path = quota_state_path
        self.quota_probe_status = quota_probe_status
        self.quota_probe_health_path = quota_probe_health_path
        self.quota_warning_count = quota_warning_count
        self.history_index_status = history_index_status
        self.history_row_count = history_row_count
        self.duplicate_signal_rate = duplicate_signal_rate
        self.status_transition_count_1h = status_transition_count_1h
        self.anomaly_count = anomaly_count
    }
}

public struct CodexQuotaWindowUIState: Codable, Equatable {
    public var id: String?
    public var label: String?
    public var bucket_id: String?
    public var remaining_percent: Int?
    public var used_percent: Int?
    public var reset_label: String?
    public var reset_at: String?
    public var window_duration_mins: Int?
    public var health: String?
    public var selection_reason: String?

    public init(
        id: String? = nil,
        label: String? = nil,
        bucket_id: String? = nil,
        remaining_percent: Int? = nil,
        used_percent: Int? = nil,
        reset_label: String? = nil,
        reset_at: String? = nil,
        window_duration_mins: Int? = nil,
        health: String? = nil,
        selection_reason: String? = nil
    ) {
        self.id = id
        self.label = label
        self.bucket_id = bucket_id
        self.remaining_percent = remaining_percent
        self.used_percent = used_percent
        self.reset_label = reset_label
        self.reset_at = reset_at
        self.window_duration_mins = window_duration_mins
        self.health = health
        self.selection_reason = selection_reason
    }
}

public struct CodexQuotaResetWindow: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var bucket_id: String?
    public var remaining_percent: Int?
    public var reset_label: String?
    public var reset_at: String?
    public var window_duration_mins: Int?
    public var validity_label: String

    public init(
        id: String,
        label: String,
        bucket_id: String? = nil,
        remaining_percent: Int? = nil,
        reset_label: String? = nil,
        reset_at: String? = nil,
        window_duration_mins: Int? = nil,
        validity_label: String
    ) {
        self.id = id
        self.label = label
        self.bucket_id = bucket_id
        self.remaining_percent = remaining_percent
        self.reset_label = reset_label
        self.reset_at = reset_at
        self.window_duration_mins = window_duration_mins
        self.validity_label = validity_label
    }
}

public struct CodexQuotaResetCreditUIState: Codable, Equatable, Identifiable {
    public var id: String
    public var status: String?
    public var issued_at: String?
    public var issued_date: String?
    public var expires_at: String?
    public var expiry_date: String?
    public var redeemed: Bool?
    public var reset_type: String?

    public init(
        id: String,
        status: String? = nil,
        issued_at: String? = nil,
        issued_date: String? = nil,
        expires_at: String? = nil,
        expiry_date: String? = nil,
        redeemed: Bool? = nil,
        reset_type: String? = nil
    ) {
        self.id = id
        self.status = status
        self.issued_at = issued_at
        self.issued_date = issued_date
        self.expires_at = expires_at
        self.expiry_date = expiry_date
        self.redeemed = redeemed
        self.reset_type = reset_type
    }
}

public struct CodexQuotaResetSnapshot: Codable, Equatable {
    public var status: String
    public var manual_resets_available: Int?
    public var manual_resets_total_count: Int?
    public var manual_resets_used_count: Int?
    public var manual_resets_expired_count: Int?
    public var next_expiry: String?
    public var manual_resets_label: String
    public var windows: [CodexQuotaResetWindow]
    public var credits: [CodexQuotaResetCreditUIState]
    public var summary: String

    public init(
        status: String,
        manual_resets_available: Int? = nil,
        manual_resets_total_count: Int? = nil,
        manual_resets_used_count: Int? = nil,
        manual_resets_expired_count: Int? = nil,
        next_expiry: String? = nil,
        manual_resets_label: String,
        windows: [CodexQuotaResetWindow] = [],
        credits: [CodexQuotaResetCreditUIState] = [],
        summary: String
    ) {
        self.status = status
        self.manual_resets_available = manual_resets_available
        self.manual_resets_total_count = manual_resets_total_count
        self.manual_resets_used_count = manual_resets_used_count
        self.manual_resets_expired_count = manual_resets_expired_count
        self.next_expiry = next_expiry
        self.manual_resets_label = manual_resets_label
        self.windows = windows
        self.credits = credits
        self.summary = summary
    }
}

public struct CodexQuotaUIState: Codable, Equatable {
    public var source: String?
    public var fresh: Bool
    public var status: String
    public var effective_remaining_percent: Int?
    public var display_windows: [CodexQuotaWindowUIState]?
    public var raw_window_count: Int?
    public var captured_age_sec: Double?
    public var probe_mode: String?
    public var bucket_id: String?
    public var warnings: [String]?
    public var short_percent: Int?
    public var short_label: String?
    public var short_reset_label: String?
    public var short_bucket_id: String?
    public var long_percent: Int?
    public var long_label: String?
    public var long_reset_label: String?
    public var long_bucket_id: String?
    public var manual_resets_available: Int?
    public var manual_resets_total_count: Int?
    public var manual_resets_used_count: Int?
    public var manual_resets_expired_count: Int?
    public var manual_resets_next_expiry: String?
    public var manual_reset_credits: [CodexQuotaResetCreditUIState]?
    public var captured_at: String?
    public var recommendation: String?

    public init(
        source: String? = nil,
        fresh: Bool = false,
        status: String = "unknown",
        effective_remaining_percent: Int? = nil,
        display_windows: [CodexQuotaWindowUIState]? = nil,
        raw_window_count: Int? = nil,
        captured_age_sec: Double? = nil,
        probe_mode: String? = nil,
        bucket_id: String? = nil,
        warnings: [String]? = nil,
        short_percent: Int? = nil,
        short_label: String? = nil,
        short_reset_label: String? = nil,
        short_bucket_id: String? = nil,
        long_percent: Int? = nil,
        long_label: String? = nil,
        long_reset_label: String? = nil,
        long_bucket_id: String? = nil,
        manual_resets_available: Int? = nil,
        manual_resets_total_count: Int? = nil,
        manual_resets_used_count: Int? = nil,
        manual_resets_expired_count: Int? = nil,
        manual_resets_next_expiry: String? = nil,
        manual_reset_credits: [CodexQuotaResetCreditUIState]? = nil,
        captured_at: String? = nil,
        recommendation: String? = nil
    ) {
        self.source = source
        self.fresh = fresh
        self.status = status
        self.effective_remaining_percent = effective_remaining_percent
        self.display_windows = display_windows
        self.raw_window_count = raw_window_count
        self.captured_age_sec = captured_age_sec
        self.probe_mode = probe_mode
        self.bucket_id = bucket_id
        self.warnings = warnings
        self.short_percent = short_percent
        self.short_label = short_label
        self.short_reset_label = short_reset_label
        self.short_bucket_id = short_bucket_id
        self.long_percent = long_percent
        self.long_label = long_label
        self.long_reset_label = long_reset_label
        self.long_bucket_id = long_bucket_id
        self.manual_resets_available = manual_resets_available
        self.manual_resets_total_count = manual_resets_total_count
        self.manual_resets_used_count = manual_resets_used_count
        self.manual_resets_expired_count = manual_resets_expired_count
        self.manual_resets_next_expiry = manual_resets_next_expiry
        self.manual_reset_credits = manual_reset_credits
        self.captured_at = captured_at
        self.recommendation = recommendation
    }
}

public enum TaskLightPresenceMode: String, Codable, CaseIterable {
    case normal
    case focusCapsule
    case menuBarOnly

    public var title: String {
        switch self {
        case .normal:
            return "正常"
        case .focusCapsule:
            return "Focus 胶囊"
        case .menuBarOnly:
            return "只留菜单栏"
        }
    }
}

public struct QuotaHistorySample: Codable, Equatable {
    public var schema_version: String
    public var captured_at: String
    public var source: String?
    public var fresh: Bool
    public var window_id: String
    public var label: String?
    public var bucket_id: String?
    public var remaining_percent: Int
    public var reset_label: String?
    public var reset_at: String?
    public var window_duration_mins: Int?

    public init(
        schema_version: String = "0.1",
        captured_at: String,
        source: String? = nil,
        fresh: Bool,
        window_id: String,
        label: String? = nil,
        bucket_id: String? = nil,
        remaining_percent: Int,
        reset_label: String? = nil,
        reset_at: String? = nil,
        window_duration_mins: Int? = nil
    ) {
        self.schema_version = schema_version
        self.captured_at = captured_at
        self.source = source
        self.fresh = fresh
        self.window_id = window_id
        self.label = label
        self.bucket_id = bucket_id
        self.remaining_percent = remaining_percent
        self.reset_label = reset_label
        self.reset_at = reset_at
        self.window_duration_mins = window_duration_mins
    }
}

public struct QuotaBurnRateWindow: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var bucket_id: String?
    public var remaining_percent: Int?
    public var samples: Int
    public var burn_percent_per_hour: Double?
    public var estimated_empty_at: String?
    public var reset_label: String?
    public var reset_at: String?
    public var warning: String?
    public var data_status: String
    public var confidence: QuotaBurnRateConfidence

    public init(
        id: String,
        label: String,
        bucket_id: String? = nil,
        remaining_percent: Int? = nil,
        samples: Int,
        burn_percent_per_hour: Double? = nil,
        estimated_empty_at: String? = nil,
        reset_label: String? = nil,
        reset_at: String? = nil,
        warning: String? = nil,
        data_status: String,
        confidence: QuotaBurnRateConfidence = .insufficient
    ) {
        self.id = id
        self.label = label
        self.bucket_id = bucket_id
        self.remaining_percent = remaining_percent
        self.samples = samples
        self.burn_percent_per_hour = burn_percent_per_hour
        self.estimated_empty_at = estimated_empty_at
        self.reset_label = reset_label
        self.reset_at = reset_at
        self.warning = warning
        self.data_status = data_status
        self.confidence = confidence
    }
}

public enum QuotaBurnRateConfidence: String, Codable, Equatable, CaseIterable {
    case insufficient
    case warming
    case stable
    case stale
}

public struct QuotaBurnRateSnapshot: Codable, Equatable {
    public var status: String
    public var generated_at: String
    public var effective_remaining_percent: Int?
    public var is_low_quota: Bool
    public var windows: [QuotaBurnRateWindow]
    public var summary: String
    public var confidence: QuotaBurnRateConfidence

    public init(
        status: String,
        generated_at: String = TaskLightTaskRecord.nowString(),
        effective_remaining_percent: Int? = nil,
        is_low_quota: Bool = false,
        windows: [QuotaBurnRateWindow] = [],
        summary: String,
        confidence: QuotaBurnRateConfidence = .insufficient
    ) {
        self.status = status
        self.generated_at = generated_at
        self.effective_remaining_percent = effective_remaining_percent
        self.is_low_quota = is_low_quota
        self.windows = windows
        self.summary = summary
        self.confidence = confidence
    }
}

public struct WorkspaceDoctorRow: Codable, Equatable, Identifiable {
    public var id: String { workspace }
    public var workspace: String
    public var name: String
    public var group: String
    public var coverage_status: String
    public var hook_status: String?
    public var hook_detail: String?
    public var hook_visibility: String?
    public var reason: String
    public var recommended_action: String
    public var severity: String
    public var preferred: Bool

    public init(
        workspace: String,
        name: String,
        group: String,
        coverage_status: String,
        hook_status: String? = nil,
        hook_detail: String? = nil,
        hook_visibility: String? = nil,
        reason: String,
        recommended_action: String,
        severity: String,
        preferred: Bool
    ) {
        self.workspace = workspace
        self.name = name
        self.group = group
        self.coverage_status = coverage_status
        self.hook_status = hook_status
        self.hook_detail = hook_detail
        self.hook_visibility = hook_visibility
        self.reason = reason
        self.recommended_action = recommended_action
        self.severity = severity
        self.preferred = preferred
    }
}

public struct StatusReplayRecord: Codable, Equatable, Identifiable {
    public var id: String
    public var recorded_at: String
    public var from_status: String
    public var to_status: String
    public var lamp_status: String
    public var evidence: String
    public var markers: [String]
    public var counts_summary: String
    public var writer_status: String
    public var hook_bridge_status: String

    public init(
        id: String,
        recorded_at: String,
        from_status: String,
        to_status: String,
        lamp_status: String,
        evidence: String,
        markers: [String],
        counts_summary: String,
        writer_status: String,
        hook_bridge_status: String
    ) {
        self.id = id
        self.recorded_at = recorded_at
        self.from_status = from_status
        self.to_status = to_status
        self.lamp_status = lamp_status
        self.evidence = evidence
        self.markers = markers
        self.counts_summary = counts_summary
        self.writer_status = writer_status
        self.hook_bridge_status = hook_bridge_status
    }
}

public struct InteractionRuleSelfTestResult: Codable, Equatable {
    public var single_click_toggles: Bool
    public var drag_threshold_prevents_toggle: Bool
    public var long_press_prevents_toggle: Bool
    public var double_click_opens_diagnostics: Bool
    public var threshold_points: Double
    public var long_press_ms: Int

    public init(
        single_click_toggles: Bool,
        drag_threshold_prevents_toggle: Bool,
        long_press_prevents_toggle: Bool,
        double_click_opens_diagnostics: Bool,
        threshold_points: Double,
        long_press_ms: Int
    ) {
        self.single_click_toggles = single_click_toggles
        self.drag_threshold_prevents_toggle = drag_threshold_prevents_toggle
        self.long_press_prevents_toggle = long_press_prevents_toggle
        self.double_click_opens_diagnostics = double_click_opens_diagnostics
        self.threshold_points = threshold_points
        self.long_press_ms = long_press_ms
    }
}

public struct WorkspaceHookInstallRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var workspaces: [String]
    public var created_at: String
    public var requires_user_confirmation: Bool
    public var manual_trust_required: Bool
    public var command_preview: String
    public var risk_summary: String
    public var post_install_next_action: String

    public init(
        id: String = UUID().uuidString,
        workspaces: [String],
        created_at: String = TaskLightTaskRecord.nowString(),
        requires_user_confirmation: Bool = true,
        manual_trust_required: Bool = true,
        command_preview: String,
        risk_summary: String = "Installs hooks only; never auto-trusts workspace hooks.",
        post_install_next_action: String = "Open each Codex workspace and manually trust hooks in the Codex UI."
    ) {
        self.id = id
        self.workspaces = workspaces
        self.created_at = created_at
        self.requires_user_confirmation = requires_user_confirmation
        self.manual_trust_required = manual_trust_required
        self.command_preview = command_preview
        self.risk_summary = risk_summary
        self.post_install_next_action = post_install_next_action
    }
}

public struct WorkspaceHookInstallResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var status: String
    public var installed_count: Int
    public var failed_count: Int
    public var manual_trust_required: Bool
    public var message: String
    public var updated_at: String

    public init(
        id: String = UUID().uuidString,
        status: String,
        installed_count: Int = 0,
        failed_count: Int = 0,
        manual_trust_required: Bool = true,
        message: String,
        updated_at: String = TaskLightTaskRecord.nowString()
    ) {
        self.id = id
        self.status = status
        self.installed_count = installed_count
        self.failed_count = failed_count
        self.manual_trust_required = manual_trust_required
        self.message = message
        self.updated_at = updated_at
    }
}

public enum ProviderHealth: String, Codable, Equatable, CaseIterable {
    case ok
    case warning
    case disabled
    case unavailable
}

public struct UsageProviderSnapshot: Codable, Equatable, Identifiable {
    public var id: String
    public var display_name: String
    public var health: ProviderHealth
    public var quota_text: String
    public var remaining_percent: Int?
    public var is_low_quota: Bool
    public var updated_at: String
    public var diagnostic_only: Bool
    public var source_label: String?
    public var freshness_label: String?
    public var conflict_label: String?

    public init(
        id: String,
        display_name: String,
        health: ProviderHealth,
        quota_text: String,
        remaining_percent: Int? = nil,
        is_low_quota: Bool = false,
        updated_at: String = TaskLightTaskRecord.nowString(),
        diagnostic_only: Bool = true,
        source_label: String = "local presentation",
        freshness_label: String = "unknown freshness",
        conflict_label: String? = nil
    ) {
        self.id = id
        self.display_name = display_name
        self.health = health
        self.quota_text = quota_text
        self.remaining_percent = remaining_percent
        self.is_low_quota = is_low_quota
        self.updated_at = updated_at
        self.diagnostic_only = diagnostic_only
        self.source_label = source_label
        self.freshness_label = freshness_label
        self.conflict_label = conflict_label
    }
}

public protocol UsageProviderAdapter {
    var id: String { get }
    var displayName: String { get }
    var isEnabled: Bool { get }
    func snapshot(from uiState: TaskLightUIState) -> UsageProviderSnapshot
}

public struct CodexUsageProviderAdapter: UsageProviderAdapter {
    public let id = "codex"
    public let displayName = "Codex"
    public let isEnabled = true

    public init() {}

    public func snapshot(from uiState: TaskLightUIState) -> UsageProviderSnapshot {
        guard let quota = uiState.quota else {
            return UsageProviderSnapshot(
                id: id,
                display_name: displayName,
                health: .unavailable,
                quota_text: "Q?",
                remaining_percent: uiState.quota?.effective_remaining_percent,
                diagnostic_only: true,
                source_label: "no local quota snapshot",
                freshness_label: "unavailable"
            )
        }
        let values = [quota.short_percent, quota.long_percent, quota.effective_remaining_percent].compactMap { $0 }
        let lowQuota = values.min().map { $0 < 20 } ?? false
        let short = quota.short_percent.map(String.init) ?? "?"
        let long = quota.long_percent.map(String.init) ?? quota.effective_remaining_percent.map(String.init) ?? "?"
        let source = quota.source ?? "unknown local source"
        let sourceLabel: String
        switch source {
        case "codex_appserver":
            sourceLabel = "ChatGPT Work local app-server"
        case "codex_appserver_cached":
            sourceLabel = "Last valid ChatGPT Work snapshot"
        default:
            sourceLabel = source
        }
        let freshness = quota.fresh
            ? quota.captured_age_sec.map { "fresh \(Int($0.rounded()))s" } ?? "fresh"
            : "stale"
        let conflict = quota.warnings?.first(where: {
            $0.localizedCaseInsensitiveContains("conflict")
                || $0.localizedCaseInsensitiveContains("schema_changed")
                || $0.localizedCaseInsensitiveContains("probe_error")
        }).map { warning in
            warning.contains("schema_changed") || warning.contains("probe_error")
                ? "Source changed; using the last valid local snapshot"
                : warning
        }
        let health: ProviderHealth = !quota.fresh ? .unavailable : (lowQuota || conflict != nil ? .warning : .ok)
        return UsageProviderSnapshot(
            id: id,
            display_name: displayName,
            health: health,
            quota_text: "⚡\(short)·\(long)",
            remaining_percent: quota.effective_remaining_percent,
            is_low_quota: lowQuota,
            updated_at: quota.captured_at ?? TaskLightTaskRecord.nowString(),
            diagnostic_only: true,
            source_label: sourceLabel,
            freshness_label: freshness,
            conflict_label: conflict
        )
    }
}

public struct DisabledUsageProviderAdapter: UsageProviderAdapter {
    public let id: String
    public let displayName: String
    public let isEnabled = false

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public func snapshot(from uiState: TaskLightUIState) -> UsageProviderSnapshot {
        UsageProviderSnapshot(
            id: id,
            display_name: displayName,
            health: .disabled,
            quota_text: "disabled",
            diagnostic_only: true
        )
    }
}

public struct TaskLightWidgetSnapshot: Codable, Equatable {
    public var schema_version: String
    public var generated_at: String
    public var source: String
    public var global_status: String
    public var lamp_status: String
    public var display_title: String
    public var running_count: Int
    public var pending_count: Int
    public var observed_count: Int
    public var blocked_count: Int
    public var done_count: Int
    public var quota_text: String
    public var quota_remaining_percent: Int?
    public var quota_is_low: Bool
    public var workspace_ok_count: Int
    public var workspace_warning_count: Int
    public var workspace_attention_count: Int
    public var workspace_unknown_count: Int
    public var providers: [UsageProviderSnapshot]

    public init(
        schema_version: String = "0.1",
        generated_at: String = TaskLightTaskRecord.nowString(),
        source: String,
        global_status: String,
        lamp_status: String,
        display_title: String,
        running_count: Int,
        pending_count: Int,
        observed_count: Int,
        blocked_count: Int,
        done_count: Int,
        quota_text: String,
        quota_remaining_percent: Int?,
        quota_is_low: Bool,
        workspace_ok_count: Int,
        workspace_warning_count: Int,
        workspace_attention_count: Int,
        workspace_unknown_count: Int,
        providers: [UsageProviderSnapshot]
    ) {
        self.schema_version = schema_version
        self.generated_at = generated_at
        self.source = source
        self.global_status = global_status
        self.lamp_status = lamp_status
        self.display_title = display_title
        self.running_count = running_count
        self.pending_count = pending_count
        self.observed_count = observed_count
        self.blocked_count = blocked_count
        self.done_count = done_count
        self.quota_text = quota_text
        self.quota_remaining_percent = quota_remaining_percent
        self.quota_is_low = quota_is_low
        self.workspace_ok_count = workspace_ok_count
        self.workspace_warning_count = workspace_warning_count
        self.workspace_attention_count = workspace_attention_count
        self.workspace_unknown_count = workspace_unknown_count
        self.providers = providers
    }
}

public enum TaskLightWidgetBridge {
    public static let widgetKind = "66TaskLightWidget"
    public static let appGroupID = "group.com.66tasklight.widget"
    public static let snapshotFileName = "widget_snapshot.json"

    public static func appGroupSnapshotURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFileName)
    }

    public static func encodeSnapshot(_ snapshot: TaskLightWidgetSnapshot) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeSnapshot(_ raw: String?) -> TaskLightWidgetSnapshot? {
        guard let raw,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(TaskLightWidgetSnapshot.self, from: data)
    }
}

public struct TaskLightUIState: Codable, Equatable {
    public var schema_version: String
    public var source: String
    public var projector_version: String?
    public var projector_pid: Int?
    public var projector_executable_path: String?
    public var projector_code_hash: String?
    public var projector_launch_label: String?
    public var projector_instance_id: String?
    public var projector_generated_at: String
    public var global_status: String
    public var lamp_status: String
    public var global_display_title: String
    public var state_confidence: Double
    public var counts: TaskLightUICounts
    public var tasks: [TaskLightUITask]
    public var observations: [TaskLightUIObservation]
    public var runtime_candidates: [TaskLightRuntimeCandidate]?
    public var quota: CodexQuotaUIState?
    public var diagnostics: TaskLightUIDiagnostics

    public init(
        schema_version: String = "0.1",
        source: String = "state_projector",
        projector_version: String? = nil,
        projector_pid: Int? = nil,
        projector_executable_path: String? = nil,
        projector_code_hash: String? = nil,
        projector_launch_label: String? = nil,
        projector_instance_id: String? = nil,
        projector_generated_at: String = TaskLightTaskRecord.nowString(),
        global_status: String = "idle",
        lamp_status: String = "idle",
        global_display_title: String = "IDLE",
        state_confidence: Double = 1,
        counts: TaskLightUICounts = TaskLightUICounts(),
        tasks: [TaskLightUITask] = [],
        observations: [TaskLightUIObservation] = [],
        runtime_candidates: [TaskLightRuntimeCandidate]? = nil,
        quota: CodexQuotaUIState? = nil,
        diagnostics: TaskLightUIDiagnostics = TaskLightUIDiagnostics()
    ) {
        self.schema_version = schema_version
        self.source = source
        self.projector_version = projector_version
        self.projector_pid = projector_pid
        self.projector_executable_path = projector_executable_path
        self.projector_code_hash = projector_code_hash
        self.projector_launch_label = projector_launch_label
        self.projector_instance_id = projector_instance_id
        self.projector_generated_at = projector_generated_at
        self.global_status = global_status
        self.lamp_status = lamp_status
        self.global_display_title = global_display_title
        self.state_confidence = state_confidence
        self.counts = counts
        self.tasks = tasks
        self.observations = observations
        self.runtime_candidates = runtime_candidates
        self.quota = quota
        self.diagnostics = diagnostics
    }
}

public enum TaskLightProjectedPresentation {
    public static func primaryStatus(from state: TaskLightUIState) -> String {
        let global = normalizedStatus(state.global_status)
        let lamp = normalizedStatus(state.lamp_status)
        return global.isEmpty ? (lamp.isEmpty ? TaskLightStatus.idle.rawValue : lamp) : global
    }

    public static func displayTitle(from state: TaskLightUIState) -> String {
        let status = primaryStatus(from: state)
        let expected = displayTitle(for: status)
        let projected = state.global_display_title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projected.isEmpty else {
            return expected
        }
        let projectedUpper = projected.uppercased()
        if expected != "IDLE", projectedUpper != expected {
            return expected
        }
        return projected
    }

    public static func displayTitle(for status: String) -> String {
        switch normalizedStatus(status) {
        case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue:
            return "BLOCKED"
        case TaskLightStatus.running.rawValue, TaskLightStatus.queued.rawValue:
            return "RUNNING"
        case "pending", TaskLightStatus.done_unverified.rawValue:
            return "PENDING"
        case TaskLightStatus.done_verified.rawValue:
            return "DONE"
        default:
            return "IDLE"
        }
    }

    public static func menuBarStatusLabel(from state: TaskLightUIState) -> String {
        switch primaryStatus(from: state) {
        case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue:
            return "Blocked"
        case TaskLightStatus.running.rawValue, TaskLightStatus.queued.rawValue:
            return "Running"
        case "pending", TaskLightStatus.done_unverified.rawValue:
            return "Pending"
        case TaskLightStatus.done_verified.rawValue:
            return "Done"
        default:
            if state.counts.stale > 0 {
                return "Stale"
            }
            if state.counts.observed_active > 0 {
                return "Observed"
            }
            if weakRuntimeCandidateCount(from: state) > 0 {
                return "Watch"
            }
            return "Idle"
        }
    }

    public static func menuBarActivityCount(from state: TaskLightUIState) -> Int {
        switch primaryStatus(from: state) {
        case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue:
            return state.counts.blocked + state.counts.stale
        case TaskLightStatus.running.rawValue, TaskLightStatus.queued.rawValue:
            let managedCount = state.counts.running + state.counts.queued
            return max(managedCount, authoritativeActiveCandidateCount(from: state))
        case "pending", TaskLightStatus.done_unverified.rawValue:
            return state.counts.pending_verify_count
        case TaskLightStatus.done_verified.rawValue:
            return state.counts.done_verified_visible
        default:
            if state.counts.stale > 0 {
                return state.counts.stale
            }
            if state.counts.observed_active > 0 {
                return state.counts.observed_active
            }
            return weakRuntimeCandidateCount(from: state)
        }
    }

    private static func weakRuntimeCandidateCount(from state: TaskLightUIState) -> Int {
        (state.runtime_candidates ?? []).filter { candidate in
            let freshness = candidate.freshness_score ?? 0
            guard freshness > 0 else { return false }
            if candidate.display_scope == "observed_only" {
                return true
            }
            guard candidate.display_scope == "ignored", freshness >= 0.5 else {
                return false
            }
            let sources = Set(candidate.source_set)
            let hasDiagnosticSource = sources.contains("codex_appserver")
                || sources.contains("codex_private_probe")
            let cause = candidate.state_cause ?? ""
            let ignoredReason = candidate.why_ignored ?? ""
            return hasDiagnosticSource && (
                cause.contains("codex_appserver:unknown")
                    || cause.contains("private_active")
                    || ignoredReason == "runtime_score_below_threshold"
            )
        }.count
    }

    private static func authoritativeActiveCandidateCount(from state: TaskLightUIState) -> Int {
        let candidateIDs = (state.runtime_candidates ?? []).compactMap { candidate -> String? in
            guard candidate.display_scope == "active_execution" else { return nil }
            guard (candidate.freshness_score ?? 0) > 0 else { return nil }
            return candidate.candidate_id
        }
        return Set(candidateIDs).count
    }

    private static func normalizedStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct TaskLightUIClientRecord: Codable, Equatable {
    public var schema_version: String
    public var pid: Int
    public var bundle_id: String
    public var bundle_path: String
    public var executable_path: String
    public var build_id: String
    public var state_dir: String
    public var started_at: String
    public var updated_at: String

    public init(
        schema_version: String = "0.1",
        pid: Int,
        bundle_id: String,
        bundle_path: String,
        executable_path: String,
        build_id: String,
        state_dir: String,
        started_at: String = TaskLightTaskRecord.nowString(),
        updated_at: String = TaskLightTaskRecord.nowString()
    ) {
        self.schema_version = schema_version
        self.pid = pid
        self.bundle_id = bundle_id
        self.bundle_path = bundle_path
        self.executable_path = executable_path
        self.build_id = build_id
        self.state_dir = state_dir
        self.started_at = started_at
        self.updated_at = updated_at
    }
}

public struct TaskLightWorkspaceCoverageRunStatus: Codable, Equatable {
    public var schema_version: String?
    public var status: String
    public var message: String?
    public var updated_at: String?
    public var latest_json_path: String?
    public var report_path: String?

    public init(
        schema_version: String? = "0.1",
        status: String,
        message: String? = nil,
        updated_at: String? = nil,
        latest_json_path: String? = nil,
        report_path: String? = nil
    ) {
        self.schema_version = schema_version
        self.status = status
        self.message = message
        self.updated_at = updated_at
        self.latest_json_path = latest_json_path
        self.report_path = report_path
    }
}

public struct TaskLightWorkspaceCoverageReport: Codable, Equatable {
    public struct Summary: Codable, Equatable {
        public var workspace_count: Int?
        public var trusted: Int?
        public var installed_needs_trust: Int?
        public var missing_hooks: Int?
        public var invalid_hooks: Int?
        public var not_loaded: Int?
        public var diagnostic_only: Int?
        public var unknown: Int?
        public var preferred_workspace_count: Int?
        public var preferred_trusted: Int?
        public var preferred_installed_needs_trust: Int?
        public var preferred_missing_hooks: Int?
        public var preferred_invalid_hooks: Int?
    }

    public var schema_version: String?
    public var generated_at: String?
    public var status: String?
    public var summary: Summary?
}

public struct TaskLightWorkspaceCoveragePresentation: Equatable {
    public var message: String
    public var status: String
    public var isError: Bool
    public var reportURL: URL?

    public init(message: String, status: String, isError: Bool = false, reportURL: URL? = nil) {
        self.message = message
        self.status = status
        self.isError = isError
        self.reportURL = reportURL
    }
}

public struct TaskLightEventRecord: Codable, Equatable {
    public var schema_version: Int
    public var event_id: String
    public var task_id: String
    public var from: String
    public var to: String
    public var created_at: String
    public var sound_type: String
    public var reason: String?
    public var message: String?
    public var summary: String?
    public var phase: String?
    public var progress: Double?
    public var title: String?

    public init(
        schema_version: Int = 3,
        event_id: String,
        task_id: String,
        from: String,
        to: String,
        created_at: String,
        sound_type: String,
        reason: String? = nil,
        message: String? = nil,
        summary: String? = nil,
        phase: String? = nil,
        progress: Double? = nil,
        title: String? = nil
    ) {
        self.schema_version = schema_version
        self.event_id = event_id
        self.task_id = task_id
        self.from = from
        self.to = to
        self.created_at = created_at
        self.sound_type = sound_type
        self.reason = reason
        self.message = message
        self.summary = summary
        self.phase = phase
        self.progress = progress
        self.title = title
    }
}

public struct TaskLightSoundWindow: Codable, Equatable {
    public var last_played_at: String?
    public var last_event_id: String?

    public init(last_played_at: String? = nil, last_event_id: String? = nil) {
        self.last_played_at = last_played_at
        self.last_event_id = last_event_id
    }
}

public struct TaskLightPlayedEventsLedger: Codable, Equatable {
    public var schema_version: Int
    public var muted: Bool
    public var played_event_ids: [String]
    public var sound_windows: [String: TaskLightSoundWindow]
    public var updated_at: String

    public init(
        schema_version: Int = 2,
        muted: Bool = false,
        played_event_ids: [String] = [],
        sound_windows: [String: TaskLightSoundWindow] = [
            "blocked": TaskLightSoundWindow(),
            "done_verified": TaskLightSoundWindow()
        ],
        updated_at: String = TaskLightTaskRecord.nowString()
    ) {
        self.schema_version = schema_version
        self.muted = muted
        self.played_event_ids = played_event_ids
        self.sound_windows = sound_windows
        self.updated_at = updated_at
    }
}

public enum TaskLightLedgerKeys {
    public static let lastAlertStatus = "TaskLightLastAlertStatus"
    public static let lastAlertFingerprint = "TaskLightLastAlertFingerprint"
    public static let windowFrame = "TaskLightWindowFrame"
    public static let compactWindowFrame = "TaskLightCompactWindowFrame"
    public static let edgeRailWindowFrame = "TaskLightEdgeRailWindowFrame"
    public static let muted = "TaskLightMuted"
    public static let expanded = "TaskLightExpanded"
    public static let edgeCollapsed = "TaskLightEdgeCollapsed"
    public static let presenceMode = "TaskLightPresenceMode"
    public static let autoMeetingMode = "TaskLightAutoMeetingMode"
}

private enum SHA256 {
    static func hexDigest(data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension TaskLightTaskRecord {
    public static func nowString() -> String {
        nowString(from: Date())
    }

    public static func nowString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date).replacingOccurrences(of: "+00:00", with: "Z")
    }
}
