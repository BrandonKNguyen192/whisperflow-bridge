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
    /// Two columns (compose | trackpad) when the window is wide: iPhone Duo
    /// unfolded in landscape, iPad, Stage Manager. Read from this view's own
    /// size, so it follows every fold, rotation and window resize.
    @State private var wideLayout = false
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
                // AnyLayout keeps the same view identity when the layout flips,
                // so the draft text and trackpad state survive a fold or resize.
                let layout = wideLayout
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                layout {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if configured { modePill }
                        profileChips
                        composeCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    controlPanel
                        .frame(maxWidth: .infinity)
                }
                .padding(wideLayout ? 28 : 24)
                .frame(maxWidth: wideLayout ? 1200 : 880)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width >= 720
            } action: { isWide in
                wideLayout = isWide
            }
        }
        .onAppear { syncBluetooth() }
        .onChange(of: active?.id) { syncBluetooth() }
        .onChange(of: active?.transport) { syncBluetooth() }
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

    @ViewBuilder
    private var controlPanel: some View {
        if bluetooth {
            // Bluetooth carries text only: no trackpad or air mouse.
            Label("Bluetooth mode sends text only. Trackpad and air mouse need Wi-Fi or Tailscale.",
                  systemImage: "dot.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            syncBluetooth()
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

    /// The iPhone advertises only while a Bluetooth profile is active, so the
    /// Mac helper can find it; Wi-Fi profiles turn advertising off.
    private func syncBluetooth() {
        if let active, active.transport == .bluetooth {
            bluetoothLink.warmUp(token: active.token)
        } else {
            bluetoothLink.stop()
        }
    }

    private var modeDescription: (String, String, String, Color) {
        guard let active else { return ("questionmark", "Not set", "", palette.textSecondary) }
        if active.transport == .bluetooth {
            let blue = Color(hex: "#2F7BFF")
            switch bluetoothLink.phase {
            case .connected where bluetoothLink.pairingMismatch:
                return ("exclamationmark.triangle.fill", "Bluetooth", "Pairing doesn't match — scan the Mac's QR", .orange)
            case .connected:
                return ("antenna.radiowaves.left.and.right", "Bluetooth", "Connected to \(bluetoothLink.macName)", blue)
            case .searching:
                return ("antenna.radiowaves.left.and.right", "Bluetooth", "Waiting for the Mac…", blue)
            case .idle:
                return ("antenna.radiowaves.left.and.right.slash", "Bluetooth", "\(bluetoothLink.status) — tap to retry", palette.textSecondary)
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
                    .layoutPriority(1)
                actionButton("Copy", icon: "doc.on.clipboard") {
                    send(mode: "clipboard")
                }
            }

            // Single keys pressed on the computer; they work with an empty draft.
            // Narrow windows (iPhone, Duo folded) stack the label under the icon.
            ViewThatFits(in: .horizontal) {
                keyRow(stacked: false)
                keyRow(stacked: true)
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

    private func keyRow(stacked: Bool) -> some View {
        HStack(spacing: 12) {
            actionButton("Tab", icon: "arrow.right.to.line", stacked: stacked) {
                send(mode: "tab")
            }
            actionButton("Backspace", icon: "delete.left", stacked: stacked) {
                send(mode: "backspace")
            }
            actionButton("Enter", icon: "return", stacked: stacked) {
                send(mode: "enter")
            }
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        stacked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if stacked {
                    VStack(spacing: 4) {
                        Image(systemName: icon)
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, -3)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                        Text(title)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
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
        .accessibilityLabel(title)
    }

    // MARK: - Actions

    private static let keyModes: Set<String> = ["enter", "tab", "backspace"]

    private func send(mode: String) {
        guard let active, active.isConfigured else {
            withAnimation(Motion.tap) {
                message = "Configure the connection in Settings"
                messageIsError = true
            }
            return
        }
        let isKey = Self.keyModes.contains(mode)
        if !isKey && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            withAnimation(Motion.tap) {
                message = "Nothing to send"
                messageIsError = true
            }
            return
        }
        sending = true
        let payload = isKey ? "" : text
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
