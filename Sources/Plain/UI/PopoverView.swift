import SwiftUI

// MARK: - Stats

struct StatsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let s = model.stats
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statCard("Today", Duration.short(s.todayMinutes))
                statCard("This week", Duration.short(s.weekMinutes))
                statCard("Streak", "\(s.streakDays) day\(s.streakDays == 1 ? "" : "s")", icon: "flame.fill")
            }
            WeekBars(days: s.weekDays)
            TideCard(model: model)
            AppTimeList(model: model)
            FlowRow(spacing: 10) {
                ForEach(Category.allCases) { c in
                    let m = s.weekByCategory[c] ?? 0
                    HStack(spacing: 4) {
                        Rectangle().fill(Theme.color(c)).frame(width: 7, height: 7)
                        Text("\(c.label) \(Duration.short(m))").font(Theme.rounded(10)).foregroundStyle(m > 0 ? Theme.muted : Theme.faint)
                    }
                }
            }
            Text("RECENT").font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.6)
            if s.recent.isEmpty {
                Text("No sessions yet. Wren is waiting.").font(Theme.rounded(12)).foregroundStyle(Theme.faint)
            }
            ForEach(s.recent) { r in
                HStack {
                    Image(systemName: r.category.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.color(r.category)).frame(width: 18)
                    Text(r.label).font(Theme.rounded(12)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    Text(r.end.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(Theme.rounded(10)).foregroundStyle(Theme.faint)
                    Text("\(r.minutes)m").font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.color(r.category)).frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private func statCard(_ title: String, _ value: String, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(Theme.rounded(9, .bold)).foregroundStyle(Theme.faint).kerning(0.5)
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).foregroundStyle(Theme.accentDeep).font(.system(size: 12)) }
                Text(value).font(Theme.rounded(17, .bold)).foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
    }
}

/// Tide's study time: headline numbers, the last two weeks and what kind of studying it was.
/// From Tide's study data API when a token is set (Settings), else its log file. Never written.
struct TideCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Image(systemName: "water.waves").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.study)
                Text("Tide").font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.text)
                Text(model.tide.fromAPI ? "live" : "log file").font(Theme.rounded(9, .bold)).foregroundStyle(Theme.faint)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Theme.line))
                    .help(model.tide.fromAPI ? "From Tide's study data API" : "From Tide's log file. Add the API token in Settings for the full picture.")
                Spacer()
                Button { model.onOpenDashboard?() } label: {
                    Label("Dashboard", systemImage: "rectangle.3.group").font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(PressableStyle())
                .help("Every number, chart and session in a window")
            }
            if model.tide.available {
                HStack(spacing: Space.l) {
                    number("Today", Duration.short(model.tide.todayMinutes))
                    number("Week", Duration.short(model.tide.weekMinutes))
                    if let streak = model.tide.streak { number("Streak", "\(streak)d") }
                    if let s = model.tideSummary { number("30 days", Duration.short(s.totals.inRange)) }
                }
                if let now = model.tide.studyingNow {
                    Label("Studying now: \(now)", systemImage: "dot.radiowaves.left.and.right").font(TypeScale.meta).foregroundStyle(Theme.study).lineLimit(1)
                } else if let last = model.tide.lastLabel {
                    Text("Last: \(last)").font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if let s = model.tideSummary {
                    fortnight(s.days.suffix(14))
                    kinds(s.activities)
                }
            } else {
                Text(model.tide.problem ?? "Not found.").font(Theme.rounded(11)).foregroundStyle(Theme.faint)
            }
            if let why = model.tideAPIProblem {
                Text(why).font(Theme.rounded(10)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.study.opacity(0.10)))
    }

    private func number(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(Theme.rounded(9, .bold)).foregroundStyle(Theme.faint).kerning(0.5)
            Text(value).font(Theme.rounded(15, .bold)).foregroundStyle(Theme.text).monospacedDigit()
        }
    }

    /// The last 14 days as thin bars, today brightest.
    private func fortnight(_ days: ArraySlice<TideAPI.Summary.Day>) -> some View {
        let peak = max(30, days.map(\.minutes).max() ?? 0)
        let list = Array(days)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(list.indices, id: \.self) { i in
                let d = list[i]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(d.minutes == 0 ? Theme.line : (i == list.count - 1 ? Theme.study : Theme.study.opacity(0.6)))
                    .frame(height: d.minutes == 0 ? 2 : max(3, 34 * CGFloat(d.minutes) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
                    .help("\(TideAPI.date(d.date)?.formatted(.dateTime.weekday(.abbreviated).day()) ?? d.date): \(Duration.short(d.minutes))\(d.cards > 0 ? " · \(d.cards) cards" : "")")
            }
        }
        .frame(height: 34, alignment: .bottom)
    }

    /// One bar split by kind of study, labelled underneath.
    private func kinds(_ rows: [TideAPI.Summary.ActivityRow]) -> some View {
        let shown = rows.filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }
        let total = max(1, shown.reduce(0) { $0 + $1.minutes })
        return VStack(alignment: .leading, spacing: 5) {
            if !shown.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(shown) { r in
                            RoundedRectangle(cornerRadius: 2).fill(ChartColor.activity(r.activity))
                                .frame(width: max(3, (g.size.width - CGFloat(shown.count * 2)) * CGFloat(r.minutes) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 6)
                FlowRow(spacing: 8) {
                    ForEach(shown) { r in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5).fill(ChartColor.activity(r.activity)).frame(width: 7, height: 7)
                            Text("\(TideAPI.label(r.activity)) \(Duration.short(r.minutes))").font(Theme.rounded(10)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }
}

/// Time per app in front, today or this week. Tide is highlighted.
struct AppTimeList: View {
    @ObservedObject var model: AppModel
    @StateObject private var weekBox = Box(false)
    private var week: Bool { get { weekBox.value } nonmutating set { weekBox.value = newValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("APPS IN FRONT").font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.6)
                Spacer()
                Button(week ? "This week" : "Today") { week.toggle() }.buttonStyle(.plain)
                    .font(Theme.rounded(10, .semibold)).foregroundStyle(Theme.accent)
            }
            if !model.settings.appTracking {
                Text("App time is off (Settings).").font(Theme.rounded(11)).foregroundStyle(Theme.faint)
            } else {
                let rows = Array(model.appTotals(week: week).prefix(7))
                let peak = max(1, rows.first?.minutes ?? 1)
                if rows.isEmpty { Text("Nothing yet.").font(Theme.rounded(11)).foregroundStyle(Theme.faint) }
                ForEach(rows) { r in
                    let tide = r.bundleID == AppWatcher.tideBundleID
                    HStack(spacing: 8) {
                        Text(r.name).font(Theme.rounded(12, tide ? .bold : .regular)).foregroundStyle(tide ? Theme.study : Theme.text)
                            .lineLimit(1).frame(width: 110, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(tide ? Theme.study : Theme.accent.opacity(0.55))
                                .frame(width: max(3, g.size.width * CGFloat(r.minutes) / CGFloat(peak)), height: 6)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                        Text(Duration.short(r.minutes)).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.muted).frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
    }
}

struct WeekBars: View {
    let days: [Int]
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let peak = max(60, days.max() ?? 0)
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    // Stacked pixel blocks, one per ~10%.
                    let blocks = days[i] == 0 ? 0 : max(1, Int((Double(days[i]) / Double(peak) * 8).rounded()))
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        ForEach(0..<blocks, id: \.self) { _ in
                            Rectangle().fill(i == today ? Theme.accent : Theme.accent.opacity(0.55)).frame(height: 6)
                        }
                    }
                    .frame(height: 64)
                    Text(labels[i]).font(Theme.rounded(10, i == today ? .bold : .regular)).foregroundStyle(i == today ? Theme.text : Theme.faint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
    }
}

// MARK: - Sound

struct SoundPane: View {
    @ObservedObject var sound: SoundController
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MUSIC · SOMAFM").font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.6)
                Spacer()
                if sound.musicOn && !sound.status.isEmpty {
                    Text(sound.status).font(Theme.rounded(10)).foregroundStyle(Theme.good)
                }
                RoundButton(symbol: sound.musicOn ? "pause.fill" : "play.fill", size: 26) { sound.toggleMusic() }
                    .help(sound.musicOn ? "Pause the music" : "Play the music")
                RoundButton(symbol: "forward.end.fill", size: 26) { sound.nextStation() }.help("Next station")
            }
            ForEach(Station.genres, id: \.self) { genre in
                VStack(alignment: .leading, spacing: 4) {
                    Text(genre).font(Theme.rounded(10, .semibold)).foregroundStyle(Theme.muted)
                    FlowRow(spacing: 5) {
                        ForEach(Station.all.filter { $0.genre == genre }) { st in
                            Chip(label: st.name, selected: sound.station == st.id) {
                                sound.station = sound.station == st.id ? nil : st.id
                            }
                            .help(st.blurb)
                        }
                    }
                }
            }
            volume("Music", value: $sound.musicVolume, disabled: sound.station == nil)
            Divider().overlay(Theme.line)
            Text("AMBIENCE").font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.6)
            FlowRow(spacing: 5) {
                Chip(label: "None", selected: sound.ambience == nil) { sound.ambience = nil }
                ForEach(NoiseKind.nature) { k in
                    Chip(label: k.label, selected: sound.ambience == k, tint: Theme.good) { sound.ambience = k }
                }
                ForEach(NoiseKind.noises) { k in
                    Chip(label: k.label, selected: sound.ambience == k) { sound.ambience = k }
                }
            }
            volume("Ambience", value: $sound.ambienceVolume, disabled: sound.ambience == nil)
            HStack {
                Toggle(isOn: $model.settings.autoSound) {
                    Text("Fade in with sessions, out at the end").font(Theme.rounded(11)).foregroundStyle(Theme.muted)
                }
                .toggleStyle(.switch).controlSize(.mini)
                Spacer()
                RoundButton(symbol: sound.isPlaying ? "speaker.slash.fill" : "speaker.wave.2.fill", label: sound.isPlaying ? "Stop all" : "Play now", size: 26) { sound.toggle() }
                    .disabled(!sound.hasAnything)
            }
        }
    }

    private func volume(_ label: String, value: Binding<Double>, disabled: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.rounded(11)).foregroundStyle(Theme.muted).frame(width: 64, alignment: .leading)
            Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(Theme.faint)
            Slider(value: value, in: 0...1).controlSize(.mini).tint(Theme.accent)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundStyle(Theme.faint)
        }
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }
}

/// Compact play/pause, next and music volume; used by the island and Settings.
struct SoundBar: View {
    @ObservedObject var sound: SoundController
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Button { sound.toggleMusic() } label: {
                Image(systemName: sound.musicOn ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: compact ? 14 : 17))
                    .foregroundStyle(sound.musicOn ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.plain)
            Button { sound.nextStation() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: compact ? 10 : 12)).foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            if !compact {
                Text(sound.summary).font(Theme.rounded(11)).foregroundStyle(Theme.muted).lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
            Slider(value: $sound.musicVolume, in: 0...1).controlSize(.mini).tint(Theme.accent)
        }
    }
}

/// The Tide question or the editor nudge, when the island is off.
struct PromptCard: View {
    @ObservedObject var model: AppModel
    let prompt: IslandPrompt

    var body: some View {
        Group {
            switch prompt {
            case .tide:
                TidePrompt(model: model).padding(.bottom, 10)
            case .editor(let name):
                HStack(spacing: 8) {
                    Text("Deep in \(name)? Make it a session.").font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Chip(label: "25 min", selected: true) { model.start(SessionPlan(title: "", category: .work, minutes: 25)) }
                    Chip(label: "50 min") { model.start(SessionPlan(title: "", category: .work, minutes: 50)) }
                    Button { model.prompt = nil } label: { Image(systemName: "xmark").foregroundStyle(Theme.faint) }.buttonStyle(.plain)
                }
                .padding(10)
            }
        }
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }
}
