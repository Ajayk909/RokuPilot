import Foundation

struct ToolStep: Identifiable, Hashable, Sendable {
    let id = UUID()
    let tool: String
    let summary: String
    let ok: Bool
}

struct AssistantReply: Sendable {
    let text: String
    let steps: [ToolStep]
}

/// Keeps a "turn the TV off in N minutes" timer while the app is alive.
@MainActor
final class SleepTimer {
    static let shared = SleepTimer()
    private(set) var endsAt: Date?
    private var task: Task<Void, Never>?

    func start(minutes: Double) {
        cancel()
        endsAt = Date().addingTimeInterval(minutes * 60)
        task = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            try? await RokuClient.current.press("PowerOff")
            self.endsAt = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        endsAt = nil
    }

    var minutesLeft: Int? {
        guard let e = endsAt else { return nil }
        return max(0, Int((e.timeIntervalSinceNow / 60).rounded(.up)))
    }
}

/// The brain: sends your request to Gemini, runs the tools it asks for against the TV,
/// and loops until Gemini gives a final answer. UI-free so Siri can use it too.
struct AssistantEngine: Sendable {
    let roku: RokuClient
    let gemini: GeminiClient

    static var current: AssistantEngine { AssistantEngine(roku: .current, gemini: .current) }

    static let system = """
    You are Pilot, the assistant for the user's Roku TV. You control the TV's normal Roku UI through tools.
    Act, don't ask: pick the most sensible reading of the request and do it.
    - For "play <song/video/creator/topic>" use play_youtube unless another app is named.
    - To play a specific movie, show or anime in ANY streaming app (Netflix, Prime Video, Disney+, Crunchyroll,
      Tubi, Apple TV, Crave, Max, Paramount+...), use play_title with the app name. If no app is named, use
      Netflix. Never try to type into an app's own search box.
    - For vague requests ("any horror movie on Prime", "a good anime on Crunchyroll"), first call suggest_titles,
      pick the first suggestion, then call play_title with it. Tell the user which title you picked.
    - If play_title fails, it already falls back to opening the app or Roku search; tell the user plainly.
    - Apps take 3-6 seconds to load: call wait before pressing keys inside an app you just opened.
    - "Louder"/"quieter" = 3 VolumeUp/VolumeDown presses unless a number is given.
    - "Turn it off in N minutes" = set_sleep_timer. "What's on?" = status.
    Reply in one or two short, friendly sentences describing what you did. No markdown.
    """

    static let tools: [JSON] = [
        fn("press_keys", "Press Roku remote buttons in order. Valid keys: \(RokuClient.keys.joined(separator: ", "))",
           ["keys": ["type": "array", "items": ["type": "string"]]], ["keys"]),
        fn("type_text", "Type text into the on-screen keyboard or search box that is currently open.",
           ["text": ["type": "string"]], ["text"]),
        fn("list_apps", "List the apps installed on the TV."),
        fn("launch_app", "Open an installed app by name (fuzzy match). Optionally deep-link with content_id.",
           ["app": ["type": "string"], "content_id": ["type": "string"], "media_type": ["type": "string"]], ["app"]),
        fn("play_title", "Open a streaming app directly on a movie/show/anime and start it. app = the streaming app name.",
           ["title": ["type": "string"], "app": ["type": "string"],
            "is_series": ["type": "boolean", "description": "true for TV shows and anime series"]], ["title", "app"]),
        fn("suggest_titles", "Get real, currently available titles matching a description (genre, mood) on a streaming app.",
           ["description": ["type": "string"], "app": ["type": "string"]], ["description", "app"]),
        fn("roku_search", "Open Roku's global search for a movie, show or actor.",
           ["keyword": ["type": "string"]], ["keyword"]),
        fn("play_youtube", "Find the best YouTube video for a search (matches title and channel) and play it.",
           ["query": ["type": "string"]], ["query"]),
        fn("send_to_tv", "Play a link on the TV. YouTube links open in YouTube; direct .mp4/.m3u8 links play in the Beam app.",
           ["url": ["type": "string"], "title": ["type": "string"]], ["url"]),
        fn("status", "Get what's on the TV now: app, playback state and position, power state, sleep timer."),
        fn("set_sleep_timer", "Turn the TV off after N minutes (works while the Pilot app stays open).",
           ["minutes": ["type": "number"]], ["minutes"]),
        fn("cancel_sleep_timer", "Cancel the sleep timer."),
        fn("wait", "Wait N seconds (max 10), e.g. for an app to finish loading.",
           ["seconds": ["type": "number"]], ["seconds"]),
    ]

    private static func fn(_ name: String, _ desc: String, _ props: [String: JSON]? = nil, _ required: [String] = []) -> JSON {
        var d: [String: JSON] = ["name": .string(name), "description": .string(desc)]
        if let props {
            d["parameters"] = ["type": "object", "properties": .object(props), "required": .array(required.map { .string($0) })]
        }
        return .object(d)
    }

    /// - Parameter history: previous user/model text turns, oldest first.
    func run(_ text: String, history: [JSON] = []) async throws -> AssistantReply {
        var contents = history + [["role": "user", "parts": [["text": .string(text)]]]]
        var steps: [ToolStep] = []

        for _ in 0..<10 {
            let response = try await gemini.generate(system: Self.system, contents: contents, tools: Self.tools)
            guard var content = response["candidates"]?.arrayValue?.first?["content"]?.objectValue else {
                throw GeminiError.empty
            }
            content["role"] = "model"
            let parts = content["parts"]?.arrayValue ?? []
            contents.append(.object(content))

            let calls = parts.compactMap { $0["functionCall"] }
            if calls.isEmpty {
                let reply = parts.compactMap { $0["text"]?.stringValue }.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return AssistantReply(text: reply.isEmpty ? "Done." : reply, steps: steps)
            }

            var responses: [JSON] = []
            for call in calls {
                let name = call["name"]?.stringValue ?? ""
                let args = call["args"]?.objectValue ?? [:]
                let result: JSON
                var ok = true
                do {
                    result = try await execute(name, args)
                } catch {
                    ok = false
                    result = ["ok": false, "error": .string(error.localizedDescription)]
                }
                steps.append(ToolStep(tool: name, summary: Self.describe(name, args), ok: ok))
                var fr: [String: JSON] = ["name": .string(name), "response": ["result": result]]
                if let id = call["id"] { fr["id"] = id }
                responses.append(["functionResponse": .object(fr)])
            }
            contents.append(["role": "user", "parts": .array(responses)])
        }
        return AssistantReply(text: "That took too many steps. Try asking a bit more simply.", steps: steps)
    }

    private func execute(_ name: String, _ a: [String: JSON]) async throws -> JSON {
        func s(_ k: String) -> String { a[k]?.stringValue ?? "" }
        switch name {
        case "press_keys":
            let keys = a["keys"]?.arrayValue?.compactMap(\.stringValue) ?? []
            try await roku.press(keys)
            return ["ok": true, "pressed": .array(keys.map { .string($0) })]
        case "type_text":
            try await roku.type(s("text"))
            return ["ok": true]
        case "list_apps":
            return ["apps": .array(try await roku.apps().map { .string($0.name) })]
        case "launch_app":
            let app = try await roku.findApp(s("app"))
            var params: [String: String] = [:]
            if !s("content_id").isEmpty {
                params = ["contentId": s("content_id"), "mediaType": s("media_type").isEmpty ? "movie" : s("media_type")]
            }
            try await roku.launch(app.id, params: params)
            return ["ok": true, "launched": .string(app.name)]
        case "play_title":
            return try await playTitle(s("title"), appName: s("app").isEmpty ? "Netflix" : s("app"),
                                       isSeries: a["is_series"].map { $0 == .bool(true) } ?? false)
        case "suggest_titles":
            let list = await TitleFinder.suggestions(s("description"), on: s("app").isEmpty ? "Netflix" : s("app"))
            return list.isEmpty ? ["ok": false, "error": "Couldn't find suggestions"]
                                : ["ok": true, "titles": .array(list.map { .string($0) })]
        case "roku_search":
            try await roku.search(s("keyword"))
            return ["ok": true]
        case "play_youtube":
            guard let r = try await YouTube.search(s("query")) else {
                return ["ok": false, "error": "No YouTube results"]
            }
            try await roku.playYouTube(videoID: r.id)
            return ["ok": true, "playing": .string(r.title), "channel": .string(r.channel)]
        case "send_to_tv":
            let how = try await roku.beam(s("url"), title: s("title"))
            return ["ok": true, "opened_in": .string(how)]
        case "status":
            let st = try await roku.status()
            let timer = await SleepTimer.shared.minutesLeft
            return [
                "app": .string(st.appName), "state": .string(st.playerState),
                "position_seconds": .number(Double(st.position / 1000)),
                "duration_seconds": .number(Double(st.duration / 1000)),
                "power": .string(st.powerMode),
                "sleep_timer_minutes_left": timer.map { JSON.number(Double($0)) } ?? JSON.null,
            ]
        case "set_sleep_timer":
            let m = a["minutes"]?.doubleValue ?? 30
            await SleepTimer.shared.start(minutes: m)
            return ["ok": true, "minutes": .number(m)]
        case "cancel_sleep_timer":
            await SleepTimer.shared.cancel()
            return ["ok": true]
        case "wait":
            let secs = min(max(a["seconds"]?.doubleValue ?? 2, 0), 10)
            try? await Task.sleep(for: .seconds(secs))
            return ["ok": true]
        default:
            return ["ok": false, "error": "Unknown tool"]
        }
    }

    private func playTitle(_ title: String, appName: String, isSeries: Bool) async throws -> JSON {
        let app = try await roku.findApp(appName)
        let service = StreamingService.matching(appName: app.name) ?? StreamingService.named(appName)

        // Netflix: proven path.
        if service?.name == "Netflix" {
            guard let t = await Netflix.find(title) else {
                try await roku.launch(app.id)
                return ["ok": false, "error": .string("Couldn't find \(title) on Netflix. Opened Netflix instead.")]
            }
            try await roku.playNetflix(t)
            return ["ok": true, "playing": .string(t.name), "app": "Netflix"]
        }

        guard let service else {
            try await roku.launch(app.id)
            try? await Task.sleep(for: .seconds(4))
            try await roku.search(title)
            return ["ok": false, "error": .string("Pilot can't open titles directly in \(app.name) yet, so it opened Roku search for \(title).")]
        }
        guard let found = await TitleFinder.find(title, on: service) else {
            try await roku.launch(app.id)
            return ["ok": false, "error": .string("Couldn't find \(title) on \(service.name). Opened \(app.name) instead.")]
        }
        let playing = try await roku.playTitle(found, appID: app.id, isSeries: isSeries)
        return playing
            ? ["ok": true, "playing": .string(found.name), "app": .string(app.name)]
            : ["ok": true, "opened": .string(found.name), "app": .string(app.name),
               "note": "Opened the title page; it may need one more OK press or a profile pick to start."]
    }

    static func describe(_ name: String, _ a: [String: JSON]) -> String {
        func s(_ k: String) -> String { a[k]?.stringValue ?? "" }
        switch name {
        case "press_keys": return "Pressed " + (a["keys"]?.arrayValue?.compactMap(\.stringValue).joined(separator: ", ") ?? "")
        case "type_text": return "Typed \u{201C}\(s("text"))\u{201D}"
        case "list_apps": return "Checked installed apps"
        case "launch_app": return "Opened \(s("app"))"
        case "play_title": return "\(s("app").isEmpty ? "Netflix" : s("app")): \(s("title"))"
        case "suggest_titles": return "Found \(s("description")) on \(s("app"))"
        case "roku_search": return "Searched Roku for \(s("keyword"))"
        case "play_youtube": return "YouTube: \(s("query"))"
        case "send_to_tv": return "Sent link to TV"
        case "status": return "Checked what's playing"
        case "set_sleep_timer": return "Sleep timer \(s("minutes")) min"
        case "cancel_sleep_timer": return "Cancelled sleep timer"
        case "wait": return "Waited \(s("seconds"))s"
        default: return name
        }
    }
}
