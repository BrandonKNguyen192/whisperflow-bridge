import SwiftUI
import WhisperBridgeCore

struct SidebarView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var theme: ThemeStore
    @Binding var showSettings: Bool

    @State private var showAdd = false
    @State private var addName = ""

    private var accent: Color { Color(hex: theme.accentHex) }

    var body: some View {
        List {
            Section("Computers") {
                ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        profiles.setActive(index)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: profile.host.isEmpty ? "desktopcomputer" : "laptopcomputer")
                                .foregroundStyle(profiles.activeIndex == index ? accent : Color.secondary)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(profile.host.isEmpty ? "Not configured" : profile.host)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if profiles.activeIndex == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        profiles.activeIndex == index ? accent.opacity(0.12) : nil
                    )
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            profiles.remove(at: index)
                        }
                    }
                }
            }
            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Add Computer", systemImage: "plus.circle.fill")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Whisper Bridge")
        .safeAreaInset(edge: .bottom) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .padding(12)
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
}
