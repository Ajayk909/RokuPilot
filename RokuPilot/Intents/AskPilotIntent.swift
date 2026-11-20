import AppIntents
import Foundation

/// "Hey Siri, Ask Pilot" → Siri asks what to do → Pilot does it on the TV and answers.
struct AskPilotIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Pilot"
    static var description = IntentDescription("Tell your Roku TV what to do, in plain words.")
    static var openAppWhenRun = false

    @Parameter(title: "Request", requestValueDialog: "What should I do on the TV?")
    var request: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard Settings.hasCompletedSetup else {
            return .result(dialog: "Open Pilot first and add your TV and Gemini key.")
        }
        do {
            let reply = try await AssistantEngine.current.run(request)
            return .result(dialog: IntentDialog(stringLiteral: reply.text))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

/// One-tap remote actions that also show up in Shortcuts, Spotlight and the Action Button.
enum TVButton: String, AppEnum {
    case playPause, home, back, volumeUp, volumeDown, mute, power

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TV Button"
    static var caseDisplayRepresentations: [TVButton: DisplayRepresentation] = [
        .playPause: "Play/Pause", .home: "Home", .back: "Back",
        .volumeUp: "Volume Up", .volumeDown: "Volume Down", .mute: "Mute", .power: "Power",
    ]

    var key: String {
        switch self {
        case .playPause: return "Play"
        case .home: return "Home"
        case .back: return "Back"
        case .volumeUp: return "VolumeUp"
        case .volumeDown: return "VolumeDown"
        case .mute: return "VolumeMute"
        case .power: return "Power"
        }
    }
}

struct PressTVButtonIntent: AppIntent {
    static var title: LocalizedStringResource = "Press TV Button"
    static var description = IntentDescription("Press a button on your Roku TV.")
    static var openAppWhenRun = false

    @Parameter(title: "Button")
    var button: TVButton

    func perform() async throws -> some IntentResult {
        try await RokuClient.current.press(button.key)
        return .result()
    }
}

struct TurnTVOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn TV On"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RokuClient.current.powerOn()
        return .result(dialog: "TV is on.")
    }
}

struct TurnTVOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn TV Off"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RokuClient.current.powerOff()
        return .result(dialog: "TV is off.")
    }
}

struct PilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskPilotIntent(),
            phrases: ["Ask \(.applicationName)", "Tell \(.applicationName)", "\(.applicationName) TV"],
            shortTitle: "Ask Pilot",
            systemImageName: "sparkles.tv"
        )
        AppShortcut(
            intent: TurnTVOnIntent(),
            phrases: ["Turn on the TV with \(.applicationName)", "\(.applicationName) TV on"],
            shortTitle: "TV On",
            systemImageName: "power"
        )
        AppShortcut(
            intent: TurnTVOffIntent(),
            phrases: ["Turn off the TV with \(.applicationName)", "\(.applicationName) TV off"],
            shortTitle: "TV Off",
            systemImageName: "power.dotted"
        )
        AppShortcut(
            intent: PressTVButtonIntent(),
            phrases: ["Press \(\.$button) with \(.applicationName)", "\(.applicationName) \(\.$button)"],
            shortTitle: "TV Button",
            systemImageName: "av.remote"
        )
    }
}
