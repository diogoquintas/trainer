import Foundation

actor MockTrainerService: TrainerServicing {
    nonisolated let readings: AsyncStream<TrainerReading>

    private let continuation: AsyncStream<TrainerReading>.Continuation
    private var task: Task<Void, Never>?
    private var targetWatts = 140
    private var currentPower = 120.0
    private var cadence = 84.0

    nonisolated var connectionState: DeviceConnectionState {
        .connected(DeviceDescriptor(name: "Wahoo KICKR CORE Simulator", kind: .trainer, rssi: -48, source: .simulation))
    }

    init() {
        var capturedContinuation: AsyncStream<TrainerReading>.Continuation?
        readings = AsyncStream { continuation in
            continuation.onTermination = { _ in }
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func start() async {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.emitReading()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
    }

    func setERGTarget(watts: Int) async throws {
        targetWatts = watts
    }

    private func emitReading() {
        let powerDelta = Double(targetWatts) - currentPower
        currentPower += powerDelta * 0.045
        currentPower += Double.random(in: -1.0...1.0)

        let cadenceTarget = targetWatts > 210 ? 92.0 : targetWatts < 140 ? 82.0 : 88.0
        cadence += (cadenceTarget - cadence) * 0.03
        cadence += Double.random(in: -0.25...0.25)

        continuation.yield(
            TrainerReading(
                powerWatts: max(0, Int(currentPower.rounded())),
                cadenceRPM: max(0, Int(cadence.rounded())),
                speedMetersPerSecond: Double.random(in: 7.5...10.8)
            )
        )
    }
}
