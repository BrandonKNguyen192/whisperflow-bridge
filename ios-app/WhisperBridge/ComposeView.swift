import SwiftUI
import UIKit
import WhisperBridgeCore

struct ComposeView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var theme: ThemeStore
    @Binding var showSettings: Bool

    @State private var text = ""
    @State private var enterAfter = false
    @State private var message = ""
    @State private var messageIsError = false
    @State private var sending = false
    @State private var showAdd = false
    @State private var addName = ""
    @State private var sentPulse = false
    @FocusState private var textFocused: Bool
    @Namespace private var chipGlass
    @ObservedObject private var bluetoothLink = BluetoothBridge.shared

    private var palette: AppPalette { AppPalette.palette(for: theme.mode) }
    private var accent: Color { Color(hex: theme.accentHex) }
    private var active: Profile? { profiles.active }
    private var configured: Bool { active?.isConfigured == true }
    private var bluetooth: Bool { active?.transport == .bluetooth }

    var body: some View {
        ZStack {
            AmbientBackground(palette: palette, accent: accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if configured { modePill }
                    profileChips
                    composeCard
                    if bluetooth {
                        // Bluetooth carries text only: no trackpad or air mouse.
                        Label("Bluetooth mode sends text only. Trackpad and air mouse need Wi-Fi or Tailscale.",
                              systemImage: "dot.radiowaves.left.and.right")
                            .font(.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .padding(16)
                            .glassCard()
                    } else {
                        TrackpadView { text, isError in
                            withAnimation(Motion.tap) {
                                message = text
                                messageIsError = isError
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { if bluetooth { bluetoothLink.warmUp() } }
        .onChange(of: active?.id) { if bluetooth { bluetoothLink.warmUp() } }
        .alert("New Computer", isPresented: $showAdd) {
            TextField("Name (e.g. Mac Studio)", text: $addName)
            Button("Add") {
                let name = addName.trimmingCharacters(in: .whitespacesAndNewlines)
                withAnimation(Motion.pop) {
                    profiles.add(name: name.isEmpty ? "MacBook Pro" : name)
                }
                addName = ""
            }
            Button("Cancel", role: .cancel) {
                addName = ""
            }
        } message: {
            Text("You'll set its host and token in Settings.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#4C8DFF"), Color(hex: "#34C77B"), Color(hex: "#F2C14E")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating.speed(0.5), value: sending)
            }
            .frame(width: 46, height: 46)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Whisper Bridge")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(configured ? accent : palette.statusIdle)
                        .frame(width: 7, height: 7)
                        .symbolEffect(.pulse, options: .repeating, value: !configured)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(configured ? accent : palette.textSecondary)
                        .contentTransition(.opacity)
                }
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(palette.textSecondary)
        }
    }

    private var statusText: String {
        guard let active, configured else { return "Not connected" }
        return active.transport == .bluetooth
            ? "\(active.name) · Bluetooth (text only)"
            : "\(active.name) · \(active.host)"
    }

    /// Always-visible answer to "how is this phone talking to the Mac right now?"
    private var modePill: some View {
        let (icon, title, detail, color) = modeDescription
        return Button {
            if bluetooth { bluetoothLink.warmUp() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .symbolEffect(.variableColor.iterative, options: .repeating,
                                  isActive: bluetooth && bluetoothLink.phase == .searching)
                Text(title).fontWeight(.bold)
                Text("·").foregroundStyle(color.opacity(0.6))
                Text(detail)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .font(.subheadline)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color.opacity(0.22)), in: Capsule())
        .accessibilityLabel("\(title), \(detail)")
        .animation(Motion.tap, value: bluetoothLink.phase)
    }

    private var modeDescription: (String, String, String, Color) {
        guard let active else { return ("questionmark", "Not set", "", palette.textSecondary) }
        if active.transport == .bluetooth {
            let blue = Color(hex: "#2F7BFF")
            switch bluetoothLink.phase {
            case .connected:
                return ("antenna.radiowaves.left.and.right", "Bluetooth", "Connected to \(bluetoothLink.macName)", blue)
            case .searching:
                return ("antenna.radiowaves.left.and.right", "Bluetooth", "Searching…", blue)
            case .idle:
                return ("antenna.radiowaves.left.and.right.slash", "Bluetooth", "Not connected — tap to retry", palette.textSecondary)
            }
        }
        return Pairing.isTailscale(active.host)
            ? ("network", "Tailscale", active.host, accent)
            : ("wifi", "Wi‑Fi", active.host, accent)
    }

    private var profileChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                        let isActive = profiles.activeIndex == index
                        Button {
                            withAnimation(Motion.tap) {
                                profiles.setActive(index)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(profile.name,
                                  systemImage: profile.transport == .bluetooth
                                      ? "antenna.radiowaves.left.and.right" : "wifi")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isActive ? accent : palette.textPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 11)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            (isActive ? Glass.regular.tint(accent.opacity(0.35)) : .regular).interactive(),
                            in: Capsule()
                        )
                        .glassEffectID(profile.id, in: chipGlass)
                        .scaleEffect(isActive ? 1.04 : 1.0)
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .glassEffectID("add", in: chipGlass)
                }
                // Room for the active chip's 1.04x pop on both ends so the
                // first pill never gets clipped by the scroll view edge.
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
            }
        }
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("COMPOSE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Toggle("Enter after", isOn: $enterAfter)
                    .font(.caption)
                    .tint(accent)
            }

            TextField("Type or dictate…", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .focused($textFocused)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                sendButton
                actionButton("Enter", icon: "return") {
                    send(mode: "enter")
                }
                actionButton("Copy", icon: "doc.on.clipboard") {
                    send(mode: "clipboard")
                }
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
        }
        .padding(20)
        .glassCard()
    }

    private var sendButton: some View {
        Button {
            send(mode: "type")
        } label: {
            HStack(spacing: 8) {
                if sending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: sentPulse ? "checkmark" : (bluetooth ? "antenna.radiowaves.left.and.right" : "keyboard"))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(sentPulse ? "Sent" : (bluetooth ? "Send via Bluetooth" : "Type"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(accent)
        .disabled(sending)
        .sensoryFeedback(.success, trigger: sentPulse)
    }

    private func actionButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(palette.textPrimary)
        .disabled(sending)
    }

    // MARK: - Actions

    private func send(mode: String) {
        guard let active, active.isConfigured else {
            withAnimation(Motion.tap) {
                message = "Configure the connection in Settings"
                messageIsError = true
            }
            return
        }
        if mode != "enter" && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            withAnimation(Motion.tap) {
                message = "Nothing to send"
                messageIsError = true
            }
            return
        }
        sending = true
        let payload = mode == "enter" ? "" : text
        Task {
            let result = active.transport == .bluetooth
                ? await BluetoothBridge.shared.send(
                    text: payload, mode: mode, enterAfter: enterAfter, token: active.token)
                : await BridgeClient.live.sendText(
                    host: active.host,
                    port: active.port,
                    text: payload,
                    mode: mode,
                    token: active.token,
                    enterAfter: enterAfter
                )
            withAnimation(Motion.tap) {
                message = result.message
                messageIsError = !result.ok
                sending = false
            }
            if result.ok {
                if mode == "type" { text = "" }
                sentPulse = true
                try? await Task.sleep(for: .seconds(1.4))
                sentPulse = false
            }
        }
    }
}
