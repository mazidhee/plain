import Foundation

/// Where Plain keeps its files: ~/Library/Application Support/Plain, or PLAIN_DATA_DIR for tests.
enum PlainPaths {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["PLAIN_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Plain", isDirectory: true)
    }

    static func file(_ name: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}

enum JSONFiles {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Every focus block, in sessions.json.
final class SessionStore {
    private(set) var sessions: [CompletedSession]
    let url: URL

    init(url: URL = PlainPaths.file("sessions.json")) {
        self.url = url
        sessions = JSONFiles.load([CompletedSession].self, from: url) ?? []
    }

    func add(_ session: CompletedSession) {
        sessions.append(session)
        JSONFiles.save(sessions, to: url)
    }
}

/// Totals for the Stats tab.
struct Stats: Equatable {
    var todayMinutes: Int
    var weekMinutes: Int
    var todayByCategory: [Category: Int]
    var weekByCategory: [Category: Int]
    /// Minutes per day, Monday first.
    var weekDays: [Int]
    var streakDays: Int
    var recent: [CompletedSession]

    static func compute(_ sessions: [CompletedSession], now: Date, calendar: Calendar = .current) -> Stats {
        var cal = calendar
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        var todayBy: [Category: Int] = [:], weekBy: [Category: Int] = [:]
        var days = Array(repeating: 0, count: 7)
        for s in sessions where s.minutes > 0 {
            if s.end >= today && s.end <= now.addingTimeInterval(1) { todayBy[s.category, default: 0] += s.minutes }
            if s.end >= weekStart {
                weekBy[s.category, default: 0] += s.minutes
                let d = cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: s.end)).day ?? 0
                if (0..<7).contains(d) { days[d] += s.minutes }
            }
        }
        // Streak: consecutive days with focus, ending today (or yesterday if today has none yet).
        let focusDays = Set(sessions.filter { $0.minutes > 0 }.map { cal.startOfDay(for: $0.end) })
        var streak = 0
        var day = focusDays.contains(today) ? today : cal.date(byAdding: .day, value: -1, to: today)!
        while focusDays.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        let recent = Array(sessions.sorted { $0.end > $1.end }.prefix(6))
        return Stats(todayMinutes: todayBy.values.reduce(0, +), weekMinutes: weekBy.values.reduce(0, +),
                     todayByCategory: todayBy, weekByCategory: weekBy, weekDays: days, streakDays: streak, recent: recent)
    }
}

enum Duration {
    /// "1h 20m", "40m", "0m".
    static func short(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "24:13" or "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let s = Int(max(0, seconds).rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}
