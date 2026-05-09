import CoreBluetooth
import Foundation

@MainActor
final class CoreBluetoothManager: NSObject, ObservableObject, BluetoothManaging {
    @Published private(set) var trainerConnectionState: DeviceConnectionState = .disconnected
    @Published private(set) var heartRateConnectionState: DeviceConnectionState = .disconnected

    private let central: CBCentralManager
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var discoveredDevices: [DeviceKind: [DeviceDescriptor]] = [:]
    private var scanContinuation: CheckedContinuation<[DeviceDescriptor], Never>?
    private var scannedKind: DeviceKind?
    private var scanTask: Task<Void, Never>?
    private var pendingConnections: [UUID: (DeviceKind, CheckedContinuation<Void, Error>)] = [:]

    var trainerCommunicationHandler: ((TrainerCommunicationLogEntry) -> Void)?

    private(set) var connectedTrainerService: BluetoothTrainerService?
    private(set) var connectedHeartRateService: BluetoothHeartRateService?

    override init() {
        central = CBCentralManager(delegate: nil, queue: .main)
        super.init()
        central.delegate = self
    }

    func scanForDevices(kind: DeviceKind) async -> [DeviceDescriptor] {
        guard central.state == .poweredOn else {
            setState(.failed(bluetoothStateMessage), for: kind)
            return []
        }

        scanTask?.cancel()
        scanContinuation?.resume(returning: discoveredDevices[kind] ?? [])
        scanContinuation = nil

        setState(.scanning, for: kind)
        discoveredDevices[kind] = []
        scannedKind = kind
        central.scanForPeripherals(withServices: serviceUUIDs(for: kind), options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        return await withCheckedContinuation { continuation in
            scanContinuation = continuation
            scanTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                await MainActor.run {
                    self?.finishScan()
                }
            }
        }
    }

    func connectTrainer(_ device: DeviceDescriptor) async throws {
        try await connect(device, kind: .trainer)
    }

    func connectHeartRate(_ device: DeviceDescriptor) async throws {
        try await connect(device, kind: .heartRate)
    }

    func disconnectTrainer() async {
        disconnect(kind: .trainer)
    }

    func disconnectHeartRate() async {
        disconnect(kind: .heartRate)
    }

    private func connect(_ device: DeviceDescriptor, kind: DeviceKind) async throws {
        guard let peripheral = discoveredPeripherals[device.id] else {
            setState(.failed("Device is no longer available"), for: kind)
            throw BluetoothDeviceError.deviceUnavailable
        }

        setState(.connecting(device.name), for: kind)
        try await withCheckedThrowingContinuation { continuation in
            pendingConnections[peripheral.identifier] = (kind, continuation)
            central.connect(peripheral, options: nil)
        }
    }

    private func disconnect(kind: DeviceKind) {
        switch kind {
        case .trainer:
            if let peripheral = connectedTrainerService?.peripheral {
                central.cancelPeripheralConnection(peripheral)
            }
            connectedTrainerService = nil
            trainerConnectionState = .disconnected
        case .heartRate:
            if let peripheral = connectedHeartRateService?.peripheral {
                central.cancelPeripheralConnection(peripheral)
            }
            connectedHeartRateService = nil
            heartRateConnectionState = .disconnected
        }
    }

    private func finishScan() {
        guard let kind = scannedKind else { return }
        central.stopScan()
        scanTask?.cancel()
        scanTask = nil
        scannedKind = nil
        if case .scanning = state(for: kind) {
            setState(.disconnected, for: kind)
        }
        scanContinuation?.resume(returning: discoveredDevices[kind] ?? [])
        scanContinuation = nil
    }

    private func serviceUUIDs(for kind: DeviceKind) -> [CBUUID] {
        switch kind {
        case .trainer:
            [
                BluetoothUUIDs.fitnessMachineService,
                BluetoothUUIDs.cyclingPowerService
            ]
        case .heartRate:
            [BluetoothUUIDs.heartRateService]
        }
    }

    private var bluetoothStateMessage: String {
        switch central.state {
        case .poweredOn:
            "Bluetooth is ready"
        case .poweredOff:
            "Bluetooth is powered off"
        case .unauthorized:
            "Bluetooth permission was not granted"
        case .unsupported:
            "Bluetooth LE is not supported on this Mac"
        case .resetting:
            "Bluetooth is resetting"
        case .unknown:
            "Bluetooth is not ready yet"
        @unknown default:
            "Bluetooth is unavailable"
        }
    }

    private func state(for kind: DeviceKind) -> DeviceConnectionState {
        switch kind {
        case .trainer:
            trainerConnectionState
        case .heartRate:
            heartRateConnectionState
        }
    }

    private func setState(_ state: DeviceConnectionState, for kind: DeviceKind) {
        switch kind {
        case .trainer:
            trainerConnectionState = state
        case .heartRate:
            heartRateConnectionState = state
        }
    }
}

extension CoreBluetoothManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state != .poweredOn else { return }
        let message = bluetoothStateMessage
        trainerConnectionState = .failed(message)
        heartRateConnectionState = .failed(message)
        finishScan()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let kind = scannedKind else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unnamed \(kind == .trainer ? "Trainer" : "Heart Rate")"
        let device = DeviceDescriptor(
            id: peripheral.identifier,
            name: name,
            kind: kind,
            rssi: RSSI.intValue,
            source: .bluetooth
        )

        discoveredPeripherals[peripheral.identifier] = peripheral
        var devices = discoveredDevices[kind] ?? []
        devices.removeAll { $0.id == device.id }
        devices.append(device)
        devices.sort { ($0.rssi ?? -127) > ($1.rssi ?? -127) }
        discoveredDevices[kind] = devices
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let (kind, continuation) = pendingConnections.removeValue(forKey: peripheral.identifier) else { return }
        peripheral.delegate = self

        switch kind {
        case .trainer:
            let device = discoveredDevices[.trainer]?.first { $0.id == peripheral.identifier }
                ?? DeviceDescriptor(id: peripheral.identifier, name: peripheral.name ?? "Smart Trainer", kind: .trainer, source: .bluetooth)
            let service = BluetoothTrainerService(
                device: device,
                peripheral: peripheral,
                logHandler: { [weak self] entry in
                    self?.trainerCommunicationHandler?(entry)
                }
            )
            connectedTrainerService = service
            trainerConnectionState = .connected(device)
            service.discover()
        case .heartRate:
            let device = discoveredDevices[.heartRate]?.first { $0.id == peripheral.identifier }
                ?? DeviceDescriptor(id: peripheral.identifier, name: peripheral.name ?? "Heart Rate", kind: .heartRate, source: .bluetooth)
            let service = BluetoothHeartRateService(device: device, peripheral: peripheral)
            connectedHeartRateService = service
            heartRateConnectionState = .connected(device)
            service.discover()
        }

        continuation.resume()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let (kind, continuation) = pendingConnections.removeValue(forKey: peripheral.identifier) else { return }
        let message = error?.localizedDescription ?? "Could not connect"
        setState(.failed(message), for: kind)
        continuation.resume(throwing: error ?? BluetoothDeviceError.connectionFailed(message))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedTrainerService?.peripheral.identifier == peripheral.identifier {
            connectedTrainerService = nil
            trainerConnectionState = error.map { .failed($0.localizedDescription) } ?? .disconnected
        }

        if connectedHeartRateService?.peripheral.identifier == peripheral.identifier {
            connectedHeartRateService = nil
            heartRateConnectionState = error.map { .failed($0.localizedDescription) } ?? .disconnected
        }
    }
}

extension CoreBluetoothManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if connectedTrainerService?.peripheral.identifier == peripheral.identifier {
            connectedTrainerService?.handleDiscoveredServices(error: error)
        }
        if connectedHeartRateService?.peripheral.identifier == peripheral.identifier {
            connectedHeartRateService?.handleDiscoveredServices(error: error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if connectedTrainerService?.peripheral.identifier == peripheral.identifier {
            connectedTrainerService?.handleDiscoveredCharacteristics(for: service, error: error)
        }
        if connectedHeartRateService?.peripheral.identifier == peripheral.identifier {
            connectedHeartRateService?.handleDiscoveredCharacteristics(for: service, error: error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if connectedTrainerService?.peripheral.identifier == peripheral.identifier {
            connectedTrainerService?.handleUpdatedValue(for: characteristic, error: error)
        }
        if connectedHeartRateService?.peripheral.identifier == peripheral.identifier {
            connectedHeartRateService?.handleUpdatedValue(for: characteristic, error: error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if connectedTrainerService?.peripheral.identifier == peripheral.identifier {
            connectedTrainerService?.handleUpdatedNotificationState(for: characteristic, error: error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if connectedTrainerService?.peripheral.identifier == peripheral.identifier {
            connectedTrainerService?.handleWrite(for: characteristic, error: error)
        }
    }
}

enum BluetoothDeviceError: LocalizedError {
    case deviceUnavailable
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            "Device is no longer available"
        case .connectionFailed(let message):
            message
        }
    }
}

enum BluetoothUUIDs {
    static let fitnessMachineService = CBUUID(string: "1826")
    static let fitnessMachineFeature = CBUUID(string: "2ACC")
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let supportedResistanceLevelRange = CBUUID(string: "2AD6")
    static let supportedPowerRange = CBUUID(string: "2AD8")
    static let fitnessMachineControlPoint = CBUUID(string: "2AD9")
    static let cyclingPowerService = CBUUID(string: "1818")
    static let cyclingPowerMeasurement = CBUUID(string: "2A63")
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
}
