import SwiftUI

struct RemoteView: View {
    @Environment(AppModel.self) private var model
    @State private var typed = ""
    @State private var link = ""
    @State private var beamResult: String?
    @State private var beaming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    NowPlayingCard()

                    HStack {
                        RoundKey(icon: "arrow.uturn.backward", label: "Back") { model.press("Back") }
                        Spacer()
                        RoundKey(icon: "house.fill", label: "Home") { model.press("Home") }
                        Spacer()
                        RoundKey(icon: "power", label: model.status.isOn ? "Turn off" : "Turn on",
                                 tint: model.status.isOn ? .red : Theme.green) { model.togglePower() }
                    }
                    .padding(.horizontal, 8)

                    DPad()

                    HStack {
                        RoundKey(icon: "gobackward", label: "Replay") { model.press("InstantReplay") }
                        Spacer()
                        RoundKey(icon: "asterisk", label: "Options") { model.press("Info") }
                        Spacer()
                        RoundKey(icon: "magnifyingglass", label: "Search") { model.press("Search") }
                    }
                    .padding(.horizontal, 8)

                    HStack(spacing: 12) {
                        PillKey(icon: "backward.fill") { model.press("Rev") }
                        PillKey(icon: "playpause.fill", prominent: true) { model.press("Play") }
                        PillKey(icon: "forward.fill") { model.press("Fwd") }
                    }

                    HStack(spacing: 12) {
                        PillKey(icon: "speaker.slash.fill") { model.press("VolumeMute") }
                        PillKey(icon: "speaker.minus.fill") { model.press("VolumeDown") }
                        PillKey(icon: "speaker.plus.fill") { model.press("VolumeUp") }
                    }

                    keyboardCard
                    beamCard
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Remote")
        }
    }

    private var keyboardCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Type on TV")
                HStack(spacing: 10) {
                    TextField("Text for a search box", text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit(sendTyped)
                    Button("Send", action: sendTyped)
                        .font(.subheadline.weight(.semibold))
                        .disabled(typed.isEmpty)
                    Button { model.press("Backspace") } label: { Image(systemName: "delete.left") }
                        .accessibilityLabel("Backspace")
                }
            }
        }
    }

    private var beamCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Send a link to the TV")
                HStack(spacing: 10) {
                    TextField("YouTube link or .mp4 / .m3u8", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if link.isEmpty {
                        Button("Paste") { link = UIPasteboard.general.string ?? "" }
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Button {
                            beaming = true
                            Task {
                                beamResult = await model.beam(link)
                                link = ""
                                beaming = false
                            }
                        } label: {
                            if beaming { ProgressView() } else { Text("Beam").fontWeight(.semibold) }
                        }
                    }
                }
                if let beamResult {
                    Text(beamResult).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func sendTyped() {
        model.type(typed)
        typed = ""
    }
}

struct DPad: View {
    @Environment(AppModel.self) private var model
    private let size: CGFloat = 250

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .overlay(Circle().strokeBorder(Theme.stroke))
                .background(.ultraThinMaterial.opacity(0.5), in: Circle())

            arrow("chevron.up", "Up").offset(y: -size * 0.34)
            arrow("chevron.down", "Down").offset(y: size * 0.34)
            arrow("chevron.left", "Left").offset(x: -size * 0.34)
            arrow("chevron.right", "Right").offset(x: size * 0.34)

            Button { model.press("Select") } label: {
                Text("OK")
                    .font(.title3.weight(.bold))
                    .frame(width: size * 0.36, height: size * 0.36)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.violet.opacity(0.5), radius: 14)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("OK")
        }
        .frame(width: size, height: size)
        .foregroundStyle(.white)
    }

    private func arrow(_ icon: String, _ key: String) -> some View {
        Button { model.press(key) } label: {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .accessibilityLabel(key)
    }
}

struct RoundKey: View {
    let icon: String
    let label: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 60, height: 60)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

struct PillKey: View {
    let icon: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
    }
}
