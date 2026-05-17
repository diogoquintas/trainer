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

    static func distance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }

        return "\(Int(meters.rounded())) m"
    }

    static func grade(_ grade: Double) -> String {
        String(format: "%+.1f%%", grade * 100)
    }

    static func speed(_ metersPerSecond: Double) -> String {
        String(format: "%.1f km/h", metersPerSecond * 3.6)
    }
}
