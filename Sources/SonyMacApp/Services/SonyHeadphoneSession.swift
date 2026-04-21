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

@Observable
@MainActor
final class SonyHeadphoneSession {
    private static let autoConnectRetryDelay: TimeInterval = 8

    private let driver: SonyHeadphoneDriver
    private let classicInspector: ClassicBluetoothInspector
    private let bleDiscovery: BLEGATTDiscovery
    private let blockingQueue = DispatchQueue(label: "SonyMacApp.blocking", qos: .userInitiated)
    private let statusRefreshRequestDelay: Duration = .milliseconds(700)
    private let statusRefreshSnapshotDelay: Duration = .seconds(2)
    private var autoRefreshTask: Task<Void, Never>?
    private var lastAutoConnectFailure: (deviceID: String, date: Date)?
    private var didBootstrap = false
    private var actionGeneration: UInt64 = 0
    private var classicInspectionGeneration: UInt64 = 0

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
        if state.connectedDeviceID == nil {
            state.statusMessage = "Ready"
        }
    }

    func refreshDevices(allowAutoConnect: Bool = false) {
        devices = driver.loadDevices()
        if let connectedDeviceID = state.connectedDeviceID,
           devices.contains(where: { $0.id == connectedDeviceID }) == false {
            state.connectedDeviceID = nil
            state.connectionLabel = "No Sony headphones connected"
            state.volumeLevel = 0
            state.statusMessage = "Refresh completed."
        } else if state.connectedDeviceID == nil {
            state.connectionLabel = "No Sony headphones connected"
        }

        if devices.contains(where: { $0.isConnected }) == false {
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
            autoConnectIfNeeded()
        } else if state.connectedDeviceID == nil {
            state.statusMessage = "Refresh completed."
        }
    }

    func connect(to device: SonyDevice, isAutomatic: Bool = false) {
        guard state.isBusy == false else {
            return
        }

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

        if let fallbackDevice = devices.first {
            connect(to: fallbackDevice)
            return
        }

        state.statusMessage = "No paired XM6 was found."
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

    func disconnect() {
        actionGeneration &+= 1

        state.connectedDeviceID = nil
        state.connectionLabel = "No Sony headphones connected"
        state.batteryText = "Unknown"
        state.volumeLevel = 0
        state.statusMessage = "Disconnected"
        state.isBusy = false
        connectionRecoveryGuide = nil

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
        refreshDevices()

        if let retryDeviceID = guide?.retryDeviceID,
           let device = devices.first(where: { $0.id == retryDeviceID }) {
            connect(to: device, isAutomatic: guide?.isAutomatic ?? false)
            return
        }

        connectPreferredDevice()
    }

    func applyNoiseControlMode(_ mode: NoiseControlMode) {
        sendNoiseControl(
            mode: mode,
            ambientLevel: Int(state.ambientLevel.rounded()),
            focusOnVoice: state.focusOnVoice
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
        guard state.connectedDeviceID != nil else {
            state.statusMessage = "Connect your Sony headphones first."
            return
        }

        guard state.isBusy == false else {
            return
        }

        let token = beginBusyAction(busyLabel)
        let attemptedDevice = attemptedDevice ?? currentDevice

        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await self.runBlocking(work)
                self.completeDriverAction(
                    token: token,
                    snapshot: snapshot,
                    successMessage: successMessage
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

    private func autoConnectIfNeeded() {
        guard state.connectedDeviceID == nil, state.isBusy == false else {
            return
        }

        guard let candidate = devices.first(where: { $0.isConnected }) else {
            return
        }

        if let lastAutoConnectFailure,
           candidate.id == lastAutoConnectFailure.deviceID,
           Date().timeIntervalSince(lastAutoConnectFailure.date) < Self.autoConnectRetryDelay {
            return
        }

        connect(to: candidate, isAutomatic: true)
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
        connectionRecoveryGuide = nil
        state.statusMessage = "Connected to XM6 control channel."
        state.isBusy = false
        refreshConnectedStateInBackground(deviceID: device.id)
    }

    private func completeDriverAction(token: UInt64, snapshot: DriverSnapshot, successMessage: String) {
        guard token == actionGeneration else {
            return
        }

        applyDriverSnapshot(snapshot)
        connectionRecoveryGuide = nil
        state.statusMessage = successMessage
        state.isBusy = false
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
            state.connectionLabel = "No Sony headphones connected"
            if isAutomatic {
                lastAutoConnectFailure = (attemptedDevice?.id ?? "", Date())
            }
        }

        state.statusMessage = isAutomatic ? "Auto-connect failed: \(error.localizedDescription)" : error.localizedDescription
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

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func refreshConnectedStateInBackground(deviceID: String) {
        let driver = self.driver

        Task { [weak self, driver] in
            guard let self else { return }

            guard self.state.connectedDeviceID == deviceID else {
                return
            }

            do {
                try await Task.sleep(for: statusRefreshRequestDelay)

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
                fputs("[SonyHeadphoneSession] background refresh failed: \(error.localizedDescription)\n", stderr)
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
