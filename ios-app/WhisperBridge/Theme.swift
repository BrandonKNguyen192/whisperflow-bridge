import SwiftUI
import UIKit
import WhisperBridgeCore

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var cleaned = hex.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return ThemeStore.defaultAccent
        }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct AppPalette {
    let background: Color
    let surface: Color
    let card: Color
    let input: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let border: Color
    let chip: Color
    let statusIdle: Color

    static let light = AppPalette(
        background: Color(hex: "#F5F5F7"),
        surface: Color(hex: "#EFEFF2"),
        card: .white,
        input: Color(hex: "#FBFBFD"),
        textPrimary: Color(hex: "#1D1D1F"),
        textSecondary: Color(hex: "#6E6E73"),
        textTertiary: Color(hex: "#86868B"),
        border: Color(hex: "#E3E3E8"),
        chip: Color(hex: "#ECECF0"),
        statusIdle: Color(hex: "#B6B4AC")
    )

    static let earth = AppPalette(
        background: Color(hex: "#F1EEE6"),
        surface: Color(hex: "#E8E3D8"),
        card: Color(hex: "#FBF8F1"),
        input: Color(hex: "#F7F3EB"),
        textPrimary: Color(hex: "#2B2923"),
        textSecondary: Color(hex: "#655F54"),
        textTertiary: Color(hex: "#8A8274"),
        border: Color(hex: "#D8D1C3"),
        chip: Color(hex: "#E8E1D4"),
        statusIdle: Color(hex: "#A89D8A")
    )

    static let dark = AppPalette(
        background: .black,
        surface: Color(hex: "#0D0D0F"),
        card: Color(hex: "#121214"),
        input: Color(hex: "#1A1A1C"),
        textPrimary: Color(hex: "#F5F5F7"),
        textSecondary: Color(hex: "#A1A1A6"),
        textTertiary: Color(hex: "#6E6E73"),
        border: Color(hex: "#2A2A2E"),
        chip: Color(hex: "#1C1C1E"),
        statusIdle: Color(hex: "#55555A")
    )

    static func palette(for mode: ThemeMode) -> AppPalette {
        switch mode {
        case .light: return .light
        case .earth: return .earth
        case .darkOLED: return .dark
        case .system:
            return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
        }
    }
}

enum Accents {
    static let options: [(name: String, hex: String)] = [
        ("Sage", "#2E7D46"),
        ("Sky", "#0EA5E9"),
        ("Rose", "#E11D48"),
        ("Amber", "#D97706"),
        ("Violet", "#7C3AED"),
        ("Teal", "#0D9488"),
        ("Ruby", "#DC2626"),
        ("Mint", "#059669")
    ]

    static func soft(_ hex: String, mode: ThemeMode) -> Color {
        let isDark = mode == .darkOLED
            || (mode == .system && UITraitCollection.current.userInterfaceStyle == .dark)
        return Color(hex: hex).opacity(isDark ? 0.28 : 0.14)
    }
}

@available(iOS 26.0, *)
extension View {
    /// Layered translucent material with Liquid Glass treatment on top.
    func glassCard(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
