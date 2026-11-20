import Foundation

struct YouTubeResult: Sendable {
    let id: String
    let title: String
    let channel: String
}

/// Finds YouTube videos by reading YouTube's public search page (best effort - YouTube can change it).
enum YouTube {
    static func videoID(from link: String) -> String? {
        let pattern = #"(?:v=|youtu\.be/|shorts/|embed/|live/)([\w-]{11})"#
        return XML.matches(pattern, in: link).first?.first
    }

    static func search(_ query: String) async throws -> YouTubeResult? {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(decoding: data, as: UTF8.self)
        return bestMatch(in: html, for: query)
    }

    static func bestMatch(in html: String, for query: String) -> YouTubeResult? {
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 }
        let compactQuery = query.lowercased().filter { $0.isLetter || $0.isNumber }
        guard let re = try? NSRegularExpression(pattern: #""videoRenderer":\{"videoId":"([\w-]{11})""#) else { return nil }
        let ns = html as NSString
        let hits = re.matches(in: html, range: NSRange(location: 0, length: ns.length)).prefix(15)

        var best: YouTubeResult?
        var bestScore = -Double.infinity
        for (i, m) in hits.enumerated() {
            let id = ns.substring(with: m.range(at: 1))
            let start = m.range.location + m.range.length
            let chunk = ns.substring(with: NSRange(location: start, length: min(8000, ns.length - start)))
            let title = XML.matches(#""title":\{"runs":\[\{"text":"(.*?)""#, in: chunk).first?.first ?? ""
            let channel = XML.matches(#""ownerText":\{"runs":\[\{"text":"(.*?)""#, in: chunk).first?.first ?? ""
            let hay = (title + " " + channel).lowercased()
            var score = Double(words.filter { hay.contains($0) }.count)
            if !compactQuery.isEmpty, hay.filter({ $0.isLetter || $0.isNumber }).contains(compactQuery) {
                score += Double(words.count)
            }
            score -= Double(i) * 0.01
            if score > bestScore {
                bestScore = score
                best = YouTubeResult(id: id, title: decode(title), channel: decode(channel))
            }
        }
        return best
    }

    private static func decode(_ s: String) -> String {
        guard let d = "\"\(s)\"".data(using: .utf8),
              let out = try? JSONDecoder().decode(String.self, from: d) else { return s }
        return out
    }
}
