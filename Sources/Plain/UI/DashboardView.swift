import Charts
import SwiftUI

/// Chart colours: a validated categorical set for Plain's dark cards (fixed order, never cycled),
/// so stacked and adjacent series stay apart for colour-blind eyes too.
enum ChartColor {
    static let series: [Color] = [0x3987e5, 0xd95926, 0x199e70, 0xc98500, 0xd55181, 0x008300, 0x9085e9].map { Color(hex: $0) }
    /// Tide study and Plain focus, wherever both appear.
    static let tide = series[0]
    static let plain = series[1]

    static func activity(_ a: String) -> Color {
        series[TideAPI.activities.firstIndex(of: a) ?? (series.count - 1)]
    }
}

/// Loads what the dashboard shows: Tide's API for the range (and the one before, for comparison)
/// plus Plain's own sessions.
final class DashboardData: ObservableObject {
    let model: AppModel
    @Published var days = 30 { didSet { if days != oldValue { load() } } }
    @Published private(set) var tide: TideAPI.Summary?
    /// Twice the range, only for "vs the previous N days".
    @Published private(set) var tideDouble: TideAPI.Summary?
    @Published private(set) var tideSessions: [TideAPI.Session] = []
    @Published private(set) var problem: String?
    @Published private(set) var loading = false
    @Published private(set) var loadedAt: Date?
    @Published var tab: DashTab = .overview
    @Published var sessionFilter = "All"

    init(model: AppModel) { self.model = model }

    /// Snapshots: fixed data, no network.
    func preview(tide: TideAPI.Summary, double: TideAPI.Summary, sessions: [TideAPI.Session]) {
        self.tide = tide; tideDouble = double; tideSessions = sessions; loadedAt = Date(); problem = nil
    }

    func load() {
        guard let token = model.tideToken, !token.isEmpty else {
            tide = nil; tideDouble = nil; tideSessions = []
            problem = TideAPI.Failure.noToken.description
            return
        }
        loading = true
        let days = self.days
        Task {
            do {
                async let s = TideAPI.summary(days: days, token: token)
                async let d = TideAPI.summary(days: min(366, days * 2), token: token)
                async let list = TideAPI.sessions(from: Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!, token: token)
                let (a, b, c) = try await (s, d, list)
                await MainActor.run {
                    guard days == self.days else { return }
                    self.tide = a; self.tideDouble = b; self.tideSessions = c
                    self.problem = nil; self.loading = false; self.loadedAt = Date()
                }
            } catch {
                await MainActor.run {
                    self.problem = (error as? TideAPI.Failure)?.description ?? "\(error)"
                    self.loading = false
                }
            }
        }
    }

    // MARK: Plain's side, for the same range

    var rangeStart: Date { Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))! }

    /// Snapshots set this instead of reading the store.
    var sessionsOverride: [CompletedSession]?
    private var allPlain: [CompletedSession] { sessionsOverride ?? model.store.sessions }

    var plainSessions: [CompletedSession] {
        let from = rangeStart
        return allPlain.filter { $0.minutes > 0 && $0.end >= from }
    }

    var plainPrevious: Int {
        let from = Calendar.current.date(byAdding: .day, value: -days, to: rangeStart)!
        return allPlain.filter { $0.minutes > 0 && $0.end >= from && $0.end < rangeStart }.reduce(0) { $0 + $1.minutes }
    }

    var tidePrevious: Int? {
        guard let d = tideDouble else { return nil }
        let start = TideAPI.date(tide?.range.from ?? "") ?? rangeStart
        return d.days.filter { (TideAPI.date($0.date) ?? .distantFuture) < start }.reduce(0) { $0 + $1.minutes }
    }
}

/// One bar segment on the day chart.
struct DayPoint: Identifiable {
    var date: Date
    var source: String
    var minutes: Int
    var id: String { "\(date.timeIntervalSince1970)-\(source)" }
}

/// One row of the combined session log.
struct LogRow: Identifiable {
    var start: Date
    var minutes: Int
    var source: String
    var kind: String
    var title: String
    var color: Color
    var id: String { "\(source)-\(start.timeIntervalSince1970)-\(title)" }
}

enum DashTab: String, CaseIterable { case overview = "Overview", tide = "Tide", plain = "Plain", sessions = "Sessions" }

/// The dashboard window: where the time went, in depth, for Tide study and Plain focus together.
struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var data: DashboardData

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let problem = data.problem { notice(problem) }
                    switch data.tab {
                    case .overview: overview
                    case .tide: tidePage
                    case .plain: plainPage
                    case .sessions: sessionsPage
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .onAppear { if data.loadedAt == nil && !model.isPreview { data.load() } }
    }

    // MARK: Header

    /// Clear of the traffic lights: tabs in the middle, range and refresh on the right.
    private var header: some View {
        HStack(spacing: Space.l) {
            HStack(spacing: Space.s) {
                PixelView(grid: Wren.frame(.study, tick: 0), palette: Wren.palette, pixel: 1.6)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your time").font(Theme.rounded(16, .bold)).foregroundStyle(Theme.text)
                    Text(sourceLine).font(Theme.rounded(10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(.leading, 76)
            Spacer(minLength: Space.l)
            HStack(spacing: 2) {
                ForEach(DashTab.allCases, id: \.self) { t in
                    Button { data.tab = t } label: {
                        Text(t.rawValue).font(Theme.rounded(12, data.tab == t ? .bold : .medium))
                            .foregroundStyle(data.tab == t ? Theme.text : Theme.muted)
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(Capsule().fill(data.tab == t ? Theme.cardHi : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Theme.card))
            Spacer(minLength: Space.l)
            HStack(spacing: 2) {
                ForEach([7, 30, 90, 365], id: \.self) { d in
                    Segment(label: d == 365 ? "1y" : "\(d)d", selected: data.days == d, accent: Theme.accent) { data.days = d }
                }
            }
            .padding(2)
            .background(Capsule().fill(Theme.card))
            IconButton(symbol: "arrow.clockwise", help: "Refresh") { data.load(); model.refreshTide() }
                .opacity(data.loading ? 0.4 : 1)
        }
        .padding(.horizontal, Space.l)
        .frame(height: 56)
        .background(Theme.bg)
    }

    private var sourceLine: String {
        var parts = ["Last \(data.days) days"]
        if let t = data.loadedAt { parts.append("updated \(t.formatted(date: .omitted, time: .shortened))") }
        return parts.joined(separator: " · ")
    }

    private func notice(_ text: String) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.accent)
            Text("Tide: \(text) Plain's own numbers still show.").font(TypeScale.body).foregroundStyle(Theme.text)
            Spacer()
            if data.problem == TideAPI.Failure.noToken.description {
                Button("Paste token") {
                    if let t = NSPasteboard.general.string(forType: .string) { model.setTideToken(t); data.load() }
                }
                .help("Copy the token in Tide › Settings › Tools first")
            }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.card))
    }

    // MARK: Pages

    private var overview: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.l) {
                hero.frame(width: 420)
                kpiGrid
            }
            .fixedSize(horizontal: false, vertical: true)
            DayChart(points: dayPoints, days: data.days).card("Where your time goes", subtitle: "Minutes per day, Tide study and Plain focus stacked")
            row {
                CalendarHeat(days: dayTotals, start: data.rangeStart).card("Every day", subtitle: activeDaysText)
                WeekHourHeat(cells: weekHour).card("When you work", subtitle: peakText)
            }
            row {
                KindBars(rows: data.tide?.activities ?? []).card("Tide by kind of study", subtitle: kindSubtitle)
                RankedList(rows: plainByMode, color: ChartColor.plain, empty: "No Plain sessions in this range.", colors: plainModeColors)
                    .card("Plain by mode", subtitle: "Work, study, exams, reading and chilling")
            }
        }
    }

    private var tidePage: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                Tile(title: "Tide study", value: Duration.short(tideTotal), detail: "in the last \(data.days) days", dot: ChartColor.tide)
                Tile(title: "Today", value: Duration.short(data.tide?.totals.today ?? model.tide.todayMinutes), detail: "this week \(Duration.short(data.tide?.totals.thisWeek ?? model.tide.weekMinutes))")
                Tile(title: "Study days", value: "\(data.tide?.totals.studyDays ?? 0)", detail: "avg \(Duration.short(data.tide?.totals.averagePerStudyDay ?? 0)) a day")
                Tile(title: "Streak", value: "\(data.tide?.totals.streak ?? 0)d", detail: "longest \(data.tide?.totals.longestStreak ?? 0)d", icon: "flame.fill")
            }
            if let now = data.tide?.now {
                Label("Studying now: \(now.label) · \(Duration.short(now.minutes))", systemImage: "dot.radiowaves.left.and.right")
                    .font(TypeScale.bodyStrong).foregroundStyle(Theme.study)
                    .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.study.opacity(0.12)))
            }
            row {
                KindBars(rows: data.tide?.activities ?? []).card("By kind of study", subtitle: kindSubtitle)
                HourChart(tide: data.tide?.hours ?? Array(repeating: 0, count: 24), plain: Array(repeating: 0, count: 24), legend: false)
                    .card("Hours of the day", subtitle: "Minutes of study started in each hour")
            }
            row {
                PerformanceCard(summary: data.tide).card("How it went", subtitle: "Answers in lessons and quizzes, and flashcards")
                VStack(spacing: Space.l) {
                    RankedList(rows: (data.tide?.notebooks ?? []).map { ($0.notebook, $0.minutes) }, color: ChartColor.tide, empty: "No notebooks yet.")
                        .card("Notebooks", subtitle: "Minutes per notebook")
                    RankedList(rows: (data.tide?.topics ?? []).map { ($0.label, $0.minutes) }, color: ChartColor.tide, empty: "No topics yet.")
                        .card("Longest topics", subtitle: "What you spent most time on")
                }
            }
        }
    }

    private var plainPage: some View {
        let runs = data.plainSessions.filter { $0.rounds != nil }
        let fullRuns = runs.filter { $0.round == $0.rounds && !$0.endedEarly }.count
        return VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                Tile(title: "Plain focus", value: Duration.short(plainTotal), detail: "in the last \(data.days) days", dot: ChartColor.plain)
                Tile(title: "Sessions", value: "\(data.plainSessions.count)", detail: "avg \(Duration.short(plainTotal / max(1, data.plainSessions.count)))")
                Tile(title: "Pomodoro rounds", value: "\(runs.count)", detail: "\(fullRuns) full run\(fullRuns == 1 ? "" : "s") finished")
                Tile(title: "Finished as planned", value: "\(data.plainSessions.isEmpty ? 0 : data.plainSessions.filter { !$0.endedEarly }.count * 100 / data.plainSessions.count)%",
                     detail: { let n = data.plainSessions.filter(\.endedEarly).count; return n == 0 ? "none ended early" : "\(n) ended early" }())
            }
            row {
                RankedList(rows: plainByMode, color: ChartColor.plain, empty: "No Plain sessions in this range.", colors: plainModeColors)
                    .card("By mode", subtitle: "Work, study, exams, reading and chilling")
                RankedList(rows: plainTopTitles, color: ChartColor.plain, empty: "Nothing yet.")
                    .card("Top focus", subtitle: "By to-do or title")
            }
            row {
                HourChart(tide: Array(repeating: 0, count: 24), plain: plainHours, legend: false).card("Hours of the day", subtitle: "Minutes of focus started in each hour")
                AppRows(model: model).card("Apps in front", subtitle: "This week, local only")
            }
        }
    }

    private var sessionsPage: some View {
        let rows = logRows.filter { data.sessionFilter == "All" || $0.source == data.sessionFilter }
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                HStack(spacing: 2) {
                    ForEach(["All", "Tide", "Plain"], id: \.self) { f in
                        Segment(label: f, selected: data.sessionFilter == f, accent: Theme.accent) { data.sessionFilter = f }
                            .frame(width: 56)
                    }
                }
                .padding(2).background(Capsule().fill(Theme.card))
                Spacer()
                Text("\(rows.count) sessions · \(Duration.short(rows.reduce(0) { $0 + $1.minutes }))").font(TypeScale.meta).foregroundStyle(Theme.muted)
            }
            SessionLog(rows: rows).card("Every session", subtitle: "Newest first, the last \(data.days) days")
        }
    }

    /// Two cards side by side, as tall as the taller one.
    private func row<A: View, B: View>(@ViewBuilder _ content: () -> TupleView<(A, B)>) -> some View {
        HStack(alignment: .top, spacing: Space.l) { content() }.fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Hero and numbers

    private var tideTotal: Int { data.tide?.totals.inRange ?? 0 }
    private var plainTotal: Int { data.plainSessions.reduce(0) { $0 + $1.minutes } }
    private var tideToday: Int { data.tide?.totals.today ?? model.tide.todayMinutes }
    private var plainToday: Int { model.stats.todayMinutes }

    /// Today in the pixel clock, split by app, with the last seven days underneath.
    private var hero: some View {
        let today = tideToday + plainToday
        let week = Array(dayTotals.suffix(7))
        let peak = max(30, week.map(\.1).max() ?? 0)
        return VStack(alignment: .leading, spacing: Space.l) {
            Text("TODAY").font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.6)
            PixelClock(text: pixelDuration(today), pixel: 7, ink: Theme.textInk)
            VStack(alignment: .leading, spacing: Space.s) {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        if today == 0 { RoundedRectangle(cornerRadius: 3).fill(Theme.line) }
                        if tideToday > 0 { RoundedRectangle(cornerRadius: 3).fill(ChartColor.tide).frame(width: (g.size.width - 2) * CGFloat(tideToday) / CGFloat(max(1, today))) }
                        if plainToday > 0 { RoundedRectangle(cornerRadius: 3).fill(ChartColor.plain) }
                    }
                }
                .frame(height: 8)
                HStack(spacing: Space.l) {
                    legend("Tide \(Duration.short(tideToday))", ChartColor.tide)
                    legend("Plain \(Duration.short(plainToday))", ChartColor.plain)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(d.1 == 0 ? Theme.line : (i == week.count - 1 ? Theme.accent : Theme.accent.opacity(0.55)))
                            .frame(height: d.1 == 0 ? 3 : max(4, 44 * CGFloat(d.1) / CGFloat(peak)))
                        Text(d.0.formatted(.dateTime.weekday(.narrow))).font(Theme.rounded(9, i == week.count - 1 ? .bold : .regular))
                            .foregroundStyle(i == week.count - 1 ? Theme.text : Theme.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(d.0.formatted(.dateTime.weekday(.wide).month().day())): \(Duration.short(d.1))")
                }
            }
            .frame(height: 60, alignment: .bottom)
        }
        .padding(Space.xl)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(LinearGradient(colors: [Theme.cardHi, Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.accent.opacity(0.18)))
    }

    /// "1h55m" or "45m" for the pixel font.
    private func pixelDuration(_ m: Int) -> String { m >= 60 ? "\(m / 60)h\(String(format: "%02d", m % 60))m" : "\(m)m" }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(TypeScale.meta).foregroundStyle(Theme.muted)
        }
    }

    private var kpiGrid: some View {
        let total = tideTotal + plainTotal
        let prev = (data.tidePrevious ?? 0) + data.plainPrevious
        let active = dayTotals.filter { $0.1 > 0 }.count
        let sessions = (data.tide?.totals.sessions ?? 0) + data.plainSessions.count
        let best = dayTotals.max { $0.1 < $1.1 }
        return Grid(horizontalSpacing: Space.l, verticalSpacing: Space.l) {
            GridRow {
                Tile(title: "Last \(data.days) days", value: Duration.short(total), detail: delta(total, prev))
                Tile(title: "Per active day", value: Duration.short(active > 0 ? total / active : 0), detail: "\(active) of \(data.days) days active")
            }
            GridRow {
                Tile(title: "Sessions", value: "\(sessions)", detail: sessions > 0 ? "\(Duration.short(total / max(1, sessions))) on average" : "None yet")
                Tile(title: "Streak", value: "\(max(data.tide?.totals.streak ?? 0, model.stats.streakDays)) days",
                     detail: best.map { $0.1 > 0 ? "Best: \($0.0.formatted(.dateTime.month(.abbreviated).day())), \(Duration.short($0.1))" : "No best day yet" } ?? "", icon: "flame.fill")
            }
        }
    }

    private func delta(_ now: Int, _ before: Int) -> String {
        guard before > 0 else { return now > 0 ? "Nothing in the \(data.days) days before" : "Nothing yet" }
        let pct = Int((Double(now - before) / Double(before) * 100).rounded())
        return "\(pct >= 0 ? "↑" : "↓") \(abs(pct))% on the \(data.days) days before"
    }

    // MARK: Derived data

    private var dayPoints: [DayPoint] {
        let cal = Calendar.current
        var plain: [Date: Int] = [:]
        for s in data.plainSessions { plain[cal.startOfDay(for: s.end), default: 0] += s.minutes }
        var tide: [Date: Int] = [:]
        for d in data.tide?.days ?? [] { if let date = TideAPI.date(d.date) { tide[cal.startOfDay(for: date)] = d.minutes } }
        return (0..<data.days).flatMap { i -> [DayPoint] in
            let day = cal.date(byAdding: .day, value: i, to: data.rangeStart)!
            return [DayPoint(date: day, source: "Tide", minutes: tide[day] ?? 0), DayPoint(date: day, source: "Plain", minutes: plain[day] ?? 0)]
        }
    }

    /// Both apps per day, oldest first.
    private var dayTotals: [(Date, Int)] {
        Dictionary(grouping: dayPoints, by: \.date).map { ($0.key, $0.value.reduce(0) { $0 + $1.minutes }) }.sorted { $0.0 < $1.0 }
    }

    private var activeDaysText: String {
        let active = dayTotals.filter { $0.1 > 0 }.count
        return "\(active) of \(data.days) days with study or focus"
    }

    /// Minutes by weekday (Monday first) and hour, from when each session started.
    private var weekHour: [[Int]] {
        var cells = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let cal = Calendar.current
        func add(_ start: Date, _ minutes: Int) {
            let wd = (cal.component(.weekday, from: start) + 5) % 7
            cells[wd][cal.component(.hour, from: start)] += minutes
        }
        for s in data.tideSessions { add(s.start, s.minutes) }
        for s in data.plainSessions { add(s.start, s.minutes) }
        return cells
    }

    private var peakText: String {
        let cells = weekHour
        var best = (0, 0, 0)
        for d in 0..<7 { for h in 0..<24 where cells[d][h] > best.2 { best = (d, h, cells[d][h]) } }
        guard best.2 > 0 else { return "Weekday and hour sessions start" }
        let day = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"][best.0]
        let hour = Calendar.current.date(bySettingHour: best.1, minute: 0, second: 0, of: Date())!.formatted(date: .omitted, time: .shortened)
        return "Most often \(day) around \(hour)"
    }

    private var plainHours: [Int] {
        var h = Array(repeating: 0, count: 24)
        for s in data.plainSessions { h[Calendar.current.component(.hour, from: s.start)] += s.minutes }
        return h
    }

    private var kindSubtitle: String {
        guard let top = data.tide?.activities.max(by: { $0.minutes < $1.minutes }), top.minutes > 0 else { return "Lessons, reading, practice, review, chat, exams" }
        let share = Int(Double(top.minutes) / Double(max(1, tideTotal)) * 100)
        return "Mostly \(TideAPI.label(top.activity).lowercased()): \(share)% of your study"
    }

    private var plainByMode: [(String, Int)] {
        var by: [Category: Int] = [:]
        for s in data.plainSessions { by[s.category, default: 0] += s.minutes }
        return Category.allCases.compactMap { c in by[c].map { (c.label, $0) } }.sorted { $0.1 > $1.1 }
    }

    private var plainModeColors: [String: Color] {
        Dictionary(uniqueKeysWithValues: Category.allCases.map { ($0.label, Theme.color($0)) })
    }

    private var plainTopTitles: [(String, Int)] {
        var by: [String: Int] = [:]
        for s in data.plainSessions { by[s.label, default: 0] += s.minutes }
        return by.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    private var logRows: [LogRow] {
        let plain = data.plainSessions.map { s in
            LogRow(start: s.start, minutes: s.minutes, source: "Plain", kind: s.category.label + (s.rounds.map { " · round \(s.round ?? 1)/\($0)" } ?? ""),
                   title: s.label, color: ChartColor.plain)
        }
        let tide = data.tideSessions.map {
            LogRow(start: $0.start, minutes: $0.minutes, source: "Tide", kind: TideAPI.label($0.activity) + ($0.notebook.map { " · \($0)" } ?? ""),
                   title: $0.label ?? "Study", color: ChartColor.tide)
        }
        return (plain + tide).sorted { $0.start > $1.start }
    }
}

// MARK: - Pieces

private extension View {
    /// A titled card on the dashboard; fills its row's height so pairs line up.
    func card(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TypeScale.heading).foregroundStyle(Theme.text)
                Text(subtitle).font(TypeScale.meta).foregroundStyle(Theme.muted)
            }
            self
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
    }
}

/// Sequential amber steps for heatmaps: one hue, dim to bright, empty cells in the line colour.
enum Heat {
    static func color(_ minutes: Int, peak: Int) -> Color {
        guard minutes > 0, peak > 0 else { return Theme.line }
        let f = Double(minutes) / Double(peak)
        let step = f > 0.75 ? 1.0 : f > 0.5 ? 0.75 : f > 0.25 ? 0.5 : 0.3
        return Theme.accent.opacity(step)
    }

    static func legend() -> some View {
        HStack(spacing: 4) {
            Text("Less").font(Theme.rounded(10)).foregroundStyle(Theme.faint)
            ForEach([0.0, 0.3, 0.5, 0.75, 1.0], id: \.self) { o in
                RoundedRectangle(cornerRadius: 2).fill(o == 0 ? Theme.line : Theme.accent.opacity(o)).frame(width: 10, height: 10)
            }
            Text("More").font(Theme.rounded(10)).foregroundStyle(Theme.faint)
        }
    }
}

/// The range as a pixel calendar: a column per week, Monday at the top.
struct CalendarHeat: View {
    let days: [(Date, Int)]
    let start: Date

    var body: some View {
        let cal = Calendar.current
        let lead = (cal.component(.weekday, from: start) + 5) % 7
        let slots: [(Date, Int)?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        let weeks = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<min($0 + 7, slots.count)]) }
        let peak = days.map(\.1).max() ?? 0
        let cell: CGFloat = weeks.count > 30 ? 11 : weeks.count > 14 ? 14 : 30
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.xl) {
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(Array(["M", "", "W", "", "F", "", "S"].enumerated()), id: \.offset) { _, l in
                        Text(l).font(Theme.rounded(9)).foregroundStyle(Theme.faint).frame(width: 12, height: cell)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { i in
                            if i < week.count, let d = week[i] {
                                RoundedRectangle(cornerRadius: cell > 20 ? 4 : 2).fill(Heat.color(d.1, peak: peak)).frame(width: cell, height: cell)
                                    .overlay {
                                        if cell > 20 {
                                            Text("\(cal.component(.day, from: d.0))").font(Theme.rounded(9, .semibold))
                                                .foregroundStyle(d.1 == 0 ? Theme.faint : Double(d.1) / Double(max(1, peak)) > 0.5 ? Theme.bg : Theme.text)
                                        }
                                    }
                                    .help("\(d.0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(Duration.short(d.1))")
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            weekdays
            }
            Spacer(minLength: 0)
            Heat.legend()
        }
    }
}

extension CalendarHeat {
    /// Total per weekday across the range, Monday first: which days carry the load.
    var weekdays: some View {
        let cal = Calendar.current
        var totals = Array(repeating: 0, count: 7)
        for d in days { totals[(cal.component(.weekday, from: d.0) + 5) % 7] += d.1 }
        let peak = max(1, totals.max() ?? 1)
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let best = totals.firstIndex(of: totals.max() ?? 0) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("BY WEEKDAY").font(Theme.rounded(9, .bold)).foregroundStyle(Theme.faint).kerning(0.5)
            ForEach(0..<7, id: \.self) { i in
                HStack(spacing: Space.s) {
                    Text(names[i]).font(Theme.rounded(11, i == best && totals[i] > 0 ? .bold : .regular))
                        .foregroundStyle(i == best && totals[i] > 0 ? Theme.text : Theme.muted).frame(width: 30, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 2).fill(totals[i] == 0 ? Theme.line : Theme.accent.opacity(i == best ? 1 : 0.55))
                            .frame(width: max(3, g.size.width * CGFloat(totals[i]) / CGFloat(peak)), height: 8).frame(maxHeight: .infinity)
                    }
                    .frame(height: 14)
                    Text(Duration.short(totals[i])).font(Theme.rounded(10)).foregroundStyle(Theme.muted).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Weekday by hour: when sessions start.
struct WeekHourHeat: View {
    let cells: [[Int]]

    var body: some View {
        let peak = cells.flatMap { $0 }.max() ?? 0
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<7, id: \.self) { d in
                    HStack(spacing: 3) {
                        Text(days[d]).font(Theme.rounded(9)).foregroundStyle(Theme.faint).frame(width: 26, alignment: .leading)
                        ForEach(0..<24, id: \.self) { h in
                            RoundedRectangle(cornerRadius: 2).fill(Heat.color(cells[d][h], peak: peak))
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .help("\(days[d]) \(h):00 · \(Duration.short(cells[d][h]))")
                        }
                    }
                }
                HStack(spacing: 3) {
                    Color.clear.frame(width: 26, height: 1)
                    ForEach(0..<24, id: \.self) { h in
                        Text(h % 6 == 0 ? (h == 0 ? "12a" : h == 12 ? "12p" : h < 12 ? "\(h)a" : "\(h - 12)p") : "")
                            .font(Theme.rounded(9)).foregroundStyle(Theme.faint).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
            Heat.legend()
        }
    }
}

/// Apps in front this week, without a card of its own (the dashboard's card holds it).
struct AppRows: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let rows = Array(model.appTotals(week: true).prefix(8))
        let peak = max(1, rows.first?.minutes ?? 1)
        VStack(alignment: .leading, spacing: Space.s) {
            if !model.settings.appTracking { Text("App time is off (Settings).").font(TypeScale.body).foregroundStyle(Theme.faint) }
            else if rows.isEmpty { Text("Nothing yet this week.").font(TypeScale.body).foregroundStyle(Theme.faint) }
            ForEach(rows) { r in
                let tide = r.bundleID == AppWatcher.tideBundleID
                HStack(spacing: Space.m) {
                    Text(r.name).font(TypeScale.body).foregroundStyle(Theme.text).lineLimit(1).frame(width: 140, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(tide ? ChartColor.tide : Theme.muted.opacity(0.6))
                            .frame(width: max(4, g.size.width * CGFloat(r.minutes) / CGFloat(peak)), height: 10).frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text(Duration.short(r.minutes)).font(TypeScale.meta).foregroundStyle(Theme.muted).monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            }
        }
    }
}

struct Tile: View {
    let title: String
    let value: String
    var detail: String = ""
    var dot: Color? = nil
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 6) {
                if let dot { RoundedRectangle(cornerRadius: 2).fill(dot).frame(width: 8, height: 8) }
                Text(title.uppercased()).font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.5)
            }
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.accentDeep) }
                Text(value).font(Theme.rounded(26, .bold)).foregroundStyle(Theme.text).monospacedDigit()
            }
            Text(detail).font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
    }
}

/// Stacked minutes per day, with a hover readout.
struct DayChart: View {
    let points: [DayPoint]
    let days: Int
    @StateObject private var hoverBox = Box<Date?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.l) {
                legend("Tide study", ChartColor.tide)
                legend("Plain focus", ChartColor.plain)
                Spacer()
                Text(readout).font(TypeScale.meta).foregroundStyle(Theme.text).monospacedDigit()
            }
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value("Minutes", p.minutes), width: .ratio(0.72))
                        .foregroundStyle(by: .value("Source", p.source))
                        .cornerRadius(days > 120 ? 1 : 3)
                        .opacity(hoverBox.value == nil || Calendar.current.isDate(p.date, inSameDayAs: hoverBox.value!) ? 1 : 0.45)
                }
            }
            .chartForegroundStyleScale(["Tide": ChartColor.tide, "Plain": ChartColor.plain])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { if let m = v.as(Int.self) { Text(Duration.short(m)).font(TypeScale.meta).foregroundStyle(Theme.faint) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: days <= 7 ? 1 : days <= 31 ? 7 : days <= 90 ? 14 : 60)) { _ in
                    AxisValueLabel(format: days <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                        .font(TypeScale.meta).foregroundStyle(Theme.faint)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                let x = loc.x - geo[proxy.plotFrame!].origin.x
                                hoverBox.value = proxy.value(atX: x, as: Date.self).map { Calendar.current.startOfDay(for: $0) }
                            case .ended: hoverBox.value = nil
                            }
                        }
                }
            }
            .frame(height: 220)
        }
    }

    private var readout: String {
        guard let d = hoverBox.value else {
            let total = points.reduce(0) { $0 + $1.minutes }
            return "\(Duration.short(total)) in all"
        }
        let day = points.filter { Calendar.current.isDate($0.date, inSameDayAs: d) }
        let t = day.first { $0.source == "Tide" }?.minutes ?? 0, p = day.first { $0.source == "Plain" }?.minutes ?? 0
        return "\(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · Tide \(Duration.short(t)) · Plain \(Duration.short(p)) · \(Duration.short(t + p))"
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(TypeScale.meta).foregroundStyle(Theme.muted)
        }
    }
}

/// Minutes started in each hour, Tide and Plain stacked.
struct HourChart: View {
    let tide: [Int]
    let plain: [Int]
    /// Off when only one app is drawn (the card's title names it).
    var legend = true

    var body: some View {
        Chart {
            ForEach(0..<24, id: \.self) { h in
                BarMark(x: .value("Hour", h), y: .value("Minutes", tide[safe: h] ?? 0), width: .fixed(11))
                    .foregroundStyle(by: .value("Source", "Tide")).cornerRadius(2)
                BarMark(x: .value("Hour", h), y: .value("Minutes", plain[safe: h] ?? 0), width: .fixed(11))
                    .foregroundStyle(by: .value("Source", "Plain")).cornerRadius(2)
            }
        }
        .chartForegroundStyleScale(["Tide": ChartColor.tide, "Plain": ChartColor.plain])
        .chartLegend(legend ? .visible : .hidden)
        .chartLegend(position: .top, alignment: .leading)
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { v in
                AxisValueLabel { if let h = v.as(Int.self) { Text(h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p").font(TypeScale.meta).foregroundStyle(Theme.faint) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { if let m = v.as(Int.self) { Text(Duration.short(m)).font(TypeScale.meta).foregroundStyle(Theme.faint) } }
            }
        }
        .frame(height: 190)
    }
}

/// Tide's kinds of study as labelled bars.
struct KindBars: View {
    let rows: [TideAPI.Summary.ActivityRow]

    var body: some View {
        let shown = rows.filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }
        let peak = max(1, shown.first?.minutes ?? 1)
        let total = max(1, shown.reduce(0) { $0 + $1.minutes })
        VStack(alignment: .leading, spacing: Space.s) {
            if shown.isEmpty { Text("No Tide study in this range.").font(TypeScale.body).foregroundStyle(Theme.faint) }
            ForEach(shown) { r in
                HStack(spacing: Space.m) {
                    Text(TideAPI.label(r.activity)).font(TypeScale.body).foregroundStyle(Theme.text).frame(width: 78, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(ChartColor.activity(r.activity))
                            .frame(width: max(4, g.size.width * CGFloat(r.minutes) / CGFloat(peak)), height: 12)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text("\(Duration.short(r.minutes)) · \(r.minutes * 100 / total)%").font(TypeScale.meta).foregroundStyle(Theme.muted)
                        .monospacedDigit().frame(width: 84, alignment: .trailing)
                    Text("\(r.sessions)×").font(TypeScale.meta).foregroundStyle(Theme.faint).frame(width: 30, alignment: .trailing)
                }
                .help("\(TideAPI.label(r.activity)): \(r.minutes) min over \(r.sessions) sessions")
            }
        }
    }
}

/// Name, bar, minutes: notebooks, topics, modes and titles.
struct RankedList: View {
    let rows: [(String, Int)]
    var color: Color
    var empty: String
    var colors: [String: Color] = [:]

    var body: some View {
        let peak = max(1, rows.map(\.1).max() ?? 1)
        VStack(alignment: .leading, spacing: Space.s) {
            if rows.isEmpty { Text(empty).font(TypeScale.body).foregroundStyle(Theme.faint) }
            ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { _, r in
                HStack(spacing: Space.m) {
                    Text(r.0).font(TypeScale.body).foregroundStyle(Theme.text).lineLimit(1).frame(width: 170, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(colors[r.0] ?? color)
                            .frame(width: max(4, g.size.width * CGFloat(r.1) / CGFloat(peak)), height: 10)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text(Duration.short(r.1)).font(TypeScale.meta).foregroundStyle(Theme.muted).monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                .help("\(r.0): \(r.1) min")
            }
        }
    }
}

/// Answers and flashcards from Tide.
struct PerformanceCard: View {
    let summary: TideAPI.Summary?

    var body: some View {
        let a = summary?.answers ?? .init(), f = summary?.flashcards ?? .init()
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.xl) {
                stat("Accuracy", a.total > 0 ? "\(a.right * 100 / a.total)%" : "–", a.total > 0 ? "\(a.total) answers" : "No answers yet")
                stat("Avg score", a.averageScore.map { "\(Int(($0 * 100).rounded()))" } ?? "–", "out of 100")
                stat("Cards", "\(f.reviewed)", "reviewed")
            }
            split("Answers", [("Right", a.right, Theme.good), ("Partly", a.partly, Theme.accent), ("Wrong", a.wrong, Theme.color(.exam))])
            split("Flashcards", [("Again", f.again, Theme.color(.exam)), ("Hard", f.hard, Theme.accent), ("Good", f.good, Theme.good), ("Easy", f.easy, Theme.study)])
            AccuracyTrend(days: summary?.days ?? [])
        }
    }

    private func stat(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.5)
            Text(value).font(Theme.rounded(22, .bold)).foregroundStyle(Theme.text).monospacedDigit()
            Text(detail).font(TypeScale.meta).foregroundStyle(Theme.muted)
        }
    }

    /// One bar split into labelled parts (2px gaps), with counts written out so colour isn't the only cue.
    /// Status colours (right/wrong, again/easy) with the counts written beside them.
    private func split(_ title: String, _ parts: [(String, Int, Color)]) -> some View {
        let total = parts.reduce(0) { $0 + $1.1 }
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(TypeScale.meta).foregroundStyle(Theme.muted)
            if total == 0 {
                RoundedRectangle(cornerRadius: 3).fill(Theme.line).frame(height: 10)
            } else {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                            if p.1 > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(p.2)
                                    .frame(width: max(3, (g.size.width - CGFloat(parts.count * 2)) * CGFloat(p.1) / CGFloat(total)))
                                    .help("\(p.0): \(p.1)")
                            }
                        }
                    }
                }
                .frame(height: 10)
            }
            HStack(spacing: Space.m) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(p.2).frame(width: 8, height: 8)
                        Text("\(p.0) \(p.1)").font(TypeScale.meta).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}

/// Share of answers right, per day that had answers.
struct AccuracyTrend: View {
    let days: [TideAPI.Summary.Day]

    var body: some View {
        let pts = days.compactMap { d -> (Date, Double)? in
            guard let a = d.accuracy, let date = TideAPI.date(d.date) else { return nil }
            return (date, a * 100)
        }
        if pts.count >= 2 {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Accuracy by day").font(TypeScale.meta).foregroundStyle(Theme.muted)
                Chart {
                    ForEach(pts, id: \.0) { p in
                        LineMark(x: .value("Day", p.0, unit: .day), y: .value("Accuracy", p.1))
                            .foregroundStyle(ChartColor.series[2]).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Day", p.0, unit: .day), y: .value("Accuracy", p.1))
                            .foregroundStyle(ChartColor.series[2]).symbolSize(36)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)%").font(TypeScale.meta).foregroundStyle(Theme.faint) } }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(TypeScale.meta).foregroundStyle(Theme.faint) }
                }
                .frame(height: 110)
            }
        }
    }
}

/// Plain and Tide sessions, one list, newest first.
struct SessionLog: View {
    let rows: [LogRow]
    @StateObject private var allBox = Box(false)

    var body: some View {
        let shown = allBox.value ? rows : Array(rows.prefix(14))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                col("When", 150); col("App", 60); col("Kind", 190); Text("What").frame(maxWidth: .infinity, alignment: .leading); col("Time", 60, trailing: true)
            }
            .font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint)
            .padding(.bottom, Space.s)
            if rows.isEmpty { Text("No sessions in this range.").font(TypeScale.body).foregroundStyle(Theme.faint).padding(.vertical, Space.s) }
            ForEach(shown) { r in
                HStack(spacing: Space.m) {
                    Text(r.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .frame(width: 150, alignment: .leading).foregroundStyle(Theme.muted)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(r.color).frame(width: 8, height: 8)
                        Text(r.source).foregroundStyle(Theme.text)
                    }
                    .frame(width: 60, alignment: .leading)
                    Text(r.kind).lineLimit(1).frame(width: 190, alignment: .leading).foregroundStyle(Theme.muted)
                    Text(r.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.text)
                    Text(Duration.short(r.minutes)).monospacedDigit().frame(width: 60, alignment: .trailing).foregroundStyle(Theme.text)
                }
                .font(TypeScale.body)
                .padding(.vertical, 6)
                Divider().overlay(Theme.line)
            }
            if rows.count > 14 {
                Button(allBox.value ? "Show fewer" : "Show all \(rows.count)") { allBox.value.toggle() }
                    .buttonStyle(.plain).font(TypeScale.meta).foregroundStyle(Theme.accent).padding(.top, Space.s)
            }
        }
    }

    private func col(_ t: String, _ w: CGFloat, trailing: Bool = false) -> some View {
        Text(t).frame(width: w, alignment: trailing ? .trailing : .leading)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
