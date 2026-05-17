import Foundation

struct Workout: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var author: String?
    var description: String?
    var ftp: Int
    var steps: [WorkoutStep]
    var textEvents: [WorkoutTextEvent]

    init(
        id: UUID = UUID(),
        name: String,
        author: String? = nil,
        description: String? = nil,
        ftp: Int = 250,
        steps: [WorkoutStep],
        textEvents: [WorkoutTextEvent] = []
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.description = description
        self.ftp = ftp
        self.steps = steps
        self.textEvents = textEvents.sorted { $0.offset < $1.offset }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case author
        case description
        case ftp
        case steps
        case textEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        ftp = try container.decode(Int.self, forKey: .ftp)
        steps = try container.decode([WorkoutStep].self, forKey: .steps)
        textEvents = try container.decodeIfPresent([WorkoutTextEvent].self, forKey: .textEvents) ?? []
        textEvents.sort { $0.offset < $1.offset }
    }

    var totalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.duration }
    }

    static func sample(ftp: Int = 250) -> Workout {
        Workout(
            name: "Simulation Ramp",
            author: "Trainer",
            description: "A short synthetic workout for UI development.",
            ftp: ftp,
            steps: [
                WorkoutStep(name: "Warmup", duration: 60, target: .init(power: .percentFTP(0.55), cadenceRPM: 85, heartRateBPM: 125)),
                WorkoutStep(name: "Build", duration: 90, target: .init(power: .percentFTP(0.75), cadenceRPM: 90, heartRateBPM: 145)),
                WorkoutStep(name: "ERG Block", duration: 120, target: .init(power: .watts(230), cadenceRPM: 92, heartRateBPM: 158)),
                WorkoutStep(name: "Recovery", duration: 60, target: .init(power: .percentFTP(0.45), cadenceRPM: 80, heartRateBPM: 132)),
                WorkoutStep(name: "Finish", duration: 90, target: .init(power: .percentFTP(0.85), cadenceRPM: 95, heartRateBPM: 165))
            ]
        )
    }
}

struct WorkoutTextEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var offset: TimeInterval
    var message: String

    init(id: UUID = UUID(), offset: TimeInterval, message: String) {
        self.id = id
        self.offset = offset
        self.message = message
    }
}

struct WorkoutStep: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String?
    var description: String?
    var duration: TimeInterval
    var target: WorkoutTarget
    var controlMode: WorkoutStepControlMode

    init(
        id: UUID = UUID(),
        name: String? = nil,
        description: String? = nil,
        duration: TimeInterval,
        target: WorkoutTarget,
        controlMode: WorkoutStepControlMode = .erg
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.duration = duration
        self.target = target
        self.controlMode = controlMode
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case duration
        case target
        case controlMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        target = try container.decode(WorkoutTarget.self, forKey: .target)
        controlMode = try container.decodeIfPresent(WorkoutStepControlMode.self, forKey: .controlMode) ?? .erg
    }

    func target(at elapsed: TimeInterval) -> WorkoutTarget {
        guard duration > 0 else { return target }
        return target.interpolated(progress: elapsed / duration)
    }
}

struct WorkoutTarget: Codable, Equatable {
    var power: PowerTarget?
    var cadenceRPM: Int?
    var cadenceLowRPM: Int?
    var cadenceHighRPM: Int?
    var heartRateBPM: Int?

    init(
        power: PowerTarget? = nil,
        cadenceRPM: Int? = nil,
        cadenceLowRPM: Int? = nil,
        cadenceHighRPM: Int? = nil,
        heartRateBPM: Int? = nil
    ) {
        self.power = power
        self.cadenceRPM = cadenceRPM
        self.cadenceLowRPM = cadenceLowRPM
        self.cadenceHighRPM = cadenceHighRPM
        self.heartRateBPM = heartRateBPM
    }

    func resolvedPowerWatts(ftp: Int) -> Int? {
        power?.watts(ftp: ftp)
    }

    func interpolated(progress: Double) -> WorkoutTarget {
        let clampedProgress = min(1, max(0, progress))
        let interpolatedCadence: Int?
        if let cadenceLowRPM, let cadenceHighRPM {
            interpolatedCadence = Int((Double(cadenceLowRPM) + (Double(cadenceHighRPM - cadenceLowRPM) * clampedProgress)).rounded())
        } else {
            interpolatedCadence = cadenceRPM
        }

        return WorkoutTarget(
            power: power?.interpolated(progress: clampedProgress),
            cadenceRPM: interpolatedCadence,
            cadenceLowRPM: cadenceLowRPM,
            cadenceHighRPM: cadenceHighRPM,
            heartRateBPM: heartRateBPM
        )
    }
}

enum WorkoutStepControlMode: String, Codable, Equatable {
    case erg
    case freeRide
}

enum PowerTarget: Codable, Equatable {
    case watts(Int)
    case percentFTP(Double)
    case range(lower: Int, upper: Int)
    case wattsRamp(start: Int, end: Int)
    case percentFTPRamp(start: Double, end: Double)

    func watts(ftp: Int) -> Int {
        switch self {
        case .watts(let value):
            value
        case .percentFTP(let percent):
            Int((Double(ftp) * percent).rounded())
        case .range(let lower, let upper):
            (lower + upper) / 2
        case .wattsRamp(let start, let end):
            (start + end) / 2
        case .percentFTPRamp(let start, let end):
            Int((Double(ftp) * ((start + end) / 2)).rounded())
        }
    }

    func interpolated(progress: Double) -> PowerTarget {
        let clampedProgress = min(1, max(0, progress))
        switch self {
        case .wattsRamp(let start, let end):
            return .watts(Int((Double(start) + (Double(end - start) * clampedProgress)).rounded()))
        case .percentFTPRamp(let start, let end):
            return .percentFTP(start + ((end - start) * clampedProgress))
        case .watts, .percentFTP, .range:
            return self
        }
    }
}

struct WorkoutSample: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let elapsed: TimeInterval
    let powerWatts: Int?
    let cadenceRPM: Int?
    let heartRateBPM: Int?
    let targetPowerWatts: Int?
    let targetCadenceRPM: Int?
    let targetHeartRateBPM: Int?
    let stepIndex: Int?
    let latitude: Double?
    let longitude: Double?
    let altitudeMeters: Double?
    let distanceMeters: Double?
    let speedMetersPerSecond: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        elapsed: TimeInterval,
        powerWatts: Int?,
        cadenceRPM: Int?,
        heartRateBPM: Int?,
        targetPowerWatts: Int?,
        targetCadenceRPM: Int?,
        targetHeartRateBPM: Int?,
        stepIndex: Int?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitudeMeters: Double? = nil,
        distanceMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.elapsed = elapsed
        self.powerWatts = powerWatts
        self.cadenceRPM = cadenceRPM
        self.heartRateBPM = heartRateBPM
        self.targetPowerWatts = targetPowerWatts
        self.targetCadenceRPM = targetCadenceRPM
        self.targetHeartRateBPM = targetHeartRateBPM
        self.stepIndex = stepIndex
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.distanceMeters = distanceMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

enum WorkoutState: String, Codable {
    case stopped
    case running
    case paused
    case finished
}

enum TrainerControlMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case erg
    case resistance
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .erg:
            "ERG"
        case .resistance:
            "Resistance"
        case .off:
            "Off"
        }
    }
}
