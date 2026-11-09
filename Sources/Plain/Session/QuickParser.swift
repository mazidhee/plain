import Foundation

/// Turns "Reading system design docs 40 min study" into a title, minutes and a category.
enum QuickParser {
    struct Result: Equatable {
        var title: String
        var minutes: Int?
        var category: Category?
    }

    /// Words that name a category on their own ("... study", "exam: ...").
    static let categoryWords: [String: Category] = [
        "work": .work, "working": .work, "coding": .work, "code": .work, "dev": .work,
        "study": .study, "studying": .study, "revise": .study, "revising": .study, "revision": .study, "flashcards": .study,
        "exam": .exam, "test": .exam, "practice": .exam, "quiz": .exam, "mock": .exam,
        "read": .reading, "reading": .reading,
        "chill": .chilling, "chilling": .chilling, "relax": .chilling, "break": .chilling,
    ]

    /// Category words trusted at the end of a sentence ("... 40 min study"). Others ("test",
    /// "code") are too likely to be part of the title, so they need a "#" or "exam:" form.
    static let trailingWords: Set<String> = ["work", "study", "exam", "reading", "read", "chill", "chilling", "flashcards"]

    /// Leading verbs that are dropped from the title ("Reading x" → "X").
    static let leadingVerbs: [String: Category] = [
        "reading": .reading, "read": .reading, "studying": .study, "study": .study, "revising": .study, "reviewing": .study,
        "working on": .work, "work on": .work, "coding": .work, "writing": .work, "building": .work, "fixing": .work,
        "practising": .exam, "practicing": .exam, "chilling": .chilling,
    ]

    static func parse(_ text: String) -> Result {
        var s = " " + text.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        var minutes: Int?
        var category: Category?

        // Durations: "1h30", "1h 15m", "1.5h", "90 min", "40m", "for 40 minutes", "1 hour".
        let patterns: [(String, (NSTextCheckingResult, NSString) -> Int?)] = [
            (#"(?i)\s(?:for\s+)?(\d+)\s*h(?:ours?|rs?)?\s*(\d+)\s*m(?:in(?:ute)?s?)?(?=\s)"#, { m, ns in
                Int(ns.substring(with: m.range(at: 1))).flatMap { h in Int(ns.substring(with: m.range(at: 2))).map { h * 60 + $0 } } }),
            (#"(?i)\s(?:for\s+)?(\d+)h(\d{1,2})(?=\s)"#, { m, ns in
                Int(ns.substring(with: m.range(at: 1))).flatMap { h in Int(ns.substring(with: m.range(at: 2))).map { h * 60 + $0 } } }),
            (#"(?i)\s(?:for\s+)?(\d+(?:[.,]\d+)?)\s*(?:h|hr|hrs|hour|hours)(?=\s)"#, { m, ns in
                Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")).map { Int(($0 * 60).rounded()) } }),
            (#"(?i)\s(?:for\s+)?(\d+)\s*(?:m|min|mins|minute|minutes|’|')(?=\s)"#, { m, ns in Int(ns.substring(with: m.range(at: 1))) }),
            (#"(?i)\s(?:for\s+)?(\d{2,3})(?=\s*$)"#, { m, ns in Int(ns.substring(with: m.range(at: 1))) }),
        ]
        for (pattern, value) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), let v = value(m, ns), v > 0, v <= 600 {
                minutes = v
                s = ns.replacingCharacters(in: m.range, with: " ")
                break
            }
        }

        // An explicit category word, preferring a trailing one or a "tag:" prefix.
        var words = s.split(separator: " ").map(String.init)
        if let last = words.last, let c = categoryWords[clean(last)], trailingWords.contains(clean(last)) || last.hasPrefix("#") {
            category = c
            if words.count > 1 { words.removeLast() }
        } else if let first = words.first, first.hasSuffix(":"), let c = categoryWords[clean(first)] {
            category = c
            words.removeFirst()
        } else if let i = words.firstIndex(where: { $0.hasPrefix("#") && categoryWords[clean($0)] != nil }) {
            category = categoryWords[clean(words[i])]
            words.remove(at: i)
        }
        // Trailing filler like "in", "for".
        while let last = words.last, ["for", "in", "-", "—", "–", "·"].contains(last.lowercased()) { words.removeLast() }

        // Leading verb: sets the category if none given, and is dropped from the title.
        var title = words.joined(separator: " ")
        let lower = title.lowercased()
        for (verb, c) in leadingVerbs.sorted(by: { $0.key.count > $1.key.count }) where lower.hasPrefix(verb + " ") {
            let rest = String(title.dropFirst(verb.count + 1))
            if rest.count >= 3 {
                title = rest
                if category == nil { category = c }
            }
            break
        }
        title = title.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",.-—:")))
        if let first = title.first, first.isLowercase { title = first.uppercased() + title.dropFirst() }
        return Result(title: title, minutes: minutes, category: category)
    }

    private static func clean(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#:,.!"))
    }
}
