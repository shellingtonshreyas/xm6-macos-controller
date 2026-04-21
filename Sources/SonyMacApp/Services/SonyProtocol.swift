import Foundation
import IOBluetooth

enum SonyProtocolError: LocalizedError, Sendable {
    case invalidAmbientLevel
    case invalidVolume
    case unsupportedFeature(String)
    case malformedPacket

    var errorDescription: String? {
        switch self {
        case .invalidAmbientLevel:
            "Ambient level must be between 0 and 20."
        case .invalidVolume:
            "Volume must be between 0 and 30."
        case let .unsupportedFeature(message):
            message
        case .malformedPacket:
            "The headset sent a malformed control packet."
        }
    }
}

enum SonyProtocol {
    static let startMarker: UInt8 = 62
    static let endMarker: UInt8 = 60
    static let escapeSentry: UInt8 = 61

    static let serviceUUIDV2Bytes: [UInt8] = [
        0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8,
        0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2
    ]

    static let serviceUUIDV1Bytes: [UInt8] = [
        0x96, 0xCC, 0x20, 0x3E, 0x50, 0x68, 0x46, 0xAD,
        0xB3, 0x2D, 0xE3, 0x16, 0xF5, 0xE0, 0x69, 0xBA
    ]

    static let fallbackRFCOMMChannelID: BluetoothRFCOMMChannelID = 9

    enum DataType: UInt8, Sendable {
        case data = 0
        case ack = 1
        case dataMDR = 12
    }

    enum CommandType: UInt8, Sendable {
        case batteryNotify = 0x13
        case batteryGet = 0x22
        case batteryReturn = 0x23
        case noiseControlGet = 0x66
        case noiseControlReturn = 0x67
        case noiseControlSet = 0x68
        case noiseControlNotify = 0x69
        case equalizerGet = 0x56
        case equalizerReturn = 0x57
        case equalizerSet = 0x58
        case equalizerNotify = 0x59
        case volumeGet = 0xA6
        case volumeReturn = 0xA7
        case volumeSet = 0xA8
        case dseeGet = 0xE6
        case dseeReturn = 0xE7
        case dseeSet = 0xE8
        case dseeNotify = 0xE9
        case speakToChatGet = 0xF6
        case speakToChatReturn = 0xF7
        case speakToChatSet = 0xF8
        case speakToChatNotify = 0xF9
    }

    enum NoiseControlInquiryType: UInt8, Sendable {
        case xm5 = 0x17
        case xm6 = 0x19
    }

    enum EqualizerPresetID: UInt8, Sendable {
        case off = 0x00
        case heavy = 0x30
        case clear = 0x31
        case hard = 0x32
    }

    enum SoundPositionPreset: UInt8, Sendable {
        case off = 0
        case frontLeft = 1
        case frontRight = 2
        case front = 3
        case rearLeft = 17
        case rearRight = 18
    }

    struct PacketMessage: Equatable, Sendable {
        let dataType: DataType
        let sequence: UInt8
        let payload: [UInt8]
    }

    static func packetize(
        payload: [UInt8],
        dataType: DataType = .data,
        sequence: UInt8 = 0
    ) -> Data {
        var packet = [UInt8]()
        packet.reserveCapacity(payload.count + 8)
        packet.append(dataType.rawValue)
        packet.append(sequence)
        packet.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).bigEndian, Array.init))
        packet.append(contentsOf: payload)
        packet.append(checksum(for: packet))

        let escaped = escapeSpecials(packet)
        return Data([startMarker] + escaped + [endMarker])
    }

    static func makeACKPacket(sequence: UInt8) -> Data {
        packetize(payload: [], dataType: .ack, sequence: sequence)
    }

    static func extractMessage(from buffer: [UInt8]) throws -> (PacketMessage?, [UInt8]) {
        guard let startIndex = buffer.firstIndex(of: startMarker) else {
            return (nil, [])
        }

        let searchStart = buffer.index(after: startIndex)
        guard searchStart < buffer.endIndex,
              let endIndex = buffer[searchStart...].firstIndex(of: endMarker) else {
            return (nil, Array(buffer[startIndex...]))
        }

        let raw = Array(buffer[startIndex...endIndex])
        let remaining = Array(buffer[(endIndex + 1)...])

        guard let message = try unpack(raw) else {
            return try extractMessage(from: Array(buffer[(startIndex + 1)...]))
        }

        return (message, remaining)
    }

    static func makeNoiseControlPacket(
        mode: NoiseControlMode,
        ambientLevel: Int,
        focusOnVoice: Bool
    ) throws -> Data {
        packetize(
            payload: try noiseControlPayload(
                mode: mode,
                ambientLevel: ambientLevel,
                focusOnVoice: focusOnVoice
            ),
            dataType: .dataMDR
        )
    }

    static func noiseControlPayload(
        mode: NoiseControlMode,
        ambientLevel: Int,
        focusOnVoice: Bool,
        inquiryType: NoiseControlInquiryType = .xm6
    ) throws -> [UInt8] {
        guard NoiseControlMode.ambientLevelRange.contains(ambientLevel) else {
            throw SonyProtocolError.invalidAmbientLevel
        }

        let enabled: UInt8 = mode == .off ? 0x00 : 0x01
        let ambientOn: UInt8 = mode == .ambient ? 0x01 : 0x00
        let ncOn: UInt8 = mode == .noiseCancelling ? 0x01 : 0x00

        if inquiryType == .xm5 {
            // XM5 uses a 7-byte payload without the NC-enable or focus-on-voice fields
            return [
                CommandType.noiseControlSet.rawValue,
                NoiseControlInquiryType.xm5.rawValue,
                0x01,
                enabled,
                ambientOn,
                ncOn,
                UInt8(ambientLevel)
            ]
        }

        return [
            CommandType.noiseControlSet.rawValue,
            NoiseControlInquiryType.xm6.rawValue,
            0x01,
            enabled,
            ambientOn,
            ncOn,
            UInt8(ambientLevel),
            (focusOnVoice ? 0x01 : 0x00),
            0x00
        ]
    }

    static func makeNoiseControlQueryPacket(inquiryType: NoiseControlInquiryType = .xm6) -> Data {
        packetize(
            payload: [CommandType.noiseControlGet.rawValue, inquiryType.rawValue],
            dataType: .dataMDR
        )
    }

    static func makeBatteryQueryPacket() -> Data {
        packetize(payload: [CommandType.batteryGet.rawValue, 0x00], dataType: .dataMDR)
    }

    static func makeVolumeQueryPacket() -> Data {
        packetize(payload: [CommandType.volumeGet.rawValue, 0x20], dataType: .dataMDR)
    }

    static func makeVolumeSetPacket(level: Int) throws -> Data {
        packetize(payload: try volumeSetPayload(level), dataType: .dataMDR)
    }

    static func volumeSetPayload(_ level: Int) throws -> [UInt8] {
        guard (0 ... 30).contains(level) else {
            throw SonyProtocolError.invalidVolume
        }

        return [CommandType.volumeSet.rawValue, 0x20, UInt8(level)]
    }

    static func makeDSEEQueryPacket() -> Data {
        packetize(payload: [CommandType.dseeGet.rawValue, 0x01], dataType: .dataMDR)
    }

    static func makeDSEESetPacket(_ enabled: Bool) -> Data {
        packetize(payload: dseeSetPayload(enabled), dataType: .dataMDR)
    }

    static func dseeSetPayload(_ enabled: Bool) -> [UInt8] {
        [
            CommandType.dseeSet.rawValue,
            0x01,
            enabled ? 0x01 : 0x00
        ]
    }

    static func makeSpeakToChatQueryPacket() -> Data {
        packetize(payload: [CommandType.speakToChatGet.rawValue, 0x02], dataType: .dataMDR)
    }

    static func makeSpeakToChatSetPacket(_ enabled: Bool) -> Data {
        packetize(payload: speakToChatSetPayload(enabled), dataType: .dataMDR)
    }

    static func speakToChatSetPayload(_ enabled: Bool) -> [UInt8] {
        [
            CommandType.speakToChatSet.rawValue,
            0x02,
            enabled ? 0x01 : 0x00,
            0x01,
            0x01
        ]
    }

    static func makeEqualizerPresetPacket(_ preset: EqualizerPreset) throws -> Data {
        packetize(payload: try equalizerPresetPayload(preset), dataType: .dataMDR)
    }

    static func makeEqualizerQueryPacket() -> Data {
        packetize(payload: [CommandType.equalizerGet.rawValue, 0x04], dataType: .dataMDR)
    }

    static func equalizerPresetPayload(_ preset: EqualizerPreset) throws -> [UInt8] {
        guard let presetID = EqualizerPresetID(preset) else {
            throw SonyProtocolError.unsupportedFeature("Custom EQ band packets are not mapped for XM6 yet.")
        }

        return [CommandType.equalizerSet.rawValue, 0x04, presetID.rawValue, 0x00]
    }

    static func equalizerPreset(from payloadID: UInt8) -> EqualizerPreset? {
        guard let presetID = EqualizerPresetID(rawPayloadID: payloadID) else {
            return nil
        }

        return EqualizerPreset(protocolID: presetID)
    }

    static func makeInitializationPackets() -> [Data] {
        [
            packetize(payload: [0x00, 0x00], dataType: .dataMDR),
            packetize(payload: [0x06, 0x00], dataType: .dataMDR)
        ]
    }

    private static func checksum(for bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0, &+)
    }

    private static func escapeSpecials(_ bytes: [UInt8]) -> [UInt8] {
        var escaped = [UInt8]()

        for byte in bytes {
            switch byte {
            case 60:
                escaped.append(contentsOf: [escapeSentry, 44])
            case 61:
                escaped.append(contentsOf: [escapeSentry, 45])
            case 62:
                escaped.append(contentsOf: [escapeSentry, 46])
            default:
                escaped.append(byte)
            }
        }

        return escaped
    }

    private static func unpack(_ raw: [UInt8]) throws -> PacketMessage? {
        guard raw.count >= 2, raw.first == startMarker, raw.last == endMarker else {
            return nil
        }

        let inner = unescapeSpecials(Array(raw.dropFirst().dropLast()))
        guard inner.count >= 7 else {
            return nil
        }

        let expectedChecksum = inner.last ?? 0
        let payloadRegion = Array(inner.dropLast())
        guard checksum(for: payloadRegion) == expectedChecksum else {
            throw SonyProtocolError.malformedPacket
        }

        guard let dataType = DataType(rawValue: payloadRegion[0]) else {
            return nil
        }

        let length = Int(
            (UInt32(payloadRegion[2]) << 24) |
            (UInt32(payloadRegion[3]) << 16) |
            (UInt32(payloadRegion[4]) << 8) |
            UInt32(payloadRegion[5])
        )

        let payload = Array(payloadRegion.dropFirst(6))
        guard payload.count == length else {
            return nil
        }

        return PacketMessage(
            dataType: dataType,
            sequence: payloadRegion[1],
            payload: payload
        )
    }

    private static func unescapeSpecials(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        var index = 0

        while index < bytes.count {
            if bytes[index] == escapeSentry, index + 1 < bytes.count {
                switch bytes[index + 1] {
                case 44:
                    result.append(endMarker)
                    index += 2
                    continue
                case 45:
                    result.append(escapeSentry)
                    index += 2
                    continue
                case 46:
                    result.append(startMarker)
                    index += 2
                    continue
                default:
                    break
                }
            }

            result.append(bytes[index])
            index += 1
        }

        return result
    }
}

extension SonyProtocol.EqualizerPresetID {
    init?(_ preset: EqualizerPreset) {
        switch preset {
        case .off:
            self = .off
        case .heavy:
            self = .heavy
        case .clear:
            self = .clear
        case .hard:
            self = .hard
        }
    }

    init?(rawPayloadID: UInt8) {
        switch rawPayloadID {
        case Self.off.rawValue:
            self = .off
        case Self.heavy.rawValue:
            self = .heavy
        case Self.clear.rawValue:
            self = .clear
        case Self.hard.rawValue:
            self = .hard
        default:
            return nil
        }
    }
}

extension EqualizerPreset {
    init?(protocolID: SonyProtocol.EqualizerPresetID) {
        switch protocolID {
        case .off:
            self = .off
        case .heavy:
            self = .heavy
        case .clear:
            self = .clear
        case .hard:
            self = .hard
        }
    }
}
