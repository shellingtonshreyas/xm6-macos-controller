import Foundation

struct ClassicServiceRecord: Identifiable, Hashable {
    let id: String
    let name: String
    let recordHandle: String
    let rfcommChannel: String?
    let l2capPSM: String?
    let attributeCount: Int
}

struct BLEPeripheralRecord: Identifiable, Hashable {
    let id: UUID
    var name: String
    var advertisedName: String?
    var rssi: Int
    var isConnectable: Bool
    var isConnected: Bool
    var advertisedServices: [String]
    var manufacturerDataHex: String?
    var serviceData: [String: String]
    var lastSeen: Date

    var displayName: String {
        if let advertisedName, !advertisedName.isEmpty {
            return advertisedName
        }
        if !name.isEmpty {
            return name
        }
        return "Unnamed peripheral"
    }
}

struct GATTDescriptorRecord: Identifiable, Hashable {
    let id: String
    let uuid: String
    var valueSummary: String?
}

struct GATTCharacteristicRecord: Identifiable, Hashable {
    let id: String
    let uuid: String
    var properties: [String]
    var isNotifying: Bool
    var valueHex: String?
    var descriptors: [GATTDescriptorRecord]
    var errorSummary: String?
}

struct GATTServiceRecord: Identifiable, Hashable {
    let id: String
    let uuid: String
    let isPrimary: Bool
    var characteristics: [GATTCharacteristicRecord]
    var errorSummary: String?
}

struct BLEWriteTarget: Identifiable, Hashable {
    let peripheralID: UUID
    let serviceUUID: String
    let characteristicUUID: String

    var id: String {
        "\(peripheralID.uuidString)|\(serviceUUID)|\(characteristicUUID)"
    }

    var label: String {
        "\(serviceUUID) -> \(characteristicUUID)"
    }
}

struct BLEConsoleLogEntry: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case info
        case incoming
        case outgoing
        case error
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    let label: String
    let payload: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        label: String,
        payload: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.label = label
        self.payload = payload
    }
}
