import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var availableTrainers: [DeviceDescriptor] = []
    @Published var availableHeartRateDevices: [DeviceDescriptor] = []
    @Published var workouts: [Workout]
    @Published var selectedWorkoutID: Workout.ID
    @Published var workout: Workout
    @Published var engine: WorkoutEngine
    @Published var statusMessage = "Simulation mode ready"
    @Published var trainerSource: DeviceSource = .simulation
    @Published var heartRateSource: DeviceSource = .simulation

    private let simulationBluetoothManager: MockBluetoothManager
    private let bluetoothManager: CoreBluetoothManager
    private let parser: WorkoutParsing
    private let libraryStore: WorkoutLibraryStore
    private var trainerService: any TrainerServicing
    private var heartRateService: any HeartRateServicing

    init() {
        let libraryStore = WorkoutLibraryStore()
        var workouts = libraryStore.loadWorkouts()
        if workouts.isEmpty {
            workouts = [Workout.sample()]
            try? libraryStore.saveWorkouts(workouts)
        }

        let workout = workouts.first ?? Workout.sample()
        let trainer = MockTrainerService()
        let heartRate = MockHeartRateService()
        let recorder = DataRecorder()

        self.workouts = workouts
        self.selectedWorkoutID = workout.id
        self.workout = workout
        self.engine = WorkoutEngine(
            workout: workout,
            trainerService: trainer,
            heartRateService: heartRate,
            recorder: recorder
        )
        self.simulationBluetoothManager = MockBluetoothManager()
        self.bluetoothManager = CoreBluetoothManager()
        self.trainerService = trainer
        self.heartRateService = heartRate
        self.parser = ZWOParser()
        self.libraryStore = libraryStore
    }

    var trainerConnectionText: String {
        switch trainerSource {
        case .simulation:
            simulationBluetoothManager.trainerConnectionState.displayText
        case .bluetooth:
            bluetoothManager.trainerConnectionState.displayText
        }
    }

    var heartRateConnectionText: String {
        switch heartRateSource {
        case .simulation:
            simulationBluetoothManager.heartRateConnectionState.displayText
        case .bluetooth:
            bluetoothManager.heartRateConnectionState.displayText
        }
    }

    func scanAndConnectSimulationDevices() async {
        availableTrainers = await simulationBluetoothManager.scanForDevices(kind: .trainer)
        if let trainer = availableTrainers.first {
            try? await simulationBluetoothManager.connectTrainer(trainer)
        }

        availableHeartRateDevices = await simulationBluetoothManager.scanForDevices(kind: .heartRate)
        if let heartRate = availableHeartRateDevices.first {
            try? await simulationBluetoothManager.connectHeartRate(heartRate)
        }

        trainerSource = .simulation
        heartRateSource = .simulation
        trainerService = MockTrainerService()
        heartRateService = MockHeartRateService()
        engine.replaceTrainerService(trainerService)
        engine.replaceHeartRateService(heartRateService)
        statusMessage = "Connected to simulated trainer and HR broadcast"
    }

    func scanForBluetoothTrainers() async {
        trainerSource = .bluetooth
        availableTrainers = await bluetoothManager.scanForDevices(kind: .trainer)
        statusMessage = availableTrainers.isEmpty ? "No Bluetooth trainers found" : "Found \(availableTrainers.count) trainer device(s)"
    }

    func scanForBluetoothHeartRateDevices() async {
        heartRateSource = .bluetooth
        availableHeartRateDevices = await bluetoothManager.scanForDevices(kind: .heartRate)
        statusMessage = availableHeartRateDevices.isEmpty ? "No heart-rate broadcasts found" : "Found \(availableHeartRateDevices.count) heart-rate device(s)"
    }

    func connectBluetoothTrainer(_ device: DeviceDescriptor) async {
        do {
            try await bluetoothManager.connectTrainer(device)
            guard let service = bluetoothManager.connectedTrainerService else { return }
            trainerSource = .bluetooth
            trainerService = service
            engine.replaceTrainerService(service)
            statusMessage = "Connected to \(device.name)"
        } catch {
            statusMessage = "Trainer connection failed: \(error.localizedDescription)"
        }
    }

    func connectBluetoothHeartRate(_ device: DeviceDescriptor) async {
        do {
            try await bluetoothManager.connectHeartRate(device)
            guard let service = bluetoothManager.connectedHeartRateService else { return }
            heartRateSource = .bluetooth
            heartRateService = service
            engine.replaceHeartRateService(service)
            statusMessage = "Connected to \(device.name)"
        } catch {
            statusMessage = "Heart-rate connection failed: \(error.localizedDescription)"
        }
    }

    func useSimulationTrainer() async {
        await bluetoothManager.disconnectTrainer()
        availableTrainers = await simulationBluetoothManager.scanForDevices(kind: .trainer)
        if let trainer = availableTrainers.first {
            try? await simulationBluetoothManager.connectTrainer(trainer)
        }
        trainerSource = .simulation
        trainerService = MockTrainerService()
        engine.replaceTrainerService(trainerService)
        statusMessage = "Using simulated trainer"
    }

    func useSimulationHeartRate() async {
        await bluetoothManager.disconnectHeartRate()
        availableHeartRateDevices = await simulationBluetoothManager.scanForDevices(kind: .heartRate)
        if let heartRate = availableHeartRateDevices.first {
            try? await simulationBluetoothManager.connectHeartRate(heartRate)
        }
        heartRateSource = .simulation
        heartRateService = MockHeartRateService()
        engine.replaceHeartRateService(heartRateService)
        statusMessage = "Using simulated heart-rate broadcast"
    }

    func importWorkout(from url: URL) {
        do {
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            let importedWorkout = try parser.parseWorkout(from: data, ftp: workout.ftp)
            addWorkout(importedWorkout)
            selectWorkout(importedWorkout)
            statusMessage = "Imported and saved \(importedWorkout.name)"
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func selectWorkout(_ selected: Workout) {
        guard workout.id != selected.id else { return }
        selectedWorkoutID = selected.id
        replaceWorkout(selected)
        statusMessage = "Loaded \(selected.name)"
    }

    func exportCSV() {
        do {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "\(workout.name.safeFilename)-samples.csv"
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let url = panel.url else { return }
            try engine.exportCSV().write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported CSV to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportJSON() {
        do {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "\(workout.name.safeFilename)-samples.json"
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let url = panel.url else { return }
            try engine.exportJSON().write(to: url)
            statusMessage = "Exported JSON to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func replaceWorkout(_ newWorkout: Workout) {
        engine.stop()
        workout = newWorkout
        selectedWorkoutID = newWorkout.id
        rebuildEngine()
    }

    private func rebuildEngine() {
        engine.stop()
        engine = WorkoutEngine(
            workout: workout,
            trainerService: trainerService,
            heartRateService: heartRateService,
            recorder: DataRecorder()
        )
    }

    private func addWorkout(_ newWorkout: Workout) {
        workouts.removeAll { $0.id == newWorkout.id }
        workouts.append(newWorkout)
        do {
            try libraryStore.saveWorkouts(workouts)
        } catch {
            statusMessage = "Workout imported but saving failed: \(error.localizedDescription)"
        }
    }
}

private extension String {
    var safeFilename: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: invalid).joined(separator: "-")
    }
}
