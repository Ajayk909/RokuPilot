import Foundation

struct NetflixTitle: Sendable {
    let id: String
    let name: String
}

/// Finds a movie/show's Netflix title ID so Pilot can deep-link straight into it
/// instead of typing into Netflix's on-screen keyboard.
enum Netflix {
    static let appID = "12"

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func find(_ title: String) async -> NetflixTitle? {
        // 1. A plain web search for netflix.com/title/<id> links (free, no AI quota).
        for id in await webSearchIDs(title) {
            if let t = await verify(id: id, matches: title) { return t }
        }
        // 2. Ask Gemini with Google Search grounding.
        for id in await geminiIDs(title) {
            if let t = await verify(id: id, matches: title) { return t }
        }
        return nil
    }

    private static func ids(in text: String) -> [String] {
        var seen = Set<String>()
        return XML.matches(#"netflix\.com/(?:[a-z]{2}(?:-[a-z]{2})?/)?title/(\d{6,9})"#, in: text)
            .compactMap(\.first)
            .filter { seen.insert($0).inserted }
    }

    private static func webSearchIDs(_ title: String) async -> [String] {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [URLQueryItem(name: "q", value: "\(title) site:netflix.com/title")]
        var req = URLRequest(url: comps.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        let html = String(decoding: data, as: UTF8.self).removingPercentEncoding ?? ""
        return Array(ids(in: html).prefix(5))
    }

    private static func geminiIDs(_ title: String) async -> [String] {
        let prompt = "Find the Netflix title page URL (netflix.com/title/<number>) for \"\(title)\". Reply with only the URL(s), nothing else."
        guard let text = try? await GeminiClient.current.groundedText(prompt) else { return [] }
        var found = ids(in: text)
        // Also accept bare numbers if the model replied with just the ID.
        found += XML.matches(#"\b(\d{7,9})\b"#, in: text).compactMap(\.first).filter { !found.contains($0) }
        return Array(found.prefix(5))
    }

    /// Checks the public Netflix page really is this title (and that it exists).
    private static func verify(id: String, matches query: String) async -> NetflixTitle? {
        guard let url = URL(string: "https://www.netflix.com/title/\(id)") else { return nil }
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
        let hits = words.filter { hay.contains($0) }.count
        guard !words.isEmpty, Double(hits) / Double(words.count) >= 0.6 else { return nil }
        let name = pageTitle
            .replacingOccurrences(of: #"^Watch\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\|\s*Netflix.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\|\s*Netflix Official Site$"#, with: "", options: .regularExpression)
        return NetflixTitle(id: id, name: name.isEmpty ? query : name)
    }
}

extension RokuClient {
    /// Deep-links Netflix straight to a title and starts it. If Netflix stops on the
    /// "Who's watching?" screen, presses OK once to pick the first profile.
    func playNetflix(_ title: NetflixTitle) async throws {
        try await launch(Netflix.appID, params: ["contentId": title.id, "mediaType": "movie"])
        try? await Task.sleep(for: .seconds(Settings.netflixLoadSeconds))
        if let s = try? await status(), s.playerState == "play" || s.playerState == "buffer" { return }
        if Settings.netflixAutoProfile {
            try await press("Select")
        }
    }
}
