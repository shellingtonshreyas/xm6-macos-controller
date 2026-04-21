import XCTest
@testable import SonyMacApp

final class SonyHeadphoneSessionTests: XCTestCase {
    @MainActor
    func testApplyDSEEWhileDisconnectedLeavesStateUntouched() async {
        let session = makeSession(driver: FailingDriver())

        session.applyDSEEExtreme(true)

        XCTAssertFalse(session.state.dseeExtreme)
        XCTAssertEqual(session.state.statusMessage, "Connect your Sony headphones in macOS first.")
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

    func testNoiseControlPayloadAllowsExperimentalVoiceFocusWithNoiseCancelling() throws {
        let payload = try SonyProtocol.noiseControlPayload(
            mode: .noiseCancelling,
            ambientLevel: 10,
            focusOnVoice: true
        )

        XCTAssertEqual(payload[3], 0x01)
        XCTAssertEqual(payload[4], 0x00)
        XCTAssertEqual(payload[5], 0x01)
        XCTAssertEqual(payload[7], 0x01)
    }

    @MainActor
    func testApplyVolumeWhileDisconnectedLeavesStateUntouched() async {
        let session = makeSession(driver: FailingDriver())

        session.applyVolumeLevel(18)

        XCTAssertEqual(session.state.volumeLevel, 0)
        XCTAssertEqual(session.state.statusMessage, "Connect your Sony headphones in macOS first.")
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
    func testApplyVolumeLazilyOpensControlChannelForMacConnectedDevice() async {
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: true
        )
        let driver = LazyConnectDriver(device: device)
        let session = makeSession(driver: driver)
        session.refreshDevices()

        session.applyVolumeLevel(18)
        await waitUntilIdle(session)

        XCTAssertEqual(driver.connectCallCount, 1)
        XCTAssertEqual(session.state.connectedDeviceID, device.id)
        XCTAssertEqual(session.state.connectionLabel, device.name)
        XCTAssertEqual(session.state.volumeLevel, 18)
        XCTAssertEqual(session.state.statusMessage, "Volume updated.")
    }

    @MainActor
    func testApplyVolumeReconnectsAfterResponseTimeoutWhenMacStillOwnsHeadset() async {
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: true
        )
        let driver = ResponseTimeoutThenReconnectDriver(device: device)
        let session = makeSession(driver: driver)
        session.refreshDevices()
        session.state.connectedDeviceID = device.id

        session.applyVolumeLevel(18)
        await waitUntilIdle(session)

        XCTAssertEqual(driver.connectCallCount, 1)
        XCTAssertEqual(driver.volumeAttemptCount, 2)
        XCTAssertEqual(session.state.connectedDeviceID, device.id)
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
        try? await Task.sleep(for: .milliseconds(4200))

        XCTAssertEqual(session.state.connectedDeviceID, device.id)
        XCTAssertEqual(session.state.connectionLabel, device.name)
        XCTAssertEqual(
            session.state.statusMessage,
            "Connected. Control channel is still settling because the headset was already connected in macOS."
        )
    }

    @MainActor
    func testConnectPreferredDeviceRequiresMacConnectedHeadset() async {
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: false
        )
        let session = makeSession(driver: DeviceListDriver(devices: [device]))

        session.connectPreferredDevice()

        XCTAssertNil(session.state.connectedDeviceID)
        XCTAssertEqual(session.state.statusMessage, "Connect your Sony headphones in macOS first.")
    }

    @MainActor
    func testRefreshDevicesShowsMacConnectedHeadsetBeforeControlChannelOpens() async {
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: true
        )
        let session = makeSession(driver: DeviceListDriver(devices: [device]))

        session.refreshDevices()

        XCTAssertNil(session.state.connectedDeviceID)
        XCTAssertEqual(session.state.connectionLabel, device.name)
        XCTAssertEqual(
            session.state.statusMessage,
            "Connected to \(device.name) in macOS. Sony control channel is not connected yet."
        )
    }

    @MainActor
    func testLowFrequencyBatteryRefreshUpdatesBatteryTextAfterControlChannelOpens() async {
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: true
        )
        let driver = BatteryRefreshDriver(device: device, refreshedBatteryLevel: 84)
        let session = makeSession(driver: driver)
        session.refreshDevices()
        session.state.connectedDeviceID = device.id

        session.refreshDevices()
        await waitForBatteryText(session, expected: "84%")

        XCTAssertEqual(driver.refreshBatteryStatusCallCount, 1)
        XCTAssertEqual(session.state.batteryText, "84%")
    }

    @MainActor
    func testDisconnectKeepsMacBluetoothConnectionStatus() async {
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: true
        )
        let session = makeSession(driver: DeviceListDriver(devices: [device]))
        session.refreshDevices()
        session.state.connectedDeviceID = device.id
        session.state.batteryText = "78%"
        session.state.volumeLevel = 18

        session.disconnect()

        XCTAssertNil(session.state.connectedDeviceID)
        XCTAssertEqual(session.state.connectionLabel, device.name)
        XCTAssertEqual(session.state.batteryText, "78%")
        XCTAssertEqual(session.state.volumeLevel, 18)
        XCTAssertEqual(
            session.state.statusMessage,
            "Connected to \(device.name) in macOS. Open Sony's control channel when you need live controls."
        )
    }

    @MainActor
    func testDiagnosticsReportIncludesConnectionStateDevicesAndRecentEvents() async {
        let device = SonyDevice(
            id: "device-1",
            name: "WH-1000XM6",
            address: "00-11-22-33-44-55",
            isConnected: true
        )
        let session = makeSession(driver: DeviceListDriver(devices: [device]))
        session.refreshDevices()
        session.state.connectedDeviceID = device.id
        session.state.connectionLabel = device.name
        session.applyVolumeLevel(18)
        await waitUntilIdle(session)
        session.state.batteryText = "78%"
        session.state.noiseControlMode = .ambient
        session.state.ambientLevel = 20
        session.state.statusMessage = "Ready for testing."

        let report = session.diagnosticsReport(
            now: Date(timeIntervalSince1970: 1_234_567_890)
        )

        XCTAssertTrue(report.contains("Sony Audio Diagnostics Report"))
        XCTAssertTrue(report.contains("Headset Label: \(device.name)"))
        XCTAssertTrue(report.contains("Mac Audio Connected: Yes"))
        XCTAssertTrue(report.contains("Sony Control Channel: Open (\(device.id))"))
        XCTAssertTrue(report.contains("- \(device.name) | Connected in macOS | \(device.address)"))
        XCTAssertTrue(report.contains("Battery: 78%"))
        XCTAssertTrue(report.contains("Ambient Level: 20"))
        XCTAssertTrue(report.contains("Ready for testing."))
        XCTAssertTrue(report.contains("Copied diagnostics report") == false)
        XCTAssertTrue(report.contains("Updating volume"))
    }

    @MainActor
    func testApplyNoiseControlModeDoesNotCarryAmbientVoiceFocusIntoNoiseCancelling() async {
        let session = makeSession(driver: SlowSuccessDriver(delay: 0.05))
        session.state.connectedDeviceID = "device-1"
        session.state.noiseControlMode = .ambient
        session.state.focusOnVoice = true

        session.applyNoiseControlMode(.noiseCancelling)
        await waitUntilIdle(session)

        XCTAssertEqual(session.state.noiseControlMode, .noiseCancelling)
        XCTAssertFalse(session.state.focusOnVoice)
        XCTAssertEqual(session.state.statusMessage, "Noise control updated.")
    }

    @MainActor
    func testExperimentalNoiseCancellingVoiceFocusUpdatesState() async {
        let session = makeSession(driver: SlowSuccessDriver(delay: 0.05))
        session.state.connectedDeviceID = "device-1"
        session.state.noiseControlMode = .noiseCancelling

        session.applyExperimentalNoiseCancellingVoiceFocus(true)
        await waitUntilIdle(session)

        XCTAssertEqual(session.state.noiseControlMode, .noiseCancelling)
        XCTAssertTrue(session.state.focusOnVoice)
        XCTAssertEqual(session.state.statusMessage, "Experimental ANC voice focus sent.")
    }

    @MainActor
    func testExperimentalNoiseCancellingVoiceFocusRequiresNoiseCancellingMode() async {
        let session = makeSession(driver: SlowSuccessDriver(delay: 0.05))
        session.state.connectedDeviceID = "device-1"
        session.state.noiseControlMode = .ambient
        session.state.focusOnVoice = false

        session.applyExperimentalNoiseCancellingVoiceFocus(true)

        XCTAssertFalse(session.state.isBusy)
        XCTAssertFalse(session.state.focusOnVoice)
        XCTAssertEqual(session.state.statusMessage, "Select Noise Cancelling to use experimental voice focus.")
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

    func refreshBatteryStatus() throws {
        throw TestDriverError.forcedFailure
    }

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

    func refreshBatteryStatus() throws {
        Thread.sleep(forTimeInterval: delay)
    }

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
    private var connectedDevice: SonyDevice?

    func loadDevices() -> [SonyDevice] {
        connectedDevice.map { [$0] } ?? []
    }

    func connect(to device: SonyDevice) throws {
        connectedDevice = device
    }

    func disconnect() {
        connectedDevice = nil
    }

    func refreshState() throws {
        throw TestDriverError.forcedFailure
    }

    func requestStateRefresh() throws {
        throw TestDriverError.forcedFailure
    }

    func refreshBatteryStatus() throws {
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

private final class LazyConnectDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    var currentStatus = SonyControlStatus()
    let device: SonyDevice
    private(set) var connectCallCount = 0

    init(device: SonyDevice) {
        self.device = device
    }

    func loadDevices() -> [SonyDevice] {
        [device]
    }

    func connect(to device: SonyDevice) throws {
        connectCallCount += 1
    }

    func disconnect() {}

    func refreshState() throws {}

    func requestStateRefresh() throws {}

    func refreshBatteryStatus() throws {}

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {}

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {}

    func setVolume(_ level: Int) throws {
        currentStatus.volumeLevel = level
    }

    func setDSEEExtreme(_ enabled: Bool) throws {}

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {}

    func setSpeakToChat(_ enabled: Bool) throws {}
}

extension LazyConnectDriver: @unchecked Sendable {}

private final class ResponseTimeoutThenReconnectDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    var currentStatus = SonyControlStatus()
    let device: SonyDevice
    private(set) var connectCallCount = 0
    private(set) var volumeAttemptCount = 0

    init(device: SonyDevice) {
        self.device = device
    }

    func loadDevices() -> [SonyDevice] {
        [device]
    }

    func connect(to device: SonyDevice) throws {
        connectCallCount += 1
    }

    func disconnect() {}

    func refreshState() throws {}

    func requestStateRefresh() throws {}

    func refreshBatteryStatus() throws {}

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {}

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {}

    func setVolume(_ level: Int) throws {
        volumeAttemptCount += 1
        if connectCallCount == 0 {
            throw SonyTransportError.responseTimeout(SonyProtocol.CommandType.volumeSet.rawValue)
        }

        currentStatus.volumeLevel = level
    }

    func setDSEEExtreme(_ enabled: Bool) throws {}

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {}

    func setSpeakToChat(_ enabled: Bool) throws {}
}

extension ResponseTimeoutThenReconnectDriver: @unchecked Sendable {}

private final class BatteryRefreshDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    var currentStatus = SonyControlStatus()
    let device: SonyDevice
    let refreshedBatteryLevel: Int
    private(set) var refreshBatteryStatusCallCount = 0

    init(device: SonyDevice, refreshedBatteryLevel: Int) {
        self.device = device
        self.refreshedBatteryLevel = refreshedBatteryLevel
    }

    func loadDevices() -> [SonyDevice] {
        [device]
    }

    func connect(to device: SonyDevice) throws {}

    func disconnect() {}

    func refreshState() throws {}

    func requestStateRefresh() throws {}

    func refreshBatteryStatus() throws {
        refreshBatteryStatusCallCount += 1
        currentStatus.batteryLevel = refreshedBatteryLevel
        currentStatus.isCharging = false
    }

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {}

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {}

    func setVolume(_ level: Int) throws {}

    func setDSEEExtreme(_ enabled: Bool) throws {}

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {}

    func setSpeakToChat(_ enabled: Bool) throws {}
}

extension BatteryRefreshDriver: @unchecked Sendable {}

private final class DeviceListDriver: SonyHeadphoneDriver {
    let featureSupport = FeatureSupport.xm6Native
    var currentStatus = SonyControlStatus()
    private let devices: [SonyDevice]

    init(devices: [SonyDevice]) {
        self.devices = devices
    }

    func loadDevices() -> [SonyDevice] {
        devices
    }

    func connect(to device: SonyDevice) throws {}

    func disconnect() {}

    func refreshState() throws {}

    func requestStateRefresh() throws {}

    func refreshBatteryStatus() throws {}

    func applyNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) throws {}

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) throws {}

    func setVolume(_ level: Int) throws {}

    func setDSEEExtreme(_ enabled: Bool) throws {}

    func setEqualizer(preset: EqualizerPreset, bands: [EqualizerBand]) throws {}

    func setSpeakToChat(_ enabled: Bool) throws {}
}

extension DeviceListDriver: @unchecked Sendable {}

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

@MainActor
private func waitForBatteryText(
    _ session: SonyHeadphoneSession,
    expected: String,
    timeout: TimeInterval = 1.5
) async {
    let deadline = Date().addingTimeInterval(timeout)

    while session.state.batteryText != expected, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }

    XCTAssertEqual(session.state.batteryText, expected, "Expected the session battery text to refresh before timing out.")
}
