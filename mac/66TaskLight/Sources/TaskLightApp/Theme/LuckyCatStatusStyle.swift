import SwiftUI
import TaskLightCore

enum LuckyCatVisualStatus: String {
    case idle
    case running
    case blocked
    case done
    case pending
    case observed

    var tint: Color {
        switch self {
        case .idle:
            return LuckyCatTokens.Palette.gold
        case .running:
            return LuckyCatTokens.Palette.blue
        case .blocked:
            return LuckyCatTokens.Palette.red
        case .done:
            return LuckyCatTokens.Palette.green
        case .pending:
            return LuckyCatTokens.Palette.amber
        case .observed:
            return LuckyCatTokens.Palette.cyan
        }
    }

    var glow: Color {
        switch self {
        case .idle:
            return LuckyCatTokens.Palette.gold.opacity(0.36)
        case .running:
            return tint.opacity(0.24)
        case .blocked:
            return tint.opacity(0.28)
        case .done:
            return tint.opacity(0.26)
        case .pending:
            return tint.opacity(0.22)
        case .observed:
            return tint.opacity(0.2)
        }
    }

    var mood: LuckyCatMood {
        switch self {
        case .idle:
            return .sleepy
        case .running:
            return .focused
        case .blocked:
            return .alert
        case .done:
            return .happy
        case .pending:
            return .focused
        case .observed:
            return .curious
        }
    }
}

enum LuckyCatMood {
    case sleepy
    case focused
    case alert
    case happy
    case curious
}

enum LuckyCatStatusStyle {
    static func globalStatus(from lampStatus: String) -> LuckyCatVisualStatus {
        switch lampStatus {
        case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue:
            return .blocked
        case TaskLightStatus.running.rawValue, TaskLightStatus.queued.rawValue:
            return .running
        case TaskLightStatus.done_verified.rawValue:
            return .done
        default:
            return .idle
        }
    }

    static func displayTitle(from lampStatus: String) -> String {
        switch lampStatus {
        case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue:
            return "BLOCKED"
        case TaskLightStatus.running.rawValue, TaskLightStatus.queued.rawValue:
            return "RUNNING"
        case TaskLightStatus.done_verified.rawValue:
            return "DONE"
        default:
            return "IDLE"
        }
    }

    static func taskStatus(from task: TaskLightTaskSummary) -> LuckyCatVisualStatus {
        switch task.effective_status {
        case TaskLightStatus.blocked.rawValue, TaskLightStatus.stale.rawValue, TaskLightStatus.invalid_json.rawValue:
            return .blocked
        case TaskLightStatus.running.rawValue, TaskLightStatus.queued.rawValue:
            return .running
        case TaskLightStatus.done_unverified.rawValue:
            return .pending
        case TaskLightStatus.done_verified.rawValue:
            return .done
        default:
            return .idle
        }
    }

    static func observationStatus(from thread: TaskLightObservationRecord) -> LuckyCatVisualStatus {
        switch TaskLightObservationStatus(rawValue: thread.status) {
        case .observed_attention:
            return .blocked
        case .observed_active:
            return .observed
        case .observed_quiet:
            return .running
        default:
            return .idle
        }
    }
}
