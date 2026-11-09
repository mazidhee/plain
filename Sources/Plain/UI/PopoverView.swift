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

/// Study time Tide logged itself (read from Tide, never written).
struct TideCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "water.waves").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.study)
            VStack(alignment: .leading, spacing: 2) {
                if model.tide.available {
                    Text("Studied in Tide today: \(Duration.short(model.tide.todayMinutes))").font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.text)
                    Text("This week \(Duration.short(model.tide.weekMinutes))\(model.tide.lastLabel.map { " · last: \($0)" } ?? "")")
                        .font(Theme.rounded(11)).foregroundStyle(Theme.muted).lineLimit(1)
                } else {
                    Text("Tide study time").font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.text)
                    Text(model.tide.problem ?? "Not found.").font(Theme.rounded(11)).foregroundStyle(Theme.faint)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.study.opacity(0.14)))
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
