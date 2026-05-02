import Foundation

final class DataRecorder: DataRecording {
    private var storedSamples: [WorkoutSample] = []
    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func reset() {
        storedSamples.removeAll(keepingCapacity: true)
    }

    func append(_ sample: WorkoutSample) {
        storedSamples.append(sample)
    }

    func samples() -> [WorkoutSample] {
        storedSamples
    }

    func exportJSON() throws -> Data {
        try encoder.encode(storedSamples)
    }

    func exportCSV() throws -> String {
        var rows = [
            "timestamp,elapsed,powerWatts,cadenceRPM,heartRateBPM,targetPowerWatts,targetCadenceRPM,targetHeartRateBPM,stepIndex"
        ]

        let formatter = ISO8601DateFormatter()
        rows += storedSamples.map { sample in
            [
                formatter.string(from: sample.timestamp),
                sample.elapsed.formatted(),
                sample.powerWatts.csvValue,
                sample.cadenceRPM.csvValue,
                sample.heartRateBPM.csvValue,
                sample.targetPowerWatts.csvValue,
                sample.targetCadenceRPM.csvValue,
                sample.targetHeartRateBPM.csvValue,
                sample.stepIndex.csvValue
            ].joined(separator: ",")
        }

        return rows.joined(separator: "\n")
    }
}

private extension Optional where Wrapped == Int {
    var csvValue: String {
        map(String.init) ?? ""
    }
}
