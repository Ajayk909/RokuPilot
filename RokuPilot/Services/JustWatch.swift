import Foundation

/// JustWatch knows which service streams a title in Canada and links straight to it
/// (e.g. netflix.com/title/70254350, crunchyroll.com/series/GRMG8ZQZR, watch.amazon.ca/detail?gti=...).
/// Pilot reads those links to get the IDs it needs to open the title on the TV.
enum JustWatch {
    struct Offer: Sendable {
        let service: StreamingService
        let title: FoundTitle
        let free: Bool
    }

    private static let query = """
    query Search($country: Country!, $language: Language!, $first: Int!, $filter: TitleFilter) {
      popularTitles(country: $country, first: $first, filter: $filter) {
        edges { node {
          objectType
          content(country: $country, language: $language) { title originalReleaseYear }
          offers(country: $country, platform: WEB) {
            monetizationType
            standardWebURL
            package { clearName technicalName }
          }
        } }
      }
    }
    """

    /// Every streaming offer for the best-matching title.
    static func offers(for title: String) async -> [Offer] {
        let body: JSON = [
            "operationName": "Search",
            "query": .string(query),
            "variables": [
                "country": "CA", "language": "en", "first": 5,
                "filter": ["searchQuery": .string(title)],
            ],
        ]
        guard let url = URL(string: "https://apis.justwatch.com/graphql"),
              let payload = try? JSONEncoder().encode(body) else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let json = try? JSONDecoder().decode(JSON.self, from: data) else {
            await ActivityLog.add("JustWatch: request failed")
            return []
        }
        let edges = json["data"]?["popularTitles"]?["edges"]?.arrayValue ?? []
        if edges.isEmpty {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let err = json["errors"]?.arrayValue?.first?["message"]?.stringValue ?? "no matches"
            await ActivityLog.add("JustWatch \"\(title)\" [\(code)]: \(err)")
            return []
        }

        // Pick the result whose name best matches what was asked for.
        let wanted = normalize(title)
        let best = edges.compactMap { $0["node"] }.max { a, b in
            score(normalize(a["content"]?["title"]?.stringValue ?? ""), wanted)
                < score(normalize(b["content"]?["title"]?.stringValue ?? ""), wanted)
        }
        guard let node = best else { return [] }
        let name = node["content"]?["title"]?.stringValue ?? title
        let kind: FoundTitle.Kind = node["objectType"]?.stringValue == "SHOW" ? .series : .movie

        var out: [Offer] = []
        var seen = Set<String>()
        for offer in node["offers"]?.arrayValue ?? [] {
            let pkg = (offer["package"]?["clearName"]?.stringValue ?? "").lowercased()
            let link = offer["standardWebURL"]?.stringValue ?? ""
            guard let service = StreamingService.all.first(where: { s in s.appMatch.contains { pkg.contains($0) } }),
                  !seen.contains(service.name) else { continue }
            let decoded = link.removingPercentEncoding ?? link
            guard let id = TitleFinder.ids(in: decoded, service).first?.id else { continue }
            let monetization = offer["monetizationType"]?.stringValue ?? ""
            guard ["FLATRATE", "FREE", "ADS"].contains(monetization) else { continue }  // skip rent/buy
            seen.insert(service.name)
            out.append(Offer(service: service, title: FoundTitle(id: id, name: name, kind: kind),
                             free: monetization != "FLATRATE"))
        }
        await ActivityLog.add("JustWatch \"\(name)\": \(out.map { "\($0.service.name) \($0.title.id)" }.joined(separator: ", ").ifEmpty("not streaming on a supported service"))")
        return out
    }

    static func find(_ title: String, on service: StreamingService) async -> FoundTitle? {
        await offers(for: title).first { $0.service.name == service.name }?.title
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
    }

    private static func score(_ candidate: String, _ wanted: String) -> Int {
        if candidate == wanted { return 100 }
        let w = Set(wanted.split(separator: " ")), c = Set(candidate.split(separator: " "))
        return w.intersection(c).count * 10 - abs(c.count - w.count)
    }
}
