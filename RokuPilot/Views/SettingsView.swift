import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var ip = Settings.rokuIP
    @State private var key = Settings.geminiKey
    @State private var selectedModel = Settings.model
    @State private var ytLoad = Settings.youTubeLoadSeconds
    @State private var haptics = Settings.haptics
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false

    var isOnboarding = false
    var onDone: (() -> Void)? = nil

    var body: some View {
        Form {
            if isOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("Welcome to Pilot").font(.title.bold())
                        Text("Two quick things and your TV is ready to take orders.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("e.g. 10.0.0.129", text: $ip)
                    .keyboardType(.decimalPad)
                    .onChange(of: ip) { Settings.rokuIP = ip; testResult = nil }
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if testing { ProgressView() }
                        else if let r = testResult {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.ok ? Theme.green : .orange)
                        }
                    }
                }
                .disabled(ip.isEmpty || testing)
                if let r = testResult {
                    Text(r.text).font(.footnote).foregroundStyle(r.ok ? Theme.secondaryText : .orange)
                }
            } header: {
                Text("Roku TV")
            } footer: {
                Text("On the TV: Settings › Network › About shows the IP address. Also set Settings › System › Advanced system settings › Control by mobile apps to Enabled.")
            }

            Section {
                SecureField("Paste your API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: key) { Settings.geminiKey = key }
                Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                    Label("Get a free key from Google AI Studio", systemImage: "arrow.up.right.square")
                }
                if !isOnboarding {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(Settings.models, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: selectedModel) { Settings.model = selectedModel }
                }
            } header: {
                Text("Gemini AI")
            } footer: {
                Text("Your key is stored in the iPhone Keychain and only sent to Google. If a model is busy, Pilot automatically tries the others.")
            }

            if !isOnboarding {
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("YouTube load time")
                            Spacer()
                            Text("\(Int(ytLoad)) s").foregroundStyle(Theme.secondaryText).monospacedDigit()
                        }
                        Slider(value: $ytLoad, in: 3...15, step: 1)
                            .onChange(of: ytLoad) { Settings.youTubeLoadSeconds = ytLoad }
                    }
                    Toggle("Haptic feedback", isOn: $haptics)
                        .onChange(of: haptics) { Settings.haptics = haptics }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("How long Pilot waits for YouTube to open before starting a video. Raise it if videos start on a black screen.")
                }

                Section {
                    Label("Say \u{201C}Ask Pilot\u{201D} to Siri, then your request.", systemImage: "waveform")
                    Label("Or add Pilot to the Action Button or Control Center from the Shortcuts app.", systemImage: "button.programmable")
                } header: {
                    Text("Siri")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Works with", value: "Roku TVs & players")
                } header: {
                    Text("About")
                }
            }

            if isOnboarding {
                Section {
                    Button {
                        onDone?()
                    } label: {
                        Text("Start using Pilot")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .disabled(ip.isEmpty || key.isEmpty)
                }
            }
        }
        .screenBackground()
        .navigationTitle(isOnboarding ? "" : "Settings")
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let s = try await RokuClient(ip: ip).status()
            testResult = (true, "Connected to \(s.deviceName.isEmpty ? "your Roku" : s.deviceName).")
            Haptics.success()
            await model.refreshStatus()
            await model.loadApps()
        } catch {
            testResult = (false, error.localizedDescription)
            Haptics.error()
        }
    }
}
