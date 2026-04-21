import AppKit
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

    var nsAppearance: NSAppearance? {
        switch self {
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .light:
            return NSAppearance(named: .aqua)
        }
    }
}
