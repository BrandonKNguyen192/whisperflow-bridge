import SwiftUI
import WhisperBridgeCore

@main
struct WhisperBridgeApp: App {
    @StateObject private var profiles: ProfileStore
    @StateObject private var theme: ThemeStore

    init() {
        let profiles = ProfileStore()
        let theme = ThemeStore()
        // Debug/screenshot-only override: SIMCTL_CHILD_WB_THEME=earth etc.
        if let raw = ProcessInfo.processInfo.environment["WB_THEME"],
           let mode = ThemeMode(rawValue: raw) {
            theme.setMode(mode)
        }
        _profiles = StateObject(wrappedValue: profiles)
        _theme = StateObject(wrappedValue: theme)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profiles)
                .environmentObject(theme)
                .tint(Color(hex: theme.accentHex))
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch theme.mode {
        case .genie, .darkOLED: return .dark
        case .light, .earth: return .light
        case .system: return nil
        }
    }
}
