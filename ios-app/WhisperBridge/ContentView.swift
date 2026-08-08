import SwiftUI
import WhisperBridgeCore

struct ContentView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSettings = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    SidebarView(showSettings: $showSettings)
                        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                } detail: {
                    ComposeView(showSettings: $showSettings)
                }
            } else {
                NavigationStack {
                    ComposeView(showSettings: $showSettings)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            // Debug/screenshot-only hook: SIMCTL_CHILD_WB_SHOW_SETTINGS=1
            if ProcessInfo.processInfo.environment["WB_SHOW_SETTINGS"] == "1" {
                showSettings = true
            }
        }
    }
}
