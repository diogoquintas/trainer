import Foundation

enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case trainer
    case heartRate

    var id: String { rawValue }
}

enum DeviceSource: String, Codable, CaseIterable, Identifiable {
    case simulation
    case bluetooth

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .simulation:
            "Simulation"
        case .bluetooth:
            "Bluetooth"
        }
    }
}

enum DeviceConnectionState: Equatable, Codable {
    case disconnected
    case scanning
    case connecting(String)
    case connected(DeviceDescriptor)
    case failed(String)

    var displayText: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .scanning:
            "Scanning"
        case .connecting(let name):
            "Connecting to \(name)"
        case .connected(let device):
            "Connected to \(device.name)"
        case .failed(let message):
            "Failed: \(message)"
        }
    }
}

struct DeviceDescriptor: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let kind: DeviceKind
    let rssi: Int?
    let source: DeviceSource

    init(id: UUID = UUID(), name: String, kind: DeviceKind, rssi: Int? = nil, source: DeviceSource = .simulation) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rssi = rssi
        self.source = source
    }
}

struct TrainerReading: Equatable, Codable {
    let timestamp: Date
    let powerWatts: Int?
    let cadenceRPM: Int?
    let speedMetersPerSecond: Double?

    init(timestamp: Date = Date(), powerWatts: Int?, cadenceRPM: Int?, speedMetersPerSecond: Double? = nil) {
        self.timestamp = timestamp
        self.powerWatts = powerWatts
        self.cadenceRPM = cadenceRPM
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

struct HeartRateReading: Equatable, Codable {
    let timestamp: Date
    let bpm: Int

    init(timestamp: Date = Date(), bpm: Int) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}
