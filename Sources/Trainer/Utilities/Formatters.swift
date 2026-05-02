import Foundation

enum WorkoutFormatters {
    static func duration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func value(_ value: Int?, unit: String) -> String {
        guard let value else { return "-- \(unit)" }
        return "\(value) \(unit)"
    }

    static func number(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }
}
