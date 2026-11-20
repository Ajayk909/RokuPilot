import Foundation

/// How to find a title's ID on a streaming service's website, so Pilot can deep-link the Roku app to it.
struct StreamingService: Sendable {
    let name: String
    /// Words that identify the Roku app in the TV's app list.
    let appMatch: [String]
    /// Domain used to search the web for title pages.
    let site: String
    /// Regexes whose first capture group is the title ID used for deep links.
    let idPatterns: [String]
    /// If true, the public title page is fetched to confirm it's the right title.
    var verifyPage = false
    var pageURL: (@Sendable (String) -> String)? = nil

    static let all: [StreamingService] = [
        StreamingService(
            name: "Netflix", appMatch: ["netflix"], site: "netflix.com/title",
            idPatterns: [#"netflix\.com/(?:[a-z]{2}(?:-[a-z]{2})?/)?title/(\d{6,9})"#],
            verifyPage: true, pageURL: { "https://www.netflix.com/title/\($0)" }),
        StreamingService(
            name: "Prime Video", appMatch: ["prime video", "amazon"], site: "primevideo.com",
            idPatterns: [#"primevideo\.com/(?:[^\s"'<>]*?/)?detail/(?:[^/\s"'<>]+/)?([0-9A-Z]{10,})"#,
                         #"amazon\.[a-z.]+/(?:gp/video/detail|dp)/([0-9A-Z]{10})"#]),
        StreamingService(
            name: "Disney+", appMatch: ["disney"], site: "disneyplus.com",
            idPatterns: [#"disneyplus\.com/(?:[a-z-]+/)?browse/entity-([0-9a-f-]{36})"#,
                         #"disneyplus\.com/(?:[a-z-]+/)?(?:movies|series)/[^/\s"'<>]+/([A-Za-z0-9]{8,})"#]),
        StreamingService(
            name: "Crunchyroll", appMatch: ["crunchyroll"], site: "crunchyroll.com",
            idPatterns: [#"crunchyroll\.com/(?:[a-z-]+/)?series/([A-Z0-9]{9})"#,
                         #"crunchyroll\.com/(?:[a-z-]+/)?watch/([A-Z0-9]{9})"#]),
        StreamingService(
            name: "Tubi", appMatch: ["tubi"], site: "tubitv.com",
            idPatterns: [#"tubitv\.com/(?:movies|series|tv-shows)/(\d+)"#]),
        StreamingService(
            name: "Apple TV", appMatch: ["apple tv"], site: "tv.apple.com",
            idPatterns: [#"tv\.apple\.com/(?:[a-z]{2}/)?(?:movie|show)/[^/\s"'<>]+/(umc\.cmc\.[a-z0-9]+)"#]),
        StreamingService(
            name: "Crave", appMatch: ["crave"], site: "crave.ca",
            idPatterns: [#"crave\.ca/(?:en/|fr/)?(?:movie|movies|tv-shows|series|special)/[a-z0-9-]*?-(\d{4,})"#]),
        StreamingService(
            name: "Max", appMatch: ["max", "hbo"], site: "play.max.com",
            idPatterns: [#"max\.com/(?:[a-z-]+/)?(?:movie|show)/([0-9a-f-]{36})"#]),
        StreamingService(
            name: "Paramount+", appMatch: ["paramount"], site: "paramountplus.com",
            idPatterns: [#"paramountplus\.com/(?:[a-z]{2}/)?(?:movies/video|shows/video)/([A-Za-z0-9_-]{10,})"#]),
    ]

    static func matching(appName: String) -> StreamingService? {
        let n = appName.lowercased()
        return all.first { s in s.appMatch.contains { n.contains($0) } }
    }

    static func named(_ query: String) -> StreamingService? {
        let q = query.lowercased()
        return all.first { s in s.name.lowercased() == q || s.appMatch.contains { q.contains($0) } }
    }
}

struct FoundTitle: Sendable {
    enum Kind: String, Sendable { case movie, series, episode, unknown }
    let id: String
    let name: String
    var kind: Kind = .unknown
}

/// Finds title IDs (web search first, Gemini search as a backup) and verifies them where possible.
enum TitleFinder {
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func find(_ title: String, on service: StreamingService) async -> FoundTitle? {
        for hit in await webSearchIDs(title, service) {
            if var t = await verify(hit.id, title, service) { t.kind = hit.kind; return t }
        }
        for hit in await geminiIDs(title, service) {
            if var t = await verify(hit.id, title, service) { t.kind = hit.kind; return t }
        }
        return nil
    }

    static func ids(in text: String, _ service: StreamingService) -> [(id: String, kind: FoundTitle.Kind)] {
        var seen = Set<String>()
        var out: [(String, FoundTitle.Kind)] = []
        let ns = text as NSString
        for p in service.idPatterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                let id = ns.substring(with: m.range(at: 1))
                guard !id.isEmpty, seen.insert(id).inserted else { continue }
                out.append((id, kind(of: ns.substring(with: m.range).lowercased())))
            }
        }
        return out
    }

    /// Works out what kind of page a link is from its path.
    static func kind(of link: String) -> FoundTitle.Kind {
        if link.contains("/watch/") || link.contains("/episode") { return .episode }
        if link.contains("/series/") || link.contains("/show/") || link.contains("/shows/")
            || link.contains("tv-shows") || link.contains("/tv/") { return .series }
        if link.contains("/movie") { return .movie }
        return .unknown
    }

    private static func webSearchIDs(_ title: String, _ service: StreamingService) async -> [(id: String, kind: FoundTitle.Kind)] {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [URLQueryItem(name: "q", value: "\(title) site:\(service.site)")]
        var req = URLRequest(url: comps.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            await ActivityLog.add("Web search failed for \(title) on \(service.name)")
            return []
        }
        var html = String(decoding: data, as: UTF8.self)
        html = html.removingPercentEncoding ?? html
        let found = Array(ids(in: html, service).prefix(4))
        await ActivityLog.add("Web search \(service.name) \"\(title)\": \(found.map { "\($0.id) (\($0.kind.rawValue))" }.joined(separator: ", ").ifEmpty("no results"))")
        return found
    }

    private static func geminiIDs(_ title: String, _ service: StreamingService) async -> [(id: String, kind: FoundTitle.Kind)] {
        let prompt = "Find the official \(service.name) web page URL (on \(service.site)) for the title \"\(title)\". Reply with only the URL."
        guard let text = try? await GeminiClient.current.groundedText(prompt) else { return [] }
        let found = Array(ids(in: text, service).prefix(4))
        await ActivityLog.add("Gemini lookup \(service.name) \"\(title)\": \(found.map(\.id).joined(separator: ", ").ifEmpty("nothing"))")
        return found
    }

    private static func verify(_ id: String, _ query: String, _ service: StreamingService) async -> FoundTitle? {
        guard service.verifyPage, let make = service.pageURL, let url = URL(string: make(id)) else {
            return FoundTitle(id: id, name: query)
        }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let pageTitle = XML.matches(#"<title[^>]*>(.*?)</title>"#, in: html).first?.first.map(XML.unescape) ?? ""
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 }
        let hay = pageTitle.lowercased()
        guard !words.isEmpty, Double(words.filter { hay.contains($0) }.count) / Double(words.count) >= 0.6 else { return nil }
        let name = pageTitle
            .replacingOccurrences(of: #"^Watch\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\|.*$"#, with: "", options: .regularExpression)
        return FoundTitle(id: id, name: name.isEmpty ? query : name)
    }

    /// For vague requests ("any horror movie on Prime"): asks Gemini (with Google Search) for real titles.
    static func suggestions(_ description: String, on service: String) async -> [String] {
        let prompt = """
        List 5 specific, popular titles matching "\(description)" that are currently available on \(service) in Canada.
        Reply with one title per line, titles only, no numbering or extra words.
        """
        guard let text = try? await GeminiClient.current.groundedText(prompt) else { return [] }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -*•0123456789.\t\"")) }
            .filter { !$0.isEmpty && $0.count < 80 }
            .prefix(5).map { String($0) }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

extension RokuClient {
    /// Deep-links a Roku app to a title, then checks it's really playing. If not, gets past the
    /// profile screen (using the profile list from Settings) or presses Play on a details page,
    /// and tries other link formats. Remembers the format that worked for each app.
    func playTitle(_ title: FoundTitle, appID: String, appName: String, profile: String?) async throws -> Bool {
        let learnedKey = "deeplink.\(appID)"
        var mediaTypes: [String]
        switch title.kind {
        case .series: mediaTypes = ["series", "season", "episode"]
        case .episode: mediaTypes = ["episode", "series"]
        case .movie: mediaTypes = ["movie", "episode"]
        case .unknown: mediaTypes = ["movie", "series", "episode"]
        }
        if let learned = UserDefaults.standard.string(forKey: learnedKey), title.kind == .unknown {
            mediaTypes.removeAll { $0 == learned }
            mediaTypes.insert(learned, at: 0)
        }

        var profileDone = false
        for (i, mediaType) in mediaTypes.prefix(2).enumerated() {
            await ActivityLog.add("Launch \(appName) contentId=\(title.id) mediaType=\(mediaType)")
            try await launch(appID, params: ["contentId": title.id, "mediaType": mediaType])
            try? await Task.sleep(for: .seconds(i == 0 ? Settings.appLoadSeconds : 6))
            if await isPlaying(appID) { remember(mediaType, learnedKey); return true }

            // Profile screen ("Who's watching?") - pick the right person.
            if !profileDone, try await pickProfile(appName: appName, name: profile) {
                profileDone = true
                try? await Task.sleep(for: .seconds(5))
                if await isPlaying(appID) { remember(mediaType, learnedKey); return true }
            }
            // Details page - OK usually means Play / Start watching.
            if Settings.autoPressPlay {
                await ActivityLog.add("Not playing yet - pressing OK")
                try await press("Select")
                try? await Task.sleep(for: .seconds(5))
                if await isPlaying(appID) { remember(mediaType, learnedKey); return true }
            }
        }
        await ActivityLog.add("\(appName) didn't report playback")
        return false
    }

    /// Moves to a profile on a "Who's watching?" row and selects it.
    /// Uses the names saved in Settings › Profiles. Returns false if no profiles are set for this app.
    @discardableResult
    func pickProfile(appName: String, name: String?) async throws -> Bool {
        let names = Settings.profiles(for: appName)
        guard !names.isEmpty else { return false }
        let wanted = (name?.isEmpty == false ? name! : Settings.defaultProfile(for: appName)).lowercased()
        let index = names.firstIndex { $0.lowercased() == wanted }
            ?? names.firstIndex { $0.lowercased().contains(wanted) || wanted.contains($0.lowercased()) }
            ?? 0
        await ActivityLog.add("Picking profile \(names[index]) (#\(index + 1)) in \(appName)")
        try await press(Array(repeating: "Left", count: names.count), delay: 0.25)
        if index > 0 { try await press(Array(repeating: "Right", count: index), delay: 0.35) }
        try await press("Select")
        return true
    }

    private func remember(_ mediaType: String, _ key: String) {
        UserDefaults.standard.set(mediaType, forKey: key)
    }

    func isPlaying(_ appID: String) async -> Bool {
        guard let s = try? await status(), s.appID == appID else { return false }
        return s.playerState == "play" || s.playerState == "buffer"
    }
}
