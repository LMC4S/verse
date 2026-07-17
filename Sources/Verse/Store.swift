import Foundation

extension Notification.Name {
    static let verseHistoryChanged = Notification.Name("verseHistoryChanged")
}

/// Shares settings.json and history.json with Verse 1.x (Electron), so both
/// versions of the app stay interchangeable during the rewrite. Writes always
/// merge into the existing JSON — unknown keys (saveRoot, …) are preserved.
struct AppSettings {
    var apiKey = ""
    var engine = "openai"
    var mlxModel = "mlx-community/whisper-large-v3-turbo"
    var shortcut = "Alt+Space"
    var autoPaste = true

    /// The stable Electron app's data. Read-only from this app — the dev
    /// build must never modify the shipping Verse's files.
    static var v1Directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Verse")
    }

    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VerseDev")
    }

    /// First launch: copy the v1 settings so the API key and preferences
    /// carry over, but take F10 so the stable app keeps F9. History starts
    /// empty — both apps writing one history.json invites clobbering.
    static func seedFromV1IfNeeded() {
        let fm = FileManager.default
        let v1Settings = v1Directory.appendingPathComponent("settings.json")
        guard !fm.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: v1Settings),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        json["shortcut"] = "F10"
        try? fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        if let out = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? out.write(to: fileURL)
        }
    }

    static var fileURL: URL {
        dataDirectory.appendingPathComponent("settings.json")
    }

    static func rawDictionary() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    static func load() -> AppSettings {
        let json = rawDictionary()
        var settings = AppSettings()
        settings.apiKey = json["apiKey"] as? String ?? settings.apiKey
        settings.engine = json["engine"] as? String ?? settings.engine
        settings.mlxModel = json["mlxModel"] as? String ?? settings.mlxModel
        settings.shortcut = json["shortcut"] as? String ?? settings.shortcut
        settings.autoPaste = json["autoPaste"] as? Bool ?? settings.autoPaste
        return settings
    }

    /// Merge-writes the given keys, leaving everything else untouched.
    static func save(_ mutations: [String: Any]) {
        var json = rawDictionary()
        for (key, value) in mutations { json[key] = value }
        guard let data = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? FileManager.default.createDirectory(
            at: dataDirectory, withIntermediateDirectories: true
        )
        try? (String(data: data, encoding: .utf8)! + "\n").write(
            to: fileURL, atomically: true, encoding: .utf8
        )
    }
}

enum History {
    static let limit = 200
    /// whisper-1 pricing, for the approximate-cost stat.
    static let openAICostPerMinute = 0.006

    struct Entry: Identifiable {
        let id: String
        let text: String
        let engine: String
        let createdAt: Date?
        let durationMs: Int?
    }

    static var fileURL: URL {
        AppSettings.dataDirectory.appendingPathComponent("history.json")
    }

    private static func rawEntries() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return entries
    }

    private static func write(_ entries: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? FileManager.default.createDirectory(
            at: AppSettings.dataDirectory, withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .verseHistoryChanged, object: nil)
        }
    }

    static func list() -> [Entry] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return rawEntries().compactMap { raw in
            guard let id = raw["id"] as? String, let text = raw["text"] as? String else {
                return nil
            }
            let createdAt = (raw["createdAt"] as? String).flatMap {
                formatter.date(from: $0) ?? plain.date(from: $0)
            }
            return Entry(
                id: id,
                text: text,
                engine: raw["engine"] as? String ?? "",
                createdAt: createdAt,
                durationMs: raw["durationMs"] as? Int
            )
        }
    }

    static func append(text: String, engine: String, durationMs: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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

        var entries = rawEntries()
        entries.insert(entry, at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        write(entries)
    }

    static func delete(id: String) {
        write(rawEntries().filter { $0["id"] as? String != id })
    }

    static func clear() {
        write([])
    }
}
