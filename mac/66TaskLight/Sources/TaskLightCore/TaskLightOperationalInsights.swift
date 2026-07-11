import Foundation

public struct TaskLightStatusExplanation: Codable, Equatable, Identifiable {
    public var id: String
    public var severity: String
    public var title: String
    public var detail: String
    public var evidence: String
    public var recommendedAction: String

    public init(id: String, severity: String, title: String, detail: String, evidence: String, recommendedAction: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.evidence = evidence
        self.recommendedAction = recommendedAction
    }
}

public struct WorkspaceRepairQueueItem: Codable, Equatable, Identifiable {
    public var id: String { workspace }
    public var workspace: String
    public var name: String
    public var severity: String
    public var action: String
    public var requiresUserConfirmation: Bool
    public var manualTrustRequired: Bool

    public init(workspace: String, name: String, severity: String, action: String, requiresUserConfirmation: Bool, manualTrustRequired: Bool) {
        self.workspace = workspace
        self.name = name
        self.severity = severity
        self.action = action
        self.requiresUserConfirmation = requiresUserConfirmation
        self.manualTrustRequired = manualTrustRequired
    }
}

public struct QuotaCalendarEntry: Codable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    public var dueAt: String?
    public var detail: String
    public var severity: String

    public init(id: String, kind: String, title: String, dueAt: String?, detail: String, severity: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.dueAt = dueAt
        self.detail = detail
        self.severity = severity
    }
}

public struct TaskLightProviderOptIn: Codable, Equatable {
    public var schema_version: String
    public var explicit_user_opt_in: Bool
    public var provider_ids: [String]
    public var consented_at: String?

    public init(schema_version: String = "0.1", explicit_user_opt_in: Bool = false, provider_ids: [String] = [], consented_at: String? = nil) {
        self.schema_version = schema_version
        self.explicit_user_opt_in = explicit_user_opt_in
        self.provider_ids = provider_ids
        self.consented_at = consented_at
    }

    public func allows(_ providerID: String) -> Bool {
        explicit_user_opt_in && provider_ids.contains(providerID)
    }
}

public struct TaskLightRenderTelemetry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var recorded_at: String
    public var load_milliseconds: Double
    public var status: String
    public var cache_hit: Bool

    public init(id: String = UUID().uuidString, recorded_at: String = TaskLightTaskRecord.nowString(), load_milliseconds: Double, status: String, cache_hit: Bool) {
        self.id = id
        self.recorded_at = recorded_at
        self.load_milliseconds = load_milliseconds
        self.status = status
        self.cache_hit = cache_hit
    }
}

public enum TaskLightOperationalInsights {
    public static func statusExplanations(
        uiState: TaskLightUIState,
        replay: [StatusReplayRecord],
        limit: Int = 4
    ) -> [TaskLightStatusExplanation] {
        var output: [TaskLightStatusExplanation] = []

        let writerStatus = uiState.diagnostics.writer_status ?? "unknown"
        if writerStatus != "ok" {
            output.append(TaskLightStatusExplanation(
                id: "writer-\(writerStatus)",
                severity: "attention",
                title: "Writer requires review",
                detail: "UI writer status is \(writerStatus).",
                evidence: (uiState.diagnostics.projector_reason ?? ["writer_status"]).joined(separator: ", "),
                recommendedAction: "Run State Projector and LaunchAgent checks before trusting the lamp."
            ))
        }

        let markerRules: [(String, String, String, String, String)] = [
            ("process_only_not_authoritative", "Process-only evidence was rejected", "A local process was observed but cannot independently prove managed RUNNING.", "warning", "Check hook or app-server turn evidence."),
            ("old_writer", "Old projector writer detected", "A previous writer may be publishing stale UI state.", "attention", "Restart the current State Projector and verify a single writer."),
            ("multiple_writers", "Multiple projector writers detected", "Concurrent writers can make the read model inconsistent.", "attention", "Keep one projector instance and re-run the writer check."),
            ("stale_launch_agent", "LaunchAgent is stale", "The health source is older than the freshness budget.", "warning", "Inspect the affected LaunchAgent and refresh its health report."),
            ("runtime_score_below_threshold", "Weak runtime candidate was rejected", "Observed runtime evidence did not meet the threshold for RUNNING.", "warning", "Use the replay evidence; do not promote weak process evidence."),
            ("fallback_reason", "Fallback read model is active", "The UI is showing a degraded local fallback rather than fresh projector state.", "warning", "Restore the projector signal path before relying on live status.")
        ]
        let replayMarkers = replay.flatMap(\.markers)
        for rule in markerRules where replayMarkers.contains(where: { $0.localizedCaseInsensitiveContains(rule.0) }) {
            output.append(TaskLightStatusExplanation(
                id: rule.0,
                severity: rule.3,
                title: rule.1,
                detail: rule.2,
                evidence: rule.0,
                recommendedAction: rule.4
            ))
        }

        if output.isEmpty, let latest = replay.first, latest.to_status == "idle", latest.from_status == "running" {
            output.append(TaskLightStatusExplanation(
                id: "running-to-idle",
                severity: "warning",
                title: "RUNNING returned to IDLE",
                detail: "The latest authoritative transition no longer had a qualifying runtime candidate.",
                evidence: latest.evidence,
                recommendedAction: "Inspect the latest turn, Hook Bridge, and runtime candidate diagnostics."
            ))
        }

        return Array(output.prefix(max(1, limit)))
    }

    public static func workspaceRepairQueue(rows: [WorkspaceDoctorRow], limit: Int = 12) -> [WorkspaceRepairQueueItem] {
        let rank: [String: Int] = ["attention": 0, "warning": 1, "needs_review": 1, "unknown": 2, "ok": 3]
        return rows
            .filter { $0.severity != "ok" }
            .sorted {
                let left = rank[$0.severity] ?? 2
                let right = rank[$1.severity] ?? 2
                if left != right { return left < right }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(limit)
            .map { row in
                let status = "\(row.coverage_status) \(row.hook_status ?? "")".lowercased()
                let needsTrust = status.contains("trust") || row.reason.localizedCaseInsensitiveContains("trust")
                let installable = ["attention", "warning", "needs_review"].contains(row.severity) && !needsTrust
                let action: String
                if needsTrust {
                    action = "Open the workspace in Codex and manually Trust hooks."
                } else if installable {
                    action = "Review then install hooks; coverage will be rechecked afterwards."
                } else {
                    action = "Open the workspace and rerun coverage to refresh its health."
                }
                return WorkspaceRepairQueueItem(
                    workspace: row.workspace,
                    name: row.name,
                    severity: row.severity,
                    action: action,
                    requiresUserConfirmation: installable,
                    manualTrustRequired: needsTrust
                )
            }
    }

    public static func quotaCalendar(
        reset: CodexQuotaResetSnapshot,
        now: Date = Date(),
        limit: Int = 8
    ) -> [QuotaCalendarEntry] {
        var entries: [QuotaCalendarEntry] = reset.windows.map { window in
            QuotaCalendarEntry(
                id: "reset-\(window.id)",
                kind: "reset",
                title: "\(window.label) reset",
                dueAt: window.reset_at,
                detail: "\(window.validity_label) · remaining \(window.remaining_percent.map { "\($0)%" } ?? "Q?")",
                severity: quotaSeverity(dueAt: window.reset_at, now: now)
            )
        }

        entries += reset.credits.compactMap { credit in
            guard credit.redeemed != true else { return nil }
            let expiry = credit.expires_at ?? credit.expiry_date
            return QuotaCalendarEntry(
                id: "credit-\(credit.id)",
                kind: "credit_expiry",
                title: "Reset credit expiry",
                dueAt: expiry,
                detail: "\((credit.status ?? "unknown").capitalized) credit · use before its latest valid time.",
                severity: quotaSeverity(dueAt: expiry, now: now)
            )
        }

        return entries
            .sorted { lhs, rhs in
                let left = parseDate(lhs.dueAt) ?? .distantFuture
                let right = parseDate(rhs.dueAt) ?? .distantFuture
                return left < right
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func quotaSeverity(dueAt: String?, now: Date) -> String {
        guard let date = parseDate(dueAt) else { return "unknown" }
        let seconds = date.timeIntervalSince(now)
        if seconds < 0 { return "attention" }
        if seconds < 24 * 3600 { return "attention" }
        if seconds < 72 * 3600 { return "warning" }
        return "ok"
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let timestamp = TaskLightTaskRecord.parseTimestamp(raw) { return timestamp }
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: raw)
    }
}
