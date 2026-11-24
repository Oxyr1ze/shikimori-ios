import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Единая дизайн-система приложения (вариант А: Apple + Liquid Glass + Anime Premium).
enum Theme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static let background = Color(UIColor.systemBackground)
    static let card = Color(UIColor.secondarySystemBackground)
    static let accent = Color(UIColor.systemRed)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Фон экранов: стандартный системный (чёрный в тёмной теме, белый в светлой).
struct AppBackground: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}
