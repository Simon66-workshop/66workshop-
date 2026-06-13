import CoreGraphics

public enum TaskLightPanelGeometry {
    public static let targetTransitionLatencyMilliseconds: Double = 50
    public static let usesAnimatedWindowFrameChanges = false
    public static let usesHiddenAtomicContentSwap = false
    public static let usesDualWindowSwap = true

    public static func restoredCompactFrame(
        storedFrame: CGRect?,
        fallbackFrame: CGRect,
        compactSize: CGSize,
        visibleFrames: [CGRect]
    ) -> CGRect {
        let source = storedFrame ?? fallbackFrame
        let compact = CGRect(origin: source.origin, size: compactSize)
        return clampedFrame(compact, visibleFrames: visibleFrames, preferredNear: source)
    }

    public static func expandedFrame(
        from compactFrame: CGRect,
        expandedSize: CGSize,
        visibleFrames: [CGRect]
    ) -> CGRect {
        let visible = bestVisibleFrame(containing: compactFrame, visibleFrames: visibleFrames)
        let centered = CGRect(
            x: visible.midX - expandedSize.width / 2,
            y: visible.midY - expandedSize.height / 2,
            width: expandedSize.width,
            height: expandedSize.height
        )
        return clampedFrame(centered, visibleFrame: visible)
    }

    public static func collapsedCompactFrame(
        storedCompactFrame: CGRect?,
        currentExpandedFrame: CGRect,
        compactSize: CGSize,
        visibleFrames: [CGRect]
    ) -> CGRect {
        restoredCompactFrame(
            storedFrame: storedCompactFrame,
            fallbackFrame: currentExpandedFrame,
            compactSize: compactSize,
            visibleFrames: visibleFrames
        )
    }

    public static func clampedFrame(
        _ frame: CGRect,
        visibleFrames: [CGRect],
        preferredNear preferredFrame: CGRect
    ) -> CGRect {
        let visible = bestVisibleFrame(containing: preferredFrame, visibleFrames: visibleFrames)
        return clampedFrame(frame, visibleFrame: visible)
    }

    public static func bestVisibleFrame(containing frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = visibleFrames.first(where: { $0.contains(center) }) {
            return containing
        }
        if let intersecting = visibleFrames.max(by: { lhs, rhs in
            lhs.intersection(frame).area < rhs.intersection(frame).area
        }), intersecting.intersection(frame).area > 0 {
            return intersecting
        }
        return visibleFrames.min(by: { lhs, rhs in
            lhs.distanceSquared(to: center) < rhs.distanceSquared(to: center)
        }) ?? visibleFrames[0]
    }

    public static func clampedFrame(_ frame: CGRect, visibleFrame: CGRect) -> CGRect {
        guard !visibleFrame.isEmpty else { return frame }
        var clamped = frame
        clamped.size.width = min(clamped.width, visibleFrame.width)
        clamped.size.height = min(clamped.height, visibleFrame.height)
        clamped.origin.x = min(max(clamped.origin.x, visibleFrame.minX), visibleFrame.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.origin.y, visibleFrame.minY), visibleFrame.maxY - clamped.height)
        return clamped
    }

    public static func transitionScore(
        expandsToCenter: Bool,
        restoresCompactOrigin: Bool,
        protectsCompactFrameDuringExpandedMove: Bool,
        usesHiddenAtomicContentSwap: Bool,
        usesDualWindowSwap: Bool = false,
        transitionLatencyMilliseconds: Double,
        usesAnimation: Bool
    ) -> Int {
        var score = 0
        if expandsToCenter { score += 22 }
        if restoresCompactOrigin { score += 22 }
        if protectsCompactFrameDuringExpandedMove { score += 20 }
        if usesDualWindowSwap { score += 22 }
        if usesHiddenAtomicContentSwap { score += 5 }
        if !usesAnimation { score += 10 }
        if transitionLatencyMilliseconds <= targetTransitionLatencyMilliseconds {
            score += 4
        }
        return min(score, 100)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }

    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx: CGFloat
        if point.x < minX {
            dx = minX - point.x
        } else if point.x > maxX {
            dx = point.x - maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < minY {
            dy = minY - point.y
        } else if point.y > maxY {
            dy = point.y - maxY
        } else {
            dy = 0
        }
        return dx * dx + dy * dy
    }
}
