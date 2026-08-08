import Combine
import Foundation

public enum ThemeMode: String, CaseIterable, Identifiable {
    case light
    case earth
    case darkOLED = "dark_oled"
    case system

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .light: return "Light"
        case .earth: return "Earth"
        case .darkOLED: return "Dark OLED"
        case .system: return "System"
        }
    }
}

public final class ThemeStore: ObservableObject {
    @Published public var mode: ThemeMode
    @Published public var accentHex: String

    private enum Keys {
        static let mode = "theme_mode"
        static let accent = "accent_hex"
    }

    public static let defaultAccent = "#2E7D46"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = ThemeMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .system
        self.accentHex = defaults.string(forKey: Keys.accent) ?? Self.defaultAccent
    }

    public func setMode(_ mode: ThemeMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Keys.mode)
    }

    public func setAccent(_ hex: String) {
        accentHex = hex
        defaults.set(hex, forKey: Keys.accent)
    }
}
