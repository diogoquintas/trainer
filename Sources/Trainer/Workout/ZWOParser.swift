import Foundation

final class ZWOParser: NSObject, WorkoutParsing {
    private var ftp = 250
    private var workoutName = "Imported Workout"
    private var author: String?
    private var workoutDescription: String?
    private var steps: [WorkoutStep] = []
    private var textEvents: [WorkoutTextEvent] = []
    private var workoutElapsed: TimeInterval = 0
    private var elementContexts: [ZWOElementContext] = []
    private var currentTextElement: String?
    private var currentText = ""

    func parseWorkout(from data: Data, ftp: Int) throws -> Workout {
        self.ftp = ftp
        workoutName = "Imported Workout"
        author = nil
        workoutDescription = nil
        steps = []
        textEvents = []
        workoutElapsed = 0
        elementContexts = []
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
            appendWorkoutElement(elementName, attributes: attributeDict, duration: appendSteadyState(attributeDict))
        case "Warmup", "Cooldown", "Ramp":
            appendWorkoutElement(elementName, attributes: attributeDict, duration: appendRampLikeStep(attributeDict, fallbackName: elementName))
        case "IntervalsT":
            appendWorkoutElement(elementName, attributes: attributeDict, duration: appendIntervals(attributeDict))
        case "FreeRide":
            appendWorkoutElement(elementName, attributes: attributeDict, duration: appendFreeRide(attributeDict))
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
        if let contextIndex = elementContexts.lastIndex(where: { $0.elementName == elementName }) {
            elementContexts.remove(at: contextIndex)
        }

        if currentTextElement == elementName {
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
}

private extension ZWOParser {
    func appendWorkoutElement(_ elementName: String, attributes: [String: String], duration: TimeInterval?) {
        guard let duration else { return }
        elementContexts.append(ZWOElementContext(elementName: elementName, startOffset: workoutElapsed, duration: duration))
        workoutElapsed += duration
    }

    func appendSteadyState(_ attributes: [String: String]) -> TimeInterval? {
        guard let duration = attributes.duration else { return nil }
        let target = WorkoutTarget(
            power: attributes.powerTarget(defaultKey: "Power"),
            cadenceRPM: attributes.cadenceTarget,
            cadenceLowRPM: attributes.int("CadenceLow"),
            cadenceHighRPM: attributes.int("CadenceHigh"),
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
        return duration
    }

    func appendRampLikeStep(_ attributes: [String: String], fallbackName: String) -> TimeInterval? {
        guard let duration = attributes.duration else { return nil }
        let target = WorkoutTarget(
            power: attributes.rampPowerTarget(defaultKey: "Power"),
            cadenceRPM: attributes.cadenceTarget,
            cadenceLowRPM: attributes.int("CadenceLow"),
            cadenceHighRPM: attributes.int("CadenceHigh"),
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
        return duration
    }

    func appendIntervals(_ attributes: [String: String]) -> TimeInterval? {
        let repeats = attributes.int("Repeat") ?? 1
        let onDuration = attributes.double("OnDuration") ?? 0
        let offDuration = attributes.double("OffDuration") ?? 0
        guard repeats > 0, onDuration > 0 else { return nil }

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
                            cadenceRPM: attributes.int("CadenceRest") ?? attributes.int("CadenceResting") ?? attributes.int("Cadence"),
                            heartRateBPM: attributes.int("OffHeartRate")
                        )
                    )
                )
            }
        }
        return Double(repeats) * (onDuration + offDuration)
    }

    func appendFreeRide(_ attributes: [String: String]) -> TimeInterval? {
        guard let duration = attributes.duration else { return nil }
        steps.append(
            WorkoutStep(
                name: attributes["name"] ?? "Free Ride",
                description: attributes["description"],
                duration: duration,
                target: WorkoutTarget(
                    power: attributes.powerTarget(defaultKey: "Power"),
                    cadenceRPM: attributes.int("Cadence"),
                    heartRateBPM: attributes.int("HeartRate")
                ),
                controlMode: .freeRide
            )
        )
        return duration
    }

    func appendTextEvent(_ attributes: [String: String]) {
        guard let offset = attributes.double("timeoffset"),
              let message = attributes.nonEmptyString("message") else {
            return
        }
        let baseOffset = elementContexts.last?.startOffset ?? 0
        textEvents.append(WorkoutTextEvent(offset: max(0, baseOffset + offset), message: message))
    }
}

private struct ZWOElementContext {
    var elementName: String
    var startOffset: TimeInterval
    var duration: TimeInterval
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

    var cadenceTarget: Int? {
        int("Cadence")
            ?? [int("CadenceLow"), int("CadenceHigh")].compactMap { $0 }.average
    }

    func rampPowerTarget(defaultKey: String) -> PowerTarget? {
        if let lowWatts = int("\(defaultKey)LowWatts") ?? int("PowerLowWatts") ?? int("PowerLowW"),
           let highWatts = int("\(defaultKey)HighWatts") ?? int("PowerHighWatts") ?? int("PowerHighW") {
            return .wattsRamp(start: lowWatts, end: highWatts)
        }

        if let low = double("\(defaultKey)Low") ?? double("PowerLow"),
           let high = double("\(defaultKey)High") ?? double("PowerHigh") {
            return .percentFTPRamp(start: low, end: high)
        }

        return powerTarget(defaultKey: defaultKey)
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

private extension Array where Element == Int {
    var average: Int? {
        guard !isEmpty else { return nil }
        return Int((Double(reduce(0, +)) / Double(count)).rounded())
    }
}
