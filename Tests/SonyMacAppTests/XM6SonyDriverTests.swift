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
            case SonyProtocol.CommandType.equalizerGet.rawValue:
                if payload[1] == SonyProtocol.EqualizerInquiryType.presetWithErrorCode.rawValue {
                    return SonyProtocol.PacketMessage(
                        dataType: .dataMDR,
                        sequence: 0,
                        payload: [SonyProtocol.CommandType.equalizerReturn.rawValue, 0x04, 0xA0, 0x00]
                    )
                }
                return SonyProtocol.PacketMessage(
                    dataType: .dataMDR,
                    sequence: 0,
                    payload: [
                        SonyProtocol.CommandType.equalizerReturn.rawValue,
                        0x00,
                        0xA0,
                        0x0A,
                        0x00,
                        0x01,
                        0x02,
                        0x03,
                        0x04,
                        0x05,
                        0x06,
                        0x07,
                        0x08,
                        0x09
                    ]
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
        XCTAssertEqual(driver.currentStatus.equalizerPreset, .manual)
        XCTAssertEqual(driver.currentStatus.equalizerBandValues, [-6, -5, -4, -3, -2, -1, 0, 1, 2, 3])
        XCTAssertTrue(driver.currentStatus.hasEqualizerBandValues)
        XCTAssertNil(driver.currentStatus.batteryLevel)
    }

    func testPresetResponseWithoutBandsClearsStaleCurveAvailability() throws {
        let driver = XM6SonyDriver()
        let error = SonyTransportError.responseTimeout(0)

        try driver.refreshState { payload in
            guard payload.first == SonyProtocol.CommandType.equalizerGet.rawValue else { throw error }
            return SonyProtocol.PacketMessage(
                dataType: .dataMDR,
                sequence: 0,
                payload: [
                    SonyProtocol.CommandType.equalizerReturn.rawValue,
                    0x00,
                    0xA2,
                    0x0A,
                    10, 10, 9, 4, 6, 6, 6, 8, 8, 9
                ]
            )
        }
        XCTAssertTrue(driver.currentStatus.hasEqualizerBandValues)

        try driver.refreshState { payload in
            guard payload.first == SonyProtocol.CommandType.equalizerGet.rawValue else { throw error }
            return SonyProtocol.PacketMessage(
                dataType: .dataMDR,
                sequence: 0,
                payload: [SonyProtocol.CommandType.equalizerReturn.rawValue, payload[1], 0x30, 0x00]
            )
        }

        XCTAssertEqual(driver.currentStatus.equalizerPreset, .heavy)
        XCTAssertFalse(driver.currentStatus.hasEqualizerBandValues)
    }

    func testEqualizerPresetPayloadUsesXM6InquiryType() throws {
        XCTAssertEqual(
            try SonyProtocol.equalizerPresetPayload(.clear),
            [SonyProtocol.CommandType.equalizerSet.rawValue, 0x04, 0x31, 0x00]
        )
        XCTAssertEqual(
            try SonyProtocol.equalizerPresetPayload(.custom1),
            [SonyProtocol.CommandType.equalizerSet.rawValue, 0x00, 0xA1, 0x00]
        )
        XCTAssertEqual(
            try SonyProtocol.equalizerPresetPayload(.manual),
            [SonyProtocol.CommandType.equalizerSet.rawValue, 0x00, 0xA0, 0x00]
        )
    }

    func testManualEqualizerPayloadEncodesTenXM6Bands() throws {
        let bands = [
            EqualizerBand(id: "31", label: "31", value: -6),
            EqualizerBand(id: "63", label: "63", value: -5),
            EqualizerBand(id: "125", label: "125", value: -4),
            EqualizerBand(id: "250", label: "250", value: -3),
            EqualizerBand(id: "500", label: "500", value: -2),
            EqualizerBand(id: "1k", label: "1k", value: -1),
            EqualizerBand(id: "2k", label: "2k", value: 0),
            EqualizerBand(id: "4k", label: "4k", value: 1),
            EqualizerBand(id: "8k", label: "8k", value: 2),
            EqualizerBand(id: "16k", label: "16k", value: 6)
        ]

        XCTAssertEqual(
            try SonyProtocol.equalizerManualPayload(bands),
            [SonyProtocol.CommandType.equalizerSet.rawValue, 0x00, 0xA0, 0x0A, 0, 1, 2, 3, 4, 5, 6, 7, 8, 12]
        )
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
