import AppKit

let args = CommandLine.arguments

func argument(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if args.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
} else if let dir = argument(after: "--snapshot") {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    Snapshot.run(to: URL(fileURLWithPath: dir))
    exit(0)
} else if let path = argument(after: "--make-icon") {
    AppIcon.write(to: URL(fileURLWithPath: path))
    exit(0)
} else if args.contains("--sky") {
    // The sky the scene draws now, and today's sunrise and sunset here.
    let now = Date(), place = Place.current, sky = Sky.at(now)
    let sun = Solar.sun(at: now, lat: place.lat, lon: place.lon)
    let start = Calendar.current.startOfDay(for: now)
    let t = { (d: Date?) in d?.formatted(date: .omitted, time: .shortened) ?? "-" }
    print("place \(String(format: "%.2f, %.2f", place.lat, place.lon)) (\(TimeZone.current.identifier))")
    print("sun \(String(format: "%.1f", sun.elevation))° · \(sky.period) · sunrise \(t(Solar.nextCrossing(after: start, rising: true))) · sunset \(t(Solar.nextCrossing(after: start, rising: false)))")
    print("moon \(Int(Solar.illumination(sky.moonPhase) * 100))% lit, \(sky.moonPhase < 0.5 ? "waxing" : "waning"), \(sky.moon == nil ? "below the horizon" : "up")")
    exit(0)
} else if args.contains("--tide-check") {
    // Reads Tide's study data API with the saved token (or PLAIN_TIDE_TOKEN) and prints the headline numbers.
    let done = DispatchSemaphore(value: 0)
    var ok = false
    Task {
        do {
            let s = try await TideAPI.summary(days: 30)
            let sessions = try await TideAPI.sessions(from: Date().addingTimeInterval(-7 * 86_400))
            print("today \(s.totals.today)m · week \(s.totals.thisWeek)m · month \(s.totals.thisMonth)m · streak \(s.totals.streak) (longest \(s.totals.longestStreak))")
            print("kinds: \(s.activities.map { "\($0.activity) \($0.minutes)m" }.joined(separator: ", "))")
            print("notebooks: \(s.notebooks.prefix(5).map { "\($0.notebook) \($0.minutes)m" }.joined(separator: ", "))")
            print("days \(s.days.count) · topics \(s.topics.count) · cards \(s.flashcards.reviewed) · answers \(s.answers.total) · sessions this week \(sessions.count)")
            if let now = s.now { print("now: \(now.label) (\(now.minutes)m)") }
            ok = true
        } catch {
            print("Tide API: \(error)")
        }
        done.signal()
    }
    done.wait()
    exit(ok ? 0 : 1)
} else if args.contains("--geometry") {
    _ = NSApplication.shared
    print(NotchGeometry.describe())
    exit(0)
} else if args.contains("--radio-check") {
    _ = NSApplication.shared
    var ok = true
    let only = Set(args.drop { $0 != "--radio-check" }.dropFirst())
    for station in Station.all where only.isEmpty || only.contains(station.id) {
        let result = RadioPlayer.check(station)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        print("\(station.name): \(result) — \(station.urls[0].absoluteString)")
        if result != "playing" { ok = false }
    }
    exit(ok ? 0 : 1)
} else if args.contains("--things-check") {
    _ = NSApplication.shared
    exit(ThingsCheck.run() ? 0 : 1)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
