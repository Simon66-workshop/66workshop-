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

public struct TaskLightConfig {
    public var stateDirectory: URL
    public var stateURL: URL
    public var tasksDirectoryURL: URL
    public var currentURL: URL
    public var observationsDirectoryURL: URL
    public var observationsStateURL: URL
    public var eventsURL: URL
    public var playedEventsURL: URL
    public var lockURL: URL
    public var ttlSeconds: TimeInterval
    public var verificationTTLSeconds: TimeInterval
    public var refreshSeconds: TimeInterval
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
        observationsDirectoryURL: URL? = nil,
        observationsStateURL: URL? = nil
    ) {
        self.stateDirectory = stateDirectory
        self.stateURL = stateDirectory.appendingPathComponent("state.json")
        self.tasksDirectoryURL = stateDirectory.appendingPathComponent("tasks")
        self.currentURL = stateDirectory.appendingPathComponent("current.json")
        self.observationsDirectoryURL = observationsDirectoryURL ?? stateDirectory.appendingPathComponent("observations")
        self.observationsStateURL = observationsStateURL ?? stateDirectory.appendingPathComponent("observations_state.json")
        self.eventsURL = stateDirectory.appendingPathComponent("events.jsonl")
        self.playedEventsURL = stateDirectory.appendingPathComponent("played_events.json")
        self.lockURL = stateDirectory.appendingPathComponent(".lock")
        self.ttlSeconds = ttlSeconds
        self.verificationTTLSeconds = verificationTTLSeconds
        self.refreshSeconds = refreshSeconds
        self.blockedSoundName = blockedSoundName
        self.doneSoundName = doneSoundName
        self.staleSoundName = staleSoundName
    }

    public static func fromEnvironment() -> TaskLightConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let stateDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TASKLIGHT_STATE_DIR"] ?? home.appendingPathComponent(".66tasklight").path)
        let ttlSeconds = TimeInterval(ProcessInfo.processInfo.environment["TASKLIGHT_TTL_SECONDS"].flatMap(Double.init) ?? 300)
        let verificationTTLSeconds = TimeInterval(ProcessInfo.processInfo.environment["TASKLIGHT_VERIFICATION_TTL_SECONDS"].flatMap(Double.init) ?? 900)
        let refreshSeconds = TimeInterval(ProcessInfo.processInfo.environment["TASKLIGHT_REFRESH_SECONDS"].flatMap(Double.init) ?? 1)
        let blockedSoundName = ProcessInfo.processInfo.environment["TASKLIGHT_BLOCKED_SOUND"] ?? "Basso"
        let doneSoundName = ProcessInfo.processInfo.environment["TASKLIGHT_DONE_SOUND"] ?? "Submarine"
        let staleSoundName = ProcessInfo.processInfo.environment["TASKLIGHT_STALE_SOUND"] ?? "Funk"
        let observationsDirectoryURL = ProcessInfo.processInfo.environment["TASKLIGHT_OBSERVATIONS_DIR"].map { URL(fileURLWithPath: $0) }
        let observationsStateURL = ProcessInfo.processInfo.environment["TASKLIGHT_OBSERVATIONS_STATE_PATH"].map { URL(fileURLWithPath: $0) }
        return TaskLightConfig(
            stateDirectory: stateDirectory,
            ttlSeconds: ttlSeconds,
            verificationTTLSeconds: verificationTTLSeconds,
            refreshSeconds: refreshSeconds,
            blockedSoundName: blockedSoundName,
            doneSoundName: doneSoundName,
            staleSoundName: staleSoundName,
            observationsDirectoryURL: observationsDirectoryURL,
            observationsStateURL: observationsStateURL
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
    public static let muted = "TaskLightMuted"
    public static let expanded = "TaskLightExpanded"
}

private enum SHA256 {
    static func hexDigest(data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension TaskLightTaskRecord {
    public static func nowString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date()).replacingOccurrences(of: "+00:00", with: "Z")
    }
}
