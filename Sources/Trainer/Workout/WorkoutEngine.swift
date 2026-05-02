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

    let workout: Workout
    private let engineInterval: TimeInterval = 0.1
    private let recordingInterval: TimeInterval = 1
    private let maximumChartSamples = 1_800
    private var trainerService: TrainerServicing
    private var heartRateService: HeartRateServicing
    private let recorder: DataRecording
    private var trainerTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var lastERGTarget: Int?
    private var nextRecordingElapsed: TimeInterval = 0

    init(
        workout: Workout,
        trainerService: TrainerServicing,
        heartRateService: HeartRateServicing,
        recorder: DataRecording
    ) {
        self.workout = workout
        self.trainerService = trainerService
        self.heartRateService = heartRateService
        self.recorder = recorder
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
        lastERGTarget = nil
        nextRecordingElapsed = 0
        updateStep(for: elapsed, forceERGUpdate: true)
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
        cancelTasks()
        Task {
            await trainerService.stop()
            await heartRateService.stop()
        }
    }

    func finish() {
        state = .finished
        cancelTasks()
        Task {
            await trainerService.stop()
            await heartRateService.stop()
        }
    }

    func exportJSON() throws -> Data {
        try recorder.exportJSON()
    }

    func exportCSV() throws -> String {
        try recorder.exportCSV()
    }

    func replaceTrainerService(_ service: TrainerServicing) {
        trainerTask?.cancel()
        trainerTask = nil
        let previousService = trainerService
        trainerService = service
        lastERGTarget = nil
        updateStep(for: elapsed, forceERGUpdate: true)
        if previousService !== service {
            Task {
                await previousService.stop()
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
        elapsed += engineInterval

        if elapsed >= workout.totalDuration {
            elapsed = workout.totalDuration
            appendChartSample()
            recordSampleIfNeeded(force: true)
            finish()
            return
        }

        updateStep(for: elapsed)
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
        guard let targetWatts = currentTarget.resolvedPowerWatts(ftp: workout.ftp) else { return }
        guard forceERGUpdate || targetWatts != lastERGTarget else { return }
        lastERGTarget = targetWatts

        Task {
            try? await trainerService.setERGTarget(watts: targetWatts)
        }
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

    private func cancelTasks() {
        trainerTask?.cancel()
        heartRateTask?.cancel()
        tickTask?.cancel()
        trainerTask = nil
        heartRateTask = nil
        tickTask = nil
    }
}
