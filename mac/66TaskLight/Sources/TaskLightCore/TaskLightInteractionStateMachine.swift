import Foundation

public enum TaskLightInteractionTarget: String, Codable, Sendable {
    case compact
    case edgeRail
}

public enum TaskLightInteractionDecision: Equatable, Sendable {
    case ignored
    case dragStarted(TaskLightInteractionTarget)
    case dragChanged(TaskLightInteractionTarget)
    case dragEnded(TaskLightInteractionTarget)
    case singleTap(TaskLightInteractionTarget)
    case doubleTap
    case longPress(TaskLightInteractionTarget)
}

public struct TaskLightInteractionStateMachine: Sendable {
    private struct Press: Sendable {
        let target: TaskLightInteractionTarget
        let startX: Double
        let startY: Double
        let startedAt: TimeInterval
        var didDrag: Bool
    }

    private struct Tap: Sendable {
        let target: TaskLightInteractionTarget
        let occurredAt: TimeInterval
    }

    private let dragThreshold: Double
    private let longPressDuration: TimeInterval
    private let doubleTapInterval: TimeInterval
    private var activePress: Press?
    private var lastTap: Tap?

    public init(
        dragThreshold: Double = 4,
        longPressDuration: TimeInterval = 0.45,
        doubleTapInterval: TimeInterval = 0.30
    ) {
        self.dragThreshold = dragThreshold
        self.longPressDuration = longPressDuration
        self.doubleTapInterval = doubleTapInterval
    }

    public var isTrackingPress: Bool {
        activePress != nil
    }

    public mutating func begin(
        target: TaskLightInteractionTarget,
        x: Double,
        y: Double,
        at timestamp: TimeInterval
    ) -> TaskLightInteractionDecision {
        activePress = Press(target: target, startX: x, startY: y, startedAt: timestamp, didDrag: false)
        return .ignored
    }

    public mutating func move(x: Double, y: Double) -> TaskLightInteractionDecision {
        guard var press = activePress else { return .ignored }
        let distance = hypot(x - press.startX, y - press.startY)
        if !press.didDrag, distance >= dragThreshold {
            press.didDrag = true
            activePress = press
            lastTap = nil
            return .dragStarted(press.target)
        }
        guard press.didDrag else { return .ignored }
        return .dragChanged(press.target)
    }

    public mutating func end(
        x: Double,
        y: Double,
        at timestamp: TimeInterval
    ) -> TaskLightInteractionDecision {
        guard let press = activePress else { return .ignored }
        activePress = nil

        let distance = hypot(x - press.startX, y - press.startY)
        if press.didDrag || distance >= dragThreshold {
            lastTap = nil
            return .dragEnded(press.target)
        }
        guard timestamp - press.startedAt < longPressDuration else {
            lastTap = nil
            return .longPress(press.target)
        }

        if let previous = lastTap,
           timestamp - previous.occurredAt <= doubleTapInterval,
           targetsCanBelongToOneDoubleTap(previous.target, press.target) {
            lastTap = nil
            return .doubleTap
        }

        lastTap = Tap(target: press.target, occurredAt: timestamp)
        return .singleTap(press.target)
    }

    public mutating func cancel() {
        activePress = nil
    }

    private func targetsCanBelongToOneDoubleTap(
        _ previous: TaskLightInteractionTarget,
        _ current: TaskLightInteractionTarget
    ) -> Bool {
        previous == current || (previous == .compact && current == .edgeRail) || (previous == .edgeRail && current == .compact)
    }
}
