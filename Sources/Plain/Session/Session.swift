import Foundation

enum Category: String, Codable, CaseIterable, Identifiable {
    case work, study, exam, reading, chilling

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: return "Work"
        case .study: return "Study"
        case .exam: return "Exam"
        case .reading: return "Reading"
        case .chilling: return "Chilling"
        }
    }

    var emoji: String {
        switch self {
        case .work: return "💻"
        case .study: return "📖"
        case .exam: return "📝"
        case .reading: return "📚"
        case .chilling: return "🎧"
        }
    }

    /// What Wren does during a session of this kind.
    var activity: Activity {
        switch self {
        case .work: return .work
        case .study, .reading: return .study
        case .exam: return .exam
        case .chilling: return .chilling
        }
    }

    /// The tag used in Things.
    var tag: String { rawValue }
}

/// What the user asked for when they pressed Start.
struct SessionPlan: Codable, Equatable {
    var title: String
    var category: Category
    var minutes: Int
    /// A Things to-do this session is for, if any.
    var taskID: String? = nil
    /// Minutes already tracked on that to-do when the session started.
    var trackedBefore: Int = 0
    /// A count-up tracker: no length, no chime, no break. Ends when stopped.
    var openEnded = false
    /// Kept in Plain's stats only, never sent to Things (e.g. time Tide already logs).
    var localOnly = false
    /// Ends by itself when Tide has been out of focus for a while.
    var tiedToTide = false
    /// "Lock in": focus with no to-do and no title. Stays in Plain unless a to-do is attached.
    var lockIn = false

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return lockIn ? "Lock in" : "\(category.label) session" }
        return t
    }
}

/// A finished (or cut short) focus block.
struct CompletedSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var category: Category
    var start: Date
    var end: Date
    /// Minutes actually focused (pauses excluded).
    var minutes: Int
    var plannedMinutes: Int
    var taskID: String? = nil
    var endedEarly: Bool = false
    var canceled: Bool = false
    /// A count-up tracker rather than a timed block.
    var openEnded: Bool? = nil
    /// Not sent to Things.
    var localOnly: Bool? = nil
    /// Started as "Lock in" (no to-do picked at the start).
    var lockIn: Bool? = nil

    /// "Work · Lock in" or the title.
    var label: String { lockIn == true && taskID == nil ? "\(category.label) · Lock in" : title }
}

/// The timer's rules, kept free of UI and clocks so they can be tested.
struct SessionMachine {
    enum Phase: String, Codable { case idle, focus, breakTime, summary }

    enum Event: Equatable {
        case focusEnded(CompletedSession)
        case breakEnded
    }

    private(set) var phase: Phase = .idle
    private(set) var plan: SessionPlan?
    private(set) var startedAt: Date?
    /// Target length of the current phase, in seconds.
    private(set) var target: TimeInterval = 0
    /// Time run before the latest resume.
    private(set) var accumulated: TimeInterval = 0
    /// Nil while paused.
    private(set) var resumedAt: Date?
    private(set) var lastCompleted: CompletedSession?
    /// Focus blocks finished in a row, for the long break.
    private(set) var streakCount = 0
    /// Real seconds per "minute"; 60 except in tests.
    var secondsPerMinute: Double = 60

    var isRunning: Bool { phase == .focus || phase == .breakTime }
    var isPaused: Bool { isRunning && resumedAt == nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (resumedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func remaining(at now: Date) -> TimeInterval { target.isInfinite ? .infinity : max(0, target - elapsed(at: now)) }

    func progress(at now: Date) -> Double { target > 0 && target.isFinite ? min(1, elapsed(at: now) / target) : 0 }

    /// Whole minutes focused so far (rounded to the nearest minute).
    func focusedMinutes(at now: Date) -> Int { Int((elapsed(at: now) / secondsPerMinute).rounded()) }

    mutating func start(_ plan: SessionPlan, at now: Date) {
        self.plan = plan
        phase = .focus
        startedAt = now
        target = plan.openEnded ? .infinity : Double(max(1, plan.minutes)) * secondsPerMinute
        accumulated = 0
        resumedAt = now
        lastCompleted = nil
    }

    var isOpenEnded: Bool { phase == .focus && plan?.openEnded == true }

    mutating func pause(at now: Date) {
        guard isRunning, let r = resumedAt else { return }
        accumulated += max(0, now.timeIntervalSince(r))
        resumedAt = nil
    }

    mutating func resume(at now: Date) {
        guard isRunning, resumedAt == nil else { return }
        resumedAt = now
    }

    mutating func extend(minutes: Int = 5) {
        guard isRunning else { return }
        target += Double(minutes) * secondsPerMinute
        if phase == .focus { plan?.minutes += minutes }
    }

    /// Ends focus now. Returns the record to save and log (nil if less than a minute, or not focusing).
    @discardableResult
    mutating func finish(at now: Date, early: Bool = true) -> CompletedSession? {
        guard phase == .focus, let plan, let startedAt else { return nil }
        let minutes = focusedMinutes(at: now)
        var record = CompletedSession(title: plan.displayTitle, category: plan.category, start: startedAt, end: now,
                                      minutes: minutes, plannedMinutes: plan.openEnded ? minutes : plan.minutes, taskID: plan.taskID,
                                      endedEarly: !plan.openEnded && early && remaining(at: now) > 0)
        if plan.openEnded { record.openEnded = true }
        if plan.localOnly { record.localOnly = true }
        if plan.lockIn { record.lockIn = true }
        if !record.endedEarly && !plan.openEnded { streakCount += 1 }
        resumedAt = nil
        phase = .summary
        lastCompleted = record
        return minutes >= 1 ? record : nil
    }

    /// Stops without a summary. Partial time of a minute or more is still returned, so it gets logged.
    @discardableResult
    mutating func cancel(at now: Date) -> CompletedSession? {
        var record: CompletedSession?
        if phase == .focus, let plan, let startedAt {
            let minutes = focusedMinutes(at: now)
            if minutes >= 1 {
                record = CompletedSession(title: plan.displayTitle, category: plan.category, start: startedAt, end: now,
                                          minutes: minutes, plannedMinutes: plan.minutes, taskID: plan.taskID,
                                          endedEarly: true, canceled: true)
                if plan.openEnded { record?.openEnded = true }
                if plan.localOnly { record?.localOnly = true }
                if plan.lockIn { record?.lockIn = true }
            }
        }
        reset()
        return record
    }

    /// Starts a break; long every fourth block.
    mutating func startBreak(short: Int = 5, long: Int = 15, at now: Date) -> Int {
        let minutes = streakCount > 0 && streakCount % 4 == 0 ? long : short
        phase = .breakTime
        startedAt = now
        target = Double(minutes) * secondsPerMinute
        accumulated = 0
        resumedAt = now
        return minutes
    }

    /// Swaps in updated details (title, tracked total) without touching the clock.
    mutating func replacePlan(_ p: SessionPlan) {
        guard plan != nil else { return }
        plan = p
    }

    mutating func dismissSummary() {
        guard phase == .summary else { return }
        reset()
    }

    private mutating func reset() {
        phase = .idle
        plan = nil
        startedAt = nil
        target = 0
        accumulated = 0
        resumedAt = nil
    }

    /// Advances the clock; reports when a phase runs out.
    mutating func tick(at now: Date) -> Event? {
        guard isRunning, resumedAt != nil, !target.isInfinite, remaining(at: now) <= 0 else { return nil }
        if phase == .focus {
            // Count the full target, not the overshoot between ticks.
            let end = (resumedAt ?? now).addingTimeInterval(target - accumulated)
            if let record = finish(at: end, early: false) { return .focusEnded(record) }
            return nil
        }
        reset()
        return .breakEnded
    }
}
