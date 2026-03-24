import SwiftUI

struct ProtocolDiscoveryDashboard: View {
    @Bindable var session: SonyHeadphoneSession

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader(
                    title: "Protocol Discovery",
                    subtitle: "Inspect classic SDP records and nearby BLE GATT surfaces for XM6 mapping work"
                )

                HStack(spacing: 12) {
                    Label(session.discoveryStatus, systemImage: "wave.3.right.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(session.isScanningBLE ? "Stop BLE Scan" : "Start BLE Scan") {
                        session.isScanningBLE ? session.stopBLEScan() : session.startBLEScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(session.isScanningBLE ? .gray : AppTheme.accent)
                }

                HStack(alignment: .top, spacing: 22) {
                    ClassicServicesPane(session: session)
                    BLEDiscoveryPane(session: session)
                }

                BLEConsolePane(session: session)
            }
        }
    }
}

private struct ClassicServicesPane: View {
    @Bindable var session: SonyHeadphoneSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Classic Bluetooth")
                .font(.headline)

            if session.devices.isEmpty {
                Text("No paired Sony headset is available for SDP inspection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.devices) { device in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                                .font(.body.weight(.semibold))
                            Text(device.address)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Inspect") {
                            session.inspectClassicServices(for: device)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            if session.classicServices.isEmpty {
                Text("Run SDP inspection to see service names, RFCOMM channels, and L2CAP PSMs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.classicServices) { service in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.name)
                                    .font(.subheadline.weight(.semibold))

                                HStack(spacing: 10) {
                                    ServiceTag(title: service.recordHandle)
                                    if let rfcommChannel = service.rfcommChannel {
                                        ServiceTag(title: "RFCOMM \(rfcommChannel)")
                                    }
                                    if let l2capPSM = service.l2capPSM {
                                        ServiceTag(title: "L2CAP \(l2capPSM)")
                                    }
                                    ServiceTag(title: "\(service.attributeCount) attrs")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppTheme.detailFill)
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct BLEDiscoveryPane: View {
    @Bindable var session: SonyHeadphoneSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BLE GATT")
                .font(.headline)

            if session.blePeripherals.isEmpty {
                Text("Start a BLE scan, and keep the XM6 awake or in pairing mode if it does not advertise continuously.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.blePeripherals) { peripheral in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(peripheral.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        Text("RSSI \(peripheral.rssi) dBm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(peripheral.isConnected ? "Disconnect" : "Inspect") {
                                        peripheral.isConnected
                                            ? session.disconnectBLEPeripheral(peripheral.id)
                                            : session.inspectBLEPeripheral(peripheral.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(peripheral.isConnected ? .gray : AppTheme.accent)
                                }

                                HStack(spacing: 8) {
                                    if peripheral.isConnectable {
                                        ServiceTag(title: "Connectable")
                                    }
                                    ForEach(peripheral.advertisedServices, id: \.self) { service in
                                        ServiceTag(title: service)
                                    }
                                }

                                if let manufacturerDataHex = peripheral.manufacturerDataHex {
                                    Text("MFG \(manufacturerDataHex)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(peripheral.id == session.selectedBLEPeripheralID ? AppTheme.accent.opacity(0.12) : AppTheme.detailFill)
                            )
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Divider()

            if session.selectedBLEServices.isEmpty {
                Text("Select a BLE peripheral to enumerate services and characteristics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let services = Array(session.selectedBLEServices)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(services) { service in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let errorSummary = service.errorSummary {
                                        Text(errorSummary)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.accentMuted)
                                    }

                                    ForEach(service.characteristics) { characteristic in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(characteristic.uuid)
                                                .font(.callout.monospaced())
                                                .textSelection(.enabled)

                                            if !characteristic.properties.isEmpty {
                                                Text(characteristic.properties.joined(separator: ", "))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            if let valueHex = characteristic.valueHex, !valueHex.isEmpty {
                                                Text(valueHex)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .textSelection(.enabled)
                                            }

                                            if let errorSummary = characteristic.errorSummary {
                                                Text(errorSummary)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.accentMuted)
                                            }

                                            ForEach(characteristic.descriptors) { descriptor in
                                                HStack(alignment: .top, spacing: 8) {
                                                    Text(descriptor.uuid)
                                                        .font(.caption.monospaced())
                                                        .foregroundStyle(.secondary)
                                                    if let valueSummary = descriptor.valueSummary {
                                                        Text(valueSummary)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .textSelection(.enabled)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(AppTheme.detailFillSecondary)
                                        )
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack {
                                    Text(service.uuid)
                                        .font(.subheadline.monospaced())
                                    Text("\(service.characteristics.count) chars")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(service.isPrimary ? "Primary" : "Secondary")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct BLEConsolePane: View {
    @Bindable var session: SonyHeadphoneSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BLE Console")
                .font(.headline)

            Text("Use this against the custom XM6 services that expose write/notify pairs. The strongest candidates so far are `5B833E06-...` and `DC405470-...`.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Picker(
                    "Writable Characteristic",
                    selection: Binding(
                        get: { session.selectedBLEWriteTargetID ?? "" },
                        set: { session.selectedBLEWriteTargetID = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    if session.bleWriteTargets.isEmpty {
                        Text("No writable characteristic").tag("")
                    } else {
                        ForEach(session.bleWriteTargets) { target in
                            Text(target.label).tag(target.id)
                        }
                    }
                }
                .pickerStyle(.menu)

                Button("Subscribe Notify") {
                    session.subscribeToBLENotifications()
                }
                .buttonStyle(.bordered)

                Button("Refresh Reads") {
                    session.refreshBLEReads()
                }
                .buttonStyle(.bordered)

                Button("Clear Log") {
                    session.clearBLEConsoleLog()
                }
                .buttonStyle(.bordered)

                Button("Copy Log") {
                    session.copyBLEConsoleLog()
                }
                .buttonStyle(.bordered)

                Button("Copy Report") {
                    session.copyBLEReport()
                }
                .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 12) {
                TextField("Hex payload, for example 01020304", text: $session.bleHexPayload, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("Send") {
                    session.sendBLEHexPayload()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(session.bleWriteTargets.isEmpty || session.bleHexPayload.isEmpty)
            }

            HStack(alignment: .top, spacing: 12) {
                TextField("Action marker, for example 'Pressed power button once'", text: $session.bleActionMarker, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button("Mark Action") {
                    session.addBLEActionMarker()
                }
                .buttonStyle(.bordered)
                .disabled(session.bleActionMarker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickMarkerButton(title: "Power Button") {
                        session.addBLEActionMarker("Pressed power button")
                    }
                    QuickMarkerButton(title: "Double Tap") {
                        session.addBLEActionMarker("Double tap touch panel")
                    }
                    QuickMarkerButton(title: "Triple Tap") {
                        session.addBLEActionMarker("Triple tap touch panel")
                    }
                    QuickMarkerButton(title: "ANC Button") {
                        session.addBLEActionMarker("Pressed ANC/custom button")
                    }
                    QuickMarkerButton(title: "Phone App Change") {
                        session.addBLEActionMarker("Changed setting in Sony phone app")
                    }
                    QuickMarkerButton(title: "Refresh Snapshot") {
                        session.addBLEActionMarker("Refreshing characteristic snapshot")
                    }
                }
            }

            if session.bleConsoleLog.isEmpty {
                Text("Notification traffic and writes will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.bleConsoleLog) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.kind.rawValue.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(color(for: entry.kind))
                                    Text(entry.label)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(entry.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(entry.payload)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.detailFillSecondary)
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func color(for kind: BLEConsoleLogEntry.Kind) -> Color {
        switch kind {
        case .info:
            AppTheme.accent
        case .incoming:
            AppTheme.accentMuted
        case .outgoing:
            AppTheme.textSecondary
        case .error:
            AppTheme.accentMuted
        }
    }
}

private struct ServiceTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.controlFill, in: Capsule())
            .foregroundStyle(AppTheme.textSecondary)
    }
}

private struct QuickMarkerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}
