import AppKit
import Combine
import UserNotifications

/// Something the island asks without being asked.
enum IslandPrompt: Equatable {
    case tide
    case editor(appName: String)
}

enum ThingsStatus: Equatable { case unknown, connected, offline(String) }

/// The app's state: the timer, the draft session, Things to-dos and stats. Views observe it.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    var settings = Settings()
    let sound = SoundController()
    let store: SessionStore
    let client = ThingsClient()
    let logger: ThingsLogger

    @Published private(set) var machine = SessionMachine()
    @Published private(set) var now = Date()

    // Draft for the next session.
    @Published var draftTitle = ""
    @Published var draftCategory: Category = .work
    @Published var draftMinutes = 25
    @Published var selectedTask: ThingsTask?
    /// A time block instead of a length: from/to (from in the future schedules it).
    @Published var draftUseRange = false
    /// The next session counts up instead of down.
    @Published var draftCountUp = false
    @Published var draftFrom = Date()
    @Published var draftTo = Date().addingTimeInterval(2 * 3600)
    @Published private(set) var scheduled: ScheduledBlock?

    // Things.
    @Published private(set) var todayTasks: [ThingsTask] = []
    @Published private(set) var searchResults: [ThingsTask] = []
    /// Open to-dos in the Things area linked to the draft's category (Settings › Things 4).
    @Published private(set) var areaTasks: [ThingsTask] = []
    @Published private(set) var areaTitles: [String] = []
    /// Show today's list even when the category has an area.
    @Published var pickerShowsToday = false
    /// The app in front, for the Auto scene.
    @Published var frontBundleID: String? {
        didSet { frontChanged(from: oldValue) }
    }
    /// What the Tide prompt said you're doing (study, exam…). Wren acts it out; Tide keeps the time.
    @Published var tideMood: Activity?
    /// When Tide last went to the background, for ending a Tide-tied tracker.
    private(set) var leftTideAt: Date?
    /// Tide's own study log, read-only.
    @Published private(set) var tide = TideLog.Summary()
    let appUsage = AppUsage()
    private var lastTideRead = Date.distantPast
    /// How long Tide may be out of focus before a Tide-tied tracker stops (end time = when you left).
    var tideAwayLimit: TimeInterval = 5 * 60
    /// Called when a session starts from outside (a plain:// link), to drop the popover down.
    var onExternalStart: (() -> Void)?
    @Published private(set) var thingsStatus: ThingsStatus = .unknown
    @Published private(set) var pendingLogs = 0

    // After a session.
    @Published private(set) var summaryNote: String?
    @Published private(set) var summaryTaskID: String?
    @Published private(set) var summaryTracked: Int?
    @Published private(set) var markedDone = false

    @Published var prompt: IslandPrompt?
    @Published private(set) var stats: Stats
    @Published private(set) var breakMinutes = 0

    private var timer: Timer?
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastPromptAt: Date?

    init() {
        store = SessionStore()
        logger = ThingsLogger(client: client)
        stats = Stats.compute(store.sessions, now: Date())
        if let away = ProcessInfo.processInfo.environment["PLAIN_TIDE_AWAY_SECONDS"].flatMap(Double.init), away > 0 { tideAwayLimit = away }
        if let scale = ProcessInfo.processInfo.environment["PLAIN_SECONDS_PER_MINUTE"].flatMap(Double.init), scale > 0 {
            machine.secondsPerMinute = scale
        }
        draftMinutes = settings.defaultMinutes
        scheduled = UserDefaults.standard.data(forKey: "scheduledBlock").flatMap { try? JSONFiles.decoder.decode(ScheduledBlock.self, from: $0) }
        $draftCategory.removeDuplicates().sink { [weak self] c in
            DispatchQueue.main.async { self?.refreshAreaTasks(for: c) }
        }.store(in: &cancellables)
        pendingLogs = logger.queue.count
        logger.onChange = { [weak self] in
            DispatchQueue.main.async { self?.pendingLogs = self?.logger.queue.count ?? 0 }
        }
        // Re-publish nested objects so views update.
        settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        sound.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    func startTicking() {
        appUsage.enabled = settings.appTracking
        appUsage.start()
        settings.$appTracking.dropFirst().sink { [weak self] on in self?.appUsage.enabled = on }.store(in: &cancellables)
        refreshTide()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        logger.startRetrying()
    }

    // MARK: Derived

    var phase: SessionMachine.Phase { machine.phase }
    var isRunning: Bool { machine.isRunning }
    var isPaused: Bool { machine.isPaused }
    var plan: SessionPlan? { machine.plan }
    /// Time left (0 for a count-up tracker, which has no end).
    var remaining: TimeInterval { let r = machine.remaining(at: now); return r.isFinite ? r : 0 }
    var elapsed: TimeInterval { machine.elapsed(at: now) }
    var isTracker: Bool { machine.isOpenEnded }
    /// The clock to show: time left, or time so far for a tracker.
    var clockText: String { Duration.clock(isTracker ? elapsed : remaining) }
    var progress: Double { machine.progress(at: now) }
    var lastCompleted: CompletedSession? { machine.lastCompleted }

    /// Minutes on the Things to-do including this session so far.
    var trackedIncludingNow: Int? {
        guard let plan, plan.taskID != nil, phase == .focus else { return nil }
        return plan.trackedBefore + machine.focusedMinutes(at: now)
    }

    var activity: Activity {
        switch machine.phase {
        case .focus:
            if machine.isPaused { return .idle }
            if machine.plan?.lockIn == true && machine.plan?.taskID == nil { return .lockIn }
            return machine.plan?.category.activity ?? .work
        case .breakTime: return .breakTime
        case .summary: return .breakTime
        case .idle: return tideMood ?? .idle
        }
    }

    // MARK: App time

    /// Snapshot data for previews; nil means use the live tracker.
    var previewSegments: [AppUsage.Segment]?

    func appTotals(week: Bool) -> [AppUsage.Row] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let since = week ? (cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)) : cal.startOfDay(for: now)
        return AppUsage.totals(previewSegments ?? appUsage.allSegments(now: now), since: since, until: now)
    }

    // MARK: Tide

    func refreshTide() {
        guard !isPreview else { return }
        tide = TideLog.read()
        lastTideRead = Date()
    }

    enum TideChoice: String, CaseIterable { case studying, exam, flashcards, chilling
        var label: String {
            switch self {
            case .studying: return "Studying"
            case .exam: return "Exam practice"
            case .flashcards: return "Flashcards"
            case .chilling: return "Just chilling"
            }
        }
    }

    /// The Tide prompt never starts a pomodoro: study modes only set Wren's mood (Tide logs the
    /// time itself); chilling starts a count-up tracker that ends when you leave Tide.
    func tideChoice(_ choice: TideChoice, note: String = "") {
        prompt = nil
        switch choice {
        case .studying, .flashcards: tideMood = .study
        case .exam: tideMood = .exam
        case .chilling:
            tideMood = nil
            let title = note.trimmingCharacters(in: .whitespaces).isEmpty ? "Chilling in Tide" : note
            start(SessionPlan(title: title, category: .chilling, minutes: 0, openEnded: true, localOnly: true, tiedToTide: true), sound: false)
        }
        leftTideAt = nil
        objectWillChange.send()
    }

    /// Starts an open-ended tracker (count-up): no length, no chime, no break.
    func startTracker(title: String, category: Category) {
        start(SessionPlan(title: title, category: category, minutes: 0, openEnded: true), sound: false)
    }

    private func frontChanged(from old: String?) {
        let tideID = AppWatcher.tideBundleID
        if frontBundleID == tideID {
            leftTideAt = nil
            if Date().timeIntervalSince(lastTideRead) > 30 { refreshTide() }
        } else if old == tideID, leftTideAt == nil {
            leftTideAt = Date()
        }
    }

    /// Tide has been in the background long enough: end the Tide-tied tracker at the moment you left.
    private func checkTideAway() {
        guard let left = leftTideAt, now.timeIntervalSince(left) > tideAwayLimit else { return }
        leftTideAt = nil
        tideMood = nil
        if machine.phase == .focus, machine.plan?.tiedToTide == true {
            let done = machine.finish(at: max(left, machine.startedAt ?? left), early: false)
            sessionEnded(done, natural: false)
        }
    }

    // MARK: Session control

    func startFromDraft() {
        if draftUseRange { scheduleFromDraft(); return }
        let parsed = QuickParser.parse(draftTitle)
        var title = selectedTask?.title ?? (parsed.title.isEmpty ? draftTitle : parsed.title)
        if title.isEmpty { title = "" }
        let category = selectedTask == nil ? (parsed.category ?? draftCategory) : draftCategory
        let minutes = selectedTask == nil ? (parsed.minutes ?? draftMinutes) : draftMinutes
        start(SessionPlan(title: title, category: category, minutes: minutes,
                          taskID: selectedTask?.id, trackedBefore: selectedTask?.trackedMinutes ?? 0))
    }

    /// The home screen's one primary action: start on the picked to-do, or Lock in with none.
    func startPrimary() {
        let task = selectedTask
        if draftUseRange { scheduleFromDraft(); return }
        start(SessionPlan(title: task?.title ?? "", category: draftCategory, minutes: draftMinutes, taskID: task?.id,
                          trackedBefore: task?.trackedMinutes ?? 0, openEnded: draftCountUp, lockIn: task == nil))
    }

    /// Attaches a to-do to the running session; its time lands there at the end.
    func attach(_ task: ThingsTask) {
        guard var p = machine.plan else { return }
        p.taskID = task.id
        p.title = task.title
        p.trackedBefore = task.trackedMinutes
        machine.replacePlan(p)
        objectWillChange.send()
    }

    /// Runs the same kind of session again from the summary.
    func again() {
        guard let last = machine.lastCompleted else { return }
        start(SessionPlan(title: last.lockIn == true && last.taskID == nil ? "" : last.title, category: last.category,
                          minutes: last.openEnded == true ? draftMinutes : last.plannedMinutes, taskID: last.taskID,
                          openEnded: last.openEnded == true, lockIn: last.lockIn == true))
    }

    /// The draft's time block: starts now if `from` has passed, otherwise waits for it.
    func scheduleFromDraft() {
        let parsed = QuickParser.parse(draftTitle)
        let title = selectedTask?.title ?? parsed.title
        let category = selectedTask == nil ? (parsed.category ?? draftCategory) : draftCategory
        let (from, to) = ScheduledBlock.resolve(from: draftFrom, to: draftTo, now: Date())
        var block = ScheduledBlock(start: from, end: to, title: title, category: category,
                                   taskID: selectedTask?.id, trackedBefore: selectedTask?.trackedMinutes ?? 0)
        block.lockIn = selectedTask == nil && title.isEmpty
        draftUseRange = false
        if from <= Date().addingTimeInterval(30) {
            start(block.plan(now: Date()))
        } else {
            setScheduled(block)
            draftTitle = ""
            selectedTask = nil
        }
    }

    func setScheduled(_ block: ScheduledBlock?) {
        scheduled = block
        if let block, let data = try? JSONFiles.encoder.encode(block) {
            UserDefaults.standard.set(data, forKey: "scheduledBlock")
        } else {
            UserDefaults.standard.removeObject(forKey: "scheduledBlock")
        }
    }

    /// Starts from typed text: "Reading system design docs 40 min study".
    func quickStart(_ text: String, task: ThingsTask? = nil) {
        let parsed = QuickParser.parse(text)
        let title = task?.title ?? parsed.title
        start(SessionPlan(title: title, category: parsed.category ?? draftCategory, minutes: parsed.minutes ?? draftMinutes,
                          taskID: task?.id, trackedBefore: task?.trackedMinutes ?? 0))
    }

    func start(_ plan: SessionPlan, sound playSound: Bool = true) {
        if machine.phase == .focus, let partial = machine.cancel(at: Date()) { record(partial) }
        machine.dismissSummary()
        if machine.phase == .breakTime { _ = machine.cancel(at: Date()) }
        now = Date()
        machine.start(plan, at: now)
        prompt = nil
        summaryNote = nil
        summaryTaskID = nil
        summaryTracked = nil
        markedDone = false
        draftTitle = ""
        selectedTask = nil
        if settings.autoSound && playSound { sound.fadeIn() }
        if !plan.tiedToTide { tideMood = nil }
        requestNotificationPermission()
        objectWillChange.send()
    }

    func togglePause() { isPaused ? resume() : pause() }

    func pause() {
        machine.pause(at: Date())
        sound.fadeOut(seconds: 1.5)
        now = Date()
    }

    func resume() {
        machine.resume(at: Date())
        if settings.autoSound { sound.fadeIn(seconds: 2) }
        now = Date()
    }

    func extend() {
        machine.extend(minutes: 5)
        now = Date()
    }

    func finishEarly() {
        let record = machine.finish(at: Date(), early: true)
        sessionEnded(record, natural: false)
    }

    func cancel() {
        let partial = machine.cancel(at: Date())
        sound.fadeOut(seconds: 1.2)
        if let partial { record(partial) }
        now = Date()
    }

    func startBreak() {
        breakMinutes = machine.startBreak(short: settings.shortBreak, long: settings.longBreak, at: Date())
        now = Date()
    }

    func dismissSummary() {
        machine.dismissSummary()
        now = Date()
    }

    func markDoneInThings() {
        guard let id = summaryTaskID else { return }
        Task {
            do {
                try await client.complete(id)
                await MainActor.run { self.markedDone = true; self.refreshTasks() }
            } catch {
                await MainActor.run { self.summaryNote = "Couldn't mark it done: \((error as? ThingsError)?.description ?? "\(error)")" }
            }
        }
    }

    private func tick() {
        now = Date()
        checkTideAway()
        if now.timeIntervalSince(lastTideRead) > 60 { refreshTide() }
        if let block = scheduled {
            if now >= block.end { setScheduled(nil) }
            else if now >= block.start && (machine.phase == .idle || machine.phase == .summary) {
                setScheduled(nil)
                start(block.plan(now: now))
                notify(title: "Time block started", body: "\(block.category.emoji) \(block.plan(now: now).displayTitle) until \(block.end.formatted(date: .omitted, time: .shortened))")
                onExternalStart?()
            }
        }
        guard let event = machine.tick(at: now) else { return }
        switch event {
        case .focusEnded(let done):
            sessionEnded(done, natural: true)
        case .breakEnded:
            if settings.chimeEnabled { sound.chime() }
            notify(title: "Break's over", body: "Ready for another round?")
        }
    }

    private func sessionEnded(_ done: CompletedSession?, natural: Bool) {
        let tracker = done?.openEnded == true || machine.lastCompleted?.openEnded == true
        sound.fadeOut(seconds: natural ? 4 : 1.5)
        // A count-up tracker ends quietly: no chime, no break.
        if settings.chimeEnabled && !tracker { sound.chime() }
        now = Date()
        guard let done else {
            summaryNote = "Under a minute, so nothing was logged."
            return
        }
        if !tracker {
            notify(title: natural ? "Session done · \(done.minutes) min" : "Finished early · \(done.minutes) min",
                   body: "\(done.category.emoji) \(done.title)")
        }
        record(done)
        if natural && settings.breaksEnabled && !tracker { startBreak() }
    }

    /// Study that happened mostly in Tide belongs to Tide's log, so it isn't sent to Things again.
    func tideOwns(_ s: CompletedSession) -> Bool {
        guard s.taskID == nil, [.study, .exam, .reading].contains(s.category) else { return false }
        let total = s.end.timeIntervalSince(s.start)
        guard total > 0 else { return false }
        let inTide = AppUsage.seconds(of: AppWatcher.tideBundleID, in: appUsage.allSegments(), from: s.start, to: s.end)
        return inTide / total > 0.5
    }

    /// Saves a finished block locally and sends it to Things.
    private func record(_ session: CompletedSession) {
        var marked = session
        if marked.localOnly != true && tideOwns(marked) { marked.localOnly = true }
        // Lock in with no to-do stays in Plain: no Focus Log clutter in Things.
        if marked.lockIn == true && marked.taskID == nil { marked.localOnly = true }
        let session = marked
        store.add(session)
        stats = Stats.compute(store.sessions, now: Date())
        if session.localOnly == true {
            summaryNote = session.lockIn == true || session.category == .chilling
                ? "Saved in Plain's stats."
                : "Tide logged this study, so Plain kept it local."
            return
        }
        guard settings.thingsLogging else {
            summaryNote = "Saved \(session.minutes) min."
            return
        }
        summaryNote = "Logging \(session.minutes) min to Things…"
        let canceled = session.canceled
        Task {
            let result = await logger.log(session)
            var fetched: Int?
            if let id = result.taskID, session.taskID != nil { fetched = try? await client.task(id)?.trackedMinutes }
            let tracked = fetched
            await MainActor.run {
                guard !canceled else { self.refreshTasks(); return }
                if let error = result.error {
                    self.summaryNote = "Saved here. Things later: \(error)"
                    self.thingsStatus = .offline(error)
                } else {
                    self.thingsStatus = .connected
                    self.summaryNote = session.taskID == nil ? "Logged to Things › Focus Log" : "Logged \(session.minutes) min on the to-do"
                    self.summaryTaskID = session.taskID
                    self.summaryTracked = tracked
                }
                self.refreshTasks()
            }
        }
    }

    // MARK: Things to-dos

    /// Snapshots set this so nothing reaches the network.
    var isPreview = false

    func refreshTasks() {
        guard !isPreview else { return }
        Task {
            do {
                let tasks = try await client.today()
                let all = (try? await client.allOpen()) ?? []
                await MainActor.run { self.todayTasks = tasks; self.allTasks = all; self.thingsStatus = .connected; self.refreshAreaTasks() }
            } catch {
                await MainActor.run {
                    self.todayTasks = []
                    self.thingsStatus = .offline((error as? ThingsError)?.description ?? "\(error)")
                }
            }
        }
    }

    func refreshAreaTasks(for category: Category? = nil) {
        guard !isPreview else { return }
        let c = category ?? draftCategory
        Task {
            let titles = (try? await client.areaTitles()) ?? []
            var tasks: [ThingsTask] = []
            if let area = AreaMatcher.area(for: c, chosen: settings.categoryAreas[c.rawValue], titles: titles) {
                tasks = (try? await client.list(area)) ?? []
            }
            let found = tasks
            await MainActor.run { self.areaTitles = titles; self.areaTasks = found; self.nextIndex = 0 }
        }
    }

    /// The Things area linked to the draft's category, if any.
    var draftArea: String? { area(for: draftCategory) }

    /// The area a mode pulls from: the one picked in Settings, else one whose name fits
    /// (Work → "Work", Study → "Learning"…). "-" in Settings means use Today instead.
    func area(for category: Category) -> String? {
        AreaMatcher.area(for: category, chosen: settings.categoryAreas[category.rawValue], titles: areaTitles)
    }

    /// Which to-do the "Next up" card shows.
    @Published var nextIndex = 0

    /// The scene to draw: the setting, or in Auto what you're doing.
    var scene: SceneKind {
        let chosen = SceneKind(rawValue: settings.scene) ?? .auto
        if chosen != .auto { return chosen }
        if AppWatcher.isEditor(frontBundleID) { return .code }
        if machine.phase == .idle && tideMood != nil { return .library }
        if machine.phase == .breakTime || activity == .chilling { return .beach }
        switch machine.plan?.category {
        case .study?, .exam?, .reading?: return .library
        case .work?: return .room
        default: break
        }
        if frontBundleID == AppWatcher.tideBundleID { return .library }
        return .room
    }

    /// Searches open to-dos as the user types (debounced).
    /// Searches every open Things to-do as you type: ranked locally at once (words, word stems,
    /// typos and related words), then topped up with Things' own search.
    func search(_ q: String) {
        searchTask?.cancel()
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { searchResults = []; return }
        let rank = { (pool: [ThingsTask]) in
            TaskSearch.rank(q, in: pool, area: self.draftArea, todayIDs: Set(self.todayTasks.map(\.id)))
        }
        searchResults = rank(allTasks)
        guard !isPreview else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let server = (try? await client.search(q)) ?? []
            await MainActor.run {
                guard !Task.isCancelled else { return }
                var pool = self.allTasks
                for t in server where !pool.contains(where: { $0.id == t.id }) { pool.append(t) }
                let ranked = rank(pool)
                // Things' own matches stay even if the local ranker found nothing for them.
                self.searchResults = ranked + server.filter { t in !ranked.contains { $0.id == t.id } }
            }
        }
    }

    /// Every open to-do (refreshed when the popover opens).
    @Published private(set) var allTasks: [ThingsTask] = []

    func pick(_ task: ThingsTask?) {
        selectedTask = task
        if let task, let guess = QuickParser.parse(task.title).category { draftCategory = guess }
    }

    // MARK: Prompts

    /// PLAIN_PROMPT_COOLDOWN shortens the 20-minute cooldown in tests.
    static let promptCooldown: TimeInterval = ProcessInfo.processInfo.environment["PLAIN_PROMPT_COOLDOWN"].flatMap(Double.init) ?? 20 * 60

    func canPrompt(cooldown: TimeInterval = AppModel.promptCooldown) -> Bool {
        guard machine.phase == .idle, prompt == nil else { return false }
        if let last = lastPromptAt, Date().timeIntervalSince(last) < cooldown { return false }
        return true
    }

    func showPrompt(_ p: IslandPrompt) {
        lastPromptAt = Date()
        prompt = p
    }

    // MARK: URL scheme

    /// plain://start?task=<id>&title=<title>&minutes=40&category=study
    func handle(url: URL) {
        guard url.scheme == "plain" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q: [String: String] = [:]
        for item in comps?.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let command = (url.host?.isEmpty == false ? url.host! : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        switch command {
        case "start":
            let title = q["title"] ?? ""
            let minutes = q["minutes"].flatMap(Int.init) ?? settings.defaultMinutes
            let category = q["category"].flatMap { Category(rawValue: $0.lowercased()) }
                ?? QuickParser.parse(title).category ?? .work
            let taskID = q["task"].flatMap { $0.isEmpty ? nil : $0 }
            start(SessionPlan(title: title, category: category, minutes: minutes, taskID: taskID))
            onExternalStart?()
            if let taskID {
                Task {
                    if let task = try? await client.task(taskID) {
                        await MainActor.run {
                            if self.machine.plan?.taskID == taskID { self.machine.updateTracked(task.trackedMinutes, title: task.title) }
                            self.objectWillChange.send()
                        }
                    }
                }
            }
        case "tide":
            // plain://tide?choice=studying|exam|flashcards|chilling[&note=…] — what the Tide prompt does.
            if let c = q["choice"].flatMap(TideChoice.init(rawValue:)) { tideChoice(c, note: q["note"] ?? "") }
        case "track":
            startTracker(title: q["title"] ?? "", category: q["category"].flatMap { Category(rawValue: $0.lowercased()) } ?? .work)
        case "block":
            // plain://block?from=14:00&to=17:00[&category=work&title=…] books a time block.
            func clock(_ s: String?) -> Date? {
                let parts = (s ?? "").split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
            }
            if let from = clock(q["from"]), let to = clock(q["to"]) {
                let (a, b) = ScheduledBlock.resolve(from: from, to: to, now: Date())
                let title = q["title"] ?? ""
                var block = ScheduledBlock(start: a, end: b, title: title, category: q["category"].flatMap { Category(rawValue: $0) } ?? .work)
                block.lockIn = title.isEmpty
                if a <= Date().addingTimeInterval(30) { start(block.plan(now: Date())) } else { setScheduled(block) }
            }
        case "attach":
            // plain://attach?task=<id>: put the running session's time on that to-do.
            if let id = q["task"], !id.isEmpty {
                Task {
                    if let task = try? await client.task(id) { await MainActor.run { self.attach(task) } }
                }
            }
        case "pause": pause()
        case "resume": resume()
        case "finish": finishEarly()
        case "cancel", "stop": cancel()
        default: break
        }
    }

    // MARK: Notifications

    private var askedNotifications = false

    private func requestNotificationPermission() {
        guard !askedNotifications, Bundle.main.bundleIdentifier != nil else { return }
        askedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

extension SessionMachine {
    /// Fills in the to-do's tracked total and real title once Things answers.
    mutating func updateTracked(_ minutes: Int, title: String) {
        guard var p = plan else { return }
        p.trackedBefore = minutes
        if p.title.isEmpty { p.title = title }
        replacePlan(p)
    }
}

extension AppModel {
    func setPreviewBreak(_ minutes: Int) { breakMinutes = minutes }

    func previewAreas(_ titles: [String], tasks: [ThingsTask], category: Category) {
        areaTitles = titles
        areaTasks = tasks
        draftCategory = category
        nextIndex = 0
    }

    /// Puts the model into a given state for snapshots (no sound, no network).
    func preview(machine: SessionMachine, now: Date, tasks: [ThingsTask], sessions: [CompletedSession], status: ThingsStatus = .connected,
                 summary: String? = nil, summaryTaskID: String? = nil, summaryTracked: Int? = nil, prompt: IslandPrompt? = nil) {
        isPreview = true
        allTasks = tasks
        selectedTask = nil
        draftTitle = ""
        tide = TideLog.Summary(todayMinutes: 80, weekMinutes: 245, lastLabel: "Graph algorithms", available: true)
        areaTasks = []
        areaTitles = []
        self.machine = machine
        self.now = now
        todayTasks = tasks
        thingsStatus = status
        stats = Stats.compute(sessions, now: now)
        summaryNote = summary
        self.summaryTaskID = summaryTaskID
        self.summaryTracked = summaryTracked
        self.prompt = prompt
        markedDone = false
    }
}

/// A focus block booked from one time to another ("work 14:00–17:00").
struct ScheduledBlock: Codable, Equatable {
    var start: Date
    var end: Date
    var title: String
    var category: Category
    var taskID: String?
    var trackedBefore: Int = 0
    var lockIn: Bool? = nil

    /// Minutes from `now` (or the start) to the end.
    func plan(now: Date) -> SessionPlan {
        let from = max(now, start)
        let minutes = max(1, Int((end.timeIntervalSince(from) / 60).rounded()))
        return SessionPlan(title: title, category: category, minutes: minutes, taskID: taskID, trackedBefore: trackedBefore, lockIn: lockIn == true)
    }

    /// Takes the clock times of `from` and `to` on today's date; an end before the start means tomorrow,
    /// and a start already behind us today means now.
    static func resolve(from: Date, to: Date, now: Date, calendar: Calendar = .current) -> (Date, Date) {
        func today(_ d: Date) -> Date {
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: now) ?? d
        }
        var start = today(from), end = today(to)
        if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        if end <= now { start = calendar.date(byAdding: .day, value: 1, to: start) ?? start; end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return (start, end)
    }
}

/// Matches a mode to a Things area by name, so Work only shows work and Study only shows learning.
enum AreaMatcher {
    static let keywords: [Category: [String]] = [
        .work: ["work", "job", "office", "career", "business"],
        .study: ["learning", "learn", "study", "studies", "school", "uni", "university", "college", "education", "course"],
        .exam: ["exam", "learning", "learn", "study", "studies", "school", "uni", "university", "college", "education"],
        .reading: ["reading", "read", "books", "learning", "learn", "study"],
        .chilling: [],
    ]

    static func area(for category: Category, chosen: String?, titles: [String]) -> String? {
        if let chosen, !chosen.isEmpty { return chosen == "-" ? nil : chosen }
        for word in keywords[category] ?? [] {
            if let exact = titles.first(where: { $0.lowercased() == word }) { return exact }
            if let partial = titles.first(where: { $0.lowercased().split(whereSeparator: { !$0.isLetter }).contains { $0 == Substring(word) } }) { return partial }
        }
        return nil
    }
}

/// Finds to-dos from loose wording: "chem paper" finds "Organic chemistry past paper",
/// "email maya" finds "Reply to Maya", "revise grafs" finds "Revision: graph algorithms".
enum TaskSearch {
    static let stopwords: Set<String> = ["the", "a", "an", "to", "for", "on", "of", "and", "my", "with", "in", "at", "do", "about"]

    /// Words that mean roughly the same thing when looking for a task.
    static let related: [[String]] = [
        ["email", "mail", "reply", "respond", "message", "dm", "write"],
        ["study", "revise", "revision", "learn", "review", "practice", "flashcards"],
        ["exam", "test", "paper", "quiz", "mock"],
        ["read", "reading", "book", "chapter", "article"],
        ["fix", "bug", "debug", "issue", "error"],
        ["meeting", "call", "sync", "standup", "chat"],
        ["write", "draft", "essay", "doc", "docs", "document", "readme", "notes"],
        ["design", "ui", "ux", "mockup", "figma"],
        ["code", "build", "implement", "ship", "develop", "feature", "pr"],
        ["plan", "planning", "roadmap", "schedule"],
        ["chem", "chemistry"], ["bio", "biology"], ["maths", "math", "mathematics"], ["physics", "phys"],
    ]

    static func words(_ s: String) -> [String] {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func stem(_ w: String) -> String {
        for suffix in ["ations", "ation", "ings", "ing", "ies", "ed", "es", "s", "ly"] where w.count > suffix.count + 2 && w.hasSuffix(suffix) {
            return String(w.dropLast(suffix.count))
        }
        return w
    }

    /// Edit distance capped at 2 (enough for typos).
    static func close(_ a: String, _ b: String) -> Bool {
        guard a.count >= 4, b.count >= 4, abs(a.count - b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)) }
            prev = cur
        }
        return prev[y.count] <= 1
    }

    /// How well one query word matches one word of a task.
    static func score(_ q: String, _ w: String) -> Double {
        if q == w { return 3 }
        if stem(q) == stem(w) { return 2.6 }
        if w.hasPrefix(q) && q.count >= 2 { return 2.2 }
        if q.count >= 4 && w.contains(q) { return 1.6 }
        if close(q, w) { return 1.4 }
        if related.contains(where: { $0.contains(q) && $0.contains(stem(w)) || $0.contains(stem(q)) && $0.contains(w) }) { return 1.2 }
        return 0
    }

    static func rank(_ query: String, in tasks: [ThingsTask], area: String? = nil, todayIDs: Set<String> = [], limit: Int = 20) -> [ThingsTask] {
        let q = words(query).filter { !stopwords.contains($0) }
        guard !q.isEmpty else { return [] }
        var scored: [(ThingsTask, Double)] = []
        for t in tasks {
            let title = words(t.title), ctx = words((t.context ?? "") + " " + (t.area ?? "") + " " + t.tags.joined(separator: " ")), notes = words(t.notes)
            var total = 0.0, matched = 0
            for word in q {
                let best = max(title.map { score(word, $0) * 2 }.max() ?? 0,
                               ctx.map { score(word, $0) * 1.2 }.max() ?? 0,
                               notes.map { score(word, $0) * 0.6 }.max() ?? 0)
                if best > 0 { matched += 1; total += best }
            }
            // Most of the words have to land somewhere.
            guard matched * 2 >= q.count, total > 0 else { continue }
            if let area, t.area == area || t.context == area { total += 1.5 }
            if todayIDs.contains(t.id) { total += 0.8 }
            if t.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(query.lowercased()) { total += 3 }
            scored.append((t, total + Double(matched) * 0.5))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
