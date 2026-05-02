import Foundation

actor MockHeartRateService: HeartRateServicing {
    nonisolated let readings: AsyncStream<HeartRateReading>

    private let continuation: AsyncStream<HeartRateReading>.Continuation
    private var task: Task<Void, Never>?
    private var bpm = 118.0

    nonisolated var connectionState: DeviceConnectionState {
        .connected(DeviceDescriptor(name: "Garmin HR Broadcast Simulator", kind: .heartRate, rssi: -55, source: .simulation))
    }

    init() {
        var capturedContinuation: AsyncStream<HeartRateReading>.Continuation?
        readings = AsyncStream { continuation in
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

    func setIntensityHint(powerTargetWatts: Int?) {
        let targetHR = switch powerTargetWatts ?? 140 {
        case ..<140: 124.0
        case 140..<190: 142.0
        case 190..<240: 156.0
        default: 168.0
        }
        bpm += (targetHR - bpm) * 0.08
    }

    private func emitReading() {
        bpm += Double.random(in: -0.16...0.2)
        continuation.yield(HeartRateReading(bpm: max(80, Int(bpm.rounded()))))
    }
}
