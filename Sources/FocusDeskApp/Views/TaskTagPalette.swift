import SwiftUI

enum TaskTagPalette: String, CaseIterable, Identifiable {
    case gray
    case pink
    case rose
    case green
    case mint
    case yellow
    case blue
    case purple
    case orange
    case brown

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue.capitalized
    }

    var background: Color {
        switch self {
        case .gray:
            return adaptiveColor(
                light: NSColor(calibratedWhite: 0.91, alpha: 1),
                dark: NSColor(calibratedWhite: 0.26, alpha: 1)
            )
        case .pink:
            return adaptiveColor(
                light: NSColor(red: 0.96, green: 0.84, blue: 0.89, alpha: 1),
                dark: NSColor(red: 0.36, green: 0.18, blue: 0.27, alpha: 1)
            )
        case .rose:
            return adaptiveColor(
                light: NSColor(red: 0.98, green: 0.84, blue: 0.82, alpha: 1),
                dark: NSColor(red: 0.38, green: 0.17, blue: 0.15, alpha: 1)
            )
        case .green:
            return adaptiveColor(
                light: NSColor(red: 0.80, green: 0.89, blue: 0.82, alpha: 1),
                dark: NSColor(red: 0.15, green: 0.31, blue: 0.22, alpha: 1)
            )
        case .mint:
            return adaptiveColor(
                light: NSColor(red: 0.80, green: 0.91, blue: 0.88, alpha: 1),
                dark: NSColor(red: 0.13, green: 0.32, blue: 0.30, alpha: 1)
            )
        case .yellow:
            return adaptiveColor(
                light: NSColor(red: 0.95, green: 0.88, blue: 0.68, alpha: 1),
                dark: NSColor(red: 0.38, green: 0.30, blue: 0.12, alpha: 1)
            )
        case .blue:
            return adaptiveColor(
                light: NSColor(red: 0.80, green: 0.89, blue: 0.98, alpha: 1),
                dark: NSColor(red: 0.13, green: 0.25, blue: 0.39, alpha: 1)
            )
        case .purple:
            return adaptiveColor(
                light: NSColor(red: 0.88, green: 0.82, blue: 0.95, alpha: 1),
                dark: NSColor(red: 0.28, green: 0.19, blue: 0.39, alpha: 1)
            )
        case .orange:
            return adaptiveColor(
                light: NSColor(red: 0.96, green: 0.84, blue: 0.75, alpha: 1),
                dark: NSColor(red: 0.39, green: 0.22, blue: 0.13, alpha: 1)
            )
        case .brown:
            return adaptiveColor(
                light: NSColor(red: 0.88, green: 0.82, blue: 0.77, alpha: 1),
                dark: NSColor(red: 0.31, green: 0.25, blue: 0.21, alpha: 1)
            )
        }
    }

    var foreground: Color {
        switch self {
        case .gray:
            return adaptiveColor(
                light: NSColor(calibratedWhite: 0.18, alpha: 1),
                dark: NSColor(calibratedWhite: 0.88, alpha: 1)
            )
        case .pink:
            return adaptiveColor(
                light: NSColor(red: 0.43, green: 0.20, blue: 0.32, alpha: 1),
                dark: NSColor(red: 0.96, green: 0.77, blue: 0.86, alpha: 1)
            )
        case .rose:
            return adaptiveColor(
                light: NSColor(red: 0.47, green: 0.20, blue: 0.17, alpha: 1),
                dark: NSColor(red: 0.98, green: 0.76, blue: 0.72, alpha: 1)
            )
        case .green:
            return adaptiveColor(
                light: NSColor(red: 0.18, green: 0.38, blue: 0.27, alpha: 1),
                dark: NSColor(red: 0.72, green: 0.91, blue: 0.78, alpha: 1)
            )
        case .mint:
            return adaptiveColor(
                light: NSColor(red: 0.14, green: 0.39, blue: 0.36, alpha: 1),
                dark: NSColor(red: 0.70, green: 0.92, blue: 0.88, alpha: 1)
            )
        case .yellow:
            return adaptiveColor(
                light: NSColor(red: 0.43, green: 0.34, blue: 0.13, alpha: 1),
                dark: NSColor(red: 0.96, green: 0.86, blue: 0.55, alpha: 1)
            )
        case .blue:
            return adaptiveColor(
                light: NSColor(red: 0.16, green: 0.34, blue: 0.53, alpha: 1),
                dark: NSColor(red: 0.72, green: 0.86, blue: 0.99, alpha: 1)
            )
        case .purple:
            return adaptiveColor(
                light: NSColor(red: 0.31, green: 0.22, blue: 0.47, alpha: 1),
                dark: NSColor(red: 0.87, green: 0.76, blue: 0.98, alpha: 1)
            )
        case .orange:
            return adaptiveColor(
                light: NSColor(red: 0.48, green: 0.27, blue: 0.16, alpha: 1),
                dark: NSColor(red: 0.98, green: 0.79, blue: 0.64, alpha: 1)
            )
        case .brown:
            return adaptiveColor(
                light: NSColor(red: 0.36, green: 0.28, blue: 0.23, alpha: 1),
                dark: NSColor(red: 0.88, green: 0.78, blue: 0.70, alpha: 1)
            )
        }
    }

    static func palette(for rawValue: String) -> TaskTagPalette {
        TaskTagPalette(rawValue: rawValue) ?? .gray
    }

    private func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let matchedAppearance = appearance.bestMatch(from: [.aqua, .darkAqua])
            return matchedAppearance == .darkAqua ? dark : light
        })
    }
}
