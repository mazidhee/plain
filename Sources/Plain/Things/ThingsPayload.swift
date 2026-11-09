import Foundation

/// Pure builders for what Plain sends to Things 4, so they can be tested without a server.
enum ThingsPayload {
    static let areaName = "Focus Log"
    static let source = "Plain"

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM yyyy"
        return f.string(from: date)
    }

    /// "📖 System design docs — 40 min"
    static func logTitle(_ s: CompletedSession) -> String {
        "\(s.category.emoji) \(s.title) — \(s.minutes) min"
    }

    static func notes(_ s: CompletedSession) -> String {
        var lines = [
            "Focus session (\(s.category.label))",
            "Started: \(day(s.start)) \(clock(s.start))",
            "Ended: \(day(s.end)) \(clock(s.end))",
            "Focused: \(s.minutes) min of \(s.plannedMinutes) planned",
        ]
        if s.canceled { lines.append("Stopped early.") }
        return lines.joined(separator: "\n")
    }

    static func tags(_ s: CompletedSession) -> [String] { ["focus", s.category.tag] }

    /// POST /v1/tasks for a free-text session.
    static func createBody(_ s: CompletedSession, areaID: String?) -> [String: Any] {
        var body: [String: Any] = ["title": logTitle(s), "notes": notes(s), "tags": tags(s)]
        if let areaID { body["list-id"] = areaID } else { body["list"] = areaName }
        return body
    }

    /// POST /v1/tasks/{id}/time
    static func timeBody(_ s: CompletedSession) -> [String: Any] {
        var body: [String: Any] = ["minutes": s.minutes, "start": iso.string(from: s.start), "end": iso.string(from: s.end)]
        body["note"] = s.canceled ? "\(s.category.label) focus (stopped early)" : "\(s.category.label) focus"
        return body
    }

    /// PATCH /v1/tasks/{id} when the time endpoint is missing: append a line to the notes.
    static func appendNotesBody(_ s: CompletedSession) -> [String: Any] {
        ["append-notes": "⏱ \(s.minutes) min \(s.category.label.lowercased()) focus · \(day(s.start)) \(clock(s.start))–\(clock(s.end)) (Plain)"]
    }
}
