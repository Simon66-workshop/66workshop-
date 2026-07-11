import Foundation

/// A bounded, immutable read-model payload shared by every AppKit and SwiftUI surface.
/// It intentionally contains presentation data only; it never recomputes the task lamp.
public struct TaskLightRenderSnapshot: Equatable {
    public var fingerprint: String
    public var loadedAt: Date
    public var loadMilliseconds: Double
    public var cacheHit: Bool
    public var uiState: TaskLightUIState
    public var recentEvents: [TaskLightEventRecord]
    public var statusReplay: [StatusReplayRecord]
    public var workspaceDoctorRows: [WorkspaceDoctorRow]
    public var quotaHistory: [QuotaHistorySample]
    public var externalProviders: [UsageProviderSnapshot]

    public init(
        fingerprint: String,
        loadedAt: Date = Date(),
        loadMilliseconds: Double,
        cacheHit: Bool = false,
        uiState: TaskLightUIState,
        recentEvents: [TaskLightEventRecord],
        statusReplay: [StatusReplayRecord],
        workspaceDoctorRows: [WorkspaceDoctorRow],
        quotaHistory: [QuotaHistorySample],
        externalProviders: [UsageProviderSnapshot]
    ) {
        self.fingerprint = fingerprint
        self.loadedAt = loadedAt
        self.loadMilliseconds = loadMilliseconds
        self.cacheHit = cacheHit
        self.uiState = uiState
        self.recentEvents = recentEvents
        self.statusReplay = statusReplay
        self.workspaceDoctorRows = workspaceDoctorRows
        self.quotaHistory = quotaHistory
        self.externalProviders = externalProviders
    }
}

/// Serializes filesystem work away from AppKit's main thread and coalesces callers.
/// The callback intentionally runs on the coordinator queue; UI clients must hop to main.
public final class TaskLightRenderSnapshotCoordinator {
    private let config: TaskLightConfig
    private let store: TaskLightStore
    private let queue = DispatchQueue(label: "com.66tasklight.render-snapshot", qos: .userInitiated)
    private var cachedSnapshot: TaskLightRenderSnapshot?
    private var isLoading = false
    private var needsFollowUpLoad = false
    private var pendingCompletions: [(TaskLightRenderSnapshot) -> Void] = []

    public init(config: TaskLightConfig) {
        self.config = config
        self.store = TaskLightStore(config: config)
    }

    public func refresh(force: Bool = false, completion: @escaping (TaskLightRenderSnapshot) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingCompletions.append(completion)
            if force && self.isLoading {
                self.needsFollowUpLoad = true
            }
            guard !self.isLoading else { return }
            self.isLoading = true
            self.load(force: force)
        }
    }

    public func invalidate() {
        queue.async { [weak self] in
            self?.cachedSnapshot = nil
        }
    }

    private func load(force: Bool) {
        let fingerprint = sourceFingerprint()
        let snapshot: TaskLightRenderSnapshot
        if !force, var cachedSnapshot, cachedSnapshot.fingerprint == fingerprint {
            cachedSnapshot.loadedAt = Date()
            cachedSnapshot.loadMilliseconds = 0
            cachedSnapshot.cacheHit = true
            snapshot = cachedSnapshot
        } else {
            let startedAt = DispatchTime.now()
            let uiState = store.loadProjectedUIState()
            let recentEvents = store.loadRecentEvents()
                .sorted { lhs, rhs in
                    if lhs.created_at != rhs.created_at { return lhs.created_at > rhs.created_at }
                    return lhs.event_id > rhs.event_id
                }
                .prefix(TaskLightUIPerformanceBudget.expandedRecentEventLimit)
            let statusReplay = store.loadStatusReplayRecords(
                since: Date().addingTimeInterval(-24 * 3600),
                limit: TaskLightUIPerformanceBudget.statusReplayRenderLimit
            )
            let doctorRows = store.loadWorkspaceDoctorRows(limit: TaskLightUIPerformanceBudget.workspaceDoctorRenderLimit)
            let history = store.loadQuotaHistory()
            let externalProviders = store.loadExternalUsageProviderSnapshots()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
            snapshot = TaskLightRenderSnapshot(
                fingerprint: fingerprint,
                loadMilliseconds: elapsed,
                cacheHit: false,
                uiState: uiState,
                recentEvents: Array(recentEvents),
                statusReplay: statusReplay,
                workspaceDoctorRows: doctorRows,
                quotaHistory: history,
                externalProviders: externalProviders
            )
            cachedSnapshot = snapshot
        }

        let completions = pendingCompletions
        pendingCompletions.removeAll()
        isLoading = false
        completions.forEach { $0(snapshot) }

        if needsFollowUpLoad {
            needsFollowUpLoad = false
            isLoading = true
            load(force: true)
        }
    }

    private func sourceFingerprint() -> String {
        let paths = [
            config.uiStateURL,
            config.eventsURL,
            config.uiEventFlowURL,
            config.workspaceCoverageLatestJSONURL,
            config.stateDirectory.appendingPathComponent("quota_state.json"),
            config.quotaHistoryURL,
            config.providersDirectoryURL.appendingPathComponent("provider_opt_in.json"),
            config.providersDirectoryURL.appendingPathComponent("snapshots")
        ]
        return paths.map(Self.fileFingerprint).joined(separator: "|")
    }

    private static func fileFingerprint(_ url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        return "\(url.lastPathComponent):\(modifiedAt):\(size)"
    }
}
