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

    init(
        workout: Workout,
        trainerService: TrainerServicing,
        heartRateService: HeartRateServicing,
        recorder: DataRecording,
        notifier: WorkoutNotifying,
        trainerControlMode: TrainerControlMode = .erg,
        manualVirtualGear: Int = 3
    ) {
        self.workout = workout
        self.trainerService = trainerService
        self.heartRateService = heartRateService
        self.recorder = recorder
        self.notifier = notifier
        self.trainerControlMode = trainerControlMode
        self.manualVirtualGear = manualVirtualGear.clamped(to: Self.virtualGearRange)
        self.currentVirtualGear = manualVirtualGear.clamped(to: Self.virtualGearRange)
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
                currentTarget = step.target
                break
            }
            cursor = nextCursor
        }

        currentStepIndex = resolvedIndex
        currentVirtualGear = virtualGear()
        guard let command = trainerCommand() else {
            currentResistanceLevel = nil
            if trainerControlMode == .off {
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
        switch trainerControlMode {
        case .erg:
            guard isERGControlActive else { return nil }
            guard let targetWatts = currentTarget.resolvedPowerWatts(ftp: workout.ftp) else { return nil }
            return .erg(targetWatts)
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
            stepIndex: currentStepIndex
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
