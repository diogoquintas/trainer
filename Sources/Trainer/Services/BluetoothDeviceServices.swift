import CoreBluetooth
import Foundation

@MainActor
final class BluetoothTrainerService: TrainerServicing {
    nonisolated let readings: AsyncStream<TrainerReading>
    let peripheral: CBPeripheral

    private let device: DeviceDescriptor
    private let continuation: AsyncStream<TrainerReading>.Continuation
    private let logHandler: ((TrainerCommunicationLogEntry) -> Void)?
    private var indoorBikeData: CBCharacteristic?
    private var cyclingPowerMeasurement: CBCharacteristic?
    private var controlPoint: CBCharacteristic?
    private var supportedResistanceLevelRange: CBCharacteristic?
    private var supportedPowerRange: CBCharacteristic?
    private var latestReading = TrainerReading(powerWatts: nil, cadenceRPM: nil)
    private var resistanceRange: FitnessMachineResistanceRange?
    private var powerRange: FitnessMachinePowerRange?
    private var controlPointReady = false
    private var controlState: FitnessMachineControlState = .idle
    private var machineStarted = false
    private var pendingControlCommand: FitnessMachineControlCommand?
    private var activeControlCommand: FitnessMachineControlCommand?

    nonisolated var connectionState: DeviceConnectionState {
        .connected(device)
    }

    init(device: DeviceDescriptor, peripheral: CBPeripheral, logHandler: ((TrainerCommunicationLogEntry) -> Void)? = nil) {
        self.device = device
        self.peripheral = peripheral
        self.logHandler = logHandler

        var capturedContinuation: AsyncStream<TrainerReading>.Continuation?
        readings = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func start() async {
        log(.event, "Starting trainer telemetry notifications")
        enableNotifications()
    }

    func stop() async {
        log(.event, "Stopping trainer telemetry notifications")
        if let indoorBikeData {
            peripheral.setNotifyValue(false, for: indoorBikeData)
        }
        if let cyclingPowerMeasurement {
            peripheral.setNotifyValue(false, for: cyclingPowerMeasurement)
        }
        try? await releaseControl()
    }

    func setERGTarget(watts: Int) async throws {
        let boundedWatts = powerRange?.clamped(watts) ?? watts
        let clampedWatts = Int16(max(0, min(boundedWatts, Int(Int16.max))))
        var parameters = Data()
        parameters.appendLittleEndian(clampedWatts)
        log(.event, "Queue ERG target \(clampedWatts) W")
        queueControlCommand(.targetPower(parameters))
    }

    func setResistanceLevel(_ level: Double) async throws {
        let clampedLevel = min(100, max(0, level))
        let resistanceTarget = resistanceTarget(forPercent: clampedLevel)
        let parameters = resistanceTarget.payload
        log(.event, "Queue resistance \(clampedLevel.formatted(.number.precision(.fractionLength(0...1))))% (raw \(resistanceTarget.rawValue))")
        queueControlCommand(.targetResistance(parameters))
    }

    func releaseControl() async throws {
        log(.event, "Release trainer control")
        pendingControlCommand = nil
        activeControlCommand = nil
        machineStarted = false
        guard controlState == .acquired else {
            controlState = .idle
            return
        }
        writeControlCommand(.reset)
        controlState = .idle
    }

    func discover() {
        log(.event, "Discover services: FTMS, Cycling Power")
        peripheral.discoverServices([
            BluetoothUUIDs.fitnessMachineService,
            BluetoothUUIDs.cyclingPowerService
        ])
    }

    func handleDiscoveredServices(error: Error?) {
        guard error == nil else {
            log(.error, "Discover services failed: \(error?.localizedDescription ?? "unknown error")")
            return
        }
        peripheral.services?.forEach { service in
            switch service.uuid {
            case BluetoothUUIDs.fitnessMachineService:
                log(.event, "FTMS service discovered")
                peripheral.discoverCharacteristics([
                    BluetoothUUIDs.indoorBikeData,
                    BluetoothUUIDs.fitnessMachineControlPoint,
                    BluetoothUUIDs.supportedResistanceLevelRange,
                    BluetoothUUIDs.supportedPowerRange
                ], for: service)
            case BluetoothUUIDs.cyclingPowerService:
                log(.event, "Cycling Power service discovered")
                peripheral.discoverCharacteristics([
                    BluetoothUUIDs.cyclingPowerMeasurement
                ], for: service)
            default:
                break
            }
        }
    }

    func handleDiscoveredCharacteristics(for service: CBService, error: Error?) {
        guard error == nil else {
            log(.error, "Discover characteristics failed for \(service.uuid.uuidString): \(error?.localizedDescription ?? "unknown error")")
            return
        }
        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case BluetoothUUIDs.indoorBikeData:
                indoorBikeData = characteristic
                log(.event, "Indoor Bike Data characteristic discovered")
            case BluetoothUUIDs.cyclingPowerMeasurement:
                cyclingPowerMeasurement = characteristic
                log(.event, "Cycling Power Measurement characteristic discovered")
            case BluetoothUUIDs.fitnessMachineControlPoint:
                controlPoint = characteristic
                log(.event, "FTMS Control Point characteristic discovered; enabling indications")
                peripheral.setNotifyValue(true, for: characteristic)
            case BluetoothUUIDs.supportedResistanceLevelRange:
                supportedResistanceLevelRange = characteristic
                log(.event, "Supported Resistance Level Range characteristic discovered")
                peripheral.readValue(for: characteristic)
            case BluetoothUUIDs.supportedPowerRange:
                supportedPowerRange = characteristic
                log(.event, "Supported Power Range characteristic discovered")
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
        enableNotifications()
    }

    func handleUpdatedNotificationState(for characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BluetoothUUIDs.fitnessMachineControlPoint else { return }
        guard error == nil else {
            log(.error, "Control Point indication state failed: \(error?.localizedDescription ?? "unknown error")")
            return
        }
        controlPointReady = characteristic.isNotifying
        log(.event, "Control Point indications \(controlPointReady ? "enabled" : "disabled")")
        flushPendingControlCommand()
    }

    func handleWrite(for characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BluetoothUUIDs.fitnessMachineControlPoint else { return }
        if let error {
            log(.error, "Control Point write failed: \(error.localizedDescription)")
            activeControlCommand = nil
            flushPendingControlCommand()
        } else {
            log(.event, "Control Point write acknowledged by CoreBluetooth")
        }
    }

    func handleUpdatedValue(for characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            log(.error, "Characteristic update failed for \(characteristic.uuid.uuidString): \(error?.localizedDescription ?? "unknown error")")
            return
        }

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
        case BluetoothUUIDs.fitnessMachineControlPoint:
            handleControlPointResponse(data)
        case BluetoothUUIDs.supportedResistanceLevelRange:
            if let range = FitnessMachineResistanceRange(data: data) {
                resistanceRange = range
                log(.incoming, "Resistance range \(range.minimum)...\(range.maximum), increment \(range.increment) [\(data.hexString)]")
            } else {
                log(.incoming, "Unsupported resistance range payload [\(data.hexString)]")
            }
        case BluetoothUUIDs.supportedPowerRange:
            if let range = FitnessMachinePowerRange(data: data) {
                powerRange = range
                log(.incoming, "Power range \(range.minimum)...\(range.maximum) W, increment \(range.increment) W [\(data.hexString)]")
            } else {
                log(.incoming, "Unsupported power range payload [\(data.hexString)]")
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

    private func queueControlCommand(_ command: FitnessMachineControlCommand) {
        pendingControlCommand = command
        log(.event, "Queued \(command.name)")
        flushPendingControlCommand()
    }

    private func flushPendingControlCommand() {
        guard let pendingControlCommand else { return }
        guard activeControlCommand == nil else {
            log(.event, "Waiting for \(activeControlCommand?.name ?? "active command") response before sending \(pendingControlCommand.name)")
            return
        }
        guard controlPoint != nil else {
            log(.event, "Waiting for Control Point before sending \(pendingControlCommand.name)")
            return
        }
        guard controlPointReady else {
            log(.event, "Waiting for Control Point indications before sending \(pendingControlCommand.name)")
            return
        }

        switch controlState {
        case .idle:
            controlState = .requesting
            writeControlCommand(.requestControl)
        case .requesting, .starting:
            return
        case .acquired:
            if machineStarted {
                writeControlCommand(pendingControlCommand)
                self.pendingControlCommand = nil
            } else {
                controlState = .starting
                writeControlCommand(.startOrResume)
            }
        }
    }

    private func handleControlPointResponse(_ data: Data) {
        guard let response = FitnessMachineControlResponse(data: data) else {
            log(.incoming, "Control Point raw \(data.hexString)")
            return
        }
        log(.incoming, "\(response.requestName) response: \(response.resultName) [\(data.hexString)]")
        activeControlCommand = nil

        switch response.requestOpCode {
        case FitnessMachineControlCommand.requestControl.opCode:
            if response.isSuccess, pendingControlCommand != nil {
                controlState = .acquired
                flushPendingControlCommand()
            } else {
                controlState = .idle
                pendingControlCommand = nil
                if !response.isSuccess {
                    log(.error, "Trainer control was not acquired: \(response.resultName)")
                }
            }
        case FitnessMachineControlCommand.startOrResume.opCode:
            if response.isSuccess, pendingControlCommand != nil {
                machineStarted = true
                controlState = .acquired
                flushPendingControlCommand()
            } else {
                machineStarted = false
                controlState = .idle
                pendingControlCommand = nil
                if !response.isSuccess {
                    log(.error, "Trainer start/resume was rejected: \(response.resultName)")
                }
            }
        case FitnessMachineControlCommand.reset.opCode:
            machineStarted = false
            controlState = .idle
        case FitnessMachineControlCommand.targetPower(Data()).opCode,
             FitnessMachineControlCommand.targetResistance(Data()).opCode:
            if !response.isSuccess {
                log(.error, "\(response.requestName) was rejected by trainer: \(response.resultName)")
            }
        default:
            break
        }

        flushPendingControlCommand()
    }

    private func writeControlCommand(_ command: FitnessMachineControlCommand) {
        activeControlCommand = command
        writeControlPayload(command.payload, name: command.name)
    }

    private func writeControlPayload(_ payload: Data, name: String) {
        guard let controlPoint else {
            log(.event, "No Control Point available for \(name)")
            return
        }
        log(.outgoing, "\(name) [\(payload.hexString)]")
        peripheral.writeValue(payload, for: controlPoint, type: .withResponse)
    }

    private func resistanceTarget(forPercent percent: Double) -> FitnessMachineResistanceTarget {
        guard let resistanceRange else {
            return FitnessMachineResistanceTarget(rawValue: UInt16(percent.rounded()), usesUInt16: false)
        }

        let scaled = resistanceRange.minimum + ((resistanceRange.maximum - resistanceRange.minimum) * (percent / 100))
        let snapped = resistanceRange.snap(scaled)
        return FitnessMachineResistanceTarget(rawValue: UInt16(snapped.rounded()), usesUInt16: resistanceRange.requiresUInt16Payload)
    }

    private func log(_ direction: TrainerCommunicationLogEntry.Direction, _ message: String) {
        logHandler?(TrainerCommunicationLogEntry(direction: direction, message: message))
    }
}

private enum FitnessMachineControlState {
    case idle
    case requesting
    case acquired
    case starting
}

private enum FitnessMachineControlCommand {
    case requestControl
    case reset
    case targetResistance(Data)
    case targetPower(Data)
    case startOrResume

    var opCode: UInt8 {
        switch self {
        case .requestControl:
            0x00
        case .reset:
            0x01
        case .targetResistance:
            0x04
        case .targetPower:
            0x05
        case .startOrResume:
            0x07
        }
    }

    var payload: Data {
        switch self {
        case .requestControl, .reset, .startOrResume:
            return Data([opCode])
        case .targetResistance(let parameters), .targetPower(let parameters):
            var payload = Data([opCode])
            payload.append(parameters)
            return payload
        }
    }

    var name: String {
        switch self {
        case .requestControl:
            "Request Control"
        case .reset:
            "Reset"
        case .targetResistance:
            "Set Target Resistance"
        case .targetPower:
            "Set Target Power"
        case .startOrResume:
            "Start/Resume"
        }
    }
}

private struct FitnessMachineResistanceTarget {
    let rawValue: UInt16
    let usesUInt16: Bool

    var payload: Data {
        if usesUInt16 {
            var data = Data()
            data.appendLittleEndian(rawValue)
            return data
        }
        return Data([UInt8(clamping: rawValue)])
    }
}

private struct FitnessMachineResistanceRange {
    let minimum: Double
    let maximum: Double
    let increment: Double

    init?(data: Data) {
        if data.count >= 6 {
            minimum = Double(data.uint16(at: 0))
            maximum = Double(data.uint16(at: 2))
            increment = max(1, Double(data.uint16(at: 4)))
        } else if data.count >= 3 {
            minimum = Double(data[data.startIndex])
            maximum = Double(data[data.index(data.startIndex, offsetBy: 1)])
            increment = max(1, Double(data[data.index(data.startIndex, offsetBy: 2)]))
        } else {
            return nil
        }
    }

    var requiresUInt16Payload: Bool {
        maximum > Double(UInt8.max)
    }

    func snap(_ value: Double) -> Double {
        let bounded = min(maximum, max(minimum, value))
        guard increment > 0 else { return bounded }
        let steps = ((bounded - minimum) / increment).rounded()
        return min(maximum, max(minimum, minimum + (steps * increment)))
    }
}

private struct FitnessMachinePowerRange {
    let minimum: Int
    let maximum: Int
    let increment: Int

    init?(data: Data) {
        guard data.count >= 6 else { return nil }
        minimum = Int(data.uint16(at: 0))
        maximum = Int(data.uint16(at: 2))
        increment = max(1, Int(data.uint16(at: 4)))
    }

    func clamped(_ watts: Int) -> Int {
        let bounded = min(maximum, max(minimum, watts))
        let steps = Double(bounded - minimum) / Double(increment)
        return min(maximum, max(minimum, minimum + (Int(steps.rounded()) * increment)))
    }
}

private struct FitnessMachineControlResponse {
    private static let responseCode: UInt8 = 0x80
    private static let successResultCode: UInt8 = 0x01

    let requestOpCode: UInt8
    let resultCode: UInt8

    init?(data: Data) {
        guard data.count >= 3,
              data[data.startIndex] == Self.responseCode else { return nil }
        requestOpCode = data[data.index(data.startIndex, offsetBy: 1)]
        resultCode = data[data.index(data.startIndex, offsetBy: 2)]
    }

    var isSuccess: Bool {
        resultCode == Self.successResultCode
    }

    var requestName: String {
        switch requestOpCode {
        case FitnessMachineControlCommand.requestControl.opCode:
            "Request Control"
        case FitnessMachineControlCommand.reset.opCode:
            "Reset"
        case FitnessMachineControlCommand.targetResistance(Data()).opCode:
            "Set Target Resistance"
        case FitnessMachineControlCommand.targetPower(Data()).opCode:
            "Set Target Power"
        case FitnessMachineControlCommand.startOrResume.opCode:
            "Start/Resume"
        default:
            "Opcode 0x\(String(format: "%02X", requestOpCode))"
        }
    }

    var resultName: String {
        switch resultCode {
        case 0x01:
            "success"
        case 0x02:
            "opcode not supported"
        case 0x03:
            "invalid parameter"
        case 0x04:
            "operation failed"
        case 0x05:
            "control not permitted"
        default:
            "result 0x\(String(format: "%02X", resultCode))"
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

    mutating func appendLittleEndian(_ value: UInt16) {
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

    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
