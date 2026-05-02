import CoreBluetooth
import Foundation

@MainActor
final class BluetoothTrainerService: TrainerServicing {
    nonisolated let readings: AsyncStream<TrainerReading>
    let peripheral: CBPeripheral

    private let device: DeviceDescriptor
    private let continuation: AsyncStream<TrainerReading>.Continuation
    private var indoorBikeData: CBCharacteristic?
    private var cyclingPowerMeasurement: CBCharacteristic?
    private var controlPoint: CBCharacteristic?
    private var latestReading = TrainerReading(powerWatts: nil, cadenceRPM: nil)
    private var requestedControl = false

    nonisolated var connectionState: DeviceConnectionState {
        .connected(device)
    }

    init(device: DeviceDescriptor, peripheral: CBPeripheral) {
        self.device = device
        self.peripheral = peripheral

        var capturedContinuation: AsyncStream<TrainerReading>.Continuation?
        readings = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func start() async {
        enableNotifications()
    }

    func stop() async {
        if let indoorBikeData {
            peripheral.setNotifyValue(false, for: indoorBikeData)
        }
        if let cyclingPowerMeasurement {
            peripheral.setNotifyValue(false, for: cyclingPowerMeasurement)
        }
    }

    func setERGTarget(watts: Int) async throws {
        guard let controlPoint else { return }
        if !requestedControl {
            requestedControl = true
            peripheral.writeValue(Data([0x00]), for: controlPoint, type: .withResponse)
        }

        let clampedWatts = Int16(max(0, min(watts, Int(Int16.max))))
        var payload = Data([0x05])
        payload.appendLittleEndian(clampedWatts)
        peripheral.writeValue(payload, for: controlPoint, type: .withResponse)
    }

    func discover() {
        peripheral.discoverServices([
            BluetoothUUIDs.fitnessMachineService,
            BluetoothUUIDs.cyclingPowerService
        ])
    }

    func handleDiscoveredServices(error: Error?) {
        guard error == nil else { return }
        peripheral.services?.forEach { service in
            switch service.uuid {
            case BluetoothUUIDs.fitnessMachineService:
                peripheral.discoverCharacteristics([
                    BluetoothUUIDs.indoorBikeData,
                    BluetoothUUIDs.fitnessMachineControlPoint
                ], for: service)
            case BluetoothUUIDs.cyclingPowerService:
                peripheral.discoverCharacteristics([
                    BluetoothUUIDs.cyclingPowerMeasurement
                ], for: service)
            default:
                break
            }
        }
    }

    func handleDiscoveredCharacteristics(for service: CBService, error: Error?) {
        guard error == nil else { return }
        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case BluetoothUUIDs.indoorBikeData:
                indoorBikeData = characteristic
            case BluetoothUUIDs.cyclingPowerMeasurement:
                cyclingPowerMeasurement = characteristic
            case BluetoothUUIDs.fitnessMachineControlPoint:
                controlPoint = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        enableNotifications()
    }

    func handleUpdatedValue(for characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BluetoothUUIDs.indoorBikeData:
            if let reading = TrainerReading(indoorBikeData: data, fallback: latestReading) {
                latestReading = reading
                continuation.yield(reading)
            }
        case BluetoothUUIDs.cyclingPowerMeasurement:
            if let powerWatts = data.cyclingPowerWatts {
                let reading = TrainerReading(
                    powerWatts: powerWatts,
                    cadenceRPM: latestReading.cadenceRPM,
                    speedMetersPerSecond: latestReading.speedMetersPerSecond
                )
                latestReading = reading
                continuation.yield(reading)
            }
        default:
            break
        }
    }

    private func enableNotifications() {
        if let indoorBikeData {
            peripheral.setNotifyValue(true, for: indoorBikeData)
        }
        if let cyclingPowerMeasurement {
            peripheral.setNotifyValue(true, for: cyclingPowerMeasurement)
        }
    }
}

@MainActor
final class BluetoothHeartRateService: HeartRateServicing {
    nonisolated let readings: AsyncStream<HeartRateReading>
    let peripheral: CBPeripheral

    private let device: DeviceDescriptor
    private let continuation: AsyncStream<HeartRateReading>.Continuation
    private var measurement: CBCharacteristic?

    nonisolated var connectionState: DeviceConnectionState {
        .connected(device)
    }

    init(device: DeviceDescriptor, peripheral: CBPeripheral) {
        self.device = device
        self.peripheral = peripheral

        var capturedContinuation: AsyncStream<HeartRateReading>.Continuation?
        readings = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func start() async {
        if let measurement {
            peripheral.setNotifyValue(true, for: measurement)
        }
    }

    func stop() async {
        if let measurement {
            peripheral.setNotifyValue(false, for: measurement)
        }
    }

    func discover() {
        peripheral.discoverServices([BluetoothUUIDs.heartRateService])
    }

    func handleDiscoveredServices(error: Error?) {
        guard error == nil else { return }
        peripheral.services?.forEach { service in
            guard service.uuid == BluetoothUUIDs.heartRateService else { return }
            peripheral.discoverCharacteristics([BluetoothUUIDs.heartRateMeasurement], for: service)
        }
    }

    func handleDiscoveredCharacteristics(for service: CBService, error: Error?) {
        guard error == nil, service.uuid == BluetoothUUIDs.heartRateService else { return }
        measurement = service.characteristics?.first { $0.uuid == BluetoothUUIDs.heartRateMeasurement }
        if let measurement {
            peripheral.setNotifyValue(true, for: measurement)
        }
    }

    func handleUpdatedValue(for characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == BluetoothUUIDs.heartRateMeasurement,
              let bpm = characteristic.value?.heartRateBPM
        else { return }
        continuation.yield(HeartRateReading(bpm: bpm))
    }
}

private extension TrainerReading {
    init?(indoorBikeData data: Data, fallback: TrainerReading) {
        guard data.count >= 2 else { return nil }
        let flags = data.uint16(at: 0)
        var offset = 2
        var speedMetersPerSecond = fallback.speedMetersPerSecond
        var cadenceRPM = fallback.cadenceRPM
        var powerWatts = fallback.powerWatts

        let hasMoreData = flags & (1 << 0) != 0
        if !hasMoreData, let rawSpeed = data.safeUInt16(at: offset) {
            speedMetersPerSecond = (Double(rawSpeed) * 0.01) / 3.6
            offset += 2
        }

        if flags & (1 << 1) != 0 {
            offset += 2
        }

        if flags & (1 << 2) != 0, let rawCadence = data.safeUInt16(at: offset) {
            cadenceRPM = Int((Double(rawCadence) * 0.5).rounded())
            offset += 2
        }

        if flags & (1 << 3) != 0 {
            offset += 2
        }

        if flags & (1 << 4) != 0 {
            offset += 3
        }

        if flags & (1 << 5) != 0 {
            offset += 2
        }

        if flags & (1 << 6) != 0, let rawPower = data.safeInt16(at: offset) {
            powerWatts = Int(rawPower)
        }

        self.init(powerWatts: powerWatts, cadenceRPM: cadenceRPM, speedMetersPerSecond: speedMetersPerSecond)
    }
}

private extension Data {
    var heartRateBPM: Int? {
        guard count >= 2 else { return nil }
        let flags = self[startIndex]
        if flags & 0x01 == 0 {
            return Int(self[index(startIndex, offsetBy: 1)])
        }
        guard count >= 3 else { return nil }
        return Int(uint16(at: 1))
    }

    var cyclingPowerWatts: Int? {
        guard count >= 4 else { return nil }
        return Int(int16(at: 2))
    }

    mutating func appendLittleEndian(_ value: Int16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    func safeUInt16(at offset: Int) -> UInt16? {
        guard offset + 1 < count else { return nil }
        return uint16(at: offset)
    }

    func safeInt16(at offset: Int) -> Int16? {
        guard offset + 1 < count else { return nil }
        return int16(at: offset)
    }

    func uint16(at offset: Int) -> UInt16 {
        let low = UInt16(self[index(startIndex, offsetBy: offset)])
        let high = UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8
        return low | high
    }

    func int16(at offset: Int) -> Int16 {
        Int16(bitPattern: uint16(at: offset))
    }
}

