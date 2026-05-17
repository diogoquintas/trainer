import Foundation

@MainActor
final class WorkoutEngine: ObservableObject {
    @Published private(set) var state: WorkoutState = .stopped
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentStepIndex: Int?
    @Published private(set) var currentTarget = WorkoutTarget()
    @Published private(set) var latestTrainerReading = TrainerReading(powerWatts: nil, cadenceRPM: nil)
    @Published private(set) var latestHeartRateReading: HeartRateReading?
    @Published private(set) var samples: [WorkoutSample] = []
    @Published private(set) var chartSamples: [WorkoutSample] = []
    @Published private(set) var trainerControlMode: TrainerControlMode
    @Published private(set) var currentResistanceLevel: Double?
    @Published private(set) var currentVirtualGear: Int
    @Published private(set) var isERGControlActive = false
    @Published private(set) var virtualRoute: VirtualRoute?
    @Published private(set) var virtualRouteDistanceMeters: Double = 0
    @Published private(set) var currentVirtualRouteLocation: VirtualRouteLocation?
    @Published private(set) var currentVirtualSpeedMetersPerSecond: Double = 0

    let workout: Workout
    static let virtualGearRange = 1...10

    private let engineInterval: TimeInterval = 0.1
    private let recordingInterval: TimeInterval = 1
    private let minimumCadenceForERG = 35
    private let maximumChartSamples = 1_800
    private var trainerService: TrainerServicing
    private var heartRateService: HeartRateServicing
    private let recorder: DataRecording
    private let notifier: WorkoutNotifying
    private var trainerTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var lastTrainerCommand: TrainerCommand?
    private var manualVirtualGear: Int
    private var nextRecordingElapsed: TimeInterval = 0
    private var firedTextEventIDs = Set<WorkoutTextEvent.ID>()
    private var warnedStepIndices = Set<Int>()
    private var riderWeightKg: Double
    private var trainerDifficultyPercent: Int

    init(
        workout: Workout,
        trainerService: TrainerServicing,
        heartRateService: HeartRateServicing,
        recorder: DataRecording,
        notifier: WorkoutNotifying,
        trainerControlMode: TrainerControlMode = .erg,
        manualVirtualGear: Int = 3,
        athleteProfile: AthleteProfile = AthleteProfile(),
        virtualRoute: VirtualRoute? = nil
    ) {
        self.workout = workout
        self.trainerService = trainerService
        self.heartRateService = heartRateService
        self.recorder = recorder
        self.notifier = notifier
        self.trainerControlMode = trainerControlMode
        self.manualVirtualGear = manualVirtualGear.clamped(to: Self.virtualGearRange)
        self.currentVirtualGear = manualVirtualGear.clamped(to: Self.virtualGearRange)
        self.riderWeightKg = athleteProfile.weightKg
        self.trainerDifficultyPercent = athleteProfile.trainerDifficultyPercent
        self.virtualRoute = virtualRoute
        self.currentVirtualRouteLocation = virtualRoute?.location(at: 0)
        updateStep(for: 0, forceERGUpdate: true)
    }

    var currentStep: WorkoutStep? {
        guard let currentStepIndex, workout.steps.indices.contains(currentStepIndex) else { return nil }
        return workout.steps[currentStepIndex]
    }

    var timeRemainingInStep: TimeInterval {
        guard let currentStepIndex else { return 0 }
        let stepStart = workout.steps.prefix(currentStepIndex).reduce(0) { $0 + $1.duration }
        let stepEnd = stepStart + workout.steps[currentStepIndex].duration
        return max(0, stepEnd - elapsed)
    }

    func start() {
        guard state == .stopped || state == .finished else { return }
        recorder.reset()
        samples = []
        chartSamples = []
        elapsed = 0
        resetVirtualRouteProgress()
        state = .running
        lastTrainerCommand = nil
        isERGControlActive = false
        nextRecordingElapsed = 0
        firedTextEventIDs = []
        warnedStepIndices = []
        updateStep(for: elapsed, forceERGUpdate: true)
        sendDueNotifications(previousElapsed: nil)
        recordSample()
        appendChartSample()
        nextRecordingElapsed = recordingInterval
        beginStreams()
        beginTicking()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
    }

    func stop() {
        state = .stopped
        elapsed = 0
        currentStepIndex = nil
        isERGControlActive = false
        resetVirtualRouteProgress()
        cancelTasks()
        Task {
            await trainerService.stop()
            await heartRateService.stop()
            try? await trainerService.releaseControl()
        }
    }

    func finish() {
        state = .finished
        isERGControlActive = false
        cancelTasks()
        Task {
            await trainerService.stop()
            await heartRateService.stop()
            try? await trainerService.releaseControl()
        }
    }

    func replaceVirtualRoute(_ route: VirtualRoute?) {
        virtualRoute = route
        resetVirtualRouteProgress()
        lastTrainerCommand = nil
        updateStep(for: elapsed, forceERGUpdate: true)
    }

    func updateAthleteProfile(_ profile: AthleteProfile) {
        let sanitized = profile.sanitized
        riderWeightKg = sanitized.weightKg
        trainerDifficultyPercent = sanitized.trainerDifficultyPercent
        lastTrainerCommand = nil
        updateStep(for: elapsed, forceERGUpdate: true)
    }

    func exportJSON() throws -> Data {
        try recorder.exportJSON()
    }

    func exportCSV() throws -> String {
        try recorder.exportCSV()
    }

    func exportTCX() throws -> Data {
        try recorder.exportTCX(workout: workout)
    }

    func replaceTrainerService(_ service: TrainerServicing) {
        trainerTask?.cancel()
        trainerTask = nil
        let previousService = trainerService
        trainerService = service
        lastTrainerCommand = nil
        updateStep(for: elapsed, forceERGUpdate: true)
        if previousService !== service {
            Task {
                await previousService.stop()
                try? await previousService.releaseControl()
            }
        }
        if state == .running || state == .paused {
            beginTrainerStream()
        }
    }

    func replaceHeartRateService(_ service: HeartRateServicing) {
        heartRateTask?.cancel()
        heartRateTask = nil
        let previousService = heartRateService
        heartRateService = service
        if previousService !== service {
            Task {
                await previousService.stop()
            }
        }
        if state == .running || state == .paused {
            beginHeartRateStream()
        }
    }

    func setTrainerControlMode(_ mode: TrainerControlMode) {
        guard trainerControlMode != mode else { return }
        trainerControlMode = mode
        lastTrainerCommand = nil

        if mode == .off {
            currentResistanceLevel = nil
            Task {
                try? await trainerService.releaseControl()
            }
        } else {
            updateStep(for: elapsed, forceERGUpdate: true)
        }
    }

    func setManualVirtualGear(_ gear: Int) {
        manualVirtualGear = gear.clamped(to: Self.virtualGearRange)
        guard trainerControlMode == .resistance else { return }
        lastTrainerCommand = nil
        updateStep(for: elapsed, forceERGUpdate: true)
    }

    private func beginStreams() {
        beginTrainerStream()
        beginHeartRateStream()
    }

    private func beginTrainerStream() {
        trainerTask?.cancel()
        trainerTask = Task {
            await trainerService.start()
            for await reading in trainerService.readings {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.latestTrainerReading = reading
                    self.updateERGControlReadiness(for: reading)
                }
            }
        }
    }

    private func beginHeartRateStream() {
        heartRateTask?.cancel()
        heartRateTask = Task {
            await heartRateService.start()
            for await reading in heartRateService.readings {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.latestHeartRateReading = reading
                }
            }
        }
    }

    private func beginTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard state == .running else { return }
        let previousElapsed = elapsed
        elapsed += engineInterval

        if elapsed >= workout.totalDuration {
            elapsed = workout.totalDuration
            sendDueNotifications(previousElapsed: previousElapsed)
            appendChartSample()
            recordSampleIfNeeded(force: true)
            finish()
            return
        }

        updateStep(for: elapsed)
        updateVirtualRouteProgress(deltaTime: engineInterval)
        sendDueNotifications(previousElapsed: previousElapsed)
        appendChartSample()
        recordSampleIfNeeded()
    }

    private func updateStep(for elapsed: TimeInterval, forceERGUpdate: Bool = false) {
        var cursor: TimeInterval = 0
        var resolvedIndex: Int?

        for (index, step) in workout.steps.enumerated() {
            let nextCursor = cursor + step.duration
            if elapsed < nextCursor {
                resolvedIndex = index
                currentTarget = step.target(at: elapsed - cursor)
                break
            }
            cursor = nextCursor
        }

        currentStepIndex = resolvedIndex
        currentVirtualGear = virtualGear()
        guard let command = trainerCommand() else {
            currentResistanceLevel = nil
            lastTrainerCommand = nil
            if trainerControlMode == .off || currentStep?.controlMode == .freeRide {
                Task {
                    try? await trainerService.releaseControl()
                }
            }
            return
        }
        guard forceERGUpdate || command != lastTrainerCommand else { return }
        lastTrainerCommand = command

        Task {
            switch command {
            case .erg(let watts):
                currentResistanceLevel = nil
                try? await trainerService.setERGTarget(watts: watts)
            case .resistance(let level):
                currentResistanceLevel = level
                try? await trainerService.setResistanceLevel(level)
            }
        }
    }

    private func trainerCommand() -> TrainerCommand? {
        if currentStep?.controlMode == .freeRide {
            return nil
        }

        switch trainerControlMode {
        case .erg:
            guard isERGControlActive else { return nil }
            guard let targetWatts = currentTarget.resolvedPowerWatts(ftp: workout.ftp) else { return nil }
            return .erg(gradeAdjustedERGTarget(from: targetWatts))
        case .resistance:
            return .resistance(resistanceLevel(for: manualVirtualGear))
        case .off:
            return nil
        }
    }

    private func virtualGear() -> Int {
        switch trainerControlMode {
        case .erg:
            guard let targetWatts = currentTarget.resolvedPowerWatts(ftp: workout.ftp), workout.ftp > 0 else {
                return manualVirtualGear
            }
            let intensity = Double(targetWatts) / Double(workout.ftp)
            return Int((intensity * 5).rounded()).clamped(to: Self.virtualGearRange)
        case .resistance, .off:
            return manualVirtualGear
        }
    }

    private func resistanceLevel(for gear: Int) -> Double {
        Double(gear.clamped(to: Self.virtualGearRange) - Self.virtualGearRange.lowerBound) * 2
    }

    private func resetVirtualRouteProgress() {
        virtualRouteDistanceMeters = 0
        currentVirtualSpeedMetersPerSecond = 0
        currentVirtualRouteLocation = virtualRoute?.location(at: 0)
    }

    private func updateVirtualRouteProgress(deltaTime: TimeInterval) {
        guard let virtualRoute, virtualRoute.totalDistanceMeters > 0 else {
            currentVirtualSpeedMetersPerSecond = 0
            currentVirtualRouteLocation = nil
            return
        }

        let grade = currentVirtualRouteLocation?.grade ?? 0
        let powerWatts = Double(
            latestTrainerReading.powerWatts
                ?? currentTarget.resolvedPowerWatts(ftp: workout.ftp)
                ?? 0
        )
        let speed = virtualSpeedMetersPerSecond(powerWatts: powerWatts, grade: grade)
        currentVirtualSpeedMetersPerSecond = speed
        virtualRouteDistanceMeters = min(virtualRoute.totalDistanceMeters, virtualRouteDistanceMeters + speed * deltaTime)
        currentVirtualRouteLocation = virtualRoute.location(at: virtualRouteDistanceMeters)
    }

    private func gradeAdjustedERGTarget(from targetWatts: Int) -> Int {
        guard let grade = currentVirtualRouteLocation?.grade else { return targetWatts }

        let gradeLoad = gradeLoadWatts(for: grade)
        return Int((Double(targetWatts) + gradeLoad).rounded()).clamped(to: 50...800)
    }

    private func gradeLoadWatts(for grade: Double) -> Double {
        let difficulty = Double(trainerDifficultyPercent.clamped(to: 0...100)) / 100
        let systemMassKg = max(40, riderWeightKg + 10)
        let referenceSpeed = max(4, currentVirtualSpeedMetersPerSecond)
        return systemMassKg * 9.80665 * grade * referenceSpeed * difficulty
    }

    private func virtualSpeedMetersPerSecond(powerWatts: Double, grade: Double) -> Double {
        guard powerWatts > 0 else { return grade < -0.02 ? 2.5 : 0 }

        let systemMassKg = max(40, riderWeightKg + 10)
        let rollingResistanceCoefficient = 0.005
        let airDensity = 1.225
        let dragArea = 0.32
        let drivetrainEfficiency = 0.97
        let effectivePower = powerWatts * drivetrainEfficiency

        var low = 0.0
        var high = 28.0

        for _ in 0..<32 {
            let speed = (low + high) / 2
            let rollingForce = systemMassKg * 9.80665 * rollingResistanceCoefficient
            let climbingForce = systemMassKg * 9.80665 * grade
            let aerodynamicForce = 0.5 * airDensity * dragArea * speed * speed
            let requiredPower = max(0, rollingForce + climbingForce + aerodynamicForce) * speed

            if requiredPower > effectivePower {
                high = speed
            } else {
                low = speed
            }
        }

        return low
    }

    private func updateERGControlReadiness(for reading: TrainerReading) {
        guard trainerControlMode == .erg, state == .running else { return }

        guard !isERGControlActive,
              let cadenceRPM = reading.cadenceRPM,
              cadenceRPM >= minimumCadenceForERG else { return }
        isERGControlActive = true
        lastTrainerCommand = nil
        updateStep(for: elapsed, forceERGUpdate: true)
    }

    private func recordSampleIfNeeded(force: Bool = false) {
        guard force || elapsed >= nextRecordingElapsed else { return }
        recordSample()
        while nextRecordingElapsed <= elapsed {
            nextRecordingElapsed += recordingInterval
        }
    }

    private func recordSample() {
        let sample = makeCurrentSample()
        recorder.append(sample)
        samples.append(sample)
    }

    private func appendChartSample() {
        let sample = makeCurrentSample()
        chartSamples.append(sample)
        if chartSamples.count > maximumChartSamples {
            chartSamples.removeFirst(chartSamples.count - maximumChartSamples)
        }
    }

    private func makeCurrentSample() -> WorkoutSample {
        WorkoutSample(
            elapsed: elapsed,
            powerWatts: latestTrainerReading.powerWatts,
            cadenceRPM: latestTrainerReading.cadenceRPM,
            heartRateBPM: latestHeartRateReading?.bpm,
            targetPowerWatts: currentTarget.resolvedPowerWatts(ftp: workout.ftp),
            targetCadenceRPM: currentTarget.cadenceRPM,
            targetHeartRateBPM: currentTarget.heartRateBPM,
            stepIndex: currentStepIndex,
            latitude: currentVirtualRouteLocation?.coordinate.latitude,
            longitude: currentVirtualRouteLocation?.coordinate.longitude,
            altitudeMeters: currentVirtualRouteLocation?.elevationMeters,
            distanceMeters: currentVirtualRouteLocation?.distanceMeters,
            speedMetersPerSecond: currentVirtualRouteLocation == nil ? nil : currentVirtualSpeedMetersPerSecond
        )
    }

    private func sendDueNotifications(previousElapsed: TimeInterval?) {
        let startElapsed = previousElapsed ?? -.ulpOfOne
        let endElapsed = elapsed

        for textEvent in workout.textEvents where !firedTextEventIDs.contains(textEvent.id) {
            guard textEvent.offset > startElapsed, textEvent.offset <= endElapsed else { continue }
            firedTextEventIDs.insert(textEvent.id)
            sendNotification(title: workout.name, body: textEvent.message)
        }

        var stepStart: TimeInterval = 0
        for stepIndex in workout.steps.indices.dropFirst() {
            stepStart += workout.steps[stepIndex - 1].duration
            let notificationOffset = stepStart - 60
            guard notificationOffset >= 0,
                  !warnedStepIndices.contains(stepIndex),
                  notificationOffset > startElapsed,
                  notificationOffset <= endElapsed else {
                continue
            }

            warnedStepIndices.insert(stepIndex)
            let stepName = workout.steps[stepIndex].name ?? "Step \(stepIndex + 1)"
            sendNotification(title: "Next step in 1 minute", body: stepName)
        }
    }

    private func sendNotification(title: String, body: String) {
        Task {
            _ = await notifier.sendWorkoutNotification(title: title, body: body)
        }
    }

    private func cancelTasks() {
        trainerTask?.cancel()
        heartRateTask?.cancel()
        tickTask?.cancel()
        trainerTask = nil
        heartRateTask = nil
        tickTask = nil
    }
}

private enum TrainerCommand: Equatable {
    case erg(Int)
    case resistance(Double)
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
