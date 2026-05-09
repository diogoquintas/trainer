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
    @Published var athleteProfile: AthleteProfile
    @Published var trainerControlMode: TrainerControlMode = .erg
    @Published var manualVirtualGear: Int = 3
    @Published var isUploadingToStrava = false
    @Published var isConnectingStrava = false
    @Published var isStravaConnected = false
    @Published var trainerCommunicationLog: [TrainerCommunicationLogEntry] = []

    private static let athleteProfileDefaultsKey = "trainer.athleteProfile"

    private let simulationBluetoothManager: MockBluetoothManager
    private let bluetoothManager: CoreBluetoothManager
    private let parser: WorkoutParsing
    private let libraryStore: WorkoutLibraryStore
    private let stravaService: StravaServicing
    private var trainerService: any TrainerServicing
    private var heartRateService: any HeartRateServicing

    init() {
        let athleteProfile = Self.loadAthleteProfile()
        let libraryStore = WorkoutLibraryStore()
        var workouts = libraryStore.loadWorkouts()
        if workouts.isEmpty {
            workouts = [Workout.sample(ftp: athleteProfile.ftp)]
            try? libraryStore.saveWorkouts(workouts)
        }

        var workout = workouts.first ?? Workout.sample(ftp: athleteProfile.ftp)
        workout.ftp = athleteProfile.ftp
        let trainer = MockTrainerService()
        let heartRate = MockHeartRateService()
        let recorder = DataRecorder()

        self.athleteProfile = athleteProfile
        self.workouts = workouts
        self.selectedWorkoutID = workout.id
        self.workout = workout
        self.engine = WorkoutEngine(
            workout: workout,
            trainerService: trainer,
            heartRateService: heartRate,
            recorder: recorder,
            trainerControlMode: .erg,
            manualVirtualGear: 3
        )
        self.simulationBluetoothManager = MockBluetoothManager()
        self.bluetoothManager = CoreBluetoothManager()
        self.trainerService = trainer
        self.heartRateService = heartRate
        self.parser = ZWOParser()
        self.libraryStore = libraryStore
        self.stravaService = StravaService()
        self.isStravaConnected = self.stravaService.isConnected
        self.bluetoothManager.trainerCommunicationHandler = { [weak self] entry in
            Task { @MainActor in
                self?.appendTrainerCommunicationLog(entry)
            }
        }
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
            let importedWorkout = try parser.parseWorkout(from: data, ftp: athleteProfile.ftp)
            addWorkout(importedWorkout)
            selectWorkout(importedWorkout)
            statusMessage = "Imported and saved \(importedWorkout.name)"
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func selectWorkout(_ selected: Workout) {
        var selectedWorkout = selected
        selectedWorkout.ftp = athleteProfile.ftp

        guard workout.id != selectedWorkout.id || workout.ftp != selectedWorkout.ftp else { return }
        workouts = workouts.map { $0.id == selectedWorkout.id ? selectedWorkout : $0 }
        try? libraryStore.saveWorkouts(workouts)
        selectedWorkoutID = selectedWorkout.id
        replaceWorkout(selectedWorkout)
        statusMessage = "Loaded \(selectedWorkout.name)"
    }

    func selectWorkout(id: Workout.ID) {
        guard let selected = workouts.first(where: { $0.id == id }) else {
            selectedWorkoutID = workout.id
            return
        }

        selectWorkout(selected)
    }

    func removeSelectedWorkout() {
        removeWorkout(id: selectedWorkoutID)
    }

    func removeWorkout(id: Workout.ID) {
        guard let removedIndex = workouts.firstIndex(where: { $0.id == id }) else { return }

        let previousWorkouts = workouts
        let removedWorkout = workouts[removedIndex]
        workouts.remove(at: removedIndex)

        if workouts.isEmpty {
            workouts = [Workout.sample(ftp: athleteProfile.ftp)]
        }

        do {
            try libraryStore.saveWorkouts(workouts)
        } catch {
            statusMessage = "Removing \(removedWorkout.name) failed: \(error.localizedDescription)"
            workouts = previousWorkouts
            selectedWorkoutID = workout.id
            return
        }

        if workout.id == id || !workouts.contains(where: { $0.id == selectedWorkoutID }) {
            let replacementIndex = min(removedIndex, workouts.count - 1)
            var replacement = workouts[replacementIndex]
            replacement.ftp = athleteProfile.ftp
            workouts[replacementIndex] = replacement
            replaceWorkout(replacement)
        }

        statusMessage = "Removed \(removedWorkout.name)"
    }

    func updateAthleteProfile(_ profile: AthleteProfile) {
        let previousFTP = athleteProfile.ftp
        athleteProfile = profile.sanitized
        saveAthleteProfile()
        applyAthleteFTPToCurrentWorkout(previousFTP: previousFTP)
    }

    func setTrainerControlMode(_ mode: TrainerControlMode) {
        trainerControlMode = mode
        engine.setTrainerControlMode(mode)
        statusMessage = mode == .off ? "Trainer control off" : "\(mode.displayName) trainer control enabled"
    }

    func shiftVirtualGear(by offset: Int) {
        setManualVirtualGear(manualVirtualGear + offset)
    }

    func setManualVirtualGear(_ gear: Int) {
        manualVirtualGear = gear.clamped(to: WorkoutEngine.virtualGearRange)
        engine.setManualVirtualGear(manualVirtualGear)
        if trainerControlMode == .resistance {
            statusMessage = "Virtual gear \(manualVirtualGear)"
        }
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

    func exportWorkoutProgressImage() {
        do {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "\(workout.name.safeFilename)-progress.png"
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let url = panel.url else { return }
            try renderWorkoutProgressImageData().write(to: url, options: .atomic)
            statusMessage = "Exported progress image to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Image export failed: \(error.localizedDescription)"
        }
    }

    func connectStrava() async {
        guard !isConnectingStrava else { return }
        isConnectingStrava = true
        statusMessage = "Connecting to Strava..."
        defer { isConnectingStrava = false }

        do {
            try await stravaService.connect()
            isStravaConnected = stravaService.isConnected
            statusMessage = "Connected to Strava"
        } catch {
            statusMessage = "Strava connection failed: \(error.localizedDescription)"
        }
    }

    func uploadWorkoutToStrava() async {
        guard !isUploadingToStrava else { return }
        isUploadingToStrava = true
        statusMessage = "Uploading \(workout.name) to Strava..."
        defer { isUploadingToStrava = false }

        do {
            _ = try? renderStravaSummaryImage()
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(workout.name.safeFilename)-\(UUID().uuidString).tcx")
            try engine.exportTCX().write(to: fileURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let upload = try await stravaService.uploadActivity(
                fileURL: fileURL,
                name: workout.name,
                description: stravaDescription
            )
            isStravaConnected = stravaService.isConnected

            if let error = upload.error, !error.isEmpty {
                statusMessage = "Strava is processing the upload but reported: \(error)"
            } else if let activityID = upload.activityID {
                statusMessage = "Uploaded to Strava activity \(activityID)"
            } else {
                statusMessage = upload.status.map { "Strava upload queued: \($0)" } ?? "Strava upload queued"
            }
        } catch {
            statusMessage = "Strava upload failed: \(error.localizedDescription)"
        }
    }

    func copyTrainerCommunicationLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formattedTrainerCommunicationLog, forType: .string)
        statusMessage = "Copied trainer communication log"
    }

    func clearTrainerCommunicationLog() {
        trainerCommunicationLog = []
        statusMessage = "Cleared trainer communication log"
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
            recorder: DataRecorder(),
            trainerControlMode: trainerControlMode,
            manualVirtualGear: manualVirtualGear
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

    private var stravaDescription: String {
        [
            workout.description,
            "Uploaded from Trainer."
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private func renderStravaSummaryImage() throws -> URL {
        let imageData = try renderWorkoutProgressImageData()
        let directoryURL = try stravaSummaryImageDirectory()
        let imageURL = directoryURL
            .appendingPathComponent("\(workout.name.safeFilename)-strava-summary-\(Self.exportDateFormatter.string(from: Date())).png")
        try imageData.write(to: imageURL, options: .atomic)

        return imageURL
    }

    private func renderWorkoutProgressImageData() throws -> Data {
        try WorkoutSummaryImageRenderer.renderPNG(workout: workout, samples: engine.samples)
    }

    private func stravaSummaryImageDirectory() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = documentsURL.appendingPathComponent("trainer", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private var formattedTrainerCommunicationLog: String {
        guard !trainerCommunicationLog.isEmpty else { return "Trainer communication log is empty." }
        return trainerCommunicationLog.map { entry in
            "\(Self.logDateFormatter.string(from: entry.timestamp)) [\(entry.direction.rawValue)] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    private func appendTrainerCommunicationLog(_ entry: TrainerCommunicationLogEntry) {
        trainerCommunicationLog.append(entry)
        if trainerCommunicationLog.count > 500 {
            trainerCommunicationLog.removeFirst(trainerCommunicationLog.count - 500)
        }
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func loadAthleteProfile() -> AthleteProfile {
        guard let data = UserDefaults.standard.data(forKey: athleteProfileDefaultsKey),
              let profile = try? JSONDecoder().decode(AthleteProfile.self, from: data) else {
            return AthleteProfile()
        }
        return profile.sanitized
    }

    private func saveAthleteProfile() {
        guard let data = try? JSONEncoder().encode(athleteProfile) else { return }
        UserDefaults.standard.set(data, forKey: Self.athleteProfileDefaultsKey)
    }

    private func applyAthleteFTPToCurrentWorkout(previousFTP: Int) {
        guard athleteProfile.ftp != previousFTP else { return }

        guard engine.state == .stopped || engine.state == .finished else {
            statusMessage = "FTP saved. It will apply to workout targets after this ride."
            return
        }

        var updatedWorkout = workout
        updatedWorkout.ftp = athleteProfile.ftp
        workouts = workouts.map { $0.id == updatedWorkout.id ? updatedWorkout : $0 }
        try? libraryStore.saveWorkouts(workouts)
        replaceWorkout(updatedWorkout)
        statusMessage = "FTP updated to \(athleteProfile.ftp) W"
    }
}

private extension String {
    var safeFilename: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: invalid).joined(separator: "-")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
