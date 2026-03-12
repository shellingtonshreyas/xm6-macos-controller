import Foundation
import IOBluetooth

enum ClassicBluetoothInspectorError: LocalizedError {
    case invalidAddress
    case sdpQueryFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "The device address is invalid."
        case let .sdpQueryFailed(code):
            "Classic Bluetooth service discovery failed. IOReturn \(code)."
        }
    }
}

final class ClassicBluetoothInspector {
    func inspectServices(for device: SonyDevice) throws -> [ClassicServiceRecord] {
        guard let macDevice = IOBluetoothDevice(addressString: device.address) else {
            throw ClassicBluetoothInspectorError.invalidAddress
        }

        if !macDevice.isConnected() {
            _ = macDevice.openConnection()
        }

        let result = macDevice.performSDPQuery(nil)
        guard result == kIOReturnSuccess else {
            throw ClassicBluetoothInspectorError.sdpQueryFailed(result)
        }

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let services = macDevice.services as? [IOBluetoothSDPServiceRecord], !services.isEmpty {
                return mapServices(services)
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let services = (macDevice.services as? [IOBluetoothSDPServiceRecord]) ?? []
        return mapServices(services)
    }

    private func mapServices(_ services: [IOBluetoothSDPServiceRecord]) -> [ClassicServiceRecord] {
        services.map { service in
            var channel: BluetoothRFCOMMChannelID = 0
            let hasRFCOMM = service.getRFCOMMChannelID(&channel) == kIOReturnSuccess

            var psm: BluetoothL2CAPPSM = 0
            let hasL2CAP = service.getL2CAPPSM(&psm) == kIOReturnSuccess

            var handle: BluetoothSDPServiceRecordHandle = 0
            _ = service.getHandle(&handle)

            return ClassicServiceRecord(
                id: "\(handle)",
                name: service.getServiceName() ?? "Unnamed service",
                recordHandle: String(format: "0x%08X", handle),
                rfcommChannel: hasRFCOMM ? String(channel) : nil,
                l2capPSM: hasL2CAP ? String(format: "0x%04X", psm) : nil,
                attributeCount: service.attributes.count
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
