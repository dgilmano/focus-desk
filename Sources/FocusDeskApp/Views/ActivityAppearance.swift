import SwiftUI

enum ActivityAppearance {
    static var canvas: Color { Color(nsColor: .textBackgroundColor) }

    static func accent(_ colorName: String) -> Color {
        switch TaskTagPalette.palette(for: colorName) {
        case .gray: .gray
        case .pink: .pink
        case .rose: Color(red: 0.87, green: 0.43, blue: 0.40)
        case .green: Color(red: 0.39, green: 0.65, blue: 0.40)
        case .mint: .teal
        case .yellow: Color(red: 0.76, green: 0.58, blue: 0.16)
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        case .brown: .brown
        }
    }
}
