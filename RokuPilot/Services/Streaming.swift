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
    var pageURL: ((String) -> String)? = nil

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
    let id: String
    let name: String
}

/// Finds title IDs (web search first, Gemini search as a backup) and verifies them where possible.
enum TitleFinder {
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func find(_ title: String, on service: StreamingService) async -> FoundTitle? {
        for id in await webSearchIDs(title, service) {
            if let t = await verify(id, title, service) { return t }
        }
        for id in await geminiIDs(title, service) {
            if let t = await verify(id, title, service) { return t }
        }
        return nil
    }

    static func ids(in text: String, _ service: StreamingService) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for p in service.idPatterns {
            for m in XML.matches(p, in: text) {
                if let id = m.first, !id.isEmpty, seen.insert(id).inserted { out.append(id) }
            }
        }
        return out
    }

    private static func webSearchIDs(_ title: String, _ service: StreamingService) async -> [String] {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [URLQueryItem(name: "q", value: "\(title) site:\(service.site)")]
        var req = URLRequest(url: comps.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        var html = String(decoding: data, as: UTF8.self)
        html = html.removingPercentEncoding ?? html
        return Array(ids(in: html, service).prefix(4))
    }

    private static func geminiIDs(_ title: String, _ service: StreamingService) async -> [String] {
        let prompt = "Find the official \(service.name) web page URL (on \(service.site)) for the title \"\(title)\". Reply with only the URL."
        guard let text = try? await GeminiClient.current.groundedText(prompt) else { return [] }
        return Array(ids(in: text, service).prefix(4))
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

extension RokuClient {
    /// Deep-links a Roku app to a title, then checks it's really playing. If not, presses OK
    /// (handles "Who's watching?" and details pages) and tries other link formats.
    /// Remembers the format that worked for each app.
    func playTitle(_ title: FoundTitle, appID: String, isSeries: Bool) async throws -> Bool {
        let learnedKey = "deeplink.\(appID)"
        var mediaTypes = isSeries ? ["series", "episode", "season", "movie"] : ["movie", "episode", "series"]
        if let learned = UserDefaults.standard.string(forKey: learnedKey) {
            mediaTypes.removeAll { $0 == learned }
            mediaTypes.insert(learned, at: 0)
        }

        for (i, mediaType) in mediaTypes.prefix(2).enumerated() {
            try await launch(appID, params: ["contentId": title.id, "mediaType": mediaType])
            try? await Task.sleep(for: .seconds(i == 0 ? Settings.appLoadSeconds : 5))
            if await isPlaying(appID) { UserDefaults.standard.set(mediaType, forKey: learnedKey); return true }

            if Settings.netflixAutoProfile {  // "Who's watching?" / details page "Play" button
                try await press("Select")
                try? await Task.sleep(for: .seconds(4))
                if await isPlaying(appID) { UserDefaults.standard.set(mediaType, forKey: learnedKey); return true }
            }
        }
        return false
    }

    func isPlaying(_ appID: String) async -> Bool {
        guard let s = try? await status(), s.appID == appID else { return false }
        return s.playerState == "play" || s.playerState == "buffer"
    }
}
