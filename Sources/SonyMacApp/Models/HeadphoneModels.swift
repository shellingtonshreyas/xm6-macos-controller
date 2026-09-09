import Foundation

enum NoiseControlMode: String, CaseIterable, Identifiable, Sendable {
    case noiseCancelling = "Noise Cancelling"
    case ambient = "Ambient Sound"
    case off = "Off"

    static let ambientLevelRange = 0 ... 20

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .noiseCancelling:
            "Blocks outside noise."
        case .ambient:
            "Lets the room through."
        case .off:
            "Disables both modes."
        }
    }
}

enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case heavy = "Heavy"
    case clear = "Clear"
    case hard = "Hard"
    case soft = "Soft"
    case manual = "Manual"
    case custom1 = "Custom 1"
    case custom2 = "Custom 2"

    var id: String { rawValue }
}

enum FeatureAvailability: Equatable, Sendable {
    case supported
    case unsupported(reason: String)
}

struct FeatureSupport: Equatable, Sendable {
    var noiseControl: FeatureAvailability = .supported
    var ambientLevel: FeatureAvailability = .supported
    var focusOnVoice: FeatureAvailability = .supported
    var volume: FeatureAvailability = .supported
    var dseeExtreme: FeatureAvailability = .supported
    var equalizer: FeatureAvailability = .supported
    var speakToChat: FeatureAvailability = .supported
    var surround: FeatureAvailability = .unsupported(reason: "Virtual surround is not mapped in the current driver.")

    static let xm6Native = FeatureSupport(
        noiseControl: .supported,
        ambientLevel: .supported,
        focusOnVoice: .supported,
        volume: .supported,
        dseeExtreme: .supported,
        equalizer: .supported,
        speakToChat: .supported,
        surround: .unsupported(reason: "Sony's positional surround commands are not mapped for XM6.")
    )
}

struct SonyControlStatus: Equatable, Sendable {
    var batteryLevel: Int?
    var isCharging = false
    var noiseControlMode: NoiseControlMode = .ambient
    var ambientLevel = 10
    var focusOnVoice = false
    var volumeLevel = 0
    var dseeEnabled = false
    var speakToChatEnabled = false
    var equalizerPreset: EqualizerPreset = .off
    var equalizerBandValues = Array(repeating: 0, count: 10)
    var hasEqualizerBandValues = false
}

struct SonyDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let address: String
    let isConnected: Bool

    var detail: String {
        isConnected ? "Connected to macOS" : "Paired device"
    }
}

struct EqualizerBand: Identifiable, Hashable, Sendable {
    static let valueRange = -6.0 ... 6.0

    let id: String
    let label: String
    var value: Double
}

struct HeadphoneState: Equatable, Sendable {
    static let volumeLevelRange = 0 ... 30

    var connectedDeviceID: String?
    var connectionLabel = "No Sony headphones connected"
    var batteryText = "Unknown"
    var noiseControlMode: NoiseControlMode = .noiseCancelling
    var ambientLevel: Double = 12
    var focusOnVoice = false
    var volumeLevel: Double = 0
    var dseeExtreme = false
    var speakToChat = false
    var equalizerPreset: EqualizerPreset = .off
    var hasEqualizerBandValues = false
    var bands: [EqualizerBand] = [
        .init(id: "31", label: "31", value: 0),
        .init(id: "63", label: "63", value: 0),
        .init(id: "125", label: "125", value: 0),
        .init(id: "250", label: "250", value: 0),
        .init(id: "500", label: "500", value: 0),
        .init(id: "1k", label: "1k", value: 0),
        .init(id: "2k", label: "2k", value: 0),
        .init(id: "4k", label: "4k", value: 0),
        .init(id: "8k", label: "8k", value: 0),
        .init(id: "16k", label: "16k", value: 0)
    ]
    var support = FeatureSupport.xm6Native
    var statusMessage = "Ready"
    var isBusy = false
}

struct ConnectionRecoveryGuide: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let summary: String
    let likelyCause: String
    let nextSteps: [String]
    let technicalDetail: String
    let retryDeviceID: String?
    let retryDeviceName: String?
    let isAutomatic: Bool

    var retryButtonTitle: String {
        retryDeviceID == nil ? "Refresh Devices" : "Try Again"
    }
}
