import Foundation
import IOBluetooth

enum SonyTransportError: LocalizedError {
    case invalidAddress
    case deviceConnectionFailed(IOReturn)
    case serviceQueryFailed(IOReturn)
    case channelOpenFailed(IOReturn)
    case notConnected
    case writeFailed(IOReturn)
    case responseTimeout(UInt8)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "The selected device does not have a valid Bluetooth address."
        case let .deviceConnectionFailed(code):
            "Failed to connect to the headset over Bluetooth. IOReturn \(code)."
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
    private static let initialWriteReadyTimeout: TimeInterval = 1.0
    private static let retryWriteReadyTimeout: TimeInterval = 0.35
    private static let transientWriteErrors: Set<IOReturn> = [
        kIOReturnBusy,
        kIOReturnTimeout,
        kIOReturnNotReady,
        kIOReturnNoSpace,
        kIOReturnUnderrun
    ]

    private var channel: IOBluetoothRFCOMMChannel?
    private var activeDevice: IOBluetoothDevice?
    private var receiveBuffer: [UInt8] = []
    private var pendingMessages: [SonyProtocol.PacketMessage] = []
    private var nextCommandSequence: UInt8 = 0

    var onMessage: ((SonyProtocol.PacketMessage) -> Void)?

    private func log(_ message: String) {
        fputs("[SonyRFCOMMTransport] \(message)\n", stderr)
    }

    func loadDevices() -> [SonyDevice] {
        BluetoothMainThreadExecutor.run {
            self.loadDevicesOnMain()
        }
    }

    private func loadDevicesOnMain() -> [SonyDevice] {
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
        try BluetoothMainThreadExecutor.runThrowing {
            try self.connectOnMain(to: device)
        }
    }

    private func connectOnMain(to device: SonyDevice) throws {
        log("connect start device=\(device.name) address=\(device.address) macConnected=\(device.isConnected)")
        disconnectOnMain()

        guard let macDevice = IOBluetoothDevice(addressString: device.address) else {
            log("connect failed invalid address")
            throw SonyTransportError.invalidAddress
        }

        if !macDevice.isConnected() {
            let result = macDevice.openConnection()
            log("openConnection result=\(result)")
            guard result == kIOReturnSuccess else {
                throw SonyTransportError.deviceConnectionFailed(result)
            }
        } else {
            log("device already connected in macOS")
        }

        try queryServicesIfNeeded(for: macDevice)

        let channelID = resolveRFCOMMChannelID(for: macDevice)
        log("resolved RFCOMM channel id=\(channelID)")

        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = macDevice.openRFCOMMChannelSync(&openedChannel, withChannelID: channelID, delegate: self)
        log("openRFCOMMChannelSync result=\(result)")

        guard result == kIOReturnSuccess, let openedChannel else {
            throw SonyTransportError.channelOpenFailed(result)
        }

        self.channel = openedChannel
        self.activeDevice = macDevice
        receiveBuffer.removeAll(keepingCapacity: true)
        pendingMessages.removeAll(keepingCapacity: true)
        nextCommandSequence = 0

        _ = waitUntilChannelIsWritable(timeout: Self.initialWriteReadyTimeout)
        drainIncomingMessages()
        try performInitializationHandshake()
        log("connect success device=\(device.name)")
    }

    func disconnect() {
        BluetoothMainThreadExecutor.run {
            self.disconnectOnMain()
        }
    }

    private func disconnectOnMain() {
        if channel != nil || activeDevice != nil {
            log("disconnect")
        }
        channel?.setDelegate(nil)
        _ = channel?.close()
        channel = nil
        activeDevice?.closeConnection()
        activeDevice = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        pendingMessages.removeAll(keepingCapacity: true)
        nextCommandSequence = 0
    }

    func send(_ data: Data, recoverTransiently: Bool = true) throws {
        try BluetoothMainThreadExecutor.runThrowing {
            try self.sendOnMain(data, recoverTransiently: recoverTransiently)
        }
    }

    private func sendOnMain(_ data: Data, recoverTransiently: Bool = true) throws {
        guard let channel, let activeDevice else {
            throw SonyTransportError.notConnected
        }

        try validateTransport(channel: channel, device: activeDevice)

        if recoverTransiently {
            _ = waitUntilChannelIsWritable(timeout: Self.initialWriteReadyTimeout)
            try validateTransport(channel: channel, device: activeDevice)
        }

        let attempts = recoverTransiently ? 3 : 1
        var lastError: IOReturn = kIOReturnSuccess

        for attempt in 0 ..< attempts {
            let result = performWrite(data, on: channel)
            if result == kIOReturnSuccess {
                return
            }

            lastError = result

            guard recoverTransiently,
                  attempt < attempts - 1,
                  Self.transientWriteErrors.contains(result) else {
                break
            }

            _ = waitUntilChannelIsWritable(timeout: Self.retryWriteReadyTimeout)
            try validateTransport(channel: channel, device: activeDevice)
        }

        synchronizeTransportState()
        throw SonyTransportError.writeFailed(lastError)
    }

    func sendCommand(_ payload: [UInt8], timeout: TimeInterval = 3) throws -> SonyProtocol.PacketMessage {
        try BluetoothMainThreadExecutor.runThrowing {
            try self.sendCommandOnMain(payload, timeout: timeout)
        }
    }

    private func sendCommandOnMain(_ payload: [UInt8], timeout: TimeInterval = 3) throws -> SonyProtocol.PacketMessage {
        let requestCommand = payload.first ?? 0
        log("send command=0x\(String(requestCommand, radix: 16, uppercase: true)) timeout=\(timeout)")
        let packet = SonyProtocol.packetize(
            payload: payload,
            dataType: .dataMDR,
            sequence: nextCommandSequence
        )

        pendingMessages.removeAll(keepingCapacity: true)
        try send(packet)

        let expectedCommands = expectedResponseCommands(for: requestCommand)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let index = pendingMessages.firstIndex(where: { message in
                guard let command = message.payload.first else {
                    return false
                }
                return expectedCommands.contains(command)
            }) {
                let message = pendingMessages.remove(at: index)
                if let responseCommand = message.payload.first {
                    log("received response command=0x\(String(responseCommand, radix: 16, uppercase: true)) sequence=\(message.sequence)")
                }
                return message
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        log("response timeout command=0x\(String(requestCommand, radix: 16, uppercase: true))")
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

                let commandDescription = message.payload.first.map {
                    " cmd=0x\(String($0, radix: 16, uppercase: true))"
                } ?? ""
                log("rx packet type=\(message.dataType.rawValue) seq=\(message.sequence)\(commandDescription)")

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
            log("RFCOMM channel closed by system/headset")
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
            log("SDP services already present")
            return
        }

        let result = device.performSDPQuery(nil)
        log("performSDPQuery result=\(result)")
        guard result == kIOReturnSuccess else {
            throw SonyTransportError.serviceQueryFailed(result)
        }

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if device.services != nil {
                log("SDP services resolved")
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        log("SDP query wait expired; proceeding with current service cache state")
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
        log("initialization handshake start")
        try sendInitializationPacket([0x00, 0x00])
        try sendInitializationPacket([0x06, 0x00])
        log("initialization handshake complete")
    }

    private func acknowledge(_ message: SonyProtocol.PacketMessage) throws {
        let ackSequence: UInt8 = message.sequence <= 1 ? (1 - message.sequence) : 0
        try sendOnMain(SonyProtocol.makeACKPacket(sequence: ackSequence), recoverTransiently: false)
    }

    private func drainIncomingMessages() {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        pendingMessages.removeAll(keepingCapacity: true)
    }

    private func sendInitializationPacket(_ payload: [UInt8], settleTimeout: TimeInterval = 0.8) throws {
        let commandSummary = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("send init packet [\(commandSummary)]")
        let packet = SonyProtocol.packetize(
            payload: payload,
            dataType: .dataMDR,
            sequence: nextCommandSequence
        )
        let startingSequence = nextCommandSequence
        let startingPendingCount = pendingMessages.count

        try sendOnMain(packet)

        let deadline = Date().addingTimeInterval(settleTimeout)
        while Date() < deadline {
            guard let channel, let activeDevice else {
                throw SonyTransportError.notConnected
            }

            if channel.isOpen() == false || activeDevice.isConnected() == false {
                synchronizeTransportState()
                throw SonyTransportError.notConnected
            }

            if nextCommandSequence != startingSequence || pendingMessages.count > startingPendingCount {
                log("init packet settled [\(commandSummary)] nextSequence=\(nextCommandSequence) pending=\(pendingMessages.count)")
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        log("init packet settle timeout [\(commandSummary)]")
    }

    private func performWrite(_ data: Data, on channel: IOBluetoothRFCOMMChannel) -> IOReturn {
        data.withUnsafeBytes { buffer in
            channel.writeSync(
                UnsafeMutableRawPointer(mutating: buffer.baseAddress),
                length: UInt16(buffer.count)
            )
        }
    }

    private func waitUntilChannelIsWritable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let channel, let activeDevice else {
                return false
            }

            if channel.isOpen() == false || activeDevice.isConnected() == false {
                return false
            }

            if !channel.isTransmissionPaused() {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        guard let channel, let activeDevice else {
            return false
        }

        return channel.isOpen() && activeDevice.isConnected() && !channel.isTransmissionPaused()
    }

    private func validateTransport(channel: IOBluetoothRFCOMMChannel, device: IOBluetoothDevice) throws {
        guard channel.isOpen(), device.isConnected() else {
            synchronizeTransportState()
            throw SonyTransportError.notConnected
        }
    }

    private func synchronizeTransportState() {
        if channel?.isOpen() == false {
            channel = nil
        }

        if activeDevice?.isConnected() == false {
            activeDevice = nil
        }

        if channel == nil || activeDevice == nil {
            receiveBuffer.removeAll(keepingCapacity: true)
            pendingMessages.removeAll(keepingCapacity: true)
            nextCommandSequence = 0
        }
    }

    private func expectedResponseCommands(for requestCommand: UInt8) -> Set<UInt8> {
        var commands: Set<UInt8> = [requestCommand, requestCommand &+ 1]

        switch requestCommand {
        case SonyProtocol.CommandType.batteryGet.rawValue:
            commands.insert(SonyProtocol.CommandType.batteryNotify.rawValue)
        case SonyProtocol.CommandType.noiseControlGet.rawValue:
            commands.insert(SonyProtocol.CommandType.noiseControlNotify.rawValue)
        case SonyProtocol.CommandType.equalizerGet.rawValue:
            commands.insert(SonyProtocol.CommandType.equalizerNotify.rawValue)
        case SonyProtocol.CommandType.volumeGet.rawValue:
            commands.insert(0xA9)
        case SonyProtocol.CommandType.dseeGet.rawValue:
            commands.insert(SonyProtocol.CommandType.dseeNotify.rawValue)
        case SonyProtocol.CommandType.speakToChatGet.rawValue:
            commands.insert(SonyProtocol.CommandType.speakToChatNotify.rawValue)
        default:
            break
        }

        return commands
    }
}

extension SonyRFCOMMTransport: @unchecked Sendable {}
