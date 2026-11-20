import Foundation
import SwiftUI
import UIKit

struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant, error }
    let id = UUID()
    let role: Role
    let text: String
    var steps: [ToolStep] = []
    let date = Date()
}

/// App-wide state shared by every screen.
@MainActor
@Observable
final class AppModel {
    var messages: [ChatMessage] = []
    var isThinking = false
    var status = RokuStatus()
    var connected = false
    var connectionError: String?
    var apps: [RokuApp] = []
    var appsError: String?
    var showSetup = !Settings.hasCompletedSetup

    private var history: [JSON] = []
    private var pollTask: Task<Void, Never>?

    var roku: RokuClient { .current }

    // MARK: Assistant

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: text))
        isThinking = true
        Haptics.tap()

        Task {
            do {
                let reply = try await AssistantEngine.current.run(text, history: history)
                messages.append(ChatMessage(role: .assistant, text: reply.text, steps: reply.steps))
                history += [
                    ["role": "user", "parts": [["text": .string(text)]]],
                    ["role": "model", "parts": [["text": .string(reply.text)]]],
                ]
                if history.count > 12 { history.removeFirst(history.count - 12) }
                Haptics.success()
            } catch {
                messages.append(ChatMessage(role: .error, text: error.localizedDescription))
                Haptics.error()
            }
            isThinking = false
            await refreshStatus()
        }
    }

    func clearChat() {
        messages.removeAll()
        history.removeAll()
    }

    // MARK: Remote

    func press(_ key: String) {
        Haptics.tap()
        Task {
            do { try await roku.press(key) } catch { flash(error) }
            try? await Task.sleep(for: .milliseconds(600))
            await refreshStatus()
        }
    }

    func togglePower() {
        Haptics.tap()
        Task {
            do {
                if status.isOn { try await roku.powerOff() } else { try await roku.powerOn() }
            } catch { flash(error) }
            try? await Task.sleep(for: .seconds(1))
            await refreshStatus()
        }
    }

    func type(_ text: String) {
        guard !text.isEmpty else { return }
        Task { do { try await roku.type(text) } catch { flash(error) } }
    }

    func launch(_ app: RokuApp) {
        Haptics.tap()
        Task {
            do { try await roku.launch(app.id) } catch { flash(error) }
            try? await Task.sleep(for: .seconds(1.5))
            await refreshStatus()
        }
    }

    func beam(_ link: String) async -> String {
        do {
            let how = try await roku.beam(link.trimmingCharacters(in: .whitespacesAndNewlines))
            Haptics.success()
            return "Sent to TV via \(how)."
        } catch {
            Haptics.error()
            return error.localizedDescription
        }
    }

    private func flash(_ error: Error) {
        connectionError = error.localizedDescription
        connected = false
        Haptics.error()
    }

    // MARK: Status

    func refreshStatus() async {
        guard !Settings.rokuIP.isEmpty else {
            connected = false
            connectionError = RokuError.noAddress.localizedDescription
            return
        }
        do {
            let s = try await roku.status()
            withAnimation(.smooth) {
                status = s
                connected = true
                connectionError = nil
            }
        } catch {
            withAnimation(.smooth) {
                connected = false
                connectionError = error.localizedDescription
            }
        }
    }

    func loadApps() async {
        do {
            apps = try await roku.apps()
            appsError = nil
        } catch {
            appsError = error.localizedDescription
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshStatus()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

enum Haptics {
    @MainActor static func tap() {
        guard Settings.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    @MainActor static func success() {
        guard Settings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    @MainActor static func error() {
        guard Settings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
