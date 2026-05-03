import Foundation

struct AthleteProfile: Codable, Equatable {
    var ftp: Int
    var thresholdHeartRateBPM: Int
    var maxHeartRateBPM: Int
    var restingHeartRateBPM: Int
    var weightKg: Double
    var trainerDifficultyPercent: Int

    init(
        ftp: Int = 250,
        thresholdHeartRateBPM: Int = 165,
        maxHeartRateBPM: Int = 185,
        restingHeartRateBPM: Int = 55,
        weightKg: Double = 75,
        trainerDifficultyPercent: Int = 50
    ) {
        self.ftp = ftp
        self.thresholdHeartRateBPM = thresholdHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.restingHeartRateBPM = restingHeartRateBPM
        self.weightKg = weightKg
        self.trainerDifficultyPercent = trainerDifficultyPercent
    }

    var sanitized: AthleteProfile {
        AthleteProfile(
            ftp: ftp.clamped(to: 50...600),
            thresholdHeartRateBPM: thresholdHeartRateBPM.clamped(to: 60...240),
            maxHeartRateBPM: maxHeartRateBPM.clamped(to: 80...240),
            restingHeartRateBPM: restingHeartRateBPM.clamped(to: 30...120),
            weightKg: weightKg.clamped(to: 30...250),
            trainerDifficultyPercent: trainerDifficultyPercent.clamped(to: 0...100)
        )
    }

    var wattsPerKilogram: Double {
        guard weightKg > 0 else { return 0 }
        return Double(ftp) / weightKg
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
