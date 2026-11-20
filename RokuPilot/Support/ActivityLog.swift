import Foundation

/// A short, human-readable record of what Pilot did, shown in Settings › Activity log.
@MainActor
@Observable
final class ActivityLog {
    static let shared = ActivityLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
    }

    private(set) var entries: [Entry] = []

    nonisolated static func add(_ text: String) async {
        await MainActor.run {
            shared.entries.append(Entry(text: text))
            if shared.entries.count > 300 { shared.entries.removeFirst(shared.entries.count - 300) }
        }
    }

    func clear() { entries.removeAll() }

    var asText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return entries.map { "\(f.string(from: $0.date))  \($0.text)" }.joined(separator: "\n")
    }
}
