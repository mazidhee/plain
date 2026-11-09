import Foundation

/// Reads the study time Tide logs itself, read-only. Tide appends one JSON line per study session
/// to `<vault>/.tide/focus.jsonl` (`{start, end, minutes, label, path, kind}`, times in ms), from its
/// own timer and its automatic study tracker. The vault path is in Tide's settings.json.
/// Plain never writes there.
enum TideLog {
    struct Entry: Equatable {
        var start: Date
        var end: Date
        var minutes: Int
        var label: String?
    }

    struct Summary: Equatable {
        var todayMinutes = 0
        var weekMinutes = 0
        var lastLabel: String?
        var available = false
        var problem: String?
    }

    /// Tide's study log: PLAIN_TIDE_LOG for tests, else the vault from Tide's settings.
    static var logURL: URL? {
        if let p = ProcessInfo.processInfo.environment["PLAIN_TIDE_LOG"], !p.isEmpty { return URL(fileURLWithPath: p) }
        let settings = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tide/settings.json")
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vault = json["vaultPath"] as? String, !vault.isEmpty else { return nil }
        return URL(fileURLWithPath: vault).appendingPathComponent(".tide/focus.jsonl")
    }

    /// Parses the JSON lines, skipping anything malformed.
    static func parse(_ text: String) -> [Entry] {
        text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let start = (json["start"] as? NSNumber)?.doubleValue else { return nil }
            let minutes = (json["minutes"] as? NSNumber)?.intValue ?? 0
            let end = (json["end"] as? NSNumber)?.doubleValue ?? start + Double(minutes) * 60_000
            guard minutes > 0, minutes <= 24 * 60 else { return nil }
            return Entry(start: Date(timeIntervalSince1970: start / 1000), end: Date(timeIntervalSince1970: end / 1000),
                         minutes: minutes, label: json["label"] as? String)
        }
    }

    static func summarize(_ entries: [Entry], now: Date, calendar: Calendar = .current) -> Summary {
        var cal = calendar
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let week = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        var s = Summary(available: true)
        for e in entries {
            if e.start >= today { s.todayMinutes += e.minutes }
            if e.start >= week { s.weekMinutes += e.minutes }
        }
        s.lastLabel = entries.max { $0.end < $1.end }?.label
        return s
    }

    static func read(now: Date = Date()) -> Summary {
        guard let url = logURL else { return Summary(available: false, problem: "Tide's settings (vault path) weren't found.") }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Summary(available: false, problem: "Tide hasn't logged any study yet.")
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return Summary(available: false, problem: "Tide's study log couldn't be read.")
        }
        return summarize(parse(text), now: now)
    }
}
