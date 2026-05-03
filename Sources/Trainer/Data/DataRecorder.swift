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

    func exportTCX(workout: Workout) throws -> Data {
        guard let firstSample = storedSamples.first else {
            throw DataRecorderError.noSamplesToExport
        }

        let formatter = ISO8601DateFormatter()
        let totalSeconds = Int(storedSamples.last?.elapsed.rounded() ?? 0)
        let calories = estimatedCalories(from: storedSamples)
        let trackpoints = storedSamples.map { sample in
            tcxTrackpoint(sample, formatter: formatter)
        }.joined(separator: "\n")

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(formatter.string(from: firstSample.timestamp))</Id>
              <Lap StartTime="\(formatter.string(from: firstSample.timestamp))">
                <TotalTimeSeconds>\(max(1, totalSeconds))</TotalTimeSeconds>
                <DistanceMeters>0.0</DistanceMeters>
                <Calories>\(calories)</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>
        \(trackpoints)
                </Track>
              </Lap>
              <Notes>\(workout.name.xmlEscaped)</Notes>
            </Activity>
          </Activities>
          <Author xsi:type="Application_t">
            <Name>Trainer</Name>
            <Build>
              <Version>
                <VersionMajor>0</VersionMajor>
                <VersionMinor>1</VersionMinor>
              </Version>
            </Build>
            <LangID>en</LangID>
            <PartNumber>000-00000-00</PartNumber>
          </Author>
        </TrainingCenterDatabase>
        """

        guard let data = xml.data(using: .utf8) else {
            throw DataRecorderError.encodingFailed
        }
        return data
    }

    private func tcxTrackpoint(_ sample: WorkoutSample, formatter: ISO8601DateFormatter) -> String {
        var lines = [
            "                  <Trackpoint>",
            "                    <Time>\(formatter.string(from: sample.timestamp))</Time>"
        ]

        if let heartRateBPM = sample.heartRateBPM {
            lines += [
                "                    <HeartRateBpm>",
                "                      <Value>\(heartRateBPM)</Value>",
                "                    </HeartRateBpm>"
            ]
        }

        if let cadenceRPM = sample.cadenceRPM {
            lines.append("                    <Cadence>\(cadenceRPM)</Cadence>")
        }

        if let powerWatts = sample.powerWatts {
            lines += [
                "                    <Extensions>",
                "                      <ns3:TPX>",
                "                        <ns3:Watts>\(powerWatts)</ns3:Watts>",
                "                      </ns3:TPX>",
                "                    </Extensions>"
            ]
        }

        lines.append("                  </Trackpoint>")
        return lines.joined(separator: "\n")
    }

    private func estimatedCalories(from samples: [WorkoutSample]) -> Int {
        guard samples.count > 1 else { return 0 }

        let joules = zip(samples, samples.dropFirst()).reduce(0.0) { total, pair in
            let (previous, current) = pair
            let duration = max(0, current.elapsed - previous.elapsed)
            return total + Double(current.powerWatts ?? 0) * duration
        }

        return max(0, Int((joules / 4_184).rounded()))
    }
}

private extension Optional where Wrapped == Int {
    var csvValue: String {
        map(String.init) ?? ""
    }
}

enum DataRecorderError: LocalizedError {
    case noSamplesToExport
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noSamplesToExport:
            "There are no workout samples to export."
        case .encodingFailed:
            "Could not encode the workout export."
        }
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
