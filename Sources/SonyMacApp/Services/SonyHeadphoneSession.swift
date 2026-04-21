import AppKit
import Foundation
import Observation
import SwiftUI

private struct DriverSnapshot: Sendable {
    let status: SonyControlStatus
    let support: FeatureSupport

    init(driver: SonyHeadphoneDriver) {
        status = driver.currentStatus
        support = driver.featureSupport
    }
}

private struct SessionDiagnosticsEntry: Sendable {
    let timestamp: Date
    let message: String
}

@Observable
@MainActor
final class SonyHeadphoneSession {
    private static let autoConnectRetryDelay: TimeInterval = 8
    private static let batteryRefreshInterval: TimeInterval = 30

    private let driver: SonyHeadphoneDriver
    private let classicInspector: ClassicBluetoothInspector
    private let bleDiscovery: BLEGATTDiscovery
    private let blockingQueue = DispatchQueue(label: "SonyMacApp.blocking", qos: .userInitiated)
    private let statusRefreshRequestDelayFreshConnect: Duration = .milliseconds(700)
    private let statusRefreshRequestDelayAlreadyConnected: Duration = .seconds(2)
    private let statusRefreshSnapshotDelay: Duration = .seconds(2)
    private var autoRefreshTask: Task<Void, Never>?
    private var batteryRefreshTask: Task<Void, Never>?
    private var lastBatteryRefreshAttemptAt: Date?
    private var lastAutoConnectFailure: (deviceID: String, date: Date)?
    private var didBootstrap = false
    private var actionGeneration: UInt64 = 0
    private var classicInspectionGeneration: UInt64 = 0
    private var diagnosticsLog: [SessionDiagnosticsEntry] = []

    var devices: [SonyDevice] = []
    var classicServices: [ClassicServiceRecord] = []
    var blePeripherals: [BLEPeripheralRecord] = []
    var selectedBLEPeripheralID: UUID?
    var selectedBLEServices: [GATTServiceRecord] = []
    var bleWriteTargets: [BLEWriteTarget] = []
    var selectedBLEWriteTargetID: String?
    var bleHexPayload = ""
    var bleActionMarker = ""
    var bleConsoleLog: [BLEConsoleLogEntry] = []
    var discoveryStatus = "Classic and BLE discovery idle."
    var isScanningBLE = false
    var startupIsComplete = false
    var state = HeadphoneState()
    var connectionRecoveryGuide: ConnectionRecoveryGuide?

    init(
        driver: SonyHeadphoneDriver = XM6SonyDriver(),
        classicInspector: ClassicBluetoothInspector = ClassicBluetoothInspector(),
        bleDiscovery: BLEGATTDiscovery = BLEGATTDiscovery()
    ) {
        self.driver = driver
        self.classicInspector = classicInspector
        self.bleDiscovery = bleDiscovery
        state.support = driver.featureSupport
        wireDiscoveryCallbacks()
        startAutoRefreshLoop()
        recordDiagnostic("Session initialized.")
    }

    var hasMacConnectedDevice: Bool {
        devices.contains(where: { $0.isConnected })
    }

    var hasUsableHeadsetConnection: Bool {
        state.connectedDeviceID != nil || hasMacConnectedDevice
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else {
            startupIsComplete = true
            return
        }

        didBootstrap = true
        state.statusMessage = "Initializing Bluetooth services..."
        refreshDevices(allowAutoConnect: true)
        startupIsComplete = true
        if state.connectedDeviceID == nil, hasMacConnectedDevice == false {
            state.statusMessage = "Ready"
        }
    }

    func refreshDevices(allowAutoConnect: Bool = false) {
        devices = driver.loadDevices()
        let macConnectedDevice = devices.first(where: { $0.isConnected })

        if let connectedDeviceID = state.connectedDeviceID,
           devices.contains(where: { $0.id == connectedDeviceID }) == false {
            state.connectedDeviceID = nil
            state.connectionLabel = macConnectedDevice?.name ?? "No Sony headphones connected"
            if macConnectedDevice == nil {
                state.batteryText = "Unknown"
                state.volumeLevel = 0
            }
        } else if state.connectedDeviceID == nil {
            state.connectionLabel = macConnectedDevice?.name ?? "No Sony headphones connected"
        }

        if macConnectedDevice == nil {
            lastAutoConnectFailure = nil
            if state.connectedDeviceID == nil, allowAutoConnect {
                state.statusMessage = "Ready"
            }
        } else if let lastAutoConnectFailure,
                  devices.contains(where: { $0.id == lastAutoConnectFailure.deviceID && $0.isConnected }) == false {
            self.lastAutoConnectFailure = nil
            if state.connectedDeviceID == nil, allowAutoConnect {
                state.statusMessage = "Ready"
            }
        }

        if allowAutoConnect {
            if state.connectedDeviceID == nil, state.isBusy == false, let macConnectedDevice {
                state.statusMessage = "Connected to \(macConnectedDevice.name) in macOS. Open Sony's control channel when you need live controls."
            }
        } else if state.connectedDeviceID == nil {
            if let macConnectedDevice {
                state.statusMessage = "Connected to \(macConnectedDevice.name) in macOS. Sony control channel is not connected yet."
            } else {
                state.statusMessage = "Refresh completed."
            }
        }

        scheduleBatteryRefreshIfNeeded()
    }

    func connect(to device: SonyDevice, isAutomatic: Bool = false) {
        guard state.isBusy == false else {
            return
        }

        recordDiagnostic(
            isAutomatic
                ? "Attempting automatic Sony control-channel open for \(device.name)."
                : "Attempting Sony control-channel open for \(device.name)."
        )

        let token = beginBusyAction(
            isAutomatic ? "Auto-connecting to \(device.name)..." : "Connecting to \(device.name)..."
        )
        let driver = self.driver

        Task { [weak self, driver] in
            guard let self else { return }

            do {
                let snapshot = try await self.runBlocking {
                    try driver.connect(to: device)
                    return DriverSnapshot(driver: driver)
                }
                self.completeConnect(
                    token: token,
                    device: device,
                    snapshot: snapshot
                )
            } catch {
                self.failDriverAction(
                    token: token,
                    error: error,
                    attemptedDevice: device,
                    isAutomatic: isAutomatic,
                    disconnectOnFailure: true
                )
            }
        }
    }

    func connectPreferredDevice() {
        refreshDevices()

        if let connectedAudioDevice = devices.first(where: { $0.isConnected }) {
            connect(to: connectedAudioDevice)
            return
        }

        recordDiagnostic("Connect requested, but no Sony headset was connected in macOS.")
        state.statusMessage = devices.isEmpty
            ? "No paired XM6 was found."
            : "Connect your Sony headphones in macOS first."
    }

    func inspectClassicServices(for device: SonyDevice) {
        classicInspectionGeneration &+= 1
        let token = classicInspectionGeneration
        discoveryStatus = "Inspecting classic services for \(device.name)..."

        let classicInspector = self.classicInspector

        Task { [weak self, classicInspector] in
            guard let self else { return }

            do {
                let services = try await self.runBlocking {
                    try classicInspector.inspectServices(for: device)
                }
                self.completeClassicInspection(token: token, device: device, services: services)
            } catch {
                self.failClassicInspection(token: token, error: error)
            }
        }
    }

    func startBLEScan() {
        bleDiscovery.startScanning()
    }

    func stopBLEScan() {
        bleDiscovery.stopScanning()
    }

    func inspectBLEPeripheral(_ peripheralID: UUID) {
        selectedBLEPeripheralID = peripheralID
        selectedBLEServices = bleDiscovery.services(for: peripheralID)
        refreshBLEWriteTargets()
        bleDiscovery.connect(to: peripheralID)
    }

    func disconnectBLEPeripheral(_ peripheralID: UUID) {
        bleDiscovery.disconnect(from: peripheralID)
        if selectedBLEPeripheralID == peripheralID {
            selectedBLEServices = bleDiscovery.services(for: peripheralID)
            refreshBLEWriteTargets()
        }
    }

    func subscribeToBLENotifications() {
        guard let selectedBLEPeripheralID else {
            discoveryStatus = "Select a BLE peripheral first."
            return
        }

        bleDiscovery.subscribeToNotifications(for: selectedBLEPeripheralID)
        discoveryStatus = "Subscribing to notify characteristics..."
    }

    func sendBLEHexPayload() {
        guard let target = bleWriteTargets.first(where: { $0.id == selectedBLEWriteTargetID }) else {
            discoveryStatus = "Select a writable BLE characteristic first."
            return
        }

        do {
            try bleDiscovery.writeHex(bleHexPayload, to: target)
            discoveryStatus = "Sent BLE payload to \(target.characteristicUUID)."
        } catch {
            discoveryStatus = error.localizedDescription
        }
    }

    func refreshBLEReads() {
        guard let selectedBLEPeripheralID else {
            discoveryStatus = "Select a BLE peripheral first."
            return
        }

        bleDiscovery.refreshReadableValues(for: selectedBLEPeripheralID)
        discoveryStatus = "Refreshing readable BLE characteristics..."
    }

    func clearBLEConsoleLog() {
        bleConsoleLog.removeAll(keepingCapacity: true)
    }

    func addBLEActionMarker() {
        let trimmed = bleActionMarker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            discoveryStatus = "Enter an action label first."
            return
        }

        addBLEActionMarker(trimmed)
        bleActionMarker = ""
    }

    func addBLEActionMarker(_ marker: String) {
        let trimmed = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            discoveryStatus = "Enter an action label first."
            return
        }

        appendLog(.info, label: "MARKER", payload: trimmed)
        discoveryStatus = "Added action marker."
    }

    func copyBLEConsoleLog() {
        let formatter = ISO8601DateFormatter()
        let text = bleConsoleLog.reversed().map { entry in
            "\(formatter.string(from: entry.timestamp)) [\(entry.kind.rawValue.uppercased())] \(entry.label)\n\(entry.payload)"
        }.joined(separator: "\n\n")

        copyToPasteboard(text.isEmpty ? "No BLE log entries." : text)
        discoveryStatus = "Copied BLE log to clipboard."
    }

    func copyBLEReport() {
        let formatter = ISO8601DateFormatter()

        let header = [
            "Sony Audio BLE Report",
            "Generated: \(formatter.string(from: Date()))",
            "Selected Peripheral: \(selectedPeripheralName)",
            "Discovery Status: \(discoveryStatus)"
        ].joined(separator: "\n")

        let services = selectedBLEServices.map { service in
            let serviceHeader = "Service \(service.uuid) [\(service.isPrimary ? "Primary" : "Secondary")]"
            let serviceError = service.errorSummary.map { "  Error: \($0)" } ?? ""
            let characteristics = service.characteristics.map { characteristic in
                let props = characteristic.properties.joined(separator: ", ")
                let value = characteristic.valueHex.map { "    Value: \($0)" } ?? ""
                let error = characteristic.errorSummary.map { "    Error: \($0)" } ?? ""
                let descriptors = characteristic.descriptors.map { descriptor in
                    let summary = descriptor.valueSummary ?? ""
                    return "    Descriptor \(descriptor.uuid): \(summary)"
                }.joined(separator: "\n")
                return [
                    "  Characteristic \(characteristic.uuid) [\(props)]",
                    value,
                    error,
                    descriptors
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            }.joined(separator: "\n")
            return [serviceHeader, serviceError, characteristics]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }.joined(separator: "\n\n")

        let log = bleConsoleLog.reversed().map { entry in
            "\(formatter.string(from: entry.timestamp)) [\(entry.kind.rawValue.uppercased())] \(entry.label)\n\(entry.payload)"
        }.joined(separator: "\n\n")

        let report = [header, "=== Services ===", services, "=== Log ===", log]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        copyToPasteboard(report)
        discoveryStatus = "Copied BLE report to clipboard."
    }

    func copyDiagnosticsReport() {
        copyToPasteboard(diagnosticsReport())
        recordDiagnostic("Copied diagnostics report to clipboard.")

        if !state.isBusy {
            state.statusMessage = "Copied diagnostics report to clipboard."
        }
    }

    func diagnosticsReport(now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let controlChannelStatus: String = {
            if let connectedDeviceID = state.connectedDeviceID {
                return "Open (\(connectedDeviceID))"
            }

            return hasMacConnectedDevice ? "Closed" : "Unavailable"
        }()
        let devicesSummary = devices.isEmpty
            ? "No paired Sony devices currently loaded."
            : devices.map { device in
                "- \(device.name) | \(device.isConnected ? "Connected in macOS" : "Paired only") | \(device.address)"
            }
            .joined(separator: "\n")
        let recentEvents = diagnosticsLog.isEmpty
            ? "No recent session events recorded."
            : diagnosticsLog.map { entry in
                "\(formatter.string(from: entry.timestamp)) \(entry.message)"
            }
            .joined(separator: "\n")
        let lastBatteryRefresh = lastBatteryRefreshAttemptAt.map { formatter.string(from: $0) } ?? "Never"

        return [
            "Sony Audio Diagnostics Report",
            "Generated: \(formatter.string(from: now))",
            "App Version: \(shortVersion) (\(buildNumber))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "",
            "=== Connection ===",
            "Headset Label: \(state.connectionLabel)",
            "Mac Audio Connected: \(hasMacConnectedDevice ? "Yes" : "No")",
            "Sony Control Channel: \(controlChannelStatus)",
            "Usable Headset Connection: \(hasUsableHeadsetConnection ? "Yes" : "No")",
            "Busy: \(state.isBusy ? "Yes" : "No")",
            "Status Message: \(state.statusMessage)",
            "Recovery Guide Visible: \(connectionRecoveryGuide == nil ? "No" : "Yes")",
            "",
            "=== Live State ===",
            "Battery: \(state.batteryText)",
            "Last Battery Refresh Attempt: \(lastBatteryRefresh)",
            "Noise Control Mode: \(state.noiseControlMode.rawValue)",
            "Ambient Level: \(Int(state.ambientLevel.rounded()))",
            "Focus on Voice: \(state.focusOnVoice ? "On" : "Off")",
            "Volume: \(Int(state.volumeLevel.rounded())) / \(HeadphoneState.volumeLevelRange.upperBound)",
            "DSEE Extreme: \(state.dseeExtreme ? "On" : "Off")",
            "Speak-to-Chat: \(state.speakToChat ? "On" : "Off")",
            "Equalizer Preset: \(state.equalizerPreset.rawValue)",
            "",
            "=== Devices ===",
            devicesSummary,
            "",
            "=== Recent Session Events ===",
            recentEvents,
            "",
            "If transport-level Bluetooth debugging is needed, capture the app from Terminal and include lines that start with [SonyRFCOMMTransport]."
        ].joined(separator: "\n")
    }

    func disconnect() {
        actionGeneration &+= 1
        batteryRefreshTask?.cancel()
        batteryRefreshTask = nil
        lastBatteryRefreshAttemptAt = nil

        let fallbackDeviceName = devices.first(where: { $0.isConnected })?.name

        state.connectedDeviceID = nil
        state.connectionLabel = fallbackDeviceName ?? "No Sony headphones connected"
        if fallbackDeviceName == nil {
            state.batteryText = "Unknown"
            state.volumeLevel = 0
        }
        state.statusMessage = fallbackDeviceName == nil
            ? "Ready"
            : "Connected to \(fallbackDeviceName!) in macOS. Open Sony's control channel when you need live controls."
        state.isBusy = false
        connectionRecoveryGuide = nil
        recordDiagnostic(
            fallbackDeviceName == nil
                ? "Closed Sony control channel."
                : "Closed Sony control channel while macOS kept \(fallbackDeviceName!) connected for audio."
        )

        let driver = self.driver
        Task { [weak self, driver] in
            guard let self else { return }
            _ = try? await self.runBlocking {
                driver.disconnect()
                return true
            }
        }
    }

    func dismissConnectionRecoveryGuide() {
        connectionRecoveryGuide = nil
    }

    func retryConnectionRecoveryGuide() {
        let guide = connectionRecoveryGuide
        connectionRecoveryGuide = nil
        recordDiagnostic("Retry requested from the connection recovery guide.")
        refreshDevices()

        if let retryDeviceID = guide?.retryDeviceID,
           let device = devices.first(where: { $0.id == retryDeviceID }) {
            connect(to: device, isAutomatic: guide?.isAutomatic ?? false)
            return
        }

        connectPreferredDevice()
    }

    func applyNoiseControlMode(_ mode: NoiseControlMode) {
        let focusOnVoice: Bool
        switch mode {
        case .ambient:
            focusOnVoice = state.focusOnVoice
        case .noiseCancelling, .off:
            // Keep the ANC voice-focus combination strictly opt-in through the
            // experimental control surface instead of carrying it over implicitly.
            focusOnVoice = false
        }

        sendNoiseControl(
            mode: mode,
            ambientLevel: Int(state.ambientLevel.rounded()),
            focusOnVoice: focusOnVoice
        )
    }

    func applyAmbientLevel(_ value: Double) {
        sendNoiseControl(
            mode: state.noiseControlMode,
            ambientLevel: Int(value.rounded()),
            focusOnVoice: state.focusOnVoice
        )
    }

    func applyFocusOnVoice(_ enabled: Bool) {
        sendNoiseControl(
            mode: state.noiseControlMode,
            ambientLevel: Int(state.ambientLevel.rounded()),
            focusOnVoice: enabled
        )
    }

    func applyExperimentalNoiseCancellingVoiceFocus(_ enabled: Bool) {
        guard state.noiseControlMode == .noiseCancelling else {
            state.statusMessage = "Select Noise Cancelling to use experimental voice focus."
            return
        }

        let driver = self.driver
        let ambientLevel = Int(state.ambientLevel.rounded())
        perform(
            "Sending experimental ANC voice focus…",
            successMessage: enabled
                ? "Experimental ANC voice focus sent."
                : "Experimental ANC voice focus cleared."
        ) {
            try driver.applyNoiseControl(
                mode: .noiseCancelling,
                ambientLevel: ambientLevel,
                focusOnVoice: enabled
            )
            return DriverSnapshot(driver: driver)
        }
    }

    func applyVolumeLevel(_ value: Double) {
        let driver = self.driver
        let level = Int(value.rounded())
        perform("Updating volume…", successMessage: "Volume updated.") {
            try driver.setVolume(level)
            return DriverSnapshot(driver: driver)
        }
    }

    func applyDSEEExtreme(_ enabled: Bool) {
        let driver = self.driver
        perform(
            "Updating DSEE Extreme…",
            successMessage: enabled ? "DSEE Extreme enabled." : "DSEE Extreme disabled."
        ) {
            try driver.setDSEEExtreme(enabled)
            return DriverSnapshot(driver: driver)
        }
    }

    func applySpeakToChat(_ enabled: Bool) {
        let driver = self.driver
        perform(
            "Updating Speak-to-Chat…",
            successMessage: enabled ? "Speak-to-Chat enabled." : "Speak-to-Chat disabled."
        ) {
            try driver.setSpeakToChat(enabled)
            return DriverSnapshot(driver: driver)
        }
    }

    func applyEqualizerPreset(_ preset: EqualizerPreset) {
        let driver = self.driver
        let bands = state.bands
        perform("Updating equalizer…", successMessage: "Equalizer preset updated.") {
            try driver.setEqualizer(preset: preset, bands: bands)
            return DriverSnapshot(driver: driver)
        }
    }

    func applyBandValue(id: String, value: Double) {
        _ = id
        _ = value
        state.statusMessage = "Custom EQ bands are not mapped yet. Use the captured presets instead."
    }

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) {
        let driver = self.driver
        perform("Updating spatial preset…", successMessage: "Virtual position updated.") {
            try driver.applySoundPosition(preset)
            return DriverSnapshot(driver: driver)
        }
    }

    private func sendNoiseControl(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) {
        let driver = self.driver
        perform("Updating noise control…", successMessage: "Noise control updated.") {
            try driver.applyNoiseControl(
                mode: mode,
                ambientLevel: ambientLevel,
                focusOnVoice: focusOnVoice
            )
            return DriverSnapshot(driver: driver)
        }
    }

    private func perform(
        _ busyLabel: String,
        successMessage: String,
        attemptedDevice: SonyDevice? = nil,
        isAutomatic: Bool = false,
        work: @escaping @Sendable () throws -> DriverSnapshot
    ) {
        guard state.isBusy == false else {
            return
        }

        let resolvedDevice = attemptedDevice ?? currentDevice ?? devices.first(where: { $0.isConnected })
        guard state.connectedDeviceID != nil || resolvedDevice != nil else {
            state.statusMessage = "Connect your Sony headphones in macOS first."
            return
        }

        let token = beginBusyAction(busyLabel)
        let attemptedDevice = attemptedDevice ?? currentDevice ?? resolvedDevice
        let shouldOpenControlChannel = resolvedDevice.map { state.connectedDeviceID != $0.id } ?? false
        let driver = self.driver
        recordDiagnostic("\(busyLabel) Target: \(resolvedDevice?.name ?? state.connectionLabel).")

        Task { [weak self, driver] in
            guard let self else { return }

            do {
                let snapshot = try await self.runBlocking {
                    do {
                        if shouldOpenControlChannel, let resolvedDevice {
                            try driver.connect(to: resolvedDevice)
                        }
                        return try work()
                    } catch SonyTransportError.notConnected where resolvedDevice?.isConnected == true {
                        try driver.connect(to: resolvedDevice!)
                        return try work()
                    } catch SonyTransportError.writeFailed where resolvedDevice?.isConnected == true {
                        try driver.connect(to: resolvedDevice!)
                        return try work()
                    } catch SonyTransportError.responseTimeout where resolvedDevice?.isConnected == true {
                        try driver.connect(to: resolvedDevice!)
                        return try work()
                    }
                }
                self.completeDriverAction(
                    token: token,
                    snapshot: snapshot,
                    successMessage: successMessage,
                    device: resolvedDevice
                )
            } catch {
                self.failDriverAction(
                    token: token,
                    error: error,
                    attemptedDevice: attemptedDevice,
                    isAutomatic: isAutomatic,
                    disconnectOnFailure: false
                )
            }
        }
    }

    private func applyDriverSnapshot(_ snapshot: DriverSnapshot) {
        let status = snapshot.status
        state.support = snapshot.support
        state.batteryText = {
            guard let batteryLevel = status.batteryLevel else {
                return "Unknown"
            }
            return status.isCharging ? "\(batteryLevel)% (Charging)" : "\(batteryLevel)%"
        }()
        state.noiseControlMode = status.noiseControlMode
        state.ambientLevel = Double(status.ambientLevel)
        state.focusOnVoice = status.focusOnVoice
        state.volumeLevel = Double(status.volumeLevel)
        state.dseeExtreme = status.dseeEnabled
        state.speakToChat = status.speakToChatEnabled
        state.equalizerPreset = status.equalizerPreset
    }

    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run {
                    self?.pollDevices()
                }
            }
        }
    }

    private func pollDevices() {
        guard !state.isBusy else {
            return
        }

        refreshDevices(allowAutoConnect: true)
    }

    private func scheduleBatteryRefreshIfNeeded(force: Bool = false) {
        guard state.isBusy == false else {
            return
        }

        guard batteryRefreshTask == nil else {
            return
        }

        guard state.connectedDeviceID != nil else {
            return
        }

        let now = Date()
        if !force,
           let lastBatteryRefreshAttemptAt,
           now.timeIntervalSince(lastBatteryRefreshAttemptAt) < Self.batteryRefreshInterval {
            return
        }

        lastBatteryRefreshAttemptAt = now

        let deviceID = state.connectedDeviceID
        let fallbackDevice = currentDevice ?? devices.first(where: { $0.id == deviceID }) ?? devices.first(where: { $0.isConnected })
        let driver = self.driver

        batteryRefreshTask = Task { [weak self, driver] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.batteryRefreshTask = nil
                }
            }

            do {
                let snapshot = try await self.runBlocking {
                    do {
                        try driver.refreshBatteryStatus()
                    } catch SonyTransportError.notConnected where fallbackDevice?.isConnected == true {
                        try driver.connect(to: fallbackDevice!)
                        try driver.refreshBatteryStatus()
                    } catch SonyTransportError.writeFailed where fallbackDevice?.isConnected == true {
                        try driver.connect(to: fallbackDevice!)
                        try driver.refreshBatteryStatus()
                    } catch SonyTransportError.responseTimeout where fallbackDevice?.isConnected == true {
                        try driver.connect(to: fallbackDevice!)
                        try driver.refreshBatteryStatus()
                    }

                    return DriverSnapshot(driver: driver)
                }

                await MainActor.run {
                    guard self.state.connectedDeviceID == deviceID else {
                        return
                    }

                    self.applyDriverSnapshot(snapshot)
                    self.recordDiagnostic("Battery refresh succeeded.")
                }
            } catch {
                fputs("[SonyHeadphoneSession] battery refresh failed: \(error.localizedDescription)\n", stderr)
                await MainActor.run {
                    self.recordDiagnostic("Battery refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func beginBusyAction(_ busyLabel: String) -> UInt64 {
        actionGeneration &+= 1
        state.isBusy = true
        state.statusMessage = busyLabel
        return actionGeneration
    }

    private func completeConnect(token: UInt64, device: SonyDevice, snapshot: DriverSnapshot) {
        guard token == actionGeneration else {
            return
        }

        state.connectedDeviceID = device.id
        state.connectionLabel = device.name
        applyDriverSnapshot(snapshot)
        lastAutoConnectFailure = nil
        lastBatteryRefreshAttemptAt = nil
        connectionRecoveryGuide = nil
        state.statusMessage = "Connected to XM6 control channel."
        state.isBusy = false
        recordDiagnostic("Sony control channel opened successfully for \(device.name).")
        refreshConnectedStateInBackground(
            deviceID: device.id,
            startedWhileConnectedToMac: device.isConnected
        )
    }

    private func completeDriverAction(
        token: UInt64,
        snapshot: DriverSnapshot,
        successMessage: String,
        device: SonyDevice?
    ) {
        guard token == actionGeneration else {
            return
        }

        if let device {
            state.connectedDeviceID = device.id
            state.connectionLabel = device.name
        }
        applyDriverSnapshot(snapshot)
        connectionRecoveryGuide = nil
        state.statusMessage = successMessage
        state.isBusy = false
        recordDiagnostic(successMessage)
        scheduleBatteryRefreshIfNeeded()
    }

    private func failDriverAction(
        token: UInt64,
        error: Error,
        attemptedDevice: SonyDevice?,
        isAutomatic: Bool,
        disconnectOnFailure: Bool
    ) {
        guard token == actionGeneration else {
            return
        }

        if disconnectOnFailure {
            state.connectedDeviceID = nil
            state.connectionLabel = devices.first(where: { $0.isConnected })?.name ?? "No Sony headphones connected"
            if isAutomatic {
                lastAutoConnectFailure = (attemptedDevice?.id ?? "", Date())
            }
        }

        state.statusMessage = isAutomatic ? "Auto-connect failed: \(error.localizedDescription)" : error.localizedDescription
        recordDiagnostic(
            isAutomatic
                ? "Automatic Sony control action failed: \(error.localizedDescription)"
                : "Sony control action failed: \(error.localizedDescription)"
        )
        presentConnectionRecoveryGuide(for: error, attemptedDevice: attemptedDevice, isAutomatic: isAutomatic)
        state.isBusy = false
    }

    private func completeClassicInspection(token: UInt64, device: SonyDevice, services: [ClassicServiceRecord]) {
        guard token == classicInspectionGeneration else {
            return
        }

        classicServices = services
        if services.isEmpty {
            discoveryStatus = "No classic SDP services were returned for \(device.name)."
        } else {
            discoveryStatus = "Loaded \(services.count) classic SDP services for \(device.name)."
        }
    }

    private func failClassicInspection(token: UInt64, error: Error) {
        guard token == classicInspectionGeneration else {
            return
        }

        classicServices = []
        discoveryStatus = error.localizedDescription
    }

    private var currentDevice: SonyDevice? {
        guard let connectedDeviceID = state.connectedDeviceID else {
            return nil
        }

        return devices.first(where: { $0.id == connectedDeviceID })
    }

    private func presentConnectionRecoveryGuide(for error: Error, attemptedDevice: SonyDevice?, isAutomatic: Bool) {
        guard let guide = buildConnectionRecoveryGuide(for: error, attemptedDevice: attemptedDevice, isAutomatic: isAutomatic) else {
            return
        }

        connectionRecoveryGuide = guide
    }

    private func buildConnectionRecoveryGuide(
        for error: Error,
        attemptedDevice: SonyDevice?,
        isAutomatic: Bool
    ) -> ConnectionRecoveryGuide? {
        let deviceName = attemptedDevice?.name ?? "your Sony headphones"
        let macReportedConnected = attemptedDevice?.isConnected == true
        let technicalDetail = error.localizedDescription

        if let transportError = error as? SonyTransportError {
            switch transportError {
            case let .responseTimeout(command) where command == 0x00 || command == 0x06:
                return ConnectionRecoveryGuide(
                    title: "The Sony Control Channel Timed Out",
                    summary: macReportedConnected
                        ? "\(deviceName) looked connected to this Mac, but the Sony control channel never finished starting."
                        : "The app reached \(deviceName), but the headset never finished starting Sony's control channel.",
                    likelyCause: macReportedConnected
                        ? "This usually happens while the XM6 is still switching between devices, waking up, or handing the Bluetooth link back and forth."
                        : "This usually means macOS had not fully completed the headset connection yet, or another paired device grabbed the XM6 first.",
                    nextSteps: [
                        "Keep the headset awake and close to the Mac for a few seconds.",
                        "If the XM6 is also connected to a phone or tablet, disconnect it there briefly.",
                        "Press Try Again. If that still fails, press Refresh and reconnect from the device list.",
                        "If the issue keeps repeating, power the headset off and on, then reconnect from macOS Bluetooth settings."
                    ],
                    technicalDetail: technicalDetail,
                    retryDeviceID: attemptedDevice?.id,
                    retryDeviceName: attemptedDevice?.name,
                    isAutomatic: isAutomatic
                )

            case .writeFailed, .notConnected, .channelOpenFailed:
                return ConnectionRecoveryGuide(
                    title: "The Headset Connection Dropped Mid-Setup",
                    summary: "The app could see \(deviceName), but the Sony control channel was interrupted before setup completed.",
                    likelyCause: "The Bluetooth connection likely changed underneath the app, or the headset was still busy with another device.",
                    nextSteps: [
                        "Confirm the XM6 is the active headset connected to this Mac.",
                        "Pause or disconnect any second device that may still be using the headphones.",
                        "Press Try Again after a short pause.",
                        "If the channel keeps dropping, disconnect and reconnect the XM6 from macOS Bluetooth settings."
                    ],
                    technicalDetail: technicalDetail,
                    retryDeviceID: attemptedDevice?.id,
                    retryDeviceName: attemptedDevice?.name,
                    isAutomatic: isAutomatic
                )

            case .deviceConnectionFailed, .serviceQueryFailed:
                return ConnectionRecoveryGuide(
                    title: "macOS Could Not Finish Connecting",
                    summary: "The app could not complete the Bluetooth connection needed to talk to \(deviceName).",
                    likelyCause: "The headset may still be attached to another device, out of range, or not fully connected in macOS yet.",
                    nextSteps: [
                        "Open macOS Bluetooth settings and make sure the XM6 shows as connected.",
                        "Disconnect the headset from any phone or tablet that may still have priority.",
                        "Return to the app and try again.",
                        "If needed, toggle Bluetooth on the Mac or restart the headset."
                    ],
                    technicalDetail: technicalDetail,
                    retryDeviceID: attemptedDevice?.id,
                    retryDeviceName: attemptedDevice?.name,
                    isAutomatic: isAutomatic
                )

            case .invalidAddress, .responseTimeout:
                break
            }
        }

        let description = error.localizedDescription.lowercased()
        guard description.contains("connect") || description.contains("headset") || description.contains("bluetooth") else {
            return nil
        }

        return ConnectionRecoveryGuide(
            title: "The Headset Needs To Reconnect",
            summary: "The app was not able to keep a stable control connection to \(deviceName).",
            likelyCause: "The headset connection likely changed state while the app was trying to talk to it.",
            nextSteps: [
                "Refresh the device list and make sure the XM6 is connected to this Mac.",
                "If another device is nearby, disconnect it from the headset for a moment.",
                "Try connecting again once the headset has settled."
            ],
            technicalDetail: technicalDetail,
            retryDeviceID: attemptedDevice?.id,
            retryDeviceName: attemptedDevice?.name,
            isAutomatic: isAutomatic
        )
    }

    private func wireDiscoveryCallbacks() {
        bleDiscovery.onStateChange = { [weak self] message, isScanning in
            guard let self else { return }
            self.discoveryStatus = message
            self.isScanningBLE = isScanning
        }

        bleDiscovery.onPeripheralsChanged = { [weak self] peripherals in
            guard let self else { return }
            self.blePeripherals = peripherals
            if let selectedBLEPeripheralID = self.selectedBLEPeripheralID {
                self.selectedBLEServices = self.bleDiscovery.services(for: selectedBLEPeripheralID)
                self.refreshBLEWriteTargets()
            }
        }

        bleDiscovery.onServicesChanged = { [weak self] peripheralID, services in
            guard let self else { return }
            if self.selectedBLEPeripheralID == peripheralID {
                self.selectedBLEServices = services
                self.refreshBLEWriteTargets()
            }
        }

        bleDiscovery.onLogEntry = { [weak self] entry in
            guard let self else { return }
            self.appendLog(entry.kind, label: entry.label, payload: entry.payload, timestamp: entry.timestamp)
        }
    }

    private func refreshBLEWriteTargets() {
        guard let selectedBLEPeripheralID else {
            bleWriteTargets = []
            selectedBLEWriteTargetID = nil
            return
        }

        bleWriteTargets = selectedBLEServices.flatMap { service in
            service.characteristics.compactMap { characteristic in
                let isWritable = characteristic.properties.contains("write") || characteristic.properties.contains("write-no-rsp")
                guard isWritable else {
                    return nil
                }

                return BLEWriteTarget(
                    peripheralID: selectedBLEPeripheralID,
                    serviceUUID: service.uuid,
                    characteristicUUID: characteristic.uuid
                )
            }
        }

        if bleWriteTargets.contains(where: { $0.id == selectedBLEWriteTargetID }) == false {
            selectedBLEWriteTargetID = bleWriteTargets.first?.id
        }
    }

    private var selectedPeripheralName: String {
        guard let selectedBLEPeripheralID,
              let peripheral = blePeripherals.first(where: { $0.id == selectedBLEPeripheralID }) else {
            return "None"
        }

        return peripheral.displayName
    }

    private func appendLog(
        _ kind: BLEConsoleLogEntry.Kind,
        label: String,
        payload: String,
        timestamp: Date = Date()
    ) {
        bleConsoleLog.insert(
            BLEConsoleLogEntry(timestamp: timestamp, kind: kind, label: label, payload: payload),
            at: 0
        )

        if bleConsoleLog.count > 300 {
            bleConsoleLog.removeLast(bleConsoleLog.count - 300)
        }
    }

    private func recordDiagnostic(_ message: String, timestamp: Date = Date()) {
        diagnosticsLog.insert(
            SessionDiagnosticsEntry(timestamp: timestamp, message: message),
            at: 0
        )

        if diagnosticsLog.count > 120 {
            diagnosticsLog.removeLast(diagnosticsLog.count - 120)
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func refreshConnectedStateInBackground(
        deviceID: String,
        startedWhileConnectedToMac: Bool
    ) {
        let driver = self.driver
        let requestDelay = startedWhileConnectedToMac
            ? statusRefreshRequestDelayAlreadyConnected
            : statusRefreshRequestDelayFreshConnect

        Task { [weak self, driver] in
            guard let self else { return }

            guard self.state.connectedDeviceID == deviceID else {
                return
            }

            do {
                try await Task.sleep(for: requestDelay)

                guard self.state.connectedDeviceID == deviceID else {
                    return
                }

                try await self.runBlocking {
                    try driver.requestStateRefresh()
                }

                try await Task.sleep(for: statusRefreshSnapshotDelay)

                guard self.state.connectedDeviceID == deviceID else {
                    return
                }

                let snapshot = DriverSnapshot(driver: driver)

                guard self.state.connectedDeviceID == deviceID else {
                    return
                }

                self.applyDriverSnapshot(snapshot)
            } catch {
                guard self.state.connectedDeviceID == deviceID else {
                    return
                }

                if self.state.isBusy == false {
                    self.state.statusMessage = startedWhileConnectedToMac
                        ? "Connected. Control channel is still settling because the headset was already connected in macOS."
                        : "Connected. Waiting for headset state updates."
                }

                fputs("[SonyHeadphoneSession] background refresh failed: \(error.localizedDescription)\n", stderr)
                self.recordDiagnostic("Background state refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func runBlocking<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            blockingQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
