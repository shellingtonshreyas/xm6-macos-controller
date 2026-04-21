import Foundation

protocol SonyHeadphoneDriver: AnyObject, Sendable {
    var featureSupport: FeatureSupport { get }
    var currentStatus: SonyControlStatus { get }
    func loadDevices() -> [SonyDevice]
    func connect(to device: SonyDevice) throws
    func disconnect()
    func refreshState() throws
    func requestStateRefresh() throws
    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws
    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws
    func setVolume(_ level: Int) throws
    func setDSEEExtreme(_ enabled: Bool) throws
    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws
    func setSpeakToChat(_ enabled: Bool) throws
}

final class XM6SonyDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    private(set) var currentStatus = SonyControlStatus()

    private let transport = SonyRFCOMMTransport()

    init() {
        transport.onMessage = { [weak self] message in
            self?.consume(message)
        }
    }

    func loadDevices() -> [SonyDevice] {
        transport.loadDevices()
    }

    func connect(to device: SonyDevice) throws {
        do {
            try transport.connect(to: device)
            currentStatus = SonyControlStatus()
        } catch {
            transport.disconnect()
            currentStatus = SonyControlStatus()
            throw error
        }
    }

    func disconnect() {
        transport.disconnect()
        currentStatus = SonyControlStatus()
    }

    func refreshState() throws {
        try refreshState(using: { [transport] payload in
            try transport.sendCommand(payload)
        })
    }

    func requestStateRefresh() throws {
        let packets = [
            SonyProtocol.makeNoiseControlQueryPacket(),
            SonyProtocol.makeVolumeQueryPacket(),
            SonyProtocol.makeDSEEQueryPacket(),
            SonyProtocol.makeSpeakToChatQueryPacket(),
            SonyProtocol.makeBatteryQueryPacket()
        ]

        var firstError: Error?

        for packet in packets {
            do {
                try transport.send(packet)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    func refreshState(
        using sendCommand: (_ payload: [UInt8]) throws -> SonyProtocol.PacketMessage
    ) throws {
        let queries: [[UInt8]] = [
            [SonyProtocol.CommandType.noiseControlGet.rawValue, SonyProtocol.NoiseControlInquiryType.xm6.rawValue],
            [SonyProtocol.CommandType.volumeGet.rawValue, 0x20],
            [SonyProtocol.CommandType.dseeGet.rawValue, 0x01],
            [SonyProtocol.CommandType.speakToChatGet.rawValue, 0x02],
            [SonyProtocol.CommandType.batteryGet.rawValue, 0x00]
        ]

        var firstError: Error?
        var didReceiveAnyResponse = false

        for query in queries {
            do {
                consume(try sendCommand(query))
                didReceiveAnyResponse = true
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if !didReceiveAnyResponse, let firstError {
            throw firstError
        }
    }

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {
        let payload = try SonyProtocol.noiseControlPayload(
            mode: mode,
            ambientLevel: ambientLevel,
            focusOnVoice: focusOnVoice
        )
        consume(try transport.sendCommand(payload))
    }

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {
        throw SonyProtocolError.unsupportedFeature(featureSupport.surround.unsupportedReason)
    }

    func setVolume(_ level: Int) throws {
        consume(try transport.sendCommand(SonyProtocol.volumeSetPayload(level)))
    }

    func setDSEEExtreme(_ enabled: Bool) throws {
        consume(try transport.sendCommand(SonyProtocol.dseeSetPayload(enabled)))
    }

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {
        _ = bands
        let payload = try SonyProtocol.equalizerPresetPayload(preset)
        consume(try transport.sendCommand(payload, timeout: 4))
    }

    func setSpeakToChat(_ enabled: Bool) throws {
        consume(try transport.sendCommand(SonyProtocol.speakToChatSetPayload(enabled)))
    }

    private func consume(_ message: SonyProtocol.PacketMessage) {
        guard let command = message.payload.first else {
            return
        }

        switch command {
        case SonyProtocol.CommandType.batteryNotify.rawValue,
             SonyProtocol.CommandType.batteryReturn.rawValue:
            if message.payload.count >= 4 {
                currentStatus.batteryLevel = Int(message.payload[2])
                currentStatus.isCharging = message.payload[3] != 0
            }

        case SonyProtocol.CommandType.noiseControlReturn.rawValue,
             SonyProtocol.CommandType.noiseControlNotify.rawValue:
            if message.payload.count >= 9 {
                let enabled = message.payload[3] != 0
                let ambientOn = message.payload[4] != 0

                if enabled, ambientOn {
                    currentStatus.noiseControlMode = .ambient
                } else if enabled {
                    currentStatus.noiseControlMode = .noiseCancelling
                } else {
                    currentStatus.noiseControlMode = .off
                }

                currentStatus.ambientLevel = Int(message.payload[6])
                currentStatus.focusOnVoice = message.payload[7] != 0
            }

        case SonyProtocol.CommandType.volumeReturn.rawValue, 0xA9:
            if message.payload.count >= 3 {
                currentStatus.volumeLevel = Int(message.payload[2])
            }

        case SonyProtocol.CommandType.equalizerReturn.rawValue,
             SonyProtocol.CommandType.equalizerNotify.rawValue:
            if message.payload.count >= 3,
               message.payload[1] == 0x04,
               let preset = SonyProtocol.equalizerPreset(from: message.payload[2]) {
                currentStatus.equalizerPreset = preset
            }

        case SonyProtocol.CommandType.dseeReturn.rawValue,
             SonyProtocol.CommandType.dseeNotify.rawValue:
            if message.payload.count >= 3 {
                currentStatus.dseeEnabled = message.payload[2] != 0
            }

        case SonyProtocol.CommandType.speakToChatReturn.rawValue,
             SonyProtocol.CommandType.speakToChatNotify.rawValue:
            if message.payload.count >= 3 {
                currentStatus.speakToChatEnabled = message.payload[2] != 0
            }

        default:
            break
        }
    }
}

extension XM6SonyDriver: @unchecked Sendable {}

private extension FeatureAvailability {
    var unsupportedReason: String {
        switch self {
        case .supported:
            "This feature is supported."
        case let .unsupported(reason):
            reason
        }
    }
}
