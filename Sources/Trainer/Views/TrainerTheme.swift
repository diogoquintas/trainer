import SwiftUI

enum TrainerTheme {
    enum Metric {
        static let power = Color(red: 1.0, green: 0.49, blue: 0.08)
        static let heartRate = Color(red: 1.0, green: 0.12, blue: 0.16)
        static let cadence = Color(red: 0.04, green: 0.58, blue: 1.0)
    }

    enum Control {
        static let start = Color(red: 0.10, green: 0.86, blue: 0.38)
        static let stop = Color(red: 1.0, green: 0.14, blue: 0.18)
    }

    enum Status {
        static let time = Color(red: 0.28, green: 0.86, blue: 1.0)
    }

    enum Surface {
        static let appBackground = LinearGradient(
            colors: [
                Color(red: 0.010, green: 0.011, blue: 0.015),
                Color(red: 0.030, green: 0.034, blue: 0.044)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
        static let panel = LinearGradient(
            colors: [
                Color(red: 0.040, green: 0.044, blue: 0.054),
                Color(red: 0.016, green: 0.018, blue: 0.024)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let panelElevated = LinearGradient(
            colors: [
                Color(red: 0.075, green: 0.080, blue: 0.092),
                Color(red: 0.024, green: 0.026, blue: 0.032)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let separator = Color.white.opacity(0.13)
        static let subtleFill = Color.white.opacity(0.070)
        static let strongerFill = Color.white.opacity(0.125)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.58)
        static let textTertiary = Color.white.opacity(0.42)
        static let neutralControl = Color.white.opacity(0.16)
    }
}
