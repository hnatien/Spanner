import Foundation

/// Human-readable formatting shared by every module, kept here so wording is
/// consistent and testable.
public enum SpannerFormat {
    /// Compact duration: "2 h 05 min", "45 min", "Less than a minute".
    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 60 else { return "Less than a minute" }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(String(format: "%02d", minutes)) min"
    }

    /// Countdown clock: "1:04:09" or "4:09".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
