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

    static let background = dynamic(light: 0xF3F1F9, dark: 0x0B0A12)
    static let accent = dynamic(light: 0xD23A6A, dark: 0xFF7A9E)

    /// Запасные градиенты для постеров, пока картинка грузится.
    static let posterGradients: [[Color]] = [
        [Color(hex: 0x5B7CFA), Color(hex: 0x8E5BEA), Color(hex: 0xF2709C)],
        [Color(hex: 0xF7971E), Color(hex: 0xF2506B), Color(hex: 0xB83280)],
        [Color(hex: 0x56CCA0), Color(hex: 0x2E8F8A), Color(hex: 0x1F5F7A)],
        [Color(hex: 0xA18CD1), Color(hex: 0x6C63D9), Color(hex: 0x3B3A9E)],
        [Color(hex: 0x6B7A8F), Color(hex: 0x3A4660), Color(hex: 0x1D2438)],
        [Color(hex: 0xC94B4B), Color(hex: 0x6D1F3A), Color(hex: 0x2A0F25)]
    ]
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

/// Фон экранов: глубокий цвет с мягкими цветными пятнами.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.47, green: 0.35, blue: 1).opacity(0.30), .clear],
                    center: .center, startRadius: 0, endRadius: 180))
                .frame(width: 360, height: 360)
                .offset(x: -110, y: -320)
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1, green: 0.35, blue: 0.55).opacity(0.22), .clear],
                    center: .center, startRadius: 0, endRadius: 190))
                .frame(width: 380, height: 380)
                .offset(x: 130, y: 260)
        }
        .ignoresSafeArea()
    }
}
