import Foundation

enum GeminiError: LocalizedError {
    case noKey
    case busy
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Gemini API key in Settings."
        case .busy: return "Gemini is busy right now. Try again in a moment."
        case .http(let code, let msg): return "Gemini error \(code): \(msg)"
        case .empty: return "Gemini returned an empty answer."
        }
    }
}

/// Calls the Gemini REST API with function calling. Retries busy models and
/// falls back through the model list so a single overloaded model doesn't stop you.
struct GeminiClient: Sendable {
    let apiKey: String
    let models: [String]

    static var current: GeminiClient {
        let primary = Settings.model
        return GeminiClient(apiKey: Settings.geminiKey,
                            models: [primary] + Settings.models.filter { $0 != primary })
    }

    func generate(system: String, contents: [JSON], tools: [JSON]) async throws -> JSON {
        try await send([
            "systemInstruction": ["parts": [["text": .string(system)]]],
            "contents": .array(contents),
            "tools": [["functionDeclarations": .array(tools)]],
        ])
    }

    /// One-shot question answered with Google Search grounding (used to look things up, e.g. Netflix IDs).
    func groundedText(_ prompt: String) async throws -> String {
        let r = try await send([
            "contents": [["role": "user", "parts": [["text": .string(prompt)]]]],
            "tools": [["google_search": [:]]],
        ])
        let parts = r["candidates"]?.arrayValue?.first?["content"]?["parts"]?.arrayValue ?? []
        return parts.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
    }

    func plainText(_ prompt: String) async throws -> String {
        let r = try await send(["contents": [["role": "user", "parts": [["text": .string(prompt)]]]]])
        let parts = r["candidates"]?.arrayValue?.first?["content"]?["parts"]?.arrayValue ?? []
        return parts.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
    }

    private func send(_ body: JSON) async throws -> JSON {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        let payload = try JSONEncoder().encode(body)
        var lastError: Error = GeminiError.busy

        for model in models {
            for attempt in 0..<2 {
                var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
                req.httpMethod = "POST"
                req.timeoutInterval = 40
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                req.httpBody = payload
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 200 { return try JSONDecoder().decode(JSON.self, from: data) }
                    let message = (try? JSONDecoder().decode(JSON.self, from: data))?["error"]?["message"]?.stringValue
                        ?? String(decoding: data.prefix(200), as: UTF8.self)
                    lastError = GeminiError.http(code, message)
                    if [429, 500, 503].contains(code) {
                        try? await Task.sleep(for: .seconds(Double(attempt + 1)))
                        continue
                    }
                    if code == 403 || code == 404 { break }  // model not available to this key - try next
                    throw lastError
                } catch let e as GeminiError {
                    throw e
                } catch {
                    lastError = error
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw lastError
    }
}
