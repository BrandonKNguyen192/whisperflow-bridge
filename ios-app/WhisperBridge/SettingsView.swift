import SwiftUI
import UIKit
import WhisperBridgeCore

struct SettingsView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var portText = "9877"
    @State private var token = ""
    @State private var selectedMode: ThemeMode = .system
    @State private var selectedAccent = ThemeStore.defaultAccent
    @State private var message = ""
    @State private var messageIsError = false
    @State private var testing = false
    @State private var showScan = false
    @State private var showColorPicker = false
    @State private var customColor = Color(hex: ThemeStore.defaultAccent)

    @AppStorage("trackpad_speed") private var trackpadSpeed = 5
    @AppStorage("tap_to_click") private var tapToClick = false
    @AppStorage("natural_scroll") private var naturalScroll = false

    private var palette: AppPalette { AppPalette.palette(for: theme.mode) }
    private var accent: Color { Color(hex: theme.accentHex) }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        connectionSection
                        appearanceSection
                        mouseSection
                    }
                    .padding(20)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showScan) {
                ScanView { parsed in
                    showScan = false
                    host = parsed.host
                    portText = String(parsed.port)
                    token = parsed.token
                    saveConnection()
                }
            }
            .sheet(isPresented: $showColorPicker) {
                colorPickerSheet
            }
            .onAppear { syncFromProfile() }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("CONNECTION")
            field("Host", text: $host, placeholder: "e.g. 192.168.1.5 or 100.x.x.x", keyboard: .URL)
            field("Port", text: $portText, placeholder: "9877", keyboard: .numberPad)

            VStack(alignment: .leading, spacing: 6) {
                Text("Token")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                SecureField("Leave empty on home Wi-Fi", text: $token)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .font(.body)
                    .padding(14)
                    .background(palette.input, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
            }

            HStack(spacing: 10) {
                miniButton("Scan", icon: "qrcode.viewfinder") {
                    showScan = true
                }
                miniButton(testing ? "Testing…" : "Test", icon: "bolt") {
                    testConnection()
                }
                primaryButton("Save") {
                    saveConnection()
                }
            }

            if !message.isEmpty {
                Label(
                    message,
                    systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(messageIsError ? .red : accent)
            }

            Button {
                pasteLink()
            } label: {
                Label("Paste pairing link", systemImage: "doc.on.clipboard")
                    .font(.footnote.weight(.semibold))
            }
            .tint(accent)
        }
        .padding(20)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.border, lineWidth: 1))
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(14)
                .background(palette.input, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
        }
    }

    private func saveConnection() {
        let index = profiles.activeIndex
        guard profiles.profiles.indices.contains(index) else {
            message = "Add a computer first"
            messageIsError = true
            return
        }
        let port = Int(portText.trimmingCharacters(in: .whitespaces)) ?? 9877
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        profiles.saveConnection(
            index: index,
            host: trimmedHost,
            port: port,
            token: token.trimmingCharacters(in: .whitespaces)
        )
        message = "Connection saved"
        messageIsError = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func testConnection() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else {
            message = "Enter a host first"
            messageIsError = true
            return
        }
        let port = Int(portText.trimmingCharacters(in: .whitespaces)) ?? 9877
        let trimmedToken = token.trimmingCharacters(in: .whitespaces)
        testing = true
        Task {
            let result = trimmedToken.isEmpty
                ? await BridgeClient.live.healthCheck(host: trimmedHost, port: port)
                : await BridgeClient.live.probe(host: trimmedHost, port: port, token: trimmedToken)
            message = result.message
            messageIsError = !result.ok
            testing = false
        }
    }

    private func pasteLink() {
        guard let raw = UIPasteboard.general.string,
              let parsed = Pairing.parse(raw) else {
            message = "Clipboard doesn't contain a pairing link"
            messageIsError = true
            return
        }
        host = parsed.host
        portText = String(parsed.port)
        token = parsed.token
        saveConnection()
    }

    private func syncFromProfile() {
        let profile = profiles.active
        host = profile?.host ?? ""
        portText = profile.map { String($0.port) } ?? "9877"
        token = profile?.token ?? ""
        selectedMode = theme.mode
        selectedAccent = theme.accentHex
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("APPEARANCE")
            Text("Theme")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 8) {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        theme.setMode(mode)
                    } label: {
                        Text(mode.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedMode == mode ? accent : palette.chip, in: Capsule())
                            .foregroundStyle(selectedMode == mode ? .white : palette.textPrimary)
                            .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Accent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(Accents.options, id: \.hex) { option in
                    Button {
                        selectedAccent = option.hex
                        theme.setAccent(option.hex)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: option.hex))
                                .frame(width: 46, height: 46)
                                .overlay(
                                    Circle().stroke(
                                        palette.border,
                                        lineWidth: selectedAccent == option.hex ? 3 : 1
                                    )
                                )
                            if selectedAccent == option.hex {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                customColor = Color(hex: selectedAccent)
                showColorPicker = true
            } label: {
                Label("Custom color  \(selectedAccent)", systemImage: "paintpalette")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.border, lineWidth: 1))
    }

    private var colorPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Circle()
                    .fill(customColor)
                    .frame(width: 84, height: 84)
                    .overlay(Circle().stroke(palette.border, lineWidth: 1))
                ColorPicker("Accent color", selection: $customColor, supportsOpacity: false)
                    .padding(20)
                Text("Selected \(customColor.hexString)")
                    .font(.caption.monospaced())
                    .foregroundStyle(palette.textSecondary)
            }
            .navigationTitle("Custom Accent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        selectedAccent = customColor.hexString
                        theme.setAccent(selectedAccent)
                        showColorPicker = false
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Mouse

    private var mouseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("MOUSE")
            HStack {
                Text("Trackpad speed")
                    .font(.subheadline)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(trackpadSpeed)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(accent)
            }
            Slider(
                value: Binding(
                    get: { Double(trackpadSpeed) },
                    set: { trackpadSpeed = Int($0.rounded()) }
                ),
                in: 1...10,
                step: 1
            )
            .tint(accent)
            Toggle("Tap to click", isOn: $tapToClick)
                .font(.subheadline)
                .foregroundStyle(palette.textPrimary)
                .tint(accent)
            Toggle("Natural scrolling", isOn: $naturalScroll)
                .font(.subheadline)
                .foregroundStyle(palette.textPrimary)
                .tint(accent)
        }
        .padding(20)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.border, lineWidth: 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(palette.textTertiary)
    }

    private func miniButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(palette.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
