import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SonyHeadphoneSession {
    private static let autoConnectRetryDelay: TimeInterval = 8

    private let driver: SonyHeadphoneDriver
    private let classicInspector: ClassicBluetoothInspector
    private let bleDiscovery: BLEGATTDiscovery
    private var autoRefreshTask: Task<Void, Never>?
    private var lastAutoConnectFailure: (deviceID: String, date: Date)?
    private var didBootstrap = false

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
            state.statusMessage = "Refresh completed."
        } else if state.connectedDeviceID == nil {
            state.connectionLabel = "No Sony headphones connected"
        }

        if devices.contains(where: { $0.isConnected }) == false {
            lastAutoConnectFailure = nil
        } else if let lastAutoConnectFailure,
                  devices.contains(where: { $0.id == lastAutoConnectFailure.deviceID && $0.isConnected }) == false {
            self.lastAutoConnectFailure = nil
        }

        if allowAutoConnect {
            autoConnectIfNeeded()
        } else if state.connectedDeviceID == nil {
            state.statusMessage = "Refresh completed."
        }
    }

    func connect(to device: SonyDevice, isAutomatic: Bool = false) {
        state.isBusy = true
        state.statusMessage = isAutomatic ? "Auto-connecting to \(device.name)..." : "Connecting to \(device.name)..."
        do {
            try driver.connect(to: device)
            state.connectedDeviceID = device.id
            state.connectionLabel = device.name
            syncStateFromDriver()
            lastAutoConnectFailure = nil
            state.statusMessage = "Connected to XM6 control channel."
        } catch {
            state.connectedDeviceID = nil
            state.connectionLabel = "No Sony headphones connected"
            if isAutomatic {
                lastAutoConnectFailure = (device.id, Date())
            }
            state.statusMessage = isAutomatic ? "Auto-connect failed: \(error.localizedDescription)" : error.localizedDescription
        }
        state.isBusy = false
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
        discoveryStatus = "Inspecting classic services for \(device.name)..."

        do {
            classicServices = try classicInspector.inspectServices(for: device)
            if classicServices.isEmpty {
                discoveryStatus = "No classic SDP services were returned for \(device.name)."
            } else {
                discoveryStatus = "Loaded \(classicServices.count) classic SDP services for \(device.name)."
            }
        } catch {
            classicServices = []
            discoveryStatus = error.localizedDescription
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
        driver.disconnect()
        state.connectedDeviceID = nil
        state.connectionLabel = "No Sony headphones connected"
        state.batteryText = "Unknown"
        state.statusMessage = "Disconnected"
    }

    func applyNoiseControlMode(_ mode: NoiseControlMode) {
        state.noiseControlMode = mode
        sendNoiseControl()
    }

    func applyAmbientLevel(_ value: Double) {
        state.ambientLevel = value
        sendNoiseControl()
    }

    func applyFocusOnVoice(_ enabled: Bool) {
        state.focusOnVoice = enabled
        sendNoiseControl()
    }

    func applyDSEEExtreme(_ enabled: Bool) {
        state.dseeExtreme = enabled
        perform("Updating DSEE Extreme…") {
            try driver.setDSEEExtreme(enabled)
            state.statusMessage = enabled ? "DSEE Extreme enabled." : "DSEE Extreme disabled."
        }
    }

    func applySpeakToChat(_ enabled: Bool) {
        state.speakToChat = enabled
        perform("Updating Speak-to-Chat…") {
            try driver.setSpeakToChat(enabled)
            state.statusMessage = enabled ? "Speak-to-Chat enabled." : "Speak-to-Chat disabled."
        }
    }

    func applyEqualizerPreset(_ preset: EqualizerPreset) {
        state.equalizerPreset = preset
        perform("Updating equalizer…") {
            try driver.setEqualizer(preset: preset, bands: state.bands)
            state.statusMessage = "Equalizer preset updated."
        }
    }

    func applyBandValue(id: String, value: Double) {
        _ = id
        _ = value
        state.statusMessage = "Custom EQ bands are not mapped yet. Use the captured presets instead."
    }

    func applySoundPosition(_ preset: SonyProtocol.SoundPositionPreset) {
        perform("Updating spatial preset…") {
            try driver.applySoundPosition(preset)
            state.statusMessage = "Virtual position updated."
        }
    }

    private func sendNoiseControl() {
        perform("Updating noise control…") {
            try driver.applyNoiseControl(
                mode: state.noiseControlMode,
                ambientLevel: Int(state.ambientLevel.rounded()),
                focusOnVoice: state.focusOnVoice
            )
            state.statusMessage = "Noise control updated."
        }
    }

    private func perform(_ busyLabel: String, work: () throws -> Void) {
        guard state.connectedDeviceID != nil else {
            state.statusMessage = "Connect your Sony headphones first."
            return
        }

        state.isBusy = true
        state.statusMessage = busyLabel
        do {
            try work()
            syncStateFromDriver()
        } catch {
            state.statusMessage = error.localizedDescription
        }
        state.isBusy = false
    }

    private func syncStateFromDriver() {
        let status = driver.currentStatus
        state.support = driver.featureSupport
        state.batteryText = {
            guard let batteryLevel = status.batteryLevel else {
                return "Unknown"
            }
            return status.isCharging ? "\(batteryLevel)% (Charging)" : "\(batteryLevel)%"
        }()
        state.noiseControlMode = status.noiseControlMode
        state.ambientLevel = Double(status.ambientLevel)
        state.focusOnVoice = status.focusOnVoice
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
}
