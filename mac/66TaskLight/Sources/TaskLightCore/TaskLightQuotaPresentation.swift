import Foundation

public enum TaskLightQuotaPresentation {
    public static func compactText(for quota: CodexQuotaUIState?) -> String {
        guard let quota else { return "⚡Q?" }

        var seenValues = Set<Int>()
        var parts = [
            quota.short_percent,
            quota.long_percent,
            quota.effective_remaining_percent
        ]
        .compactMap { $0 }
        .filter { (0...100).contains($0) }
        .compactMap { value -> String? in
            guard seenValues.insert(value).inserted else { return nil }
            return String(value)
        }

        if let resets = quota.manual_resets_available, resets >= 0 {
            parts.append("R\(resets)")
        }

        return parts.isEmpty ? "⚡Q?" : "⚡" + parts.joined(separator: "·")
    }
}
