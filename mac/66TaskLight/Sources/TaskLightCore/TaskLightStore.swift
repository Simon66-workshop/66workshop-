import Foundation
import Darwin
#if canImport(WidgetKit)
import WidgetKit
#endif

public final class TaskLightStore {
    public let config: TaskLightConfig
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var workspaceDoctorRowsCache: (fingerprint: String, rows: [WorkspaceDoctorRow])?
    private var statusReplayCache: (fingerprint: String, records: [StatusReplayRecord])?

    public init(config: TaskLightConfig = .fromEnvironment()) {
        self.config = config
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    }

    public func ensureLayout() {
        try? FileManager.default.createDirectory(at: config.stateDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: config.tasksDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: config.observationsDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: config.uiClientsDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: config.workspaceCoverageDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: config.providersDirectoryURL.appendingPathComponent("snapshots"), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: config.playedEventsURL.path) {
            let ledger = TaskLightPlayedEventsLedger()
            try? writeJSONAtomic(ledger, to: config.playedEventsURL)
        }
        if !FileManager.default.fileExists(atPath: config.observationsStateURL.path) {
            let observations = TaskLightObservationsState()
            try? writeJSONAtomic(observations, to: config.observationsStateURL)
        }
    }

    public func taskURL(taskID: String) -> URL {
        config.tasksDirectoryURL.appendingPathComponent("\(taskID).json")
    }

    public func loadFallbackDashboard() -> TaskLightAggregateState {
        ensureLayout()
        let stateResult = readStateSnapshot()
        let scan = scanTaskFiles()
        let observations = loadObservationsState()

        var dashboard: TaskLightAggregateState
        if !scan.valid.isEmpty || !scan.invalid.isEmpty {
            let sourceHealth = stateResult.health
            let built = buildAggregate(valid: scan.valid, invalid: scan.invalid, sourceHealth: sourceHealth)
            dashboard = refreshLiveState(built)
            dashboard.observations_state = observations
            return dashboard
        }

        if let state = stateResult.state {
            dashboard = refreshLiveState(markSourceHealth(state, sourceHealth: stateResult.health))
            dashboard.observations_state = observations
            return dashboard
        }

        if let legacy = loadLegacyCurrentRecord() {
            dashboard = refreshLiveState(buildAggregate(valid: [summary(from: legacy, filePath: config.currentURL)], invalid: [], sourceHealth: stateResult.health))
            dashboard.observations_state = observations
            return dashboard
        }

        dashboard = emptyState(sourceHealth: stateResult.health)
        dashboard.observations_state = observations
        return dashboard
    }

    public func loadDashboard() -> TaskLightAggregateState {
        loadFallbackDashboard()
    }

    public func loadProjectedUIState() -> TaskLightUIState {
        ensureLayout()
        if let projected: TaskLightUIState = try? readJSON(from: config.uiStateURL),
           isUIStateFresh(projected) {
            return projected
        }
        let fallbackReason: String
        if !FileManager.default.fileExists(atPath: config.uiStateURL.path) {
            fallbackReason = "projector_missing"
        } else {
            let decoded: TaskLightUIState? = try? readJSON(from: config.uiStateURL)
            if decoded == nil {
                fallbackReason = "projector_unreadable"
            } else {
                fallbackReason = "projector_stale"
            }
        }
        return fallbackUIState(from: loadFallbackDashboard(), reason: fallbackReason)
    }

    public func loadUIState() -> TaskLightUIState {
        loadProjectedUIState()
    }

    public func saveUIClientRecord(
        bundleID: String,
        bundlePath: String,
        executablePath: String,
        buildID: String
    ) {
        ensureLayout()
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let url = config.uiClientsDirectoryURL.appendingPathComponent("\(pid).json")
        let existing: TaskLightUIClientRecord? = try? readJSON(from: url)
        let record = TaskLightUIClientRecord(
            pid: pid,
            bundle_id: bundleID,
            bundle_path: bundlePath,
            executable_path: executablePath,
            build_id: buildID,
            state_dir: config.stateDirectory.path,
            started_at: existing?.started_at ?? TaskLightTaskRecord.nowString(),
            updated_at: TaskLightTaskRecord.nowString()
        )
        try? writeJSONAtomic(record, to: url)
    }

    public func loadTask(taskID: String) -> TaskLightTaskSummary? {
        ensureLayout()
        let scan = scanTaskFiles()
        if let match = scan.valid.first(where: { $0.task_id == taskID }) {
            return match
        }
        if let match = scan.invalid.first(where: { $0.task_id == taskID }) {
            return match
        }
        if let legacy = loadLegacyCurrentRecord(), legacy.task_id == taskID {
            return summary(from: legacy, filePath: config.currentURL)
        }
        return nil
    }

    public func loadEvents() -> [TaskLightEventRecord] {
        ensureLayout()
        guard let raw = try? String(contentsOf: config.eventsURL, encoding: .utf8), !raw.isEmpty else {
            return []
        }
        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(TaskLightEventRecord.self, from: data)
            }
    }

    public func loadRecentEvents(
        limit: Int = TaskLightUIPerformanceBudget.alertPlaybackRecentEventLimit,
        maxBytes: Int = TaskLightUIPerformanceBudget.eventTailReadMaxBytes
    ) -> [TaskLightEventRecord] {
        ensureLayout()
        guard limit > 0,
              maxBytes > 0,
              let handle = try? FileHandle(forReadingFrom: config.eventsURL)
        else {
            return []
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return [] }
        let bytesToRead = min(UInt64(maxBytes), fileSize)
        let startOffset = fileSize - bytesToRead
        do {
            try handle.seek(toOffset: startOffset)
            guard let data = try handle.readToEnd(), !data.isEmpty else { return [] }
            guard var raw = String(data: data, encoding: .utf8), !raw.isEmpty else { return [] }
            if startOffset > 0, let firstNewline = raw.firstIndex(where: \.isNewline) {
                raw = String(raw[raw.index(after: firstNewline)...])
            }
            return raw
                .split(whereSeparator: \.isNewline)
                .suffix(limit)
                .compactMap { line in
                    guard let data = String(line).data(using: .utf8) else { return nil }
                    return try? decoder.decode(TaskLightEventRecord.self, from: data)
                }
        } catch {
            return []
        }
    }

    public func loadPlayedLedger() -> TaskLightPlayedEventsLedger {
        ensureLayout()
        guard let ledger: TaskLightPlayedEventsLedger = try? readJSON(from: config.playedEventsURL) else {
            return TaskLightPlayedEventsLedger()
        }
        return ledger
    }

    public func savePlayedLedger(_ ledger: TaskLightPlayedEventsLedger) {
        ensureLayout()
        try? writeJSONAtomic(ledger, to: config.playedEventsURL)
    }

    public func appendEvent(_ event: TaskLightEventRecord) {
        ensureLayout()
        rotateJSONLIfNeeded(
            config.eventsURL,
            maxBytes: UInt64(TaskLightUIPerformanceBudget.eventLogMaxBytes),
            archiveCount: TaskLightUIPerformanceBudget.retainedLogArchiveCount
        )
        let encoded = (try? encoder.encode(event)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let line = encoded + "\n"
        let fd = open(config.eventsURL.path, O_WRONLY | O_APPEND | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withCString { pointer in
            write(fd, pointer, strlen(pointer))
        }
        fsync(fd)
    }

    public func appendUIEventFlowRecord(_ payload: [String: Any]) {
        ensureLayout()
        rotateJSONLIfNeeded(
            config.uiEventFlowURL,
            maxBytes: UInt64(TaskLightUIPerformanceBudget.uiEventFlowLogMaxBytes),
            archiveCount: TaskLightUIPerformanceBudget.retainedLogArchiveCount
        )
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        let line = encoded + "\n"
        let fd = open(config.uiEventFlowURL.path, O_WRONLY | O_APPEND | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withCString { pointer in
            write(fd, pointer, strlen(pointer))
        }
        fsync(fd)
        statusReplayCache = nil
    }

    private func rotateJSONLIfNeeded(_ url: URL, maxBytes: UInt64, archiveCount: Int) {
        guard maxBytes > 0, archiveCount > 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value >= maxBytes else {
            return
        }
        let manager = FileManager.default
        for index in stride(from: archiveCount, through: 1, by: -1) {
            let destination = URL(fileURLWithPath: url.path + ".\(index)")
            if index == archiveCount {
                try? manager.removeItem(at: destination)
            }
            let source = index == 1 ? url : URL(fileURLWithPath: url.path + ".\(index - 1)")
            if manager.fileExists(atPath: source.path) {
                try? manager.moveItem(at: source, to: destination)
            }
        }
    }

    public func appendQuotaHistorySample(from quota: CodexQuotaUIState?) {
        ensureLayout()
        guard let quota, quota.fresh else { return }
        let capturedAt = quota.captured_at ?? TaskLightTaskRecord.nowString()
        let windows = quotaHistoryWindows(from: quota)
        guard !windows.isEmpty else { return }
        for sample in windows {
            appendQuotaHistorySample(sample, capturedAt: capturedAt, source: quota.source, fresh: quota.fresh)
        }
        pruneQuotaHistoryIfNeeded()
    }

    public func loadQuotaHistory(limit: Int = 400) -> [QuotaHistorySample] {
        ensureLayout()
        guard limit > 0,
              let raw = try? String(contentsOf: config.quotaHistoryURL, encoding: .utf8),
              !raw.isEmpty else {
            return []
        }
        return raw
            .split(whereSeparator: \.isNewline)
            .suffix(limit)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(QuotaHistorySample.self, from: data)
            }
    }

    public func saveWidgetSnapshot(_ snapshot: TaskLightWidgetSnapshot) {
        ensureLayout()
        try? writeJSONAtomic(snapshot, to: config.widgetSnapshotURL)
        saveWidgetSnapshotToAppGroup(snapshot)
    }

    public func loadWidgetSnapshot() -> TaskLightWidgetSnapshot? {
        ensureLayout()
        return try? readJSON(from: config.widgetSnapshotURL)
    }

    public func loadWidgetSnapshotFromAppGroup() -> TaskLightWidgetSnapshot? {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--tasklight-") }) else {
            return nil
        }
        guard let url = TaskLightWidgetBridge.appGroupSnapshotURL(),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return TaskLightWidgetBridge.decodeSnapshot(raw)
    }

    public func loadExternalUsageProviderSnapshots() -> [UsageProviderSnapshot] {
        ensureLayout()
        let directory = config.providersDirectoryURL.appendingPathComponent("snapshots")
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                try? readJSON(from: url) as UsageProviderSnapshot
            }
            .filter { $0.diagnostic_only }
            .sorted { $0.id < $1.id }
    }

    private func saveWidgetSnapshotToAppGroup(_ snapshot: TaskLightWidgetSnapshot) {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--tasklight-") }),
              let raw = TaskLightWidgetBridge.encodeSnapshot(snapshot) else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            guard let url = TaskLightWidgetBridge.appGroupSnapshotURL() else {
                return
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? raw.write(to: url, atomically: true, encoding: .utf8)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: TaskLightWidgetBridge.widgetKind)
            #endif
        }
    }

    public func loadWorkspaceDoctorRows(limit: Int = 12) -> [WorkspaceDoctorRow] {
        ensureLayout()
        guard limit > 0 else {
            return []
        }
        let fingerprint = fileFingerprint(for: config.workspaceCoverageLatestJSONURL)
        if let cached = workspaceDoctorRowsCache, cached.fingerprint == fingerprint {
            return Array(cached.rows.prefix(limit))
        }
        guard let raw = try? Data(contentsOf: config.workspaceCoverageLatestJSONURL),
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let items = payload["workspaces"] as? [[String: Any]] else {
            workspaceDoctorRowsCache = (fingerprint, [])
            return []
        }
        let rows = items
            .compactMap(workspaceDoctorRow)
            .sorted(by: workspaceDoctorSort)
        workspaceDoctorRowsCache = (fingerprint, rows)
        return Array(rows.prefix(limit))
    }

    public func workspaceHookInstallRequest(for rows: [WorkspaceDoctorRow]) -> WorkspaceHookInstallRequest? {
        let workspaces = rows
            .filter { ["attention", "warning", "needs_review"].contains($0.severity) }
            .map(\.workspace)
            .filter { !$0.isEmpty }
        guard !workspaces.isEmpty else { return nil }
        let preview = "script/install_hooks_for_workspaces.sh " + workspaces.map { "--workspace \"\($0)\"" }.joined(separator: " ")
        let statusCounts = Dictionary(grouping: rows, by: \.coverage_status).mapValues(\.count)
        let riskSummary = [
            statusCounts["missing_hooks"].map { "missing=\($0)" },
            statusCounts["invalid_hooks"].map { "invalid=\($0)" },
            statusCounts["needs_trust"].map { "needs_trust=\($0)" },
            statusCounts["stale"].map { "stale=\($0)" },
            statusCounts["notLoaded"].map { "notLoaded=\($0)" }
        ].compactMap { $0 }.joined(separator: " · ")
        return WorkspaceHookInstallRequest(
            workspaces: workspaces,
            command_preview: preview,
            risk_summary: riskSummary.isEmpty ? "Selected workspaces need hooks attention." : riskSummary,
            post_install_next_action: "安装完成后重新打开对应 Codex workspace，并在 Codex UI 手动 Trust hooks。"
        )
    }

    public func runWorkspaceHookInstall(request: WorkspaceHookInstallRequest, confirmed: Bool) -> WorkspaceHookInstallResult {
        ensureLayout()
        guard confirmed, request.requires_user_confirmation else {
            return WorkspaceHookInstallResult(
                status: "blocked",
                message: "需要用户确认后才会安装 hooks"
            )
        }
        guard request.manual_trust_required else {
            return WorkspaceHookInstallResult(
                status: "blocked",
                message: "安装闭环必须保留 Codex UI 手动 Trust"
            )
        }
        let safeWorkspaces = request.workspaces.filter { !$0.isEmpty && !$0.contains("\n") }
        guard !safeWorkspaces.isEmpty else {
            return WorkspaceHookInstallResult(
                status: "failed",
                message: "没有可安装的 workspace"
            )
        }

        let scriptURL = projectRootURL().appendingPathComponent("script/install_hooks_for_workspaces.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path] + safeWorkspaces.flatMap { ["--workspace", $0] }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return WorkspaceHookInstallResult(
                status: "failed",
                failed_count: safeWorkspaces.count,
                message: "hooks 安装启动失败：\(error.localizedDescription)"
            )
        }

        if process.terminationStatus == 0 {
            runWorkspaceCoverageReport(openReport: false)
            return WorkspaceHookInstallResult(
                status: "success",
                installed_count: safeWorkspaces.count,
                message: "hooks 已安装；仍需在 Codex UI 手动 Trust"
            )
        }
        return WorkspaceHookInstallResult(
            status: "failed",
            failed_count: safeWorkspaces.count,
            message: "hooks 安装脚本失败，退出码 \(process.terminationStatus)"
        )
    }

    public func loadStatusReplayRecords(since: Date, limit: Int = 80) -> [StatusReplayRecord] {
        ensureLayout()
        guard limit > 0 else { return [] }
        let fingerprint = fileFingerprint(for: config.uiEventFlowURL)
        let records: [StatusReplayRecord]
        if let cached = statusReplayCache, cached.fingerprint == fingerprint {
            records = cached.records
        } else {
            guard let raw = readTextTail(from: config.uiEventFlowURL, maxBytes: TaskLightUIPerformanceBudget.statusReplayTailReadMaxBytes),
                  !raw.isEmpty else {
                statusReplayCache = (fingerprint, [])
                return []
            }
            records = raw
                .split(whereSeparator: \.isNewline)
                .suffix(800)
                .compactMap { line -> StatusReplayRecord? in
                    guard let data = String(line).data(using: .utf8),
                          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { return nil }
                    return statusReplayRecord(from: payload)
                }
                .sorted { $0.recorded_at > $1.recorded_at }
            statusReplayCache = (fingerprint, records)
        }
        return Array(records.lazy.filter {
            guard let recordedAt = TaskLightTaskRecord.parseTimestamp($0.recorded_at) else { return false }
            return recordedAt >= since
        }.prefix(limit))
    }

    public func clear(taskID: String) {
        runCLI(arguments: ["clear", "--task-id", taskID])
    }

    public func runWorkspaceCoverageReport(openReport: Bool = true) {
        ensureLayout()
        let scriptURL = projectRootURL().appendingPathComponent("script/check_codex_workspaces_coverage.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path] + (openReport ? ["--open-report"] : [])
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TASKLIGHT_STATE_DIR": config.stateDirectory.path,
            "TASKLIGHT_WORKSPACE_COVERAGE_DIR": config.workspaceCoverageDirectoryURL.path
        ]) { current, _ in current }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            let status = TaskLightWorkspaceCoverageRunStatus(
                status: "error",
                message: "巡检启动失败: \(error.localizedDescription)",
                updated_at: TaskLightTaskRecord.nowString(),
                latest_json_path: config.workspaceCoverageLatestJSONURL.path,
                report_path: config.workspaceCoverageLatestMarkdownURL.path
            )
            try? writeJSONAtomic(status, to: config.workspaceCoverageRunStatusURL)
        }
    }

    public func loadWorkspaceCoveragePresentation() -> TaskLightWorkspaceCoveragePresentation? {
        let status: TaskLightWorkspaceCoverageRunStatus? = try? readJSON(from: config.workspaceCoverageRunStatusURL)
        let report: TaskLightWorkspaceCoverageReport? = try? readJSON(from: config.workspaceCoverageLatestJSONURL)
        guard status != nil || report != nil else {
            return nil
        }
        let reportURL = config.workspaceCoverageLatestMarkdownURL
        if let status, status.status == "running" {
            return TaskLightWorkspaceCoveragePresentation(
                message: status.message ?? "正在检查 Codex 项目...",
                status: status.status,
                reportURL: reportURL
            )
        }
        if let status, status.status == "error" {
            return TaskLightWorkspaceCoveragePresentation(
                message: status.message ?? "巡检失败",
                status: status.status,
                isError: true,
                reportURL: reportURL
            )
        }
        if let summary = report?.summary {
            if (summary.preferred_installed_needs_trust ?? 0) > 0 {
                return TaskLightWorkspaceCoveragePresentation(
                    message: "常用项目 \(summary.preferred_installed_needs_trust ?? 0) 个需要 Trust",
                    status: report?.status ?? "needs_trust",
                    reportURL: reportURL
                )
            }
            if (summary.preferred_missing_hooks ?? 0) > 0 {
                return TaskLightWorkspaceCoveragePresentation(
                    message: "常用项目 \(summary.preferred_missing_hooks ?? 0) 个缺 hooks",
                    status: report?.status ?? "needs_hooks",
                    reportURL: reportURL
                )
            }
            if (summary.preferred_invalid_hooks ?? 0) > 0 {
                return TaskLightWorkspaceCoveragePresentation(
                    message: "常用项目 \(summary.preferred_invalid_hooks ?? 0) 个 hooks 异常",
                    status: report?.status ?? "needs_hooks",
                    isError: true,
                    reportURL: reportURL
                )
            }
            if (summary.installed_needs_trust ?? 0) > 0 {
                return TaskLightWorkspaceCoveragePresentation(
                    message: "发现 \(summary.installed_needs_trust ?? 0) 个项目需要 Trust",
                    status: report?.status ?? "needs_trust",
                    reportURL: reportURL
                )
            }
            if (summary.missing_hooks ?? 0) > 0 {
                return TaskLightWorkspaceCoveragePresentation(
                    message: "有 \(summary.missing_hooks ?? 0) 个项目缺 hooks",
                    status: report?.status ?? "needs_hooks",
                    reportURL: reportURL
                )
            }
            if (summary.invalid_hooks ?? 0) > 0 {
                return TaskLightWorkspaceCoveragePresentation(
                    message: "有 \(summary.invalid_hooks ?? 0) 个 hooks 配置异常",
                    status: report?.status ?? "needs_hooks",
                    isError: true,
                    reportURL: reportURL
                )
            }
            if (summary.workspace_count ?? 0) == 0 {
                return TaskLightWorkspaceCoveragePresentation(
                    message: "没有发现 Codex 项目",
                    status: report?.status ?? "empty",
                    reportURL: reportURL
                )
            }
            return TaskLightWorkspaceCoveragePresentation(
                message: "状态入口正常",
                status: report?.status ?? "ok",
                reportURL: reportURL
            )
        }
        if let status {
            return TaskLightWorkspaceCoveragePresentation(
                message: status.message ?? "点报告查看详情",
                status: status.status,
                isError: status.status == "error",
                reportURL: reportURL
            )
        }
        return nil
    }

    private struct ScanResult {
        var valid: [TaskLightTaskSummary]
        var invalid: [TaskLightTaskSummary]
    }

    private func quotaHistoryWindows(from quota: CodexQuotaUIState) -> [QuotaHistorySample] {
        let capturedAt = quota.captured_at ?? TaskLightTaskRecord.nowString()
        if let displayWindows = quota.display_windows, !displayWindows.isEmpty {
            return displayWindows.compactMap { window in
                guard let remaining = window.remaining_percent else { return nil }
                let windowID = [
                    window.bucket_id ?? quota.bucket_id ?? "quota",
                    window.window_duration_mins.map(String.init) ?? window.label ?? window.id ?? "window"
                ].joined(separator: ":")
                return QuotaHistorySample(
                    captured_at: capturedAt,
                    source: quota.source,
                    fresh: quota.fresh,
                    window_id: windowID,
                    label: window.label,
                    bucket_id: window.bucket_id ?? quota.bucket_id,
                    remaining_percent: remaining,
                    reset_label: window.reset_label,
                    reset_at: window.reset_at,
                    window_duration_mins: window.window_duration_mins
                )
            }
        }
        var samples: [QuotaHistorySample] = []
        if let short = quota.short_percent {
            samples.append(
                QuotaHistorySample(
                    captured_at: capturedAt,
                    source: quota.source,
                    fresh: quota.fresh,
                    window_id: [quota.short_bucket_id ?? quota.bucket_id ?? "quota", quota.short_label ?? "short"].joined(separator: ":"),
                    label: quota.short_label ?? "short",
                    bucket_id: quota.short_bucket_id ?? quota.bucket_id,
                    remaining_percent: short,
                    reset_label: quota.short_reset_label
                )
            )
        }
        if let long = quota.long_percent {
            samples.append(
                QuotaHistorySample(
                    captured_at: capturedAt,
                    source: quota.source,
                    fresh: quota.fresh,
                    window_id: [quota.long_bucket_id ?? quota.bucket_id ?? "quota", quota.long_label ?? "long"].joined(separator: ":"),
                    label: quota.long_label ?? "long",
                    bucket_id: quota.long_bucket_id ?? quota.bucket_id,
                    remaining_percent: long,
                    reset_label: quota.long_reset_label
                )
            )
        }
        if samples.isEmpty, let effective = quota.effective_remaining_percent {
            samples.append(
                QuotaHistorySample(
                    captured_at: capturedAt,
                    source: quota.source,
                    fresh: quota.fresh,
                    window_id: quota.bucket_id ?? "quota:effective",
                    label: "effective",
                    bucket_id: quota.bucket_id,
                    remaining_percent: effective
                )
            )
        }
        return samples
    }

    private func appendQuotaHistorySample(_ sample: QuotaHistorySample, capturedAt: String, source: String?, fresh: Bool) {
        var normalized = sample
        normalized.captured_at = capturedAt
        normalized.source = source
        normalized.fresh = fresh
        guard let data = try? encoder.encode(normalized),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        let line = encoded + "\n"
        let fd = open(config.quotaHistoryURL.path, O_WRONLY | O_APPEND | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withCString { pointer in
            write(fd, pointer, strlen(pointer))
        }
        fsync(fd)
    }

    private func pruneQuotaHistoryIfNeeded(maxSamples: Int = 2000, maxBytes: UInt64 = 512_000) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: config.quotaHistoryURL.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value > maxBytes,
              let raw = try? String(contentsOf: config.quotaHistoryURL, encoding: .utf8),
              !raw.isEmpty else {
            return
        }
        let retained = raw
            .split(whereSeparator: \.isNewline)
            .suffix(maxSamples)
            .joined(separator: "\n")
        let output = retained.isEmpty ? "" : retained + "\n"
        try? output.write(to: config.quotaHistoryURL, atomically: true, encoding: .utf8)
    }

    private func workspaceDoctorRow(from item: [String: Any]) -> WorkspaceDoctorRow? {
        guard let workspace = item["workspace"] as? String, !workspace.isEmpty else { return nil }
        let status = item["coverage_status"] as? String ?? "unknown"
        return WorkspaceDoctorRow(
            workspace: workspace,
            name: item["name"] as? String ?? URL(fileURLWithPath: workspace).lastPathComponent,
            group: item["workspace_group"] as? String ?? "unknown",
            coverage_status: status,
            hook_status: item["hook_status"] as? String,
            hook_detail: item["hook_detail"] as? String,
            hook_visibility: item["hook_visibility"] as? String,
            reason: item["reason"] as? String ?? "暂无诊断",
            recommended_action: item["recommended_action"] as? String ?? "run coverage check",
            severity: workspaceDoctorSeverity(for: status),
            preferred: item["preferred"] as? Bool ?? false
        )
    }

    private func workspaceDoctorSeverity(for status: String) -> String {
        switch status {
        case "invalid_hooks":
            return "attention"
        case "missing_hooks":
            return "warning"
        case "installed_needs_trust", "not_loaded", "diagnostic_only":
            return "needs_review"
        case "trusted":
            return "ok"
        default:
            return "unknown"
        }
    }

    private func workspaceDoctorSort(_ lhs: WorkspaceDoctorRow, _ rhs: WorkspaceDoctorRow) -> Bool {
        let rank: [String: Int] = [
            "attention": 0,
            "warning": 1,
            "needs_review": 2,
            "unknown": 3,
            "ok": 4
        ]
        let lhsRank = rank[lhs.severity] ?? 5
        let rhsRank = rank[rhs.severity] ?? 5
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.preferred != rhs.preferred { return lhs.preferred && !rhs.preferred }
        return lhs.workspace < rhs.workspace
    }

    private func statusReplayRecord(from payload: [String: Any]) -> StatusReplayRecord? {
        guard let recordedAt = payload["recorded_at"] as? String else { return nil }
        let previous = payload["previous_global_status"] as? String ?? "unknown"
        let current = payload["global_status"] as? String ?? "unknown"
        let lamp = payload["lamp_status"] as? String ?? current
        let counts = payload["counts"] as? [String: Any] ?? [:]
        let markers = statusReplayMarkers(from: payload)
        let reason = (payload["projector_reason"] as? [String])?.joined(separator: ",") ?? "none"
        let signal = payload["current_thread_signal_status"] as? String ?? "unknown"
        let decision = payload["current_thread_fusion_decision"] as? String ?? "unknown"
        let id = [
            recordedAt,
            previous,
            current,
            lamp,
            String(describing: counts["running"] ?? 0),
            String(describing: counts["observed_active"] ?? 0)
        ].joined(separator: "|")
        return StatusReplayRecord(
            id: id,
            recorded_at: recordedAt,
            from_status: previous,
            to_status: current,
            lamp_status: lamp,
            evidence: "reason \(reason) · signal \(signal) · decision \(decision)",
            markers: markers,
            counts_summary: "R \(counts["running"] ?? 0) · P \(counts["pending_verify_count"] ?? 0) · B \(counts["blocked"] ?? 0) · O \(counts["observed_active"] ?? 0)",
            writer_status: payload["writer_status"] as? String ?? "unknown",
            hook_bridge_status: payload["hook_bridge_status"] as? String ?? "unknown"
        )
    }

    private func statusReplayMarkers(from payload: [String: Any]) -> [String] {
        var markers: [String] = []
        let writer = payload["writer_status"] as? String ?? ""
        if writer == "old_writer" {
            markers.append("old_writer")
        }
        if writer == "multiple_writers" {
            markers.append("multiple_projector")
        }
        let fallback = payload["fallback_reason"] as? String ?? ""
        if !fallback.isEmpty, fallback != "none" {
            markers.append("fallback_reason")
        }
        let evidence = [
            payload["current_thread_signal_status"] as? String,
            payload["current_thread_fusion_decision"] as? String,
            (payload["projector_reason"] as? [String])?.joined(separator: ","),
            (payload["reference_task"] as? [String: Any])?["state_cause"] as? String
        ].compactMap { $0 }.joined(separator: " ")
        if evidence.contains("process_only_not_authoritative") || evidence.contains("process_observer") {
            markers.append("process_only")
        }
        if evidence.contains("runtime_score_below_threshold") {
            markers.append("runtime_score_below_threshold")
        }
        if evidence.contains("stale_launch_agent") || evidence.contains("launch_agent") && evidence.contains("stale") {
            markers.append("stale_launch_agent")
        }
        return Array(Set(markers)).sorted()
    }

    private struct StateReadResult {
        var state: TaskLightAggregateState?
        var health: TaskLightSourceHealth
    }

    private struct QuotaFallbackState: Decodable {
        var source: String?
        var fresh: Bool?
        var quota_status: String?
        var effective_remaining_percent: Int?
        var captured_at: String?
        var recommendation: String?
        var warnings: [String]?
        var display_windows: [QuotaFallbackWindow]?
        var raw_windows: [QuotaFallbackWindow]?
        var windows: [QuotaFallbackWindow]?
        var manual_resets: QuotaFallbackResets?
    }

    private struct QuotaFallbackWindow: Decodable {
        var id: String?
        var bucket_id: String?
        var label: String?
        var remaining_percent: Int?
        var used_percent: Int?
        var reset_label: String?
        var reset_at: String?
        var window_duration_mins: Int?
        var health: String?
        var selection_reason: String?
    }

    private struct QuotaFallbackResets: Decodable {
        var available_count: Int?
        var total_count: Int?
        var used_count: Int?
        var expired_count: Int?
        var next_expiry: String?
        var credits: [CodexQuotaResetCreditUIState]?
    }

    private func isUIStateFresh(_ uiState: TaskLightUIState) -> Bool {
        guard uiState.source == "state_projector" else {
            return false
        }
        guard ["M3.7", "M3.8"].contains(uiState.projector_version) else {
            return false
        }
        return Self.isProjectorTimestampFresh(
            uiState.projector_generated_at,
            maxAgeSeconds: config.projectorMaxAgeSeconds
        )
    }

    public static func isProjectorTimestampFresh(
        _ timestamp: String,
        maxAgeSeconds: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard maxAgeSeconds > 0,
              let generatedAt = TaskLightTaskRecord.parseTimestamp(timestamp) else {
            return false
        }
        let age = now.timeIntervalSince(generatedAt)
        return age >= -1 && age <= maxAgeSeconds
    }

    private func projectRootURL() -> URL {
        if let raw = ProcessInfo.processInfo.environment["TASKLIGHT_PROJECT_ROOT"], !raw.isEmpty {
            return URL(fileURLWithPath: raw)
        }
        let knownProjectRoot = URL(fileURLWithPath: "/Users/macmini-simon66/Documents/Codex状态桌面栏提醒")
        if FileManager.default.fileExists(atPath: knownProjectRoot.appendingPathComponent("script/check_codex_workspaces_coverage.sh").path) {
            return knownProjectRoot
        }
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func fallbackUIState(from dashboard: TaskLightAggregateState, reason: String) -> TaskLightUIState {
        let quota = loadQuotaFallback()
        let observedActive = dashboard.observations_state?.observations.filter {
            $0.isActive && $0.managed_task_id == nil && $0.confidence >= 0.70
        }.count ?? 0
        let counts = TaskLightUICounts(
            blocked: dashboard.counts.blocked,
            stale: dashboard.counts.stale,
            running: dashboard.counts.running,
            queued: dashboard.counts.queued,
            pending_verify_count: dashboard.counts.pending_verify_count,
            done_verified_visible: dashboard.counts.done_verified,
            observed_active: observedActive,
            appserver_active: 0,
            process_observed: observedActive,
            managed_active: dashboard.counts.blocked + dashboard.counts.stale + dashboard.counts.running + dashboard.counts.queued + dashboard.counts.done_unverified
        )
        let global: String
        let title: String
        if counts.blocked > 0 {
            global = TaskLightStatus.blocked.rawValue
            title = "BLOCKED"
        } else if counts.running + counts.queued > 0 {
            global = TaskLightStatus.running.rawValue
            title = "RUNNING"
        } else if counts.pending_verify_count > 0 {
            global = "pending"
            title = "PENDING"
        } else if counts.done_verified_visible > 0 {
            global = TaskLightStatus.done_verified.rawValue
            title = "DONE"
        } else {
            global = TaskLightStatus.idle.rawValue
            title = "IDLE"
        }
        let tasks = dashboard.tasks.map { summary in
            TaskLightUITask(
                task_id: summary.task_id,
                short_task_id: summary.short_task_id,
                title: summary.title,
                source: "swift_fallback",
                raw_status: summary.raw_status,
                effective_status: summary.effective_status,
                display_scope: fallbackDisplayScope(for: summary.effective_status),
                state_cause: "swift_fallback:\(summary.effective_status)",
                fresh: summary.effective_status == TaskLightStatus.running.rawValue || summary.effective_status == TaskLightStatus.queued.rawValue,
                phase: summary.phase,
                progress: summary.progress,
                reason: summary.reason,
                message: summary.message,
                summary: summary.summary,
                started_at: summary.started_at,
                updated_at: summary.updated_at,
                done_at: summary.done_at,
                verified_at: summary.verified_at,
                file_path: summary.file_path,
                confidence: 0.50
            )
        }
        let observations = (dashboard.observations_state?.observations ?? []).map { record in
            TaskLightUIObservation(
                observation_id: record.observation_id,
                title: record.title,
                status: record.status,
                confidence: record.confidence,
                display_scope: record.isActive && record.confidence >= 0.70 ? "observed_only" : "history",
                fresh: record.isActive,
                pid: record.pid,
                command_short: record.command_short,
                cwd: record.cwd,
                last_seen_at: record.last_seen_at
            )
        }
        return TaskLightUIState(
            source: "swift_fallback",
            global_status: global,
            lamp_status: global,
            global_display_title: title,
            state_confidence: 0.50,
            counts: counts,
            tasks: tasks,
            observations: observations,
            quota: quota,
            diagnostics: TaskLightUIDiagnostics(
                writer_status: "fallback",
                hook_bridge_status: "unknown",
                signal_bus_status: "fallback",
                signal_bus_record_count: nil,
                signal_bus_source_counts: nil,
                active_turn_bindings: nil,
                latest_hook_signal_age_sec: nil,
                latest_hook_bridge_signal_age_sec: nil,
                latest_process_observer_signal_age_sec: nil,
                latest_private_probe_signal_age_sec: nil,
                latest_private_probe_status: nil,
                latest_private_probe_quality: nil,
                latest_private_probe_confidence: nil,
                current_thread_binding_status: nil,
                current_thread_binding_fresh: nil,
                latest_current_thread_binding_age_sec: nil,
                latest_current_thread_signal_age_sec: nil,
                current_thread_task_identity: nil,
                current_thread_signal_source: nil,
                current_thread_signal_quality: nil,
                current_thread_signal_confidence: nil,
                current_thread_signal_status: nil,
                current_thread_fusion_decision: nil,
                latest_turn_binding_status: nil,
                latest_turn_binding_age_sec: nil,
                latest_turn_binding_turn_id: nil,
                latest_turn_binding_task_id: nil,
                latest_turn_signal_event: nil,
                latest_bridge_decision: nil,
                state_dir: config.stateDirectory.path,
                projector_reason: ["fallback"],
                runtime_candidate_count: 0,
                top_runtime_candidates: [],
                appserver_active_count: 0,
                process_observed_count: observedActive,
                fallback_reason: reason,
                quota_status: quota?.status,
                quota_fresh: quota?.fresh,
                quota_source: quota?.source,
                quota_state_path: config.stateDirectory.appendingPathComponent("quota_state.json").path,
                quota_warning_count: nil
            )
        )
    }

    private func loadQuotaFallback() -> CodexQuotaUIState? {
        let url = config.stateDirectory.appendingPathComponent("quota_state.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let raw: QuotaFallbackState = try? readJSON(from: url) else {
            return nil
        }
        let sourceWindows = raw.display_windows ?? selectQuotaFallbackWindows(raw.windows ?? [])
        let windows = selectQuotaFallbackWindows(sourceWindows)
        let short = windows.first
        let long = windows.count > 1 ? windows.last : nil
        return CodexQuotaUIState(
            source: raw.source,
            fresh: raw.fresh ?? false,
            status: raw.quota_status ?? "unknown",
            effective_remaining_percent: raw.effective_remaining_percent,
            display_windows: windows.map { window in
                CodexQuotaWindowUIState(
                    id: window.id,
                    label: window.label,
                    bucket_id: window.bucket_id,
                    remaining_percent: window.remaining_percent,
                    used_percent: window.used_percent,
                    reset_label: window.reset_label,
                    reset_at: window.reset_at,
                    window_duration_mins: window.window_duration_mins,
                    health: window.health,
                    selection_reason: window.selection_reason
                )
            },
            raw_window_count: raw.raw_windows?.count ?? raw.windows?.count,
            captured_age_sec: nil,
            probe_mode: nil,
            bucket_id: short?.bucket_id,
            warnings: raw.warnings,
            short_percent: short?.remaining_percent,
            short_label: short?.label,
            short_reset_label: short?.reset_label,
            short_bucket_id: short?.bucket_id,
            long_percent: long?.remaining_percent,
            long_label: long?.label,
            long_reset_label: long?.reset_label,
            long_bucket_id: long?.bucket_id,
            manual_resets_available: raw.manual_resets?.available_count,
            manual_resets_total_count: raw.manual_resets?.total_count,
            manual_resets_used_count: raw.manual_resets?.used_count,
            manual_resets_expired_count: raw.manual_resets?.expired_count,
            manual_resets_next_expiry: raw.manual_resets?.next_expiry,
            manual_reset_credits: raw.manual_resets?.credits,
            captured_at: raw.captured_at,
            recommendation: raw.recommendation
        )
    }

    private func selectQuotaFallbackWindows(_ windows: [QuotaFallbackWindow]) -> [QuotaFallbackWindow] {
        let grouped = Dictionary(grouping: windows.filter { $0.remaining_percent != nil }) { window in
            window.window_duration_mins.map(String.init) ?? window.label ?? "unknown"
        }
        return grouped.values
            .compactMap { candidates in candidates.sorted(by: quotaFallbackWindowSort).first }
            .sorted {
                ($0.window_duration_mins ?? Int.max) < ($1.window_duration_mins ?? Int.max)
            }
    }

    private func quotaFallbackWindowSort(_ lhs: QuotaFallbackWindow, _ rhs: QuotaFallbackWindow) -> Bool {
        quotaFallbackPriority(lhs) < quotaFallbackPriority(rhs)
    }

    private func quotaFallbackPriority(_ window: QuotaFallbackWindow) -> (Int, Int) {
        let bucketID = (window.bucket_id ?? "").lowercased()
        if bucketID == "codex" {
            return (0, 0)
        }
        if bucketID.hasPrefix("codex_") {
            return (2, window.remaining_percent ?? 0)
        }
        if bucketID.contains("codex") {
            return (1, window.remaining_percent ?? 0)
        }
        return (3, window.remaining_percent ?? 0)
    }

    private func fallbackDisplayScope(for status: String) -> String {
        switch status {
        case TaskLightStatus.blocked.rawValue:
            return "open_blocker"
        case TaskLightStatus.stale.rawValue:
            return "stale_blocker"
        case TaskLightStatus.running.rawValue, TaskLightStatus.queued.rawValue:
            return "active_execution"
        case TaskLightStatus.done_unverified.rawValue:
            return "pending_verify"
        case TaskLightStatus.done_verified.rawValue:
            return "recent_done"
        case TaskLightStatus.invalid_json.rawValue:
            return "invalid"
        default:
            return "history"
        }
    }

    private func readStateSnapshot() -> StateReadResult {
        guard FileManager.default.fileExists(atPath: config.stateURL.path) else {
            return StateReadResult(state: nil, health: .reconstructed)
        }
        do {
            let state: TaskLightAggregateState = try readJSON(from: config.stateURL)
            return StateReadResult(state: state, health: .healthy)
        } catch {
            return StateReadResult(state: nil, health: .corrupt_state)
        }
    }

    private func loadLegacyCurrentRecord() -> TaskLightTaskRecord? {
        guard FileManager.default.fileExists(atPath: config.currentURL.path) else {
            return nil
        }
        guard let record: TaskLightTaskRecord = try? readJSON(from: config.currentURL) else {
            return nil
        }
        if record.task_id.isEmpty && (record.status == "idle" || record.status == TaskLightStatus.idle.rawValue) {
            return nil
        }
        return record
    }

    private struct ObservationScanResult {
        var valid: [TaskLightObservationRecord]
        var invalidCount: Int
    }

    private func loadObservationsState() -> TaskLightObservationsState {
        let stateResult = readObservationsSnapshot()
        if let state = stateResult.state {
            return markObservationSourceHealth(state, sourceHealth: stateResult.health)
        }
        let scan = scanObservationFiles()
        if !scan.valid.isEmpty || scan.invalidCount > 0 {
            let built = buildObservationAggregate(records: scan.valid, sourceHealth: stateResult.health)
            return built
        }
        return emptyObservationsState(sourceHealth: stateResult.health)
    }

    private struct ObservationStateReadResult {
        var state: TaskLightObservationsState?
        var health: TaskLightSourceHealth
    }

    private func readObservationsSnapshot() -> ObservationStateReadResult {
        guard FileManager.default.fileExists(atPath: config.observationsStateURL.path) else {
            return ObservationStateReadResult(state: nil, health: .reconstructed)
        }
        do {
            let state: TaskLightObservationsState = try readJSON(from: config.observationsStateURL)
            return ObservationStateReadResult(state: state, health: .healthy)
        } catch {
            return ObservationStateReadResult(state: nil, health: .corrupt_state)
        }
    }

    private func scanObservationFiles() -> ObservationScanResult {
        guard FileManager.default.fileExists(atPath: config.observationsDirectoryURL.path) else {
            return ObservationScanResult(valid: [], invalidCount: 0)
        }
        var valid: [TaskLightObservationRecord] = []
        var invalidCount = 0
        let urls = (try? FileManager.default.contentsOfDirectory(at: config.observationsDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "json" {
            do {
                let record: TaskLightObservationRecord = try readJSON(from: url)
                if record.observation_id.isEmpty {
                    invalidCount += 1
                    continue
                }
                valid.append(record)
            } catch {
                invalidCount += 1
            }
        }
        return ObservationScanResult(valid: valid, invalidCount: invalidCount)
    }

    private func emptyObservationsState(sourceHealth: TaskLightSourceHealth) -> TaskLightObservationsState {
        TaskLightObservationsState(
            source_health: sourceHealth.rawValue,
            lamp_status: sourceHealth == .corrupt_state ? "stale" : "idle",
            global_status: "idle",
            counts: TaskLightObservationCounts(),
            observations: []
        )
    }

    private func markObservationSourceHealth(_ state: TaskLightObservationsState, sourceHealth: TaskLightSourceHealth) -> TaskLightObservationsState {
        var copy = state
        copy.source_health = sourceHealth.rawValue
        if sourceHealth == .corrupt_state {
            copy.lamp_status = "stale"
        }
        return copy
    }

    private func buildObservationAggregate(records: [TaskLightObservationRecord], sourceHealth: TaskLightSourceHealth) -> TaskLightObservationsState {
        let active = records.filter { $0.isActive && $0.managed_task_id == nil }.sorted(by: observationSort)
        var counts = TaskLightObservationCounts()
        var lamp = "idle"
        for record in records {
            counts.total += 1
            if record.managed_task_id != nil {
                counts.linked_managed += 1
                continue
            }
            switch TaskLightObservationStatus(rawValue: record.status) ?? .observed_quiet {
            case .observed_active:
                counts.active += 1
                lamp = lamp == "idle" ? "running" : lamp
            case .observed_quiet:
                counts.quiet += 1
                counts.active += 1
                lamp = lamp == "idle" ? "running" : lamp
            case .observed_attention:
                counts.attention += 1
                counts.active += 1
                if record.confidence >= 0.75 {
                    lamp = "blocked"
                } else if lamp == "idle" {
                    lamp = "running"
                }
            case .observed_disappeared:
                counts.disappeared += 1
            }
        }
        let globalStatus = lamp == "idle" ? "idle" : lamp
        let lampStatus = sourceHealth == .corrupt_state ? "stale" : globalStatus
        return TaskLightObservationsState(
            source_health: sourceHealth.rawValue,
            lamp_status: lampStatus,
            global_status: globalStatus,
            counts: counts,
            observations: active
        )
    }

    private func observationSort(_ lhs: TaskLightObservationRecord, _ rhs: TaskLightObservationRecord) -> Bool {
        let lhsRank = observationRank(lhs.status)
        let rhsRank = observationRank(rhs.status)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        if lhs.last_seen_at != rhs.last_seen_at {
            return (lhs.last_seen_at ?? lhs.detected_at ?? "") > (rhs.last_seen_at ?? rhs.detected_at ?? "")
        }
        return lhs.observation_id < rhs.observation_id
    }

    private func observationRank(_ status: String) -> Int {
        switch status {
        case TaskLightObservationStatus.observed_attention.rawValue:
            return 0
        case TaskLightObservationStatus.observed_active.rawValue:
            return 1
        case TaskLightObservationStatus.observed_quiet.rawValue:
            return 2
        case TaskLightObservationStatus.observed_disappeared.rawValue:
            return 3
        default:
            return 4
        }
    }

    private func scanTaskFiles() -> ScanResult {
        guard FileManager.default.fileExists(atPath: config.tasksDirectoryURL.path) else {
            return ScanResult(valid: [], invalid: [])
        }
        var valid: [TaskLightTaskSummary] = []
        var invalid: [TaskLightTaskSummary] = []
        let urls = (try? FileManager.default.contentsOfDirectory(at: config.tasksDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "json" {
            do {
                let record: TaskLightTaskRecord = try readJSON(from: url)
                if record.task_id.isEmpty {
                    invalid.append(invalidSummary(taskID: url.deletingPathExtension().lastPathComponent, filePath: url, error: "missing task_id"))
                    continue
                }
                valid.append(summary(from: record, filePath: url))
            } catch {
                invalid.append(invalidSummary(taskID: url.deletingPathExtension().lastPathComponent, filePath: url, error: error.localizedDescription))
            }
        }
        return ScanResult(valid: valid, invalid: invalid)
    }

    private func summary(from record: TaskLightTaskRecord, filePath: URL) -> TaskLightTaskSummary {
        let live = record.liveStatus(ttlSeconds: config.ttlSeconds, verificationTTLSeconds: config.verificationTTLSeconds)
        let shortID = record.shortTaskID
        let lastError: String? = {
            if live == .stale {
                return record.status == TaskLightStatus.done_unverified.rawValue ? "acceptance gate expired" : "heartbeat expired"
            }
            return record.last_error
        }()
        return TaskLightTaskSummary(
            schema_version: record.schema_version,
            task_id: record.task_id,
            short_task_id: shortID,
            title: record.title,
            slug: record.slug,
            status: live.rawValue,
            raw_status: record.status,
            effective_status: live.rawValue,
            phase: record.phase,
            progress: record.progress,
            reason: record.reason,
            message: record.message,
            evidence: record.evidence,
            summary: record.summary,
            created_at: record.created_at,
            started_at: record.started_at ?? record.created_at,
            updated_at: record.updated_at,
            heartbeat_at: record.heartbeat_at,
            done_at: record.done_at,
            verified_at: record.verified_at,
            cancelled_at: record.cancelled_at,
            ttl_seconds: record.ttl_seconds,
            last_error: lastError,
            file_path: filePath.path,
            alert_fingerprint: record.alertFingerprint(effectiveStatus: live),
            sound_type: (live == .blocked || live == .stale) ? "blocked" : (live == .done_verified ? "done_verified" : nil),
            is_invalid_json: false,
            invalid_json_error: nil
        )
    }

    private func invalidSummary(taskID: String, filePath: URL, error: String) -> TaskLightTaskSummary {
        TaskLightTaskSummary(
            schema_version: 3,
            task_id: taskID,
            short_task_id: taskID.components(separatedBy: "-").last ?? taskID,
            title: taskID,
            slug: taskID,
            status: TaskLightStatus.invalid_json.rawValue,
            raw_status: TaskLightStatus.invalid_json.rawValue,
            effective_status: TaskLightStatus.invalid_json.rawValue,
            phase: nil,
            progress: nil,
            reason: nil,
            message: nil,
            evidence: nil,
            summary: nil,
            created_at: TaskLightTaskRecord.nowString(),
            started_at: TaskLightTaskRecord.nowString(),
            updated_at: TaskLightTaskRecord.nowString(),
            heartbeat_at: nil,
            done_at: nil,
            verified_at: nil,
            cancelled_at: nil,
            ttl_seconds: Int(config.ttlSeconds),
            last_error: error,
            file_path: filePath.path,
            alert_fingerprint: nil,
            sound_type: nil,
            is_invalid_json: true,
            invalid_json_error: error
        )
    }

    private func emptyState(sourceHealth: TaskLightSourceHealth) -> TaskLightAggregateState {
        var counts = TaskLightCounts()
        counts.gray = 1
        return TaskLightAggregateState(
            source_health: sourceHealth.rawValue,
            lamp_status: sourceHealth == .corrupt_state ? "stale" : "idle",
            global_status: "idle",
            counts: counts,
            tasks: [],
            invalid_tasks: []
        )
    }

    private func markSourceHealth(_ state: TaskLightAggregateState, sourceHealth: TaskLightSourceHealth) -> TaskLightAggregateState {
        var copy = state
        copy.source_health = sourceHealth.rawValue
        if sourceHealth == .corrupt_state {
            copy.lamp_status = "stale"
        }
        return copy
    }

    private func buildAggregate(valid: [TaskLightTaskSummary], invalid: [TaskLightTaskSummary], sourceHealth: TaskLightSourceHealth) -> TaskLightAggregateState {
        let sortedValid = valid.sorted(by: taskSort)
        let sortedInvalid = invalid.sorted(by: { lhs, rhs in
            (lhs.title, lhs.task_id) < (rhs.title, rhs.task_id)
        })
        var counts = TaskLightCounts()
        var latestVerified: String?
        var latestEvent: String?
        var currentTaskID: String?

        for task in sortedValid {
            counts.total += 1
            switch TaskLightStatus(rawValue: task.effective_status) ?? .idle {
            case .blocked:
                counts.blocked += 1
                counts.red += 1
            case .stale:
                counts.stale += 1
                counts.red += 1
            case .running:
                counts.running += 1
                counts.blue += 1
            case .queued:
                counts.queued += 1
                counts.blue += 1
            case .done_verified:
                counts.done_verified += 1
                counts.green += 1
                if let verified = task.verified_at, latestVerified == nil || verified > (latestVerified ?? "") {
                    latestVerified = verified
                }
            case .done_unverified:
                counts.done_unverified += 1
                counts.pending_verify_count += 1
                counts.blue += 1
            case .cancelled:
                counts.cancelled += 1
            case .idle, .invalid_json:
                break
            }
            if let updated = task.updated_at, latestEvent == nil || updated > (latestEvent ?? "") {
                latestEvent = updated
                currentTaskID = task.task_id
            }
        }
        counts.invalid_json = sortedInvalid.count
        counts.total += sortedInvalid.count
        counts.active = counts.running + counts.queued + counts.done_unverified
        if counts.red == 0, counts.blue == 0, counts.green == 0 {
            counts.gray = 1
        }

        let global: String
        if counts.red > 0 {
            global = TaskLightStatus.blocked.rawValue
        } else if counts.blue > 0 {
            global = TaskLightStatus.running.rawValue
        } else if counts.green > 0 && counts.active == 0 && counts.blocked == 0 && counts.stale == 0 {
            global = TaskLightStatus.done_verified.rawValue
        } else {
            global = TaskLightStatus.idle.rawValue
        }

        let lamp = sourceHealth == .corrupt_state ? TaskLightStatus.stale.rawValue : global
        return TaskLightAggregateState(
            source_health: sourceHealth.rawValue,
            lamp_status: lamp,
            global_status: global,
            generated_at: TaskLightTaskRecord.nowString(),
            updated_at: TaskLightTaskRecord.nowString(),
            current_task_id: currentTaskID,
            last_verified_at: latestVerified,
            last_event_at: latestEvent,
            counts: counts,
            tasks: sortedValid,
            invalid_tasks: sortedInvalid
        )
    }

    private func refreshLiveState(_ state: TaskLightAggregateState) -> TaskLightAggregateState {
        let sourceHealth = TaskLightSourceHealth(rawValue: state.source_health) ?? .healthy
        var refreshedValid: [TaskLightTaskSummary] = []
        let refreshedInvalid: [TaskLightTaskSummary] = state.invalid_tasks
        var counts = TaskLightCounts()
        var latestVerified = state.last_verified_at
        var latestEvent = state.last_event_at
        var currentTaskID = state.current_task_id

        for task in state.tasks {
            let live = task.liveStatus(ttlSeconds: config.ttlSeconds, verificationTTLSeconds: config.verificationTTLSeconds)
            var copy = task
            copy.status = live.rawValue
            copy.effective_status = live.rawValue
            if live == .stale {
                copy.last_error = task.raw_status == TaskLightStatus.done_unverified.rawValue ? "acceptance gate expired" : "heartbeat expired"
                copy.sound_type = "blocked"
            }
            refreshedValid.append(copy)

            counts.total += 1
            switch live {
            case .blocked:
                counts.blocked += 1
                counts.red += 1
            case .stale:
                counts.stale += 1
                counts.red += 1
            case .running:
                counts.running += 1
                counts.blue += 1
            case .queued:
                counts.queued += 1
                counts.blue += 1
            case .done_verified:
                counts.done_verified += 1
                counts.green += 1
                if let verified = copy.verified_at, latestVerified == nil || verified > (latestVerified ?? "") {
                    latestVerified = verified
                }
            case .done_unverified:
                counts.done_unverified += 1
                counts.pending_verify_count += 1
                counts.blue += 1
            case .cancelled:
                counts.cancelled += 1
            case .idle, .invalid_json:
                break
            }
            if let updated = copy.updated_at, latestEvent == nil || updated > (latestEvent ?? "") {
                latestEvent = updated
                currentTaskID = copy.task_id
            }
        }

        counts.invalid_json = refreshedInvalid.count
        counts.total += refreshedInvalid.count
        counts.active = counts.running + counts.queued + counts.done_unverified
        if counts.red == 0, counts.blue == 0, counts.green == 0 {
            counts.gray = 1
        }

        let global: String
        if counts.red > 0 {
            global = TaskLightStatus.blocked.rawValue
        } else if counts.blue > 0 {
            global = TaskLightStatus.running.rawValue
        } else if counts.green > 0 && counts.active == 0 && counts.blocked == 0 && counts.stale == 0 {
            global = TaskLightStatus.done_verified.rawValue
        } else {
            global = TaskLightStatus.idle.rawValue
        }
        let lamp = sourceHealth == .corrupt_state ? TaskLightStatus.stale.rawValue : global

        return TaskLightAggregateState(
            source_health: sourceHealth.rawValue,
            lamp_status: lamp,
            global_status: global,
            generated_at: state.generated_at,
            updated_at: TaskLightTaskRecord.nowString(),
            current_task_id: currentTaskID,
            last_verified_at: latestVerified,
            last_event_at: latestEvent,
            counts: counts,
            tasks: refreshedValid.sorted(by: taskSort),
            invalid_tasks: refreshedInvalid.sorted(by: { lhs, rhs in (lhs.title, lhs.task_id) < (rhs.title, rhs.task_id) })
        )
    }

    private func taskSort(_ lhs: TaskLightTaskSummary, _ rhs: TaskLightTaskSummary) -> Bool {
        let lhsRank = sortRank(lhs.effective_status)
        let rhsRank = sortRank(rhs.effective_status)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.updated_at != rhs.updated_at {
            return (lhs.updated_at ?? "") > (rhs.updated_at ?? "")
        }
        return lhs.task_id < rhs.task_id
    }

    private func sortRank(_ status: String) -> Int {
        switch status {
        case TaskLightStatus.blocked.rawValue:
            return 0
        case TaskLightStatus.stale.rawValue:
            return 1
        case TaskLightStatus.running.rawValue:
            return 2
        case TaskLightStatus.queued.rawValue:
            return 3
        case TaskLightStatus.done_verified.rawValue:
            return 4
        case TaskLightStatus.done_unverified.rawValue:
            return 5
        case TaskLightStatus.cancelled.rawValue:
            return 6
        case TaskLightStatus.invalid_json.rawValue:
            return 7
        default:
            return 8
        }
    }

    private func fileFingerprint(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "missing"
        }
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return "\(modifiedAt):\(size)"
    }

    private func readTextTail(from url: URL, maxBytes: Int) -> String? {
        guard maxBytes > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return "" }
        let bytesToRead = min(UInt64(maxBytes), fileSize)
        let startOffset = fileSize - bytesToRead
        do {
            try handle.seek(toOffset: startOffset)
            guard let data = try handle.readToEnd(), var text = String(data: data, encoding: .utf8) else { return nil }
            if startOffset > 0, let firstNewline = text.firstIndex(where: \.isNewline) {
                text = String(text[text.index(after: firstNewline)...])
            }
            return text
        } catch {
            return nil
        }
    }

    private func readJSON<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func writeJSONAtomic<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func runCLI(arguments: [String]) {
        let rootURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cliURL = rootURL.appendingPathComponent("cli/tasklight.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [cliURL.path] + arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("tasklight CLI failed: \(error.localizedDescription)")
        }
    }
}
