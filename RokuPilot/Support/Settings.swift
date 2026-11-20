import Foundation

/// Persistent settings. Plain values live in UserDefaults; the API key lives in the Keychain.
/// Static accessors are used so App Intents (Siri) can read them without the UI running.
enum Settings {
    private static let d = UserDefaults.standard

    static var rokuIP: String {
        get { d.string(forKey: "rokuIP") ?? "" }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "rokuIP") }
    }

    static var geminiKey: String {
        get { Keychain.get("geminiKey") }
        set { Keychain.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: "geminiKey") }
    }

    static var model: String {
        get { d.string(forKey: "model") ?? defaultModel }
        set { d.set(newValue, forKey: "model") }
    }

    static var youTubeLoadSeconds: Double {
        get { d.object(forKey: "ytLoad") as? Double ?? 8 }
        set { d.set(newValue, forKey: "ytLoad") }
    }

    static var netflixLoadSeconds: Double {
        get { d.object(forKey: "nfLoad") as? Double ?? 7 }
        set { d.set(newValue, forKey: "nfLoad") }
    }

    /// Press OK once if Netflix opens on the "Who's watching?" screen.
    static var netflixAutoProfile: Bool {
        get { d.object(forKey: "nfProfile") as? Bool ?? true }
        set { d.set(newValue, forKey: "nfProfile") }
    }

    static var haptics: Bool {
        get { d.object(forKey: "haptics") as? Bool ?? true }
        set { d.set(newValue, forKey: "haptics") }
    }

    static var hasCompletedSetup: Bool {
        !rokuIP.isEmpty && !geminiKey.isEmpty
    }

    static let defaultModel = "gemini-3.5-flash-lite"
    static let models = ["gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.8-flash", "gemini-3.1-flash-lite"]
}
