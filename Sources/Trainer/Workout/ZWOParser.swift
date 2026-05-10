import Foundation

final class ZWOParser: NSObject, WorkoutParsing {
    private var ftp = 250
    private var workoutName = "Imported Workout"
    private var author: String?
    private var workoutDescription: String?
    private var steps: [WorkoutStep] = []
    private var textEvents: [WorkoutTextEvent] = []
    private var currentTextElement: String?
    private var currentText = ""

    func parseWorkout(from data: Data, ftp: Int) throws -> Workout {
        self.ftp = ftp
        workoutName = "Imported Workout"
        author = nil
        workoutDescription = nil
        steps = []
        textEvents = []
        currentTextElement = nil
        currentText = ""

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw WorkoutParserError.invalidXML(parser.parserError?.localizedDescription ?? "Unknown XML parser error")
        }

        guard !steps.isEmpty else {
            throw WorkoutParserError.noWorkoutSteps
        }

        return Workout(
            name: workoutName,
            author: author,
            description: workoutDescription,
            ftp: ftp,
            steps: steps,
            textEvents: textEvents
        )
    }
}

extension ZWOParser: XMLParserDelegate {
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "name", "author", "description":
            currentTextElement = elementName
            currentText = ""
        case "SteadyState":
            appendSteadyState(attributeDict)
        case "Warmup", "Cooldown", "Ramp":
            appendRampLikeStep(attributeDict, fallbackName: elementName)
        case "IntervalsT":
            appendIntervals(attributeDict)
        case "FreeRide":
            appendFreeRide(attributeDict)
        case "textevent", "TextEvent":
            appendTextEvent(attributeDict)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentTextElement != nil else { return }
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard currentTextElement == elementName else { return }
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "name":
            if !trimmed.isEmpty { workoutName = trimmed }
        case "author":
            author = trimmed.isEmpty ? nil : trimmed
        case "description":
            workoutDescription = trimmed.isEmpty ? nil : trimmed
        default:
            break
        }
        currentTextElement = nil
        currentText = ""
    }
}

private extension ZWOParser {
    func appendSteadyState(_ attributes: [String: String]) {
        guard let duration = attributes.duration else { return }
        let target = WorkoutTarget(
            power: attributes.powerTarget(defaultKey: "Power"),
            cadenceRPM: attributes.int("Cadence"),
            heartRateBPM: attributes.int("HeartRate")
        )
        steps.append(
            WorkoutStep(
                name: attributes["name"] ?? "Steady",
                description: attributes["description"],
                duration: duration,
                target: target
            )
        )
    }

    func appendRampLikeStep(_ attributes: [String: String], fallbackName: String) {
        guard let duration = attributes.duration else { return }
        let low = attributes.double("PowerLow")
        let high = attributes.double("PowerHigh")
        let averagedPower = [low, high].compactMap { $0 }.average
        let targetPower = averagedPower.map { PowerTarget.percentFTP($0) } ?? attributes.powerTarget(defaultKey: "Power")
        let target = WorkoutTarget(
            power: targetPower,
            cadenceRPM: attributes.int("Cadence"),
            heartRateBPM: attributes.int("HeartRate")
        )
        steps.append(
            WorkoutStep(
                name: attributes["name"] ?? fallbackName,
                description: attributes["description"],
                duration: duration,
                target: target
            )
        )
    }

    func appendIntervals(_ attributes: [String: String]) {
        let repeats = attributes.int("Repeat") ?? 1
        let onDuration = attributes.double("OnDuration") ?? 0
        let offDuration = attributes.double("OffDuration") ?? 0
        guard repeats > 0, onDuration > 0 else { return }

        for index in 1...repeats {
            steps.append(
                WorkoutStep(
                    name: "Interval \(index)",
                    duration: onDuration,
                    target: WorkoutTarget(
                        power: attributes.powerTarget(defaultKey: "OnPower"),
                        cadenceRPM: attributes.int("Cadence"),
                        heartRateBPM: attributes.int("OnHeartRate")
                    )
                )
            )

            if offDuration > 0 {
                steps.append(
                    WorkoutStep(
                        name: "Recovery \(index)",
                        duration: offDuration,
                        target: WorkoutTarget(
                            power: attributes.powerTarget(defaultKey: "OffPower"),
                            cadenceRPM: attributes.int("CadenceRest") ?? attributes.int("Cadence"),
                            heartRateBPM: attributes.int("OffHeartRate")
                        )
                    )
                )
            }
        }
    }

    func appendFreeRide(_ attributes: [String: String]) {
        guard let duration = attributes.duration else { return }
        steps.append(
            WorkoutStep(
                name: attributes["name"] ?? "Free Ride",
                description: attributes["description"],
                duration: duration,
                target: WorkoutTarget(
                    power: attributes.powerTarget(defaultKey: "Power"),
                    cadenceRPM: attributes.int("Cadence"),
                    heartRateBPM: attributes.int("HeartRate")
                )
            )
        )
    }

    func appendTextEvent(_ attributes: [String: String]) {
        guard let offset = attributes.double("timeoffset"),
              let message = attributes.nonEmptyString("message") else {
            return
        }
        textEvents.append(WorkoutTextEvent(offset: max(0, offset), message: message))
    }
}

enum WorkoutParserError: LocalizedError {
    case invalidXML(String)
    case noWorkoutSteps

    var errorDescription: String? {
        switch self {
        case .invalidXML(let message):
            "Invalid .zwo file: \(message)"
        case .noWorkoutSteps:
            "The .zwo file did not contain supported workout steps."
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    var duration: TimeInterval? {
        double("Duration")
    }

    func int(_ key: String) -> Int? {
        guard let raw = stringValue(key) else { return nil }
        return Int(Double(raw) ?? .nan)
    }

    func double(_ key: String) -> Double? {
        guard let raw = stringValue(key), let value = Double(raw) else { return nil }
        return value
    }

    func nonEmptyString(_ key: String) -> String? {
        guard let value = stringValue(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func powerTarget(defaultKey: String) -> PowerTarget? {
        if let watts = int("\(defaultKey)Watts") ?? int("\(defaultKey)W") {
            return .watts(watts)
        }

        guard let percent = double(defaultKey) else { return nil }
        return .percentFTP(percent)
    }

    private func stringValue(_ key: String) -> String? {
        self[key] ?? first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
