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

// MARK: - Motion

enum Motion {
    /// Default spring for taps, selections, and small state changes.
    static let tap = Animation.spring(duration: 0.35, bounce: 0.25)
    /// Bouncier spring for playful moments (send success, chip pops).
    static let pop = Animation.spring(duration: 0.45, bounce: 0.45)
    /// Gentle spring for larger layout moves.
    static let settle = Animation.spring(duration: 0.5, bounce: 0.12)
}

// MARK: - Liquid Glass

extension View {
    /// Layered translucent material with Liquid Glass treatment on top.
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Interactive glass pill — buttons, chips, toggles.
    func glassPill<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        self.glassEffect(
            (tint.map { Glass.regular.tint($0) } ?? .regular).interactive(),
            in: shape
        )
    }
}

// MARK: - Ambient background

/// Slow-drifting color blobs that sit under the glass surfaces so the Liquid
/// Glass has something alive to refract. Accent-tinted and theme aware.
struct AmbientBackground: View {
    let palette: AppPalette
    let accent: Color

    @State private var drift = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            blob(accent.opacity(0.35), size: 340,
                 offset: drift ? CGSize(width: 40, height: 30) : CGSize(width: -30, height: -40),
                 anchor: .topLeading)
            blob(Color(hex: "#4C8DFF").opacity(0.28), size: 300,
                 offset: drift ? CGSize(width: -50, height: 20) : CGSize(width: 40, height: -20),
                 anchor: .bottomTrailing)
            blob(Color(hex: "#F2C14E").opacity(0.22), size: 260,
                 offset: drift ? CGSize(width: 20, height: -30) : CGSize(width: -40, height: 40),
                 anchor: .bottomLeading)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat, offset: CGSize, anchor: Alignment) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 90)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchor)
    }
}
