import Foundation

@MainActor
final class MockBluetoothManager: ObservableObject, BluetoothManaging {
    @Published private(set) var trainerConnectionState: DeviceConnectionState = .disconnected
    @Published private(set) var heartRateConnectionState: DeviceConnectionState = .disconnected

    func scanForDevices(kind: DeviceKind) async -> [DeviceDescriptor] {
        switch kind {
        case .trainer:
            trainerConnectionState = .scanning
            try? await Task.sleep(for: .milliseconds(350))
            trainerConnectionState = .disconnected
            return [
                DeviceDescriptor(name: "Wahoo KICKR CORE Simulator", kind: .trainer, rssi: -48, source: .simulation)
            ]
        case .heartRate:
            heartRateConnectionState = .scanning
            try? await Task.sleep(for: .milliseconds(350))
            heartRateConnectionState = .disconnected
            return [
                DeviceDescriptor(name: "Garmin HR Broadcast Simulator", kind: .heartRate, rssi: -55, source: .simulation)
            ]
        }
    }

    func connectTrainer(_ device: DeviceDescriptor) async throws {
        trainerConnectionState = .connecting(device.name)
        try? await Task.sleep(for: .milliseconds(250))
        trainerConnectionState = .connected(device)
    }

    func connectHeartRate(_ device: DeviceDescriptor) async throws {
        heartRateConnectionState = .connecting(device.name)
        try? await Task.sleep(for: .milliseconds(250))
        heartRateConnectionState = .connected(device)
    }

    func disconnectTrainer() async {
        trainerConnectionState = .disconnected
    }

    func disconnectHeartRate() async {
        heartRateConnectionState = .disconnected
    }
}
