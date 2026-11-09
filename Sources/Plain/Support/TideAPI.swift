import Foundation
import Security

/// Tide's study data API (Tide › Settings › Tools › Study data API), read-only:
/// `GET /v1/summary?days=N` and `/v1/sessions?from=YYYY-MM-DD`, with the token as a Bearer header.
/// Tide keeps the token encrypted with its own key, so it's pasted into Plain once and kept in
/// Plain's Keychain item.
enum TideAPI {
    struct Summary: Decodable, Equatable {
        struct Range: Decodable, Equatable { var from: String; var to: String; var days: Int }
        struct Now: Decodable, Equatable { var label: String; var since: String; var minutes: Int }
        struct Totals: Decodable, Equatable {
            var today = 0, thisWeek = 0, thisMonth = 0, inRange = 0, sessions = 0, studyDays = 0
            var averagePerStudyDay = 0, streak = 0, longestStreak = 0
        }
        struct Day: Decodable, Equatable, Identifiable {
            var date: String
            var minutes: Int
            var sessions: Int
            var cards: Int
            var answers: Int
            var accuracy: Double?
            var id: String { date }
        }
        struct ActivityRow: Decodable, Equatable, Identifiable { var activity: String; var minutes: Int; var sessions: Int; var id: String { activity } }
        struct NotebookRow: Decodable, Equatable, Identifiable { var notebook: String; var minutes: Int; var id: String { notebook } }
        struct TopicRow: Decodable, Equatable, Identifiable { var label: String; var minutes: Int; var id: String { label } }
        struct Flashcards: Decodable, Equatable { var reviewed = 0, again = 0, hard = 0, good = 0, easy = 0 }
        struct Answers: Decodable, Equatable { var total = 0, right = 0, partly = 0, wrong = 0; var averageScore: Double? }

        var generatedAt: String
        var range: Range
        var now: Now?
        var totals: Totals
        var days: [Day]
        var activities: [ActivityRow]
        var notebooks: [NotebookRow]
        var topics: [TopicRow]
        var hours: [Int]
        var flashcards: Flashcards
        var answers: Answers
    }

    struct Session: Decodable, Equatable, Identifiable {
        var start: Date
        var end: Date
        var minutes: Int
        var activity: String
        var label: String?
        var notebook: String?
        var path: String?
        var id: String { "\(start.timeIntervalSince1970)-\(label ?? "")" }
    }

    struct SessionList: Decodable { var count: Int; var minutes: Int; var sessions: [Session] }

    enum Failure: Error, Equatable, CustomStringConvertible {
        case noToken, notRunning, badToken, other(String)
        var description: String {
            switch self {
            case .noToken: return "Paste the token from Tide › Settings › Tools › Study data API."
            case .notRunning: return "Tide isn't open, or Share my study data is off."
            case .badToken: return "Tide refused the token. Copy it again from Tide › Settings › Tools."
            case .other(let s): return s
            }
        }
    }

    /// Tide's own names for the kinds of studying, in the order the charts colour them.
    static let activities = ["lesson", "reading", "practice", "review", "chat", "exam", "study"]

    static func label(_ activity: String) -> String {
        switch activity {
        case "lesson": return "Lessons"
        case "reading": return "Reading"
        case "practice": return "Practice"
        case "review": return "Review"
        case "chat": return "Chat"
        case "exam": return "Exams"
        default: return "Study"
        }
    }

    /// PLAIN_TIDE_API for tests; else the port in Tide's settings.json.
    static var baseURL: URL {
        if let s = ProcessInfo.processInfo.environment["PLAIN_TIDE_API"], let u = URL(string: s) { return u }
        let settings = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tide/settings.json")
        var port = 47820
        if let data = try? Data(contentsOf: settings),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let api = json["studyApi"] as? [String: Any], let p = api["port"] as? Int, p > 0 { port = p }
        return URL(string: "http://127.0.0.1:\(port)/v1")!
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withMs = ISO8601DateFormatter()
        withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = withMs.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type, token: String? = Keychain.tideToken) async throws -> T {
        guard let token, !token.isEmpty else { throw Failure.noToken }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 5)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw Failure.notRunning }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw Failure.badToken }
        guard status == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Failure.other(msg ?? "Tide answered \(status).")
        }
        do { return try decoder.decode(T.self, from: data) } catch { throw Failure.other("Tide's answer didn't parse: \(error)") }
    }

    static func summary(days: Int, token: String? = Keychain.tideToken) async throws -> Summary {
        try await get("summary", query: [URLQueryItem(name: "days", value: "\(days)")], as: Summary.self, token: token)
    }

    static func sessions(from: Date, token: String? = Keychain.tideToken) async throws -> [Session] {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        return try await get("sessions", query: [URLQueryItem(name: "from", value: day.string(from: from))], as: SessionList.self, token: token).sessions
    }

    /// The day key Tide uses ("2026-11-09") as a local date.
    static func date(_ key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: key)
    }
}

/// Plain's own Keychain items.
enum Keychain {
    static let service = "com.mazidhee.plain"

    static var tideToken: String? {
        get {
            if let t = ProcessInfo.processInfo.environment["PLAIN_TIDE_TOKEN"], !t.isEmpty { return t }
            return read("tide-study-api")
        }
        set { write("tide-study-api", newValue) }
    }

    static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
