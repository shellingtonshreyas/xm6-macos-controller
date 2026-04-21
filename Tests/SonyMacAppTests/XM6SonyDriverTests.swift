import XCTest
@testable import SonyMacApp

final class XM6SonyDriverTests: XCTestCase {
    func testRefreshStateContinuesWhenOneInitialQueryFails() throws {
        let driver = XM6SonyDriver()
        let error = SonyTransportError.responseTimeout(SonyProtocol.CommandType.batteryGet.rawValue)

        try driver.refreshState { payload in
            switch payload.first {
            case SonyProtocol.CommandType.noiseControlGet.rawValue:
                return SonyProtocol.PacketMessage(
                    dataType: .dataMDR,
                    sequence: 0,
                    payload: [
                        SonyProtocol.CommandType.noiseControlReturn.rawValue,
                        SonyProtocol.NoiseControlInquiryType.xm6.rawValue,
                        0x01,
                        0x01,
                        0x00,
                        0x01,
                        0x14,
                        0x00,
                        0x00
                    ]
                )
            case SonyProtocol.CommandType.volumeGet.rawValue:
                return SonyProtocol.PacketMessage(
                    dataType: .dataMDR,
                    sequence: 0,
                    payload: [SonyProtocol.CommandType.volumeReturn.rawValue, 0x20, 0x12]
                )
            case SonyProtocol.CommandType.dseeGet.rawValue:
                return SonyProtocol.PacketMessage(
                    dataType: .dataMDR,
                    sequence: 0,
                    payload: [SonyProtocol.CommandType.dseeReturn.rawValue, 0x01, 0x01]
                )
            case SonyProtocol.CommandType.speakToChatGet.rawValue:
                return SonyProtocol.PacketMessage(
                    dataType: .dataMDR,
                    sequence: 0,
                    payload: [SonyProtocol.CommandType.speakToChatReturn.rawValue, 0x02, 0x00]
                )
            case SonyProtocol.CommandType.batteryGet.rawValue:
                throw error
            default:
                XCTFail("Unexpected query payload: \(payload)")
                throw error
            }
        }

        XCTAssertEqual(driver.currentStatus.noiseControlMode, .noiseCancelling)
        XCTAssertEqual(driver.currentStatus.volumeLevel, 18)
        XCTAssertTrue(driver.currentStatus.dseeEnabled)
        XCTAssertFalse(driver.currentStatus.speakToChatEnabled)
        XCTAssertNil(driver.currentStatus.batteryLevel)
    }

    func testRefreshStateThrowsWhenNoQueriesReturn() {
        let driver = XM6SonyDriver()
        let error = SonyTransportError.responseTimeout(SonyProtocol.CommandType.batteryGet.rawValue)

        XCTAssertThrowsError(
            try driver.refreshState { _ in
                throw error
            }
        ) { thrown in
            guard case let SonyTransportError.responseTimeout(command) = thrown else {
                return XCTFail("Unexpected error: \(thrown)")
            }
            XCTAssertEqual(command, SonyProtocol.CommandType.batteryGet.rawValue)
        }
    }
}
