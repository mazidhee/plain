import AppKit
import CoreGraphics

/// Screen Time-lite: how long each app was in front, counted only while you're at the Mac
/// (five quiet minutes stop the clock; sleep stops it too). Stored in app-usage.json, local only.
final class AppUsage {
    struct Segment: Codable, Equatable {
        var bundleID: String
        var name: String
        var start: Date
        var end: Date
    }

    struct Row: Identifiable, Equatable {
        var id: String { bundleID }
        var bundleID: String
        var name: String
        var minutes: Int
    }

    static let idleLimit: TimeInterval = 5 * 60

    private(set) var segments: [Segment]
    private var current: (bundleID: String, name: String, start: Date)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let url: URL
    private var idle = false
    var enabled = true { didSet { if !enabled { close(at: Date()) } else if oldValue == false { openFront() } } }
    var onChange: (() -> Void)?

    init(url: URL = PlainPaths.file("app-usage.json")) {
        self.url = url
        segments = JSONFiles.load([Segment].self, from: url) ?? []
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.enabled, !self.idle else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.switchTo(app, at: Date())
        })
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.close(at: Date()); self?.idle = true
        })
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.idle = false; self?.openFront()
        })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.checkIdle() }
        openFront()
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    static func secondsIdle() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func checkIdle() {
        guard enabled else { return }
        let quiet = Self.secondsIdle()
        if quiet >= Self.idleLimit {
            if !idle { close(at: Date().addingTimeInterval(-quiet)); idle = true }
        } else if idle {
            idle = false
            openFront()
        } else {
            save() // checkpoint the open segment now and then
        }
    }

    private func openFront() {
        guard enabled, !idle else { return }
        switchTo(NSWorkspace.shared.frontmostApplication, at: Date())
    }

    private func switchTo(_ app: NSRunningApplication?, at date: Date) {
        close(at: date)
        guard let id = app?.bundleIdentifier else { return }
        current = (id, app?.localizedName ?? id, date)
    }

    private func close(at date: Date) {
        guard let c = current else { return }
        current = nil
        let end = max(c.start, date)
        if end.timeIntervalSince(c.start) >= 5 {
            segments.append(Segment(bundleID: c.bundleID, name: c.name, start: c.start, end: end))
        }
        save()
    }

    private func save() {
        // Keep five weeks.
        let cutoff = Date().addingTimeInterval(-35 * 86_400)
        segments.removeAll { $0.end < cutoff }
        JSONFiles.save(segments, to: url)
        onChange?()
    }

    func flush() { if let c = current { close(at: Date()); current = (c.bundleID, c.name, Date()) } }

    /// Segments including the one still open.
    func allSegments(now: Date = Date()) -> [Segment] {
        var all = segments
        if let c = current, !idle { all.append(Segment(bundleID: c.bundleID, name: c.name, start: c.start, end: now)) }
        return all
    }

    /// Seconds an app was in front between two times.
    static func seconds(of bundleID: String, in segments: [Segment], from: Date, to: Date) -> TimeInterval {
        segments.filter { $0.bundleID == bundleID }.reduce(0) { sum, s in
            sum + max(0, min(s.end, to).timeIntervalSince(max(s.start, from)))
        }
    }

    /// Minutes per app since a time, biggest first.
    static func totals(_ segments: [Segment], since: Date, until: Date = .distantFuture) -> [Row] {
        var secs: [String: (String, TimeInterval)] = [:]
        for s in segments {
            let t = max(0, min(s.end, until).timeIntervalSince(max(s.start, since)))
            guard t > 0 else { continue }
            secs[s.bundleID, default: (s.name, 0)].1 += t
        }
        return secs.map { Row(bundleID: $0.key, name: $0.value.0, minutes: Int(($0.value.1 / 60).rounded())) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
    }
}
