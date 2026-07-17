import Foundation

/// Reads the settings written by Verse 1.x (Electron) and shares its history
/// file, so both versions of the app stay interchangeable during the rewrite.
/// Settings are read-only from this app for now; Settings UI comes later.
struct AppSettings {
    var apiKey = ""
    var engine = "openai"
    var shortcut = "Alt+Space"
    var autoPaste = true

    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Verse")
    }

    static func load() -> AppSettings {
        var settings = AppSettings()
        let url = dataDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return settings }
        settings.apiKey = json["apiKey"] as? String ?? ""
        settings.engine = json["engine"] as? String ?? "openai"
        settings.shortcut = json["shortcut"] as? String ?? "Alt+Space"
        settings.autoPaste = json["autoPaste"] as? Bool ?? true
        return settings
    }
}

enum History {
    static let limit = 200

    static var fileURL: URL {
        AppSettings.dataDirectory.appendingPathComponent("history.json")
    }

    static func append(text: String, engine: String, durationMs: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var entries: [[String: Any]] = []
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            entries = existing
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var entry: [String: Any] = [
            "id": "\(Int(Date().timeIntervalSince1970 * 1000))-\(String(format: "%06x", Int.random(in: 0..<0xFFFFFF)))",
            "text": trimmed,
            "source": "recording.m4a",
            "engine": engine,
            "createdAt": formatter.string(from: Date()),
        ]
        if let durationMs, durationMs > 0 { entry["durationMs"] = durationMs }
        entries.insert(entry, at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }

        guard let data = try? JSONSerialization.data(
            withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? FileManager.default.createDirectory(
            at: AppSettings.dataDirectory, withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}
