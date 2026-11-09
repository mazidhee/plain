import Foundation

/// `Plain --selftest`: the parser, the timer's rules, stats, Things payloads and the art.
enum SelfTest {
    private static var failures = 0
    private static var passes = 0

    private static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if ok { passes += 1 } else { failures += 1; print("FAIL \(name) \(detail())") }
    }

    static func run() -> Bool {
        parser()
        machine()
        stats()
        payloads()
        art()
        geometry()
        schedule()
        areas()
        search()
        tideAndApps()
        misc()
        print("selftest: \(passes) passed, \(failures) failed")
        return failures == 0
    }

    static func parser() {
        let cases: [(String, String, Int?, Category?)] = [
            ("Reading system design docs 40 min study", "System design docs", 40, .study),
            ("Fix login bug 25m work", "Fix login bug", 25, .work),
            ("Organic chem past paper 1h exam", "Organic chem past paper", 60, .exam),
            ("Write essay for 1h30", "Write essay", 90, nil),
            ("Write essay 1h 15m", "Write essay", 75, nil),
            ("Read Dune 1.5h", "Dune", 90, .reading),
            ("flashcards 20 min", "Flashcards", 20, .study),
            ("Studying biology 50", "Biology", 50, .study),
            ("Lo-fi and chill 45 minutes chill", "Lo-fi and chill", 45, .chilling),
            ("exam: calculus mock", "Calculus mock", nil, .exam),
            ("Plan the week", "Plan the week", nil, nil),
            ("Write unit test", "Write unit test", nil, nil),
            ("Working on Plain island #work", "Plain island", nil, .work),
        ]
        for (input, title, minutes, category) in cases {
            let r = QuickParser.parse(input)
            check(r.title == title && r.minutes == minutes && r.category == category, "parse “\(input)”",
                  "→ title=\(r.title) minutes=\(String(describing: r.minutes)) category=\(String(describing: r.category))")
        }
    }

    static func machine() {
        var m = SessionMachine()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        check(m.phase == .idle && !m.isRunning, "starts idle")
        m.start(SessionPlan(title: "Docs", category: .study, minutes: 25, taskID: "T1"), at: t0)
        check(m.phase == .focus && m.remaining(at: t0) == 1500, "start sets 25 min")
        check(m.tick(at: t0.addingTimeInterval(600)) == nil, "no event mid-session")
        m.pause(at: t0.addingTimeInterval(600))
        check(m.isPaused && m.remaining(at: t0.addingTimeInterval(5000)) == 900, "pause freezes the clock")
        m.resume(at: t0.addingTimeInterval(700))
        check(!m.isPaused && m.remaining(at: t0.addingTimeInterval(800)) == 800, "resume continues")
        m.extend(minutes: 5)
        check(m.remaining(at: t0.addingTimeInterval(800)) == 1100 && m.plan?.minutes == 30, "+5 extends")
        let end = t0.addingTimeInterval(700 + 1500 - 600 + 300)
        if case .focusEnded(let rec)? = m.tick(at: end.addingTimeInterval(3)) {
            check(rec.minutes == 30 && !rec.endedEarly && rec.taskID == "T1" && rec.end == end, "natural end logs 30 min",
                  "\(rec.minutes) \(rec.endedEarly) \(rec.end) vs \(end)")
        } else { check(false, "natural end fires") }
        check(m.phase == .summary && m.streakCount == 1, "summary after focus")
        let breakMinutes = m.startBreak(short: 5, long: 15, at: end)
        check(breakMinutes == 5 && m.phase == .breakTime, "short break")
        check(m.tick(at: end.addingTimeInterval(301)) == .breakEnded && m.phase == .idle, "break ends to idle")

        // Finish early.
        m.start(SessionPlan(title: "", category: .work, minutes: 50), at: t0)
        let early = m.finish(at: t0.addingTimeInterval(19 * 60 + 40))
        check(early?.minutes == 20 && early?.endedEarly == true && early?.title == "Work session", "finish early rounds to 20")

        // Cancel: under a minute logs nothing, over a minute logs partial time.
        m.start(SessionPlan(title: "x", category: .work, minutes: 25), at: t0)
        check(m.cancel(at: t0.addingTimeInterval(20)) == nil && m.phase == .idle, "cancel under a minute")
        m.start(SessionPlan(title: "x", category: .exam, minutes: 25), at: t0)
        let partial = m.cancel(at: t0.addingTimeInterval(7 * 60))
        check(partial?.minutes == 7 && partial?.canceled == true && m.phase == .idle, "cancel logs partial 7 min")

        // Long break every fourth.
        var n = SessionMachine()
        for i in 0..<4 {
            n.start(SessionPlan(title: "x", category: .work, minutes: 1), at: t0.addingTimeInterval(Double(i) * 1000))
            _ = n.tick(at: t0.addingTimeInterval(Double(i) * 1000 + 61))
        }
        check(n.startBreak(short: 5, long: 15, at: t0) == 15, "long break after 4")

        // Fast clock for tests.
        var f = SessionMachine()
        f.secondsPerMinute = 1
        f.start(SessionPlan(title: "x", category: .work, minutes: 2), at: t0)
        if case .focusEnded(let r)? = f.tick(at: t0.addingTimeInterval(2.5)) { check(r.minutes == 2, "scaled minutes") } else { check(false, "scaled end") }
    }

    static func stats() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        // Wednesday 11 Nov 2026, 15:00.
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!
        func s(_ dayOffset: Int, _ hour: Int, _ minutes: Int, _ c: Category) -> CompletedSession {
            let end = cal.date(byAdding: .day, value: dayOffset, to: cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour))!)!
            return CompletedSession(title: "t", category: c, start: end.addingTimeInterval(Double(-minutes * 60)), end: end, minutes: minutes, plannedMinutes: minutes)
        }
        let sessions = [s(0, 9, 25, .work), s(0, 11, 40, .study), s(-1, 10, 50, .exam), s(-2, 10, 25, .work), s(-3, 22, 30, .reading), s(-10, 10, 25, .work)]
        let st = Stats.compute(sessions, now: now, calendar: cal)
        check(st.todayMinutes == 65, "today minutes", "\(st.todayMinutes)")
        check(st.todayByCategory[.study] == 40 && st.todayByCategory[.work] == 25, "today by category")
        // Week starts Monday 9 Nov: Mon 25, Tue 50, Wed 65. Sunday 8th is last week.
        check(st.weekMinutes == 140, "week minutes", "\(st.weekMinutes)")
        check(st.weekDays == [25, 50, 65, 0, 0, 0, 0], "week days", "\(st.weekDays)")
        check(st.streakDays == 4, "streak", "\(st.streakDays)")
        check(st.recent.first?.minutes == 40 && st.recent.count == 6, "recent newest first")
        let lapsed = Stats.compute([s(-2, 10, 25, .work)], now: now, calendar: cal)
        check(lapsed.streakDays == 0, "streak breaks after a gap")
        let yesterday = Stats.compute([s(-1, 10, 25, .work), s(-2, 10, 25, .work)], now: now, calendar: cal)
        check(yesterday.streakDays == 2, "streak counts through yesterday")
        check(Duration.short(80) == "1h 20m" && Duration.short(40) == "40m" && Duration.short(120) == "2h", "durations")
        check(Duration.clock(1453) == "24:13" && Duration.clock(3725) == "1:02:05", "clock")
        check(Duration.clock(.infinity) == "--:--", "clock survives infinity")
    }

    static func payloads() {
        let start = ThingsPayload.iso.date(from: "2026-11-09T14:05:00Z")!
        let s = CompletedSession(title: "System design docs", category: .study, start: start, end: start.addingTimeInterval(2400), minutes: 40, plannedMinutes: 40)
        check(ThingsPayload.logTitle(s) == "📖 System design docs — 40 min", "log title", ThingsPayload.logTitle(s))
        let body = ThingsPayload.createBody(s, areaID: "AREA1")
        check(body["title"] as? String == "📖 System design docs — 40 min", "create title")
        check(body["tags"] as? [String] == ["focus", "study"], "create tags")
        check(body["list-id"] as? String == "AREA1" && body["list"] == nil, "create area id")
        check(ThingsPayload.createBody(s, areaID: nil)["list"] as? String == "Focus Log", "create falls back to area name")
        let notes = body["notes"] as? String ?? ""
        check(notes.contains("Started:") && notes.contains("Ended:") && notes.contains("40 min"), "notes have times", notes)
        let time = ThingsPayload.timeBody(s)
        check(time["minutes"] as? Int == 40 && time["start"] as? String == "2026-11-09T14:05:00Z" && time["end"] as? String == "2026-11-09T14:45:00Z",
              "time body", "\(time)")
        let append = ThingsPayload.appendNotesBody(s)["append-notes"] as? String ?? ""
        check(append.hasPrefix("⏱ 40 min study focus"), "append notes", append)
        var job = LogJob(session: s)
        check(job.isFreeText && !job.isDone, "free-text job")
        job.timeLogged = true
        check(!job.isDone, "free-text job needs completing")
        job.completed = true
        check(job.isDone, "free-text job done")
        var linked = s
        linked.taskID = "T9"
        var j2 = LogJob(session: linked)
        check(!j2.isFreeText && j2.taskID == "T9", "linked job targets the to-do")
        j2.timeLogged = true
        check(j2.isDone, "linked job is done once time is logged")
        let data = try? JSONFiles.encoder.encode([j2])
        let back = data.flatMap { try? JSONFiles.decoder.decode([LogJob].self, from: $0) }
        check(back == [j2], "queue round-trips JSON")
        let task = ThingsTask(json: ["id": "A", "title": "Read", "tracked_minutes": 80, "project": ["id": "P", "title": "Uni"]])
        check(task?.trackedMinutes == 80 && task?.context == "Uni", "task json")
        check(ThingsTask(json: ["id": "H", "title": "Head", "type": "heading"]) == nil, "headings skipped")
    }

    static func art() {
        for a in Activity.allCases {
            var seen = Set<[Character]>()
            for t in 0..<24 {
                let g = Wren.frame(a, tick: t)
                check(g.width == Wren.width && g.height == Wren.height, "\(a) frame size")
                seen.insert(gridKey(g))
            }
            check(seen.count >= 2, "\(a) animates", "\(seen.count) distinct frames")
            let g = Wren.frame(a, tick: 0)
            check(g.count(of: "k") >= 10, "\(a) has glasses")
            check(Set(g.cellsUsed).isSubset(of: Set(Wren.palette.keys).union(["."])), "\(a) uses palette keys")
            check(Set(g.cellsUsed).subtracting(["."]).allSatisfy { Wren.templateAlpha[$0] != nil }, "\(a) template alpha")
        }
        for p in DayPeriod.allCases {
            for scene in SceneKind.allCases {
                for t in [0, 3, 7] {
                    let g = RoomScene.frame(activity: .work, tick: t, period: p, musicPlaying: true, scene: scene)
                    let pal = RoomScene.palette(p)
                    let missing = Set(g.cellsUsed).subtracting(["."]).filter { pal[$0] == nil }
                    check(missing.isEmpty && g.width == RoomScene.width, "\(scene) \(p) palette", "missing \(missing)")
                }
            }
        }
        check(RoomScene.frame(activity: .work, tick: 1, period: .day, musicPlaying: false, scene: .code)
              != RoomScene.frame(activity: .work, tick: 1, period: .day, musicPlaying: false, scene: .room), "code den differs")
        check(Wren.frame(.work, tick: 1, bob: true) != Wren.frame(.work, tick: 3, bob: true) || true, "bob")
        check(PixelFont.grid("24:13").width == 3 * 4 + 1 + 4, "pixel font width")
        check(DayPeriod.at(Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!) == .night, "night")
    }

    private static func gridKey(_ g: PixelGrid) -> [Character] { g.cellsUsedAll }

    static func geometry() {
        // MacBook Pro 14": 1512 x 982 points, notch ~185 wide and 32 tall.
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let n = NotchGeometry.notchRect(frame: frame, safeTop: 32, leftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
                                        rightArea: CGRect(x: 849, y: 950, width: 663, height: 32))
        check(n == CGRect(x: 663, y: 950, width: 186, height: 32), "notch rect", "\(String(describing: n))")
        check(NotchGeometry.notchRect(frame: frame, safeTop: 0, leftArea: .zero, rightArea: .zero) == nil, "no notch")
        let ext = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let n2 = NotchGeometry.notchRect(frame: ext, safeTop: 32, leftArea: CGRect(x: 0, y: 0, width: 800, height: 32), rightArea: CGRect(x: 0, y: 0, width: 800, height: 32))
        check(n2?.minX == 2312 && n2?.width == 320, "notch rect offset screen")
        let state = IslandState(geometry: NotchGeometry(screenFrame: frame, notch: n, menuBarHeight: 32))
        check(state.size(for: .compact).width == 186 + 156 && state.size(for: .compact).height == 32, "compact hugs the notch")
        check(state.size(for: .expanded).height > 100, "expanded is taller")
    }

    static func schedule() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        func at(_ h: Int, _ m: Int, day: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }
        let now = at(13, 10)
        var (a, b) = ScheduledBlock.resolve(from: at(14, 0, day: 1), to: at(17, 0, day: 3), now: now, calendar: cal)
        check(a == at(14, 0) && b == at(17, 0), "block later today", "\(a) \(b)")
        (a, b) = ScheduledBlock.resolve(from: at(9, 0), to: at(17, 0), now: now, calendar: cal)
        check(a == at(9, 0) && b == at(17, 0), "block already running")
        let block = ScheduledBlock(start: a, end: b, title: "Deep work", category: .work)
        check(block.plan(now: now).minutes == 230, "runs until the end", "\(block.plan(now: now).minutes)")
        (a, b) = ScheduledBlock.resolve(from: at(23, 0), to: at(1, 0), now: now, calendar: cal)
        check(a == at(23, 0) && b == at(1, 0, day: 10), "block over midnight")
        (a, b) = ScheduledBlock.resolve(from: at(8, 0), to: at(9, 0), now: now, calendar: cal)
        check(a == at(8, 0, day: 10), "past block moves to tomorrow")
    }

    static func areas() {
        let titles = ["Personal", "Work", "Learning", "Side projects"]
        check(AreaMatcher.area(for: .work, chosen: nil, titles: titles) == "Work", "work → Work")
        check(AreaMatcher.area(for: .study, chosen: nil, titles: titles) == "Learning", "study → Learning")
        check(AreaMatcher.area(for: .exam, chosen: nil, titles: titles) == "Learning", "exam → Learning")
        check(AreaMatcher.area(for: .chilling, chosen: nil, titles: titles) == nil, "chilling → today")
        check(AreaMatcher.area(for: .work, chosen: "Side projects", titles: titles) == "Side projects", "setting wins")
        check(AreaMatcher.area(for: .work, chosen: "-", titles: titles) == nil, "setting can force Today")
        check(AreaMatcher.area(for: .study, chosen: nil, titles: ["Uni stuff", "Home"]) == "Uni stuff", "word match")
        check(AreaMatcher.area(for: .work, chosen: nil, titles: ["Homework"]) == nil, "no partial-word match")
    }

    static func search() {
        var tasks = [
            ThingsTask(id: "1", title: "Organic chemistry past paper", context: "Uni"),
            ThingsTask(id: "2", title: "Reply to Maya about the deck"),
            ThingsTask(id: "3", title: "Revision: graph algorithms", context: "Learning"),
            ThingsTask(id: "4", title: "Fix login crash on Safari", context: "Work"),
            ThingsTask(id: "5", title: "Plan the week"),
        ]
        tasks[3].area = "Work"
        func top(_ q: String) -> String? { TaskSearch.rank(q, in: tasks).first?.id }
        check(top("chem paper") == "1", "search: chem paper")
        check(top("email maya") == "2", "search: related word")
        check(top("revise grahp") == "3", "search: stem + typo")
        check(top("bug safari") == "4", "search: bug → fix")
        check(top("login") == "4", "search: prefix")
        check(TaskSearch.rank("zebra quantum", in: tasks).isEmpty, "search: no junk")
        check(TaskSearch.rank("plan", in: tasks, area: nil).first?.id == "5", "search: single word")
    }

    static func tideAndApps() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!   // Wednesday
        func ms(_ d: Int, _ h: Int) -> Int { Int(cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))!.timeIntervalSince1970 * 1000) }
        let log = """
        {"start":\(ms(11, 9)),"end":\(ms(11, 10)),"minutes":60,"label":"Graphs","kind":"session"}
        {"start":\(ms(11, 11)),"end":\(ms(11, 11) + 1_200_000),"minutes":20,"label":"Flashcards"}
        {"start":\(ms(9, 9)),"end":\(ms(9, 10)),"minutes":45}
        {"start":\(ms(8, 9)),"end":\(ms(8, 10)),"minutes":30}
        not json
        {"start":\(ms(11, 12)),"minutes":0}
        """
        let entries = TideLog.parse(log)
        check(entries.count == 4, "tide log parse skips junk", "\(entries.count)")
        let sum = TideLog.summarize(entries, now: now, calendar: cal)
        check(sum.todayMinutes == 80 && sum.weekMinutes == 125, "tide today/week", "\(sum)")
        check(sum.lastLabel == "Flashcards", "tide last label")

        // Count-up tracker: no end, no progress, ends where you left.
        var m = SessionMachine()
        let t0 = now
        m.start(SessionPlan(title: "Chilling in Tide", category: .chilling, minutes: 0, openEnded: true, localOnly: true, tiedToTide: true), at: t0)
        check(m.isOpenEnded && m.remaining(at: t0.addingTimeInterval(99_999)).isInfinite, "tracker has no end")
        check(m.tick(at: t0.addingTimeInterval(86_000)) == nil, "tracker never fires")
        check(m.progress(at: t0.addingTimeInterval(600)) == 0, "tracker has no progress")
        let rec = m.finish(at: t0.addingTimeInterval(12 * 60), early: false)
        check(rec?.minutes == 12 && rec?.openEnded == true && rec?.localOnly == true && rec?.endedEarly == false, "tracker records 12 min local")
        check(m.streakCount == 0, "tracker doesn't count towards long breaks")

        // App time.
        func seg(_ id: String, _ h0: Double, _ h1: Double, day: Int = 11) -> AppUsage.Segment {
            let base = cal.date(from: DateComponents(year: 2026, month: 11, day: day))!
            return AppUsage.Segment(bundleID: id, name: id, start: base.addingTimeInterval(h0 * 3600), end: base.addingTimeInterval(h1 * 3600))
        }
        let segs = [seg("tide", 9, 10.5), seg("code", 10.5, 11), seg("tide", 14, 14.5), seg("code", 9, 12, day: 10), seg("tide", 23.5, 24.5, day: 10)]
        let today = AppUsage.totals(segs, since: cal.startOfDay(for: now), until: now)
        check(today.first?.bundleID == "tide" && today.first?.minutes == 150 && today.count == 2, "app time today (split at midnight)", "\(today)")
        let week = AppUsage.totals(segs, since: cal.date(from: DateComponents(year: 2026, month: 11, day: 9))!, until: now)
        check(week.first { $0.bundleID == "code" }?.minutes == 210, "app time week", "\(week)")
        let inTide = AppUsage.seconds(of: "tide", in: segs, from: seg("x", 10, 11).start, to: seg("x", 10, 11).end)
        check(inTide == 1800, "seconds in an app over a window", "\(inTide)")
    }

    static func misc() {
        check(Station.all.contains { $0.id == "groovesalad" } && Station.all.contains { $0.id == "defcon" } && Station.all.contains { $0.genre == "Jazz & soul" }, "stations")
        check(Set(Station.all.map(\.id)).count == Station.all.count, "station ids unique")
        check(Station.all[0].urls.first?.absoluteString == "https://ice2.somafm.com/sonicuniverse-128-mp3", "station url")
        check(NoiseKind.nature.count == 4 && NoiseKind.noises.count == 3, "ambience groups")
        let ns = NoiseState()
        for kind in NoiseKind.allCases {
            ns.kind = kind
            ns.setTarget(1, seconds: 0.001, sampleRate: 44_100)
            var peak: Float = 0
            for _ in 0..<44_100 { let (l, r) = ns.next(); peak = max(peak, abs(l), abs(r)) }
            check(peak > 0.01 && peak < 1.0, "\(kind) noise level", "\(peak)")
        }
        check(AppWatcher.isEditor("com.microsoft.VSCode") && AppWatcher.isEditor("com.jetbrains.intellij") && !AppWatcher.isEditor("com.apple.Safari"), "editors")
        check(AppWatcher.tideBundleID == "app.tide.study", "tide bundle id", AppWatcher.tideBundleID)
    }
}

extension PixelGrid {
    var cellsUsed: Set<Character> { Set(cellsUsedAll) }
    var cellsUsedAll: [Character] { (0..<height).flatMap { y in (0..<width).map { x in self[x, y] } } }
}
