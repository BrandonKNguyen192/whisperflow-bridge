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
    @State private var savedFlash = false
    @State private var showScan = false
    @State private var showColorPicker = false
    @State private var customColor = Color(hex: ThemeStore.defaultAccent)
    @Namespace private var modeGlass

    @AppStorage("trackpad_speed") private var trackpadSpeed = 5
    @AppStorage("tap_to_click") private var tapToClick = false
    @AppStorage("natural_scroll") private var naturalScroll = false

    private var palette: AppPalette { AppPalette.palette(for: theme.mode) }
    private var accent: Color { Color(hex: theme.accentHex) }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(palette: palette, accent: accent)
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
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .tint(accent)
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
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                glassButton("Scan", icon: "qrcode.viewfinder") {
                    showScan = true
                }
                glassButton(testing ? "Testing…" : "Test", icon: "bolt", spinner: testing) {
                    testConnection()
                }
                saveButton
            }

            if !message.isEmpty {
                Label(
                    message,
                    systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(messageIsError ? .red : accent)
                .symbolEffect(.bounce, value: message)
                .transition(.move(edge: .top).combined(with: .opacity))
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
        .glassCard()
    }

    private var saveButton: some View {
        Button {
            saveConnection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: savedFlash ? "checkmark" : "checkmark")
                    .contentTransition(.symbolEffect(.replace))
                Text(savedFlash ? "Saved" : "Save")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(accent)
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func saveConnection() {
        let index = profiles.activeIndex
        guard profiles.profiles.indices.contains(index) else {
            withAnimation(Motion.tap) {
                message = "Add a computer first"
                messageIsError = true
            }
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
        withAnimation(Motion.tap) {
            message = "Connection saved"
            messageIsError = false
            savedFlash = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            savedFlash = false
        }
    }

    private func testConnection() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else {
            withAnimation(Motion.tap) {
                message = "Enter a host first"
                messageIsError = true
            }
            return
        }
        let port = Int(portText.trimmingCharacters(in: .whitespaces)) ?? 9877
        let trimmedToken = token.trimmingCharacters(in: .whitespaces)
        withAnimation(Motion.tap) { testing = true }
        Task {
            let result = trimmedToken.isEmpty
                ? await BridgeClient.live.healthCheck(host: trimmedHost, port: port)
                : await BridgeClient.live.probe(host: trimmedHost, port: port, token: trimmedToken)
            withAnimation(Motion.tap) {
                message = result.message
                messageIsError = !result.ok
                testing = false
            }
        }
    }

    private func pasteLink() {
        guard let raw = UIPasteboard.general.string,
              let parsed = Pairing.parse(raw) else {
            withAnimation(Motion.tap) {
                message = "Clipboard doesn't contain a pairing link"
                messageIsError = true
            }
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
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(ThemeMode.allCases) { mode in
                        let isSelected = selectedMode == mode
                        Button {
                            withAnimation(Motion.tap) {
                                selectedMode = mode
                                theme.setMode(mode)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(mode.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? accent : palette.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            (isSelected ? Glass.regular.tint(accent.opacity(0.35)) : .regular).interactive(),
                            in: Capsule()
                        )
                        .glassEffectID(mode.id, in: modeGlass)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                    }
                }
            }

            Text("Accent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(Accents.options, id: \.hex) { option in
                    let isSelected = selectedAccent == option.hex
                    Button {
                        withAnimation(Motion.pop) {
                            selectedAccent = option.hex
                            theme.setAccent(option.hex)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: option.hex))
                                .overlay(
                                    Circle().stroke(
                                        .white.opacity(0.6),
                                        lineWidth: isSelected ? 2.5 : 0
                                    )
                                )
                                .shadow(color: Color(hex: option.hex).opacity(isSelected ? 0.55 : 0.2),
                                        radius: isSelected ? 10 : 3, y: 2)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 46, height: 46)
                        .scaleEffect(isSelected ? 1.12 : 1.0)
                        .frame(maxWidth: .infinity)
                        .contentShape(Circle())
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
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(palette.textPrimary)
        }
        .padding(20)
        .glassCard()
    }

    private var colorPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Circle()
                    .fill(customColor)
                    .frame(width: 84, height: 84)
                    .shadow(color: customColor.opacity(0.5), radius: 16, y: 4)
                    .glassEffect(.regular, in: Circle())
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
                    .buttonStyle(.glassProminent)
                    .tint(accent)
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
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(
                    get: { Double(trackpadSpeed) },
                    set: { newValue in
                        withAnimation(Motion.tap) {
                            trackpadSpeed = Int(newValue.rounded())
                        }
                    }
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
        .glassCard()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(palette.textTertiary)
    }

    private func glassButton(
        _ title: String,
        icon: String,
        spinner: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if spinner {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(accent)
    }
}
