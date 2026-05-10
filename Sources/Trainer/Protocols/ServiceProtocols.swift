import Foundation

@MainActor
protocol BluetoothManaging: AnyObject {
    var trainerConnectionState: DeviceConnectionState { get }
    var heartRateConnectionState: DeviceConnectionState { get }

    func scanForDevices(kind: DeviceKind) async -> [DeviceDescriptor]
    func connectTrainer(_ device: DeviceDescriptor) async throws
    func connectHeartRate(_ device: DeviceDescriptor) async throws
    func disconnectTrainer() async
    func disconnectHeartRate() async
}

protocol TrainerServicing: AnyObject {
    var readings: AsyncStream<TrainerReading> { get }
    var connectionState: DeviceConnectionState { get }

    func start() async
    func stop() async
    func setERGTarget(watts: Int) async throws
    func setResistanceLevel(_ level: Double) async throws
    func releaseControl() async throws
}

protocol HeartRateServicing: AnyObject {
    var readings: AsyncStream<HeartRateReading> { get }
    var connectionState: DeviceConnectionState { get }

    func start() async
    func stop() async
}

protocol WorkoutParsing {
    func parseWorkout(from data: Data, ftp: Int) throws -> Workout
}

protocol DataRecording {
    func reset()
    func append(_ sample: WorkoutSample)
    func samples() -> [WorkoutSample]
    func exportJSON() throws -> Data
    func exportCSV() throws -> String
    func exportTCX(workout: Workout) throws -> Data
}

protocol StravaServicing {
    var isConnected: Bool { get }

    func connect() async throws
    func uploadActivity(fileURL: URL, name: String, description: String?) async throws -> StravaUpload
}

@MainActor
protocol WorkoutNotifying: AnyObject {
    var debugHandler: ((String) -> Void)? { get set }

    func requestAuthorizationIfNeeded() async
    func notificationDebugStatus() async -> String
    func sendWorkoutNotification(title: String, body: String) async -> String
}
