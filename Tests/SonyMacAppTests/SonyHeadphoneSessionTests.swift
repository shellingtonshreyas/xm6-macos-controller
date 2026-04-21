import XCTest
@testable import SonyMacApp

final class SonyHeadphoneSessionTests: XCTestCase {
    @MainActor
    func testApplyDSEEWhileDisconnectedLeavesStateUntouched() async {
        let session = makeSession(driver: FailingDriver())

        session.applyDSEEExtreme(true)

        XCTAssertFalse(session.state.dseeExtreme)
        XCTAssertEqual(session.state.statusMessage, "Connect your Sony headphones first.")
    }

    @MainActor
    func testFailedSpeakToChatDoesNotLeaveStaleUIState() async {
        let session = makeSession(driver: FailingDriver())
        session.state.connectedDeviceID = "device-1"

        session.applySpeakToChat(true)
        await waitUntilIdle(session)

        XCTAssertFalse(session.state.speakToChat)
        XCTAssertEqual(session.state.statusMessage, TestDriverError.forcedFailure.localizedDescription)
    }

    @MainActor
    func testApplyReturnsImmediatelyAndCompletesInBackground() async {
        let session = makeSession(driver: SlowSuccessDriver(delay: 0.35))
        session.state.connectedDeviceID = "device-1"

        let start = Date()
        session.applyDSEEExtreme(true)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.15)
        XCTAssertTrue(session.state.isBusy)

        await waitUntilIdle(session)

        XCTAssertTrue(session.state.dseeExtreme)
        XCTAssertEqual(session.state.statusMessage, "DSEE Extreme enabled.")
    }

    func testAmbientLevelRangeIncludesMaximumSupportedValue() throws {
        XCTAssertEqual(NoiseControlMode.ambientLevelRange, 0 ... 20)
        XCTAssertNoThrow(
            try SonyProtocol.noiseControlPayload(
                mode: .ambient,
                ambientLevel: NoiseControlMode.ambientLevelRange.upperBound,
                focusOnVoice: false
            )
        )
    }

    @MainActor
    func testApplyVolumeWhileDisconnectedLeavesStateUntouched() async {
        let session = makeSession(driver: FailingDriver())

        session.applyVolumeLevel(18)

        XCTAssertEqual(session.state.volumeLevel, 0)
        XCTAssertEqual(session.state.statusMessage, "Connect your Sony headphones first.")
    }

    @MainActor
    func testApplyVolumeCompletesInBackgroundAndUpdatesState() async {
        let session = makeSession(driver: SlowSuccessDriver(delay: 0.35))
        session.state.connectedDeviceID = "device-1"

        let start = Date()
        session.applyVolumeLevel(18)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.15)
        XCTAssertTrue(session.state.isBusy)

        await waitUntilIdle(session)

        XCTAssertEqual(session.state.volumeLevel, 18)
        XCTAssertEqual(session.state.statusMessage, "Volume updated.")
    }

    @MainActor
    func testConnectStaysEstablishedWhenInitialBackgroundRefreshFails() async {
        let session = makeSession(driver: ConnectSucceedsButRefreshFailsDriver())
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: true
        )

        session.connect(to: device)
        await waitUntilIdle(session)
        try? await Task.sleep(for: .milliseconds(2900))

        XCTAssertEqual(session.state.connectedDeviceID, device.id)
        XCTAssertEqual(session.state.connectionLabel, device.name)
        XCTAssertEqual(session.state.statusMessage, "Connected to XM6 control channel.")
    }

    func testVolumeRangeIncludesMaximumSupportedValue() throws {
        XCTAssertEqual(HeadphoneState.volumeLevelRange, 0 ... 30)
        XCTAssertNoThrow(try SonyProtocol.volumeSetPayload(HeadphoneState.volumeLevelRange.upperBound))
        XCTAssertThrowsError(try SonyProtocol.volumeSetPayload(HeadphoneState.volumeLevelRange.upperBound + 1))
    }
}

private enum TestDriverError: LocalizedError {
    case forcedFailure

    var errorDescription: String? {
        "forced failure"
    }
}

private final class FailingDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    var currentStatus = SonyControlStatus()

    func loadDevices() -> [SonyDevice] {
        []
    }

    func connect(to device: SonyDevice) throws {
        throw TestDriverError.forcedFailure
    }

    func disconnect() {}

    func refreshState() throws {}

    func requestStateRefresh() throws {}

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {
        throw TestDriverError.forcedFailure
    }

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {
        throw TestDriverError.forcedFailure
    }

    func setVolume(_ level: Int) throws {
        throw TestDriverError.forcedFailure
    }

    func setDSEEExtreme(_ enabled: Bool) throws {
        throw TestDriverError.forcedFailure
    }

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {
        throw TestDriverError.forcedFailure
    }

    func setSpeakToChat(_ enabled: Bool) throws {
        throw TestDriverError.forcedFailure
    }
}

extension FailingDriver: @unchecked Sendable {}

private final class SlowSuccessDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    var currentStatus = SonyControlStatus()
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func loadDevices() -> [SonyDevice] {
        []
    }

    func connect(to device: SonyDevice) throws {
        Thread.sleep(forTimeInterval: delay)
    }

    func disconnect() {}

    func refreshState() throws {}

    func requestStateRefresh() throws {}

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {
        Thread.sleep(forTimeInterval: delay)
        currentStatus.noiseControlMode = mode
        currentStatus.ambientLevel = ambientLevel
        currentStatus.focusOnVoice = focusOnVoice
    }

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {}

    func setVolume(_ level: Int) throws {
        Thread.sleep(forTimeInterval: delay)
        currentStatus.volumeLevel = level
    }

    func setDSEEExtreme(_ enabled: Bool) throws {
        Thread.sleep(forTimeInterval: delay)
        currentStatus.dseeEnabled = enabled
    }

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {
        Thread.sleep(forTimeInterval: delay)
        currentStatus.equalizerPreset = preset
    }

    func setSpeakToChat(_ enabled: Bool) throws {
        Thread.sleep(forTimeInterval: delay)
        currentStatus.speakToChatEnabled = enabled
    }
}

extension SlowSuccessDriver: @unchecked Sendable {}

private final class ConnectSucceedsButRefreshFailsDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    var currentStatus = SonyControlStatus()

    func loadDevices() -> [SonyDevice] {
        []
    }

    func connect(to device: SonyDevice) throws {}

    func disconnect() {}

    func refreshState() throws {
        throw TestDriverError.forcedFailure
    }

    func requestStateRefresh() throws {
        throw TestDriverError.forcedFailure
    }

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {}

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {}

    func setVolume(_ level: Int) throws {}

    func setDSEEExtreme(_ enabled: Bool) throws {}

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {}

    func setSpeakToChat(_ enabled: Bool) throws {}
}

extension ConnectSucceedsButRefreshFailsDriver: @unchecked Sendable {}

@MainActor
private func makeSession(driver: SonyHeadphoneDriver) -> SonyHeadphoneSession {
    SonyHeadphoneSession(
        driver: driver,
        classicInspector: ClassicBluetoothInspector(),
        bleDiscovery: BLEGATTDiscovery()
    )
}

@MainActor
private func waitUntilIdle(_ session: SonyHeadphoneSession, timeout: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(timeout)

    while session.state.isBusy, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }

    XCTAssertFalse(session.state.isBusy, "Expected the session to finish before timing out.")
}
