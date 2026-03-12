import Foundation
import IOBluetooth

enum SonyTransportError: LocalizedError {
    case invalidAddress
    case serviceQueryFailed(IOReturn)
    case channelOpenFailed(IOReturn)
    case notConnected
    case writeFailed(IOReturn)
    case responseTimeout(UInt8)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "The selected device does not have a valid Bluetooth address."
        case let .serviceQueryFailed(code):
            "Bluetooth service discovery failed. IOReturn \(code)."
        case let .channelOpenFailed(code):
            "Failed to open Sony control channel. IOReturn \(code)."
        case .notConnected:
            "The Sony control channel is not connected."
        case let .writeFailed(code):
            "Failed to send command to the headset. IOReturn \(code)."
        case let .responseTimeout(command):
            "The headset did not answer command 0x\(String(command, radix: 16, uppercase: true)) in time."
        }
    }
}

final class SonyRFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?
    private var activeDevice: IOBluetoothDevice?
    private var receiveBuffer: [UInt8] = []
    private var pendingMessages: [SonyProtocol.PacketMessage] = []
    private var nextCommandSequence: UInt8 = 0

    var onMessage: ((SonyProtocol.PacketMessage) -> Void)?

    func loadDevices() -> [SonyDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []

        return paired.compactMap { device in
            guard let name = device.name, isLikelySonyHeadphone(named: name) else {
                return nil
            }

            let address = device.addressString ?? ""
            return SonyDevice(
                id: address,
                name: name,
                address: address,
                isConnected: device.isConnected()
            )
        }
        .sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected && !rhs.isConnected
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func connect(to device: SonyDevice) throws {
        disconnect()

        guard let macDevice = IOBluetoothDevice(addressString: device.address) else {
            throw SonyTransportError.invalidAddress
        }

        if !macDevice.isConnected() {
            _ = macDevice.openConnection()
        }

        try queryServicesIfNeeded(for: macDevice)

        let channelID = resolveRFCOMMChannelID(for: macDevice)

        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = macDevice.openRFCOMMChannelSync(&openedChannel, withChannelID: channelID, delegate: self)

        guard result == kIOReturnSuccess, let openedChannel else {
            throw SonyTransportError.channelOpenFailed(result)
        }

        self.channel = openedChannel
        self.activeDevice = macDevice
        receiveBuffer.removeAll(keepingCapacity: true)
        pendingMessages.removeAll(keepingCapacity: true)
        nextCommandSequence = 0

        drainIncomingMessages()
        try performInitializationHandshake()
    }

    func disconnect() {
        channel?.setDelegate(nil)
        _ = channel?.close()
        channel = nil
        activeDevice?.closeConnection()
        activeDevice = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        pendingMessages.removeAll(keepingCapacity: true)
        nextCommandSequence = 0
    }

    func send(_ data: Data) throws {
        guard let channel, channel.isOpen() else {
            throw SonyTransportError.notConnected
        }

        let result = data.withUnsafeBytes { buffer in
            channel.writeSync(UnsafeMutableRawPointer(mutating: buffer.baseAddress), length: UInt16(buffer.count))
        }

        guard result == kIOReturnSuccess else {
            throw SonyTransportError.writeFailed(result)
        }
    }

    func sendCommand(_ payload: [UInt8], timeout: TimeInterval = 3) throws -> SonyProtocol.PacketMessage {
        let requestCommand = payload.first ?? 0
        let packet = SonyProtocol.packetize(
            payload: payload,
            dataType: .dataMDR,
            sequence: nextCommandSequence
        )

        pendingMessages.removeAll(keepingCapacity: true)
        try send(packet)

        let expectedCommands = [requestCommand, requestCommand &+ 1]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let index = pendingMessages.firstIndex(where: { message in
                guard let command = message.payload.first else {
                    return false
                }
                return expectedCommands.contains(command)
            }) {
                return pendingMessages.remove(at: index)
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        throw SonyTransportError.responseTimeout(requestCommand)
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel, data dataPointer: UnsafeMutableRawPointer, length dataLength: Int) {
        let incoming = dataPointer.assumingMemoryBound(to: UInt8.self)
        receiveBuffer.append(contentsOf: UnsafeBufferPointer(start: incoming, count: dataLength))

        while true {
            do {
                let (message, remaining) = try SonyProtocol.extractMessage(from: receiveBuffer)
                receiveBuffer = remaining

                guard let message else {
                    break
                }

                try acknowledge(message)

                if message.dataType != .ack {
                    pendingMessages.append(message)
                    onMessage?(message)
                } else {
                    nextCommandSequence = message.sequence
                }
            } catch {
                receiveBuffer.removeAll(keepingCapacity: true)
                break
            }
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        if rfcommChannel == channel {
            channel = nil
            activeDevice = nil
            receiveBuffer.removeAll(keepingCapacity: true)
            pendingMessages.removeAll(keepingCapacity: true)
            nextCommandSequence = 0
        }
    }

    private func isLikelySonyHeadphone(named name: String) -> Bool {
        let normalized = name.lowercased()
        if normalized.hasPrefix("le_") {
            return false
        }

        let sonyMarkers = [
            "sony",
            "wh-1000",
            "wf-1000",
            "xm",
            "linkbuds",
            "ult wear"
        ]

        return sonyMarkers.contains { normalized.contains($0) }
    }

    private func queryServicesIfNeeded(for device: IOBluetoothDevice) throws {
        if device.services != nil {
            return
        }

        let result = device.performSDPQuery(nil)
        guard result == kIOReturnSuccess else {
            throw SonyTransportError.serviceQueryFailed(result)
        }

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if device.services != nil {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func resolveRFCOMMChannelID(for device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID {
        for uuidBytes in [SonyProtocol.serviceUUIDV2Bytes, SonyProtocol.serviceUUIDV1Bytes] {
            let uuid = uuidBytes.withUnsafeBufferPointer {
                IOBluetoothSDPUUID(bytes: $0.baseAddress, length: $0.count)
            }

            if let service = device.getServiceRecord(for: uuid) {
                var channelID: BluetoothRFCOMMChannelID = 0
                if service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                    return channelID
                }
            }
        }

        return SonyProtocol.fallbackRFCOMMChannelID
    }

    private func performInitializationHandshake() throws {
        _ = try sendCommand([0x00, 0x00], timeout: 2)
        _ = try sendCommand([0x06, 0x00], timeout: 2)
    }

    private func acknowledge(_ message: SonyProtocol.PacketMessage) throws {
        let ackSequence: UInt8 = message.sequence <= 1 ? (1 - message.sequence) : 0
        try send(SonyProtocol.makeACKPacket(sequence: ackSequence))
    }

    private func drainIncomingMessages() {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        pendingMessages.removeAll(keepingCapacity: true)
    }
}
