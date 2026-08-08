import SwiftUI
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
    @FocusState private var textFocused: Bool

    private var palette: AppPalette { AppPalette.palette(for: theme.mode) }
    private var accent: Color { Color(hex: theme.accentHex) }
    private var active: Profile? { profiles.active }
    private var configured: Bool { active?.host.isEmpty == false }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    profileChips
                    composeCard
                    TrackpadView { text, isError in
                        message = text
                        messageIsError = isError
                    }
                }
                .padding(24)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .alert("New Computer", isPresented: $showAdd) {
            TextField("Name (e.g. Mac Studio)", text: $addName)
            Button("Add") {
                let name = addName.trimmingCharacters(in: .whitespacesAndNewlines)
                profiles.add(name: name.isEmpty ? "MacBook Pro" : name)
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
                RoundedRectangle(cornerRadius: 13)
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
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Whisper Bridge")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(configured ? accent : palette.textSecondary)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 46, height: 46)
                    .background(palette.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var statusText: String {
        guard let active, configured else { return "Not connected" }
        return "\(active.name) · \(active.host)"
    }

    private var profileChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        profiles.setActive(index)
                    } label: {
                        Text(profile.name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                profiles.activeIndex == index ? accent : palette.chip,
                                in: Capsule()
                            )
                            .foregroundStyle(profiles.activeIndex == index ? .white : palette.textPrimary)
                            .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                        .frame(width: 38, height: 38)
                        .background(palette.chip, in: Circle())
                        .overlay(Circle().stroke(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
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
                .background(palette.input, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.border, lineWidth: 1))

            HStack(spacing: 12) {
                actionButton("Type", icon: "keyboard", primary: true) {
                    send(mode: "type")
                }
                actionButton("Enter", icon: "return", primary: false) {
                    send(mode: "enter")
                }
                actionButton("Clipboard", icon: "doc.on.clipboard", primary: false) {
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
            }
        }
        .padding(20)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.border, lineWidth: 1))
    }

    private func actionButton(
        _ title: String,
        icon: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(primary ? accent : palette.chip, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(primary ? .white : palette.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .opacity(sending ? 0.6 : 1)
    }

    // MARK: - Actions

    private func send(mode: String) {
        guard let active, !active.host.isEmpty else {
            message = "Configure the connection in Settings"
            messageIsError = true
            return
        }
        if mode != "enter" && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "Nothing to send"
            messageIsError = true
            return
        }
        sending = true
        let payload = mode == "enter" ? "" : text
        Task {
            let result = await BridgeClient.live.sendText(
                host: active.host,
                port: active.port,
                text: payload,
                mode: mode,
                token: active.token,
                enterAfter: enterAfter
            )
            message = result.message
            messageIsError = !result.ok
            if result.ok && mode == "type" {
                text = ""
            }
            sending = false
        }
    }
}
