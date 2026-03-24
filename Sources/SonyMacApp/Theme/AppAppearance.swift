import SwiftUI

enum AppAppearance: String {
    static let storageKey = "appAppearance"

    case dark
    case light

    var colorScheme: ColorScheme {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}
