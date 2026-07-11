import Foundation

public enum TaskLightUIPerformanceBudget {
    public static let projectorFreshnessMaxSeconds: Double = 5
    public static let duplicateSignalRateMax: Double = 0.01
    public static let menuOpenMaxMilliseconds: Double = 450
    public static let radarOpenMaxMilliseconds: Double = 180
    public static let expandedApplyMaxMilliseconds: Double = 650
    public static let renderSnapshotLoadMaxMilliseconds: Double = 160
    public static let renderSnapshotTelemetryMaxBytes = 512 * 1024
    public static let statusReplayRenderLimit = 40
    public static let workspaceDoctorRenderLimit = 48
    public static let eventLogMaxBytes = 2 * 1024 * 1024
    public static let uiEventFlowLogMaxBytes = 4 * 1024 * 1024
    public static let retainedLogArchiveCount = 3
    public static let compactBellSwingDurationSeconds: Double = 1.8
    public static let expandedScrollUsesOptimizedCards = true
    public static let expandedScrollDisablesCardPulseAnimations = true
    public static let expandedScrollAvoidsPerCardMaterial = true
    public static let expandedOverviewManagedTaskInitialRenderLimit = 4
    public static let expandedOverviewManagedTaskRenderLimit = 16
    public static let expandedTaskInitialRenderLimit = 8
    public static let expandedManagedTaskRenderLimit = 48
    public static let expandedManagedTaskCachePageSize = 48
    public static let expandedManagedTaskCacheHardLimit = 240
    public static let expandedTaskRenderBatchSize = 12
    public static let expandedInvalidTaskRenderLimit = 24
    public static let expandedObservedThreadRenderLimit = 24
    public static let expandedRecentEventInitialRenderLimit = 12
    public static let expandedRecentEventLimit = 40
    public static let alertPlaybackRecentEventLimit = 240
    // Alert playback only needs the newest records. Keeping this tail bounded
    // avoids repeatedly splitting a half-megabyte JSONL buffer on the UI path.
    public static let eventTailReadMaxBytes = 96 * 1024
    // The radar only needs recent transitions. Read a bounded tail and reuse it
    // until the event-flow file changes, rather than decoding full history.
    public static let statusReplayTailReadMaxBytes = 160 * 1024

    public static func renderingScore(
        bellUsesCompositedAnimation: Bool,
        scrollUsesOptimizedCards: Bool,
        scrollDisablesCardPulseAnimations: Bool,
        scrollAvoidsPerCardMaterial: Bool
    ) -> Int {
        var score = 0
        if bellUsesCompositedAnimation { score += 25 }
        if compactBellSwingDurationSeconds >= 1.5 { score += 15 }
        if scrollUsesOptimizedCards { score += 25 }
        if scrollDisablesCardPulseAnimations { score += 20 }
        if scrollAvoidsPerCardMaterial { score += 15 }
        return min(score, 100)
    }
}
