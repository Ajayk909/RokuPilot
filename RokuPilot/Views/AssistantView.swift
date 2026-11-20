import SwiftUI

struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var speech = SpeechRecognizer()
    @FocusState private var focused: Bool

    private let suggestions: [(icon: String, text: String)] = [
        ("music.note", "Play lo-fi beats"),
        ("tv", "What's on right now?"),
        ("moon.zzz.fill", "Turn the TV off in 30 minutes"),
        ("speaker.wave.3.fill", "Turn it up a bit"),
        ("play.rectangle.fill", "Open Netflix"),
        ("magnifyingglass", "Search for Breaking Bad"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NowPlayingCard()
                    .padding(.horizontal)
                    .padding(.top, 4)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if model.messages.isEmpty {
                                emptyState
                            }
                            ForEach(model.messages) { msg in
                                MessageRow(message: msg)
                                    .id(msg.id)
                                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                            }
                            if model.isThinking {
                                ThinkingRow().id("thinking").transition(.opacity)
                            }
                        }
                        .padding()
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.messages)
                        .animation(.easeInOut, value: model.isThinking)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.messages.count) {
                        withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: model.isThinking) {
                        if model.isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                    }
                }

                inputBar
            }
            .background(Backdrop())
            .navigationTitle("Pilot")
            .toolbar {
                if !model.messages.isEmpty {
                    Button("Clear", systemImage: "trash") { withAnimation { model.clearChat() } }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("What should we watch?")
                    .font(.title2.bold())
                Text("Tap the mic and just say it. Pilot opens apps, finds videos and works the remote for you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 12)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suggestions, id: \.text) { s in
                    Button { model.send(s.text) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: s.icon)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Theme.cyan)
                            Text(s.text)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if speech.isRecording {
                Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                    .font(.callout)
                    .foregroundStyle(speech.transcript.isEmpty ? Theme.secondaryText : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
            if let err = speech.errorMessage {
                Text(err).font(.caption).foregroundStyle(.orange).padding(.horizontal, 20)
            }
            HStack(spacing: 10) {
                TextField("Ask Pilot…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))

                if input.trimmingCharacters(in: .whitespaces).isEmpty {
                    MicButton(isRecording: speech.isRecording, level: speech.level) { toggleMic() }
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .frame(width: 46, height: 46)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(model.isThinking)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: speech.isRecording)
    }

    private func submit() {
        let text = input
        input = ""
        model.send(text)
    }

    private func toggleMic() {
        if speech.isRecording {
            speech.stop()
        } else {
            focused = false
            Haptics.tap()
            Task { await speech.start { text in model.send(text) } }
        }
    }
}

struct MicButton: View {
    let isRecording: Bool
    let level: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Theme.violet.opacity(0.35))
                        .scaleEffect(1 + CGFloat(level) * 0.6)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
                Circle().fill(isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.accent))
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.headline.weight(.bold))
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isRecording ? "Stop listening" : "Talk")
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                if !message.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.steps) { step in
                            Label(step.summary, systemImage: step.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(step.ok ? Theme.secondaryText : .orange)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(bubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if message.role != .user {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke)
                }
            }
            if message.role != .user { Spacer(minLength: 48) }
        }
    }

    private var bubble: AnyShapeStyle {
        switch message.role {
        case .user: return AnyShapeStyle(Theme.accent)
        case .assistant: return AnyShapeStyle(Theme.surface)
        case .error: return AnyShapeStyle(Color.orange.opacity(0.18))
        }
    }
}

struct ThinkingRow: View {
    var body: some View {
        HStack {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Theme.cyan)
                            .frame(width: 8, height: 8)
                            .opacity(0.3 + 0.7 * abs(sin(t * 3 + Double(i) * 0.7)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer()
        }
        .accessibilityLabel("Pilot is working")
    }
}
