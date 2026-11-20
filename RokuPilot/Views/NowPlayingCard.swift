import SwiftUI

struct NowPlayingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 14) {
                AppIconView(appID: model.status.appID, name: model.status.appName, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.connected ? Theme.green : Color.orange)
                            .frame(width: 7, height: 7)
                            .shadow(color: model.connected ? Theme.green : .clear, radius: 4)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .contentTransition(.opacity)

                    if model.connected, model.status.hasProgress {
                        ProgressView(value: Double(model.status.position), total: Double(max(model.status.duration, 1)))
                            .tint(Theme.cyan)
                            .padding(.top, 2)
                        HStack {
                            Text(Self.time(model.status.position))
                            Spacer()
                            Text(Self.time(model.status.duration))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)

                if model.connected, model.status.hasProgress {
                    Button { model.press("Play") } label: {
                        Image(systemName: model.status.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(model.status.isPlaying ? "Pause" : "Play")
                }
            }
        }
    }

    private var title: String {
        if !model.connected { return "Not connected" }
        if !model.status.isOn { return "TV is off" }
        return model.status.appName.isEmpty ? "Home" : model.status.appName
    }

    private var subtitle: String {
        if !model.connected { return model.connectionError ?? "Looking for your TV…" }
        var parts = [model.status.deviceName.isEmpty ? "Roku TV" : model.status.deviceName]
        switch model.status.playerState {
        case "play": parts.append("Playing")
        case "pause": parts.append("Paused")
        case "buffer": parts.append("Buffering")
        default: break
        }
        if let m = SleepTimer.shared.minutesLeft { parts.append("Sleep in \(m)m") }
        return parts.joined(separator: " · ")
    }

    static func time(_ ms: Int) -> String {
        let s = ms / 1000
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Shows the real channel icon straight from the TV, with a tidy fallback.
struct AppIconView: View {
    let appID: String
    let name: String
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Theme.violet.opacity(0.35))
            if !appID.isEmpty, let url = RokuClient.current.iconURL(for: appID) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Theme.stroke))
    }

    private var fallback: some View {
        Image(systemName: name == "Home" || name.isEmpty ? "tv" : "play.rectangle.fill")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
    }
}
