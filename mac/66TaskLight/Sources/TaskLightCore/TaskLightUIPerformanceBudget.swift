import Foundation

public enum TaskLightUIPerformanceBudget {
    public static let compactBellSwingDurationSeconds: Double = 1.8
    public static let expandedScrollUsesOptimizedCards = true
    public static let expandedScrollDisablesCardPulseAnimations = true
    public static let expandedScrollAvoidsPerCardMaterial = true
    public static let expandedOverviewManagedTaskInitialRenderLimit = 4
    public static let expandedOverviewManagedTaskRenderLimit = 16
    public static let expandedTaskInitialRenderLimit = 10
    public static let expandedManagedTaskRenderLimit = 80
    public static let expandedManagedTaskCachePageSize = 80
    public static let expandedManagedTaskCacheHardLimit = 480
    public static let expandedTaskRenderBatchSize = 12
    public static let expandedInvalidTaskRenderLimit = 40
    public static let expandedObservedThreadRenderLimit = 40
    public static let expandedRecentEventInitialRenderLimit = 12
    public static let expandedRecentEventLimit = 40
    public static let alertPlaybackRecentEventLimit = 240
    public static let eventTailReadMaxBytes = 512 * 1024

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
