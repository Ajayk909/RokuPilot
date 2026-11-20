import SwiftUI

/// Lets you tell Pilot who's on each app's "Who's watching?" screen, in on-screen order,
/// so "use Aryan's account" can move to the right profile.
struct ProfilesView: View {
    private let apps = ["Netflix", "Prime Video", "Disney+", "Crunchyroll", "Crave", "Max", "Paramount+", "Apple TV"]

    var body: some View {
        Form {
            Section {
                Text("List **every** profile on each app's \u{201C}Who's watching?\u{201D} screen, **in the order shown on the TV**, separated by commas, including ones you never use. Pilot counts positions, so the order matters. Leave apps without profiles empty.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(apps, id: \.self) { app in
                ProfileRow(app: app)
            }
        }
        .screenBackground()
        .navigationTitle("Profiles")
    }
}

private struct ProfileRow: View {
    let app: String
    @State private var text = ""
    @State private var defaultName = ""
    @State private var vertical = false

    private var names: [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        Section(app) {
            TextField("e.g. AJ, Aryan, Kids", text: $text)
                .autocorrectionDisabled()
                .onChange(of: text) { Settings.setProfilesText(text, for: app) }
            Toggle("Listed top to bottom", isOn: $vertical)
                .onChange(of: vertical) { Settings.setProfilesVertical(vertical, for: app) }
            if names.count > 1 {
                Picker("Default", selection: $defaultName) {
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: defaultName) { Settings.setDefaultProfile(defaultName, for: app) }
            }
        }
        .onAppear {
            text = Settings.profilesText(for: app)
            defaultName = Settings.defaultProfile(for: app)
            vertical = Settings.profilesVertical(for: app)
        }
    }
}

struct ActivityLogView: View {
    @State private var log = ActivityLog.shared
    @State private var copied = false

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("Nothing yet. Ask Pilot to do something, then come back here.")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(log.entries.reversed()) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.date, style: .time).font(.caption2).foregroundStyle(Theme.secondaryText)
                    Text(e.text).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Activity log")
        .toolbar {
            Button(copied ? "Copied" : "Copy") {
                UIPasteboard.general.string = log.asText
                copied = true
            }
            .disabled(log.entries.isEmpty)
            Button("Clear", systemImage: "trash") { log.clear() }
                .disabled(log.entries.isEmpty)
        }
    }
}
