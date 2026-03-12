import CoreBluetooth
import Foundation

final class BLEGATTDiscovery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onStateChange: ((String, Bool) -> Void)?
    var onPeripheralsChanged: (([BLEPeripheralRecord]) -> Void)?
    var onServicesChanged: ((UUID, [GATTServiceRecord]) -> Void)?
    var onLogEntry: ((BLEConsoleLogEntry) -> Void)?

    private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var peripheralRecords: [UUID: BLEPeripheralRecord] = [:]
    private var serviceRecordsByPeripheral: [UUID: [GATTServiceRecord]] = [:]
    private var characteristicsByKey: [String: CBCharacteristic] = [:]

    func startScanning() {
        switch centralManager.state {
        case .poweredOn:
            centralManager.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
            onStateChange?("BLE scan running.", true)
        case .unauthorized:
            onStateChange?("Bluetooth permission was denied.", false)
        case .poweredOff:
            onStateChange?("Turn Bluetooth on to scan for BLE services.", false)
        default:
            onStateChange?("Bluetooth is not ready yet.", false)
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        onStateChange?("BLE scan stopped.", false)
    }

    func connect(to peripheralID: UUID) {
        guard let peripheral = peripheralsByID[peripheralID] else {
            onStateChange?("Selected BLE peripheral is no longer available.", false)
            return
        }

        centralManager.connect(peripheral)
        onStateChange?("Connecting to \(displayName(for: peripheral))…", false)
        log(.info, label: peripheral.identifier.uuidString, payload: "connect requested")
    }

    func disconnect(from peripheralID: UUID) {
        guard let peripheral = peripheralsByID[peripheralID] else {
            return
        }

        centralManager.cancelPeripheralConnection(peripheral)
        log(.info, label: peripheral.identifier.uuidString, payload: "disconnect requested")
    }

    func services(for peripheralID: UUID) -> [GATTServiceRecord] {
        serviceRecordsByPeripheral[peripheralID] ?? []
    }

    func subscribeToNotifications(for peripheralID: UUID) {
        guard let peripheral = peripheralsByID[peripheralID],
              let services = peripheral.services else {
            return
        }

        for service in services {
            for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
                log(.info, label: key(for: peripheral.identifier, serviceUUID: service.uuid.uuidString, characteristicUUID: characteristic.uuid.uuidString), payload: "enable notify")
            }
        }
    }

    func refreshReadableValues(for peripheralID: UUID) {
        guard let peripheral = peripheralsByID[peripheralID],
              let services = peripheral.services else {
            return
        }

        for service in services {
            for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
                log(.info, label: key(for: peripheralID, serviceUUID: service.uuid.uuidString, characteristicUUID: characteristic.uuid.uuidString), payload: "read requested")
            }
        }
    }

    func writeHex(_ hex: String, to target: BLEWriteTarget) throws {
        guard let peripheral = peripheralsByID[target.peripheralID],
              let characteristic = characteristicsByKey[key(for: target.peripheralID, serviceUUID: target.serviceUUID, characteristicUUID: target.characteristicUUID)] else {
            throw BLEConsoleError.characteristicUnavailable
        }

        let data = try Data(hexEncoded: hex)
        let writeType: CBCharacteristicWriteType

        if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else {
            throw BLEConsoleError.characteristicNotWritable
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)
        log(.outgoing, label: key(for: target.peripheralID, serviceUUID: target.serviceUUID, characteristicUUID: target.characteristicUUID), payload: data.hexString)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let message: String
        switch central.state {
        case .unknown:
            message = "Bluetooth state is unknown."
        case .resetting:
            message = "Bluetooth is resetting."
        case .unsupported:
            message = "CoreBluetooth is unsupported on this Mac."
        case .unauthorized:
            message = "Bluetooth permission was denied."
        case .poweredOff:
            message = "Bluetooth is powered off."
        case .poweredOn:
            message = "Bluetooth is ready for BLE scanning."
        @unknown default:
            message = "Bluetooth returned an unknown state."
        }

        onStateChange?(message, false)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripheralsByID[peripheral.identifier] = peripheral

        var record = peripheralRecords[peripheral.identifier] ?? BLEPeripheralRecord(
            id: peripheral.identifier,
            name: peripheral.name ?? "",
            advertisedName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue,
            isConnectable: advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? true,
            isConnected: peripheral.state == .connected,
            advertisedServices: [],
            manufacturerDataHex: nil,
            serviceData: [:],
            lastSeen: Date()
        )

        record.name = peripheral.name ?? record.name
        record.advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? record.advertisedName
        record.rssi = RSSI.intValue
        record.isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? record.isConnectable
        record.isConnected = peripheral.state == .connected
        record.lastSeen = Date()

        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            record.advertisedServices = uuids.map(\.uuidString).sorted()
        }

        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            record.manufacturerDataHex = manufacturerData.hexString
        }

        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            record.serviceData = Dictionary(
                uniqueKeysWithValues: serviceData.map { key, value in
                    (key.uuidString, value.hexString)
                }
            )
        }

        peripheralRecords[peripheral.identifier] = record
        publishPeripheralRecords()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        updateConnectionState(for: peripheral, isConnected: true)
        onStateChange?("Connected to \(displayName(for: peripheral)). Discovering services…", false)
        log(.info, label: peripheral.identifier.uuidString, payload: "connected")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        updateConnectionState(for: peripheral, isConnected: false)
        onStateChange?(error?.localizedDescription ?? "BLE connection failed.", false)
        log(.error, label: peripheral.identifier.uuidString, payload: error?.localizedDescription ?? "connect failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        updateConnectionState(for: peripheral, isConnected: false)
        if let error {
            onStateChange?(error.localizedDescription, false)
            log(.error, label: peripheral.identifier.uuidString, payload: error.localizedDescription)
        } else {
            onStateChange?("Disconnected from \(displayName(for: peripheral)).", false)
            log(.info, label: peripheral.identifier.uuidString, payload: "disconnected")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            onStateChange?(error.localizedDescription, false)
            return
        }

        let services = (peripheral.services ?? []).map {
            GATTServiceRecord(
                id: $0.uuid.uuidString,
                uuid: $0.uuid.uuidString,
                isPrimary: $0.isPrimary,
                characteristics: [],
                errorSummary: nil
            )
        }

        serviceRecordsByPeripheral[peripheral.identifier] = services
        onServicesChanged?(peripheral.identifier, services)
        log(.info, label: peripheral.identifier.uuidString, payload: "services discovered: \(services.count)")

        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            let message = error.localizedDescription
            updateServiceRecord(peripheralID: peripheral.identifier, serviceUUID: service.uuid.uuidString) { record in
                record.errorSummary = message
            }
            onStateChange?(message, false)
            return
        }

        let characteristics = (service.characteristics ?? []).map { characteristic in
            self.characteristicsByKey[self.key(for: peripheral.identifier, serviceUUID: service.uuid.uuidString, characteristicUUID: characteristic.uuid.uuidString)] = characteristic
            return GATTCharacteristicRecord(
                id: characteristic.uuid.uuidString,
                uuid: characteristic.uuid.uuidString,
                properties: characteristic.properties.labels,
                isNotifying: characteristic.isNotifying,
                valueHex: characteristic.value?.hexString,
                descriptors: [],
                errorSummary: nil
            )
        }

        updateServiceRecord(peripheralID: peripheral.identifier, serviceUUID: service.uuid.uuidString) { record in
            record.characteristics = characteristics
            record.errorSummary = nil
        }
        log(.info, label: service.uuid.uuidString, payload: "characteristics discovered: \(characteristics.count)")

        service.characteristics?.forEach { characteristic in
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let message = error.localizedDescription
            if let service = characteristic.service {
                updateCharacteristicRecord(
                    peripheralID: peripheral.identifier,
                    serviceUUID: service.uuid.uuidString,
                    characteristicUUID: characteristic.uuid.uuidString
                ) { record in
                    record.errorSummary = message
                }
            }
            onStateChange?(message, false)
            return
        }

        guard let service = characteristic.service else {
            return
        }

        updateCharacteristicRecord(
            peripheralID: peripheral.identifier,
            serviceUUID: service.uuid.uuidString,
            characteristicUUID: characteristic.uuid.uuidString
        ) { record in
            record.valueHex = characteristic.value?.hexString
            record.isNotifying = characteristic.isNotifying
            record.errorSummary = nil
        }

        if let value = characteristic.value, !value.isEmpty {
            log(.incoming, label: key(for: peripheral.identifier, serviceUUID: service.uuid.uuidString, characteristicUUID: characteristic.uuid.uuidString), payload: value.hexString)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let message = error.localizedDescription
            if let service = characteristic.service {
                updateCharacteristicRecord(
                    peripheralID: peripheral.identifier,
                    serviceUUID: service.uuid.uuidString,
                    characteristicUUID: characteristic.uuid.uuidString
                ) { record in
                    record.errorSummary = message
                }
            }
            onStateChange?(message, false)
            return
        }

        guard let service = characteristic.service else {
            return
        }

        let descriptors = (characteristic.descriptors ?? []).map { descriptor in
            GATTDescriptorRecord(
                id: descriptor.uuid.uuidString,
                uuid: descriptor.uuid.uuidString,
                valueSummary: summary(for: descriptor.value)
            )
        }

        updateCharacteristicRecord(
            peripheralID: peripheral.identifier,
            serviceUUID: service.uuid.uuidString,
            characteristicUUID: characteristic.uuid.uuidString
        ) { record in
            record.descriptors = descriptors
        }

        characteristic.descriptors?.forEach { descriptor in
            peripheral.readValue(for: descriptor)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        if let error {
            let message = error.localizedDescription
            if let characteristic = descriptor.characteristic,
               let service = characteristic.service {
                updateDescriptorRecord(
                    peripheralID: peripheral.identifier,
                    serviceUUID: service.uuid.uuidString,
                    characteristicUUID: characteristic.uuid.uuidString,
                    descriptorUUID: descriptor.uuid.uuidString
                ) { record in
                    record.valueSummary = message
                }
            }
            onStateChange?(message, false)
            return
        }

        guard let characteristic = descriptor.characteristic,
              let service = characteristic.service else {
            return
        }

        updateDescriptorRecord(
            peripheralID: peripheral.identifier,
            serviceUUID: service.uuid.uuidString,
            characteristicUUID: characteristic.uuid.uuidString,
            descriptorUUID: descriptor.uuid.uuidString
        ) { record in
            record.valueSummary = summary(for: descriptor.value)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let label = key(
            for: peripheral.identifier,
            serviceUUID: characteristic.service?.uuid.uuidString ?? "unknown-service",
            characteristicUUID: characteristic.uuid.uuidString
        )

        if let error {
            log(.error, label: label, payload: error.localizedDescription)
        } else {
            log(.info, label: label, payload: "write acknowledged")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let label = key(
            for: peripheral.identifier,
            serviceUUID: characteristic.service?.uuid.uuidString ?? "unknown-service",
            characteristicUUID: characteristic.uuid.uuidString
        )

        if let error {
            log(.error, label: label, payload: error.localizedDescription)
        } else {
            log(.info, label: label, payload: characteristic.isNotifying ? "notify enabled" : "notify disabled")
        }
    }

    private func publishPeripheralRecords() {
        let records = peripheralRecords.values.sorted { lhs, rhs in
            let lhsSony = isLikelySonyLE(name: lhs.displayName)
            let rhsSony = isLikelySonyLE(name: rhs.displayName)
            if lhsSony != rhsSony {
                return lhsSony && !rhsSony
            }
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected && !rhs.isConnected
            }
            if lhs.rssi != rhs.rssi {
                return lhs.rssi > rhs.rssi
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        onPeripheralsChanged?(records)
    }

    private func updateConnectionState(for peripheral: CBPeripheral, isConnected: Bool) {
        guard var record = peripheralRecords[peripheral.identifier] else {
            return
        }

        record.isConnected = isConnected
        peripheralRecords[peripheral.identifier] = record
        publishPeripheralRecords()
    }

    private func updateServiceRecord(peripheralID: UUID, serviceUUID: String, mutate: (inout GATTServiceRecord) -> Void) {
        guard var records = serviceRecordsByPeripheral[peripheralID],
              let index = records.firstIndex(where: { $0.uuid == serviceUUID }) else {
            return
        }

        mutate(&records[index])
        serviceRecordsByPeripheral[peripheralID] = records
        onServicesChanged?(peripheralID, records)
    }

    private func updateCharacteristicRecord(
        peripheralID: UUID,
        serviceUUID: String,
        characteristicUUID: String,
        mutate: (inout GATTCharacteristicRecord) -> Void
    ) {
        updateServiceRecord(peripheralID: peripheralID, serviceUUID: serviceUUID) { serviceRecord in
            guard let index = serviceRecord.characteristics.firstIndex(where: { $0.uuid == characteristicUUID }) else {
                return
            }
            mutate(&serviceRecord.characteristics[index])
        }
    }

    private func updateDescriptorRecord(
        peripheralID: UUID,
        serviceUUID: String,
        characteristicUUID: String,
        descriptorUUID: String,
        mutate: (inout GATTDescriptorRecord) -> Void
    ) {
        updateCharacteristicRecord(
            peripheralID: peripheralID,
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID
        ) { characteristicRecord in
            guard let index = characteristicRecord.descriptors.firstIndex(where: { $0.uuid == descriptorUUID }) else {
                return
            }
            mutate(&characteristicRecord.descriptors[index])
        }
    }

    private func summary(for value: Any?) -> String? {
        switch value {
        case let data as Data:
            data.hexString
        case let number as NSNumber:
            number.stringValue
        case let string as String:
            string
        case let array as [Any]:
            array.map { String(describing: $0) }.joined(separator: ", ")
        case nil:
            nil
        default:
            String(describing: value)
        }
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheralRecords[peripheral.identifier]?.displayName ?? peripheral.name ?? peripheral.identifier.uuidString
    }

    private func isLikelySonyLE(name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("xm") || normalized.contains("sony") || normalized.contains("wh-1000")
    }

    private func key(for peripheralID: UUID, serviceUUID: String, characteristicUUID: String) -> String {
        "\(peripheralID.uuidString)|\(serviceUUID)|\(characteristicUUID)"
    }

    private func log(_ kind: BLEConsoleLogEntry.Kind, label: String, payload: String) {
        onLogEntry?(
            BLEConsoleLogEntry(
                kind: kind,
                label: label,
                payload: payload
            )
        )
    }
}

enum BLEConsoleError: LocalizedError {
    case characteristicUnavailable
    case characteristicNotWritable
    case invalidHex

    var errorDescription: String? {
        switch self {
        case .characteristicUnavailable:
            "The selected BLE characteristic is unavailable."
        case .characteristicNotWritable:
            "The selected BLE characteristic is not writable."
        case .invalidHex:
            "Enter an even-length hexadecimal payload."
        }
    }
}

private extension Data {
    init(hexEncoded hex: String) throws {
        let cleaned = hex
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")

        guard cleaned.count.isMultiple(of: 2), !cleaned.isEmpty else {
            throw BLEConsoleError.invalidHex
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)

        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index ..< nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw BLEConsoleError.invalidHex
            }
            bytes.append(byte)
            index = nextIndex
        }

        self = Data(bytes)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

private extension CBCharacteristicProperties {
    var labels: [String] {
        var labels = [String]()

        if contains(.broadcast) { labels.append("broadcast") }
        if contains(.read) { labels.append("read") }
        if contains(.writeWithoutResponse) { labels.append("write-no-rsp") }
        if contains(.write) { labels.append("write") }
        if contains(.notify) { labels.append("notify") }
        if contains(.indicate) { labels.append("indicate") }
        if contains(.authenticatedSignedWrites) { labels.append("signed-write") }
        if contains(.extendedProperties) { labels.append("extended") }
        if contains(.notifyEncryptionRequired) { labels.append("notify-encrypted") }
        if contains(.indicateEncryptionRequired) { labels.append("indicate-encrypted") }

        return labels
    }
}
