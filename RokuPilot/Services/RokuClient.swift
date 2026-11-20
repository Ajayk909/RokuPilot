import Foundation

struct RokuApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct RokuStatus: Equatable, Sendable {
    var appName: String = ""
    var appID: String = ""
    var playerState: String = ""
    var position: Int = 0      // ms
    var duration: Int = 0      // ms
    var powerMode: String = ""
    var deviceName: String = ""

    var isPlaying: Bool { playerState == "play" }
    var isOn: Bool { powerMode.isEmpty || powerMode == "PowerOn" }
    var hasProgress: Bool { duration > 0 && (playerState == "play" || playerState == "pause") }
}

enum RokuError: LocalizedError {
    case noAddress
    case unreachable(String)
    case badKey(String)
    case appNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noAddress: return "Add your TV's IP address in Settings."
        case .unreachable(let why): return "Can't reach your TV. \(why)"
        case .badKey(let k): return "Unknown remote key \"\(k)\"."
        case .appNotFound(let a): return "No installed app matches \"\(a)\"."
        }
    }
}

/// Talks to the Roku over ECP (External Control Protocol, port 8060) on the local network.
struct RokuClient: Sendable {
    let ip: String

    static var current: RokuClient { RokuClient(ip: Settings.rokuIP) }

    static let keys: [String] = [
        "Home", "Back", "Up", "Down", "Left", "Right", "Select", "Play", "Rev", "Fwd",
        "InstantReplay", "Info", "Backspace", "Search", "Enter",
        "VolumeUp", "VolumeDown", "VolumeMute", "PowerOff", "PowerOn", "Power",
        "ChannelUp", "ChannelDown", "InputTuner", "InputAV1",
        "InputHDMI1", "InputHDMI2", "InputHDMI3", "InputHDMI4",
    ]

    static let youTubeID = "837"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    // MARK: - Raw requests

    private func url(_ path: String) throws -> URL {
        guard !ip.isEmpty else { throw RokuError.noAddress }
        guard let u = URL(string: "http://\(ip):8060\(path)") else { throw RokuError.unreachable("Check the IP address.") }
        return u
    }

    @discardableResult
    func post(_ path: String) async throws -> Int {
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.httpBody = Data()
        do {
            let (_, resp) = try await Self.session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw RokuError.unreachable(Self.hint(for: error))
        }
    }

    func get(_ path: String) async throws -> String {
        do {
            let (data, _) = try await Self.session.data(from: try url(path))
            return String(decoding: data, as: UTF8.self)
        } catch let e as RokuError {
            throw e
        } catch {
            throw RokuError.unreachable(Self.hint(for: error))
        }
    }

    func iconURL(for appID: String) -> URL? {
        try? url("/query/icon/\(appID)")
    }

    private static func hint(for error: Error) -> String {
        let ns = error as NSError
        if ns.code == NSURLErrorTimedOut || ns.code == NSURLErrorCannotConnectToHost {
            return "Make sure your phone is on the same Wi-Fi, and on the TV set Settings › System › Advanced system settings › Control by mobile apps to Enabled."
        }
        return ns.localizedDescription
    }

    // MARK: - Commands

    func press(_ key: String) async throws {
        guard let k = Self.keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) else {
            throw RokuError.badKey(key)
        }
        try await post("/keypress/\(k)")
    }

    func press(_ keys: [String], delay: Double = 0.3) async throws {
        for k in keys {
            try await press(k)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    func type(_ text: String) async throws {
        for ch in text {
            let enc = String(ch).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            try await post("/keypress/Lit_\(enc)")
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    func apps() async throws -> [RokuApp] {
        let xml = try await get("/query/apps")
        return XML.matches(#"<app id="([^"]+)"[^>]*>(.*?)</app>"#, in: xml).compactMap { m in
            guard m.count == 2 else { return nil }
            return RokuApp(id: m[0], name: XML.unescape(m[1]))
        }
    }

    func findApp(_ query: String) async throws -> RokuApp {
        let all = try await apps()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if let a = all.first(where: { $0.id == q || $0.name.lowercased() == q }) { return a }
        if let a = all.first(where: { $0.name.lowercased().contains(q) || q.contains($0.name.lowercased()) }) { return a }
        let qWords = Set(q.split(separator: " ").map(String.init))
        if let a = all.max(by: { score($0.name, qWords) < score($1.name, qWords) }), score(a.name, qWords) > 0 { return a }
        throw RokuError.appNotFound(query)
    }

    private func score(_ name: String, _ words: Set<String>) -> Int {
        let n = name.lowercased()
        return words.filter { $0.count > 2 && n.contains($0) }.count
    }

    // MARK: - Power

    /// True when the screen is on. Roku TVs report "PowerOn" vs "DisplayOff"/"Ready"/"Headless" in standby.
    func isOn() async -> Bool {
        guard let d = try? await get("/query/device-info") else { return true }
        let mode = XML.tag("power-mode", in: d) ?? "PowerOn"
        return mode == "PowerOn"
    }

    func powerOn() async throws {
        if await isOn() { return }
        try await post("/keypress/PowerOn")
        for _ in 0..<10 {  // wait for the TV to wake (up to ~5 s)
            try? await Task.sleep(for: .milliseconds(500))
            if await isOn() { break }
        }
        try? await Task.sleep(for: .seconds(1.5))
    }

    func powerOff() async throws {
        try await post("/keypress/PowerOff")
    }

    func launch(_ appID: String, params: [String: String] = [:]) async throws {
        try await powerOn()  // opening an app wakes the TV first
        var path = "/launch/\(appID)"
        if !params.isEmpty { path += "?" + Self.query(params) }
        try await post(path)
    }

    func input(_ params: [String: String]) async throws {
        try await post("/input?" + Self.query(params))
    }

    func search(_ keyword: String) async throws {
        try await post("/search/browse?" + Self.query(["keyword": keyword]))
    }

    func activeApp() async -> (id: String, name: String) {
        guard let xml = try? await get("/query/active-app") else { return ("", "") }
        if let m = XML.matches(#"<app id="([^"]+)"[^>]*>(.*?)</app>"#, in: xml).first, m.count == 2 {
            return (m[0], XML.unescape(m[1]))
        }
        return ("", "Home")
    }

    func status() async throws -> RokuStatus {
        var s = RokuStatus()
        let active = try await get("/query/active-app")
        if let m = XML.matches(#"<app id="([^"]+)"[^>]*>(.*?)</app>"#, in: active).first, m.count == 2 {
            s.appID = m[0]; s.appName = XML.unescape(m[1])
        } else {
            s.appName = "Home"
        }
        if s.appName == "Roku" { s.appName = "Home" }

        if let p = try? await get("/query/media-player") {
            s.playerState = XML.attribute("state", in: p) ?? ""
            s.position = XML.milliseconds(XML.tag("position", in: p))
            s.duration = XML.milliseconds(XML.tag("duration", in: p))
        }
        if let d = try? await get("/query/device-info") {
            s.powerMode = XML.tag("power-mode", in: d) ?? ""
            s.deviceName = XML.tag("user-device-name", in: d) ?? XML.tag("friendly-device-name", in: d) ?? XML.tag("model-name", in: d) ?? "Roku TV"
        }
        return s
    }

    /// Opens YouTube, waits for it to finish loading (cold-launching straight into a
    /// video gives a black screen on some TVs), then sends the video.
    func playYouTube(videoID: String) async throws {
        if await activeApp().id != Self.youTubeID {
            try await launch(Self.youTubeID)
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                if await activeApp().id == Self.youTubeID { break }
            }
            try? await Task.sleep(for: .seconds(Settings.youTubeLoadSeconds))
        }
        try await launch(Self.youTubeID, params: ["contentId": videoID, "mediaType": "movie"])
    }

    /// Sends any link to the TV: YouTube links open in YouTube, direct video links go to the Beam dev app.
    func beam(_ link: String, title: String = "") async throws -> String {
        if let vid = YouTube.videoID(from: link) {
            try await playYouTube(videoID: vid)
            return "YouTube"
        }
        let params = ["url": link, "title": title.isEmpty ? "Beamed video" : title]
        if await activeApp().id == "dev" {
            try await input(params)
        } else {
            try await launch("dev", params: params)
        }
        return "Beam"
    }

    static func query(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.sorted { $0.key < $1.key }.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }
}

/// Tiny regex helpers for Roku's simple XML replies.
enum XML {
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func tag(_ name: String, in text: String) -> String? {
        let v = matches("<\(name)>(.*?)</\(name)>", in: text).first?.first
        return (v?.isEmpty ?? true) ? nil : unescape(v!)
    }

    static func attribute(_ name: String, in text: String) -> String? {
        matches("\(name)=\"([^\"]*)\"", in: text).first?.first
    }

    static func milliseconds(_ s: String?) -> Int {
        Int((s ?? "").filter(\.isNumber)) ?? 0
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
