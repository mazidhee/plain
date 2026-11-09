import Foundation

/// A to-do as Things 4's API describes it.
struct ThingsTask: Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var trackedMinutes: Int
    var context: String?
    var list: String?
    var notes: String = ""
    var area: String?
    var tags: [String] = []

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, let title = json["title"] as? String else { return nil }
        if let type = json["type"] as? String, type == "heading" { return nil }
        self.id = id
        self.title = title
        trackedMinutes = (json["tracked_minutes"] as? Int) ?? (json["tracked_minutes"] as? Double).map { Int($0) } ?? 0
        context = (json["project"] as? [String: Any])?["title"] as? String ?? (json["area"] as? [String: Any])?["title"] as? String
        list = json["list"] as? String
        notes = String((json["notes"] as? String ?? "").prefix(400))
        area = (json["area"] as? [String: Any])?["title"] as? String
        tags = json["tags"] as? [String] ?? []
    }

    init(id: String, title: String, trackedMinutes: Int = 0, context: String? = nil) {
        self.id = id; self.title = title; self.trackedMinutes = trackedMinutes; self.context = context
    }
}

enum ThingsError: Error, Equatable, CustomStringConvertible {
    case notConfigured
    case unreachable(String)
    case http(Int, String)

    var description: String {
        switch self {
        case .notConfigured: return "Things 4 API isn't set up (no api.json)."
        case .unreachable(let m): return "Things 4 isn't reachable: \(m)"
        case .http(let code, let m): return "Things 4 said \(code): \(m)"
        }
    }

    /// Worth retrying later (Things closed, asleep, busy).
    var isTransient: Bool {
        switch self {
        case .notConfigured, .unreachable: return true
        case .http(let code, _): return code >= 500
        }
    }
}

/// Talks to Things 4's local HTTP API. Reads the port and token from its api.json (never writes it).
final class ThingsClient {
    struct Config: Equatable {
        var baseURL: URL
        var token: String
    }

    /// PLAIN_THINGS_CONFIG points at a scratch instance's api.json in tests.
    static var configOverride: URL?

    static var configURL: URL {
        if let configOverride { return configOverride }
        if let p = ProcessInfo.processInfo.environment["PLAIN_THINGS_CONFIG"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Things4/api.json")
    }

    static func loadConfig(from url: URL = configURL) -> Config? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else { return nil }
        let port = (json["port"] as? Int) ?? 7474
        guard let base = URL(string: "http://127.0.0.1:\(port)/v1") else { return nil }
        return Config(baseURL: base, token: token)
    }

    private let session: URLSession

    init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 10
        session = URLSession(configuration: c)
    }

    @discardableResult
    func request(_ method: String, _ path: String, query: [String: String] = [:], body: Any? = nil) async throws -> Any? {
        guard let config = Self.loadConfig() else { throw ThingsError.notConfigured }
        var comps = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue(ThingsPayload.source, forHTTPHeaderField: "X-Things-Source")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw ThingsError.unreachable(error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard (200..<300).contains(status) else {
            throw ThingsError.http(status, ((json as? [String: Any])?["error"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return json
    }

    // MARK: Reading

    func today() async throws -> [ThingsTask] {
        let list = try await request("GET", "lists/today") as? [[String: Any]] ?? []
        return list
            .filter { ($0["type"] as? String ?? "to-do") == "to-do" && ($0["status"] as? String ?? "open") == "open" }
            .compactMap(ThingsTask.init)
    }

    func search(_ q: String) async throws -> [ThingsTask] {
        let list = try await request("GET", "tasks", query: ["q": q, "status": "open", "limit": "20"]) as? [[String: Any]] ?? []
        return list.filter { ($0["type"] as? String ?? "to-do") == "to-do" }.compactMap(ThingsTask.init)
    }

    /// Open to-dos in an area or project, by title or id.
    func list(_ name: String) async throws -> [ThingsTask] {
        let list = try await request("GET", "lists/\(name.replacingOccurrences(of: "/", with: " "))") as? [[String: Any]] ?? []
        return list
            .filter { ($0["type"] as? String ?? "to-do") == "to-do" && ($0["status"] as? String ?? "open") == "open" }
            .compactMap(ThingsTask.init)
    }

    func areaTitles() async throws -> [String] {
        let list = try await request("GET", "areas") as? [[String: Any]] ?? []
        return list.compactMap { $0["title"] as? String }
    }

    /// Every open to-do, for searching locally as you type.
    func allOpen() async throws -> [ThingsTask] {
        let list = try await request("GET", "tasks", query: ["status": "open", "limit": "3000"]) as? [[String: Any]] ?? []
        return list.filter { ($0["type"] as? String ?? "to-do") == "to-do" }.compactMap(ThingsTask.init)
    }

    func task(_ id: String) async throws -> ThingsTask? {
        (try await request("GET", "tasks/\(id)") as? [String: Any]).flatMap(ThingsTask.init)
    }

    func trackedToday() async throws -> Int {
        let json = try await request("GET", "time", query: ["since": "today"]) as? [String: Any]
        return json?["total_minutes"] as? Int ?? 0
    }

    // MARK: Writing

    func ensureArea() async throws -> String? {
        let json = try await request("POST", "areas", body: ["title": ThingsPayload.areaName]) as? [String: Any]
        return json?["id"] as? String
    }

    func create(_ body: [String: Any]) async throws -> String {
        let created = try await request("POST", "tasks", body: body)
        let first = (created as? [[String: Any]])?.first ?? (created as? [String: Any])
        guard let id = first?["id"] as? String else { throw ThingsError.http(500, "No id in the reply") }
        return id
    }

    enum TimeResult: Equatable { case logged(Int), endpointMissing }

    /// Adds a time entry. Returns `.endpointMissing` on an older Things 4 without the time route.
    func addTime(_ id: String, _ body: [String: Any]) async throws -> TimeResult {
        do {
            let json = try await request("POST", "tasks/\(id)/time", body: body) as? [String: Any]
            let task = json?["task"] as? [String: Any]
            return .logged(task?["tracked_minutes"] as? Int ?? 0)
        } catch ThingsError.http(404, let message) where message.hasPrefix("No endpoint") {
            return .endpointMissing
        }
    }

    func appendNotes(_ id: String, _ body: [String: Any]) async throws {
        try await request("PATCH", "tasks/\(id)", body: body)
    }

    func complete(_ id: String) async throws {
        try await request("POST", "tasks/\(id)/complete")
    }
}
