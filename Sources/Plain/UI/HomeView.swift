import SwiftUI

// Layout tokens: one spacing scale (4/8/12/16/24), three radii, one type scale.
enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24 }
enum Radius { static let card: CGFloat = 14, control: CGFloat = 10, button: CGFloat = 12 }
enum TypeScale {
    static let title = Theme.rounded(20, .semibold)
    static let heading = Theme.rounded(15, .semibold)
    static let body = Theme.rounded(13)
    static let bodyStrong = Theme.rounded(13, .semibold)
    static let meta = Theme.rounded(11)
}

extension Category {
    /// One drawn icon per mode.
    var symbol: String {
        switch self {
        case .work: return "laptopcomputer"
        case .study: return "book.closed.fill"
        case .exam: return "pencil.and.list.clipboard"
        case .reading: return "books.vertical.fill"
        case .chilling: return "headphones"
        }
    }
}

enum PopoverRoute: Equatable { case home, stats, sound }

/// Everything under the menu bar icon: a small scene, then home, the running screen or the summary.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @StateObject private var routeBox: Box<PopoverRoute>
    private var route: PopoverRoute { get { routeBox.value } nonmutating set { routeBox.value = newValue } }
    @StateObject private var menuBox: Box<Bool>
    private var menuOpen: Bool { get { menuBox.value } nonmutating set { menuBox.value = newValue } }
    var openSettings: () -> Void

    init(model: AppModel, route: PopoverRoute = .home, menuOpen: Bool = false, openSettings: @escaping () -> Void = {}) {
        self.model = model
        _routeBox = StateObject(wrappedValue: Box(route))
        _menuBox = StateObject(wrappedValue: Box(menuOpen))
        self.openSettings = openSettings
    }

    private var screenKey: String {
        route != .home ? "\(route)" : (model.phase == .idle ? "home" : model.phase == .summary ? "summary" : "running")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            RoomView(model: model, height: model.phase == .idle && route == .home ? 136 : 168)
            ZStack(alignment: .topLeading) {
                Group {
                    switch route {
                    case .stats: SubPage(title: "Stats", back: { route = .home }) { StatsPane(model: model) }
                    case .sound: SubPage(title: "Sound", back: { route = .home }) { SoundPane(sound: model.sound, model: model) }
                    case .home:
                        switch model.phase {
                        case .idle: HomePane(model: model, menuOpen: $menuBox.value, go: { route = $0 }, openSettings: openSettings)
                        case .focus, .breakTime: RunningScreen(model: model)
                        case .summary: SummaryScreen(model: model)
                        }
                    }
                }
                .id(screenKey)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                if menuOpen && route == .home && model.phase == .idle {
                    Color.black.opacity(0.001).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { menuOpen = false }
                    ModeMenu(model: model) { menuOpen = false }
                        .padding(.top, 36)
                        .transition(.scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
        .padding(Space.l)
        .frame(width: 368)
        .background(Theme.bg)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: screenKey)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: menuOpen)
        .onAppear { model.refreshTasks() }
    }
}

/// Stats and Sound: a quiet back row, then the pane.
struct SubPage<Content: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button(action: back) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text(title).font(TypeScale.title)
                }
                .foregroundStyle(Theme.text)
            }
            .buttonStyle(PressableStyle())
            content
        }
    }
}

// MARK: - Scene

/// The room with Wren, clipped to a small, atmospheric strip on the home screen.
struct RoomView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var animator = Animator.shared
    var height: CGFloat = 168
    var pixel: CGFloat = 3.5
    var period: DayPeriod? = nil
    var scene: SceneKind? = nil

    var body: some View {
        let p = period ?? DayPeriod.at(model.now)
        let grid = RoomScene.frame(activity: model.activity, tick: animator.frameTick, period: p,
                                   musicPlaying: model.sound.musicOn, scene: scene ?? model.scene)
        PixelView(grid: grid, palette: RoomScene.palette(p), pixel: pixel)
            .frame(width: 336, height: height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) { sceneButton.padding(Space.s) }
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(.white.opacity(0.06)))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: height)
    }

    private var sceneButton: some View {
        Menu {
            ForEach(SceneKind.allCases) { k in
                Button { model.settings.scene = k.rawValue } label: {
                    if model.settings.scene == k.rawValue { Label(k == .auto ? "Auto · \(model.scene.label)" : k.label, systemImage: "checkmark") }
                    else { Text(k == .auto ? "Auto (follows what you're doing)" : k.label) }
                }
            }
        } label: {
            Image(systemName: "photo").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 26)
        .background(Circle().fill(.black.opacity(0.35)))
        .help("Scene: \(model.scene.label)")
    }
}

// MARK: - Home

struct HomePane: View {
    @ObservedObject var model: AppModel
    @Binding var menuOpen: Bool
    var go: (PopoverRoute) -> Void
    var openSettings: () -> Void
    @StateObject private var customBox = Box(false)
    private var custom: Bool { get { customBox.value } nonmutating set { customBox.value = newValue } }

    private var accent: Color { Theme.color(model.draftCategory) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            if let prompt = model.prompt { PromptCard(model: model, prompt: prompt) }
            if let mood = model.tideMood { tideBanner(mood) }
            VStack(alignment: .leading, spacing: Space.s) {
                if model.draftCategory != .chilling || model.selectedTask != nil { NextUpRow(model: model) }
                primaryButton
            }
            options
            SearchBox(model: model)
            footer
        }
    }

    // Mode switcher plus quiet navigation.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Space.s) {
                Button { menuOpen.toggle() } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: model.draftCategory.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                        Text(model.draftCategory.label).font(TypeScale.title).foregroundStyle(Theme.text)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(menuOpen ? 180 : 0))
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("Switch mode")
                Spacer()
                IconButton(symbol: "chart.bar.fill", help: "Stats") { go(.stats) }
                IconButton(symbol: model.sound.isPlaying ? "speaker.wave.2.fill" : "music.note", tint: model.sound.isPlaying ? accent : nil, help: "Sound") { go(.sound) }
                IconButton(symbol: "gearshape.fill", help: "Settings", action: openSettings)
            }
            Text(todayLine).font(TypeScale.meta).foregroundStyle(Theme.muted)
        }
    }

    private var todayLine: String {
        var parts: [String] = []
        parts.append(model.stats.todayMinutes > 0 ? "\(Duration.short(model.stats.todayMinutes)) focused today" : "Nothing focused yet today")
        if model.tide.available && model.tide.todayMinutes > 0 { parts.append("Tide \(Duration.short(model.tide.todayMinutes))") }
        if let area = model.draftArea { parts.append("from \(area)") }
        return parts.joined(separator: " · ")
    }

    private var primaryButton: some View {
        Button(action: model.startPrimary) {
            HStack(spacing: Space.s) {
                Image(systemName: model.selectedTask != nil ? "play.fill" : (model.draftCategory == .chilling ? "headphones" : "bolt.fill")).font(.system(size: 13, weight: .bold))
                Text(primaryLabel).font(Theme.rounded(15, .bold))
                Spacer(minLength: 0)
                Text("↩").font(TypeScale.meta).opacity(0.55)
            }
            .foregroundStyle(Theme.bg)
            .padding(.horizontal, Space.l)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(accent))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .keyboardShortcut(.defaultAction)
    }

    private var primaryLabel: String {
        let verb = model.selectedTask != nil ? "Start" : (model.draftCategory == .chilling ? "Chill" : "Lock in")
        if model.draftUseRange {
            let (from, to) = ScheduledBlock.resolve(from: model.draftFrom, to: model.draftTo, now: Date())
            let t = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
            return from > Date().addingTimeInterval(30) ? "Book \(t(from))–\(t(to))" : "\(verb) until \(t(to))"
        }
        if model.draftCountUp { return "\(verb) · count up" }
        return "\(verb) · \(model.draftMinutes) min"
    }

    // Length, count-up and time block: secondary, quiet until chosen.
    private var options: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                // Length: one segmented group, so it reads as a single choice.
                HStack(spacing: 2) {
                    ForEach(model.settings.durations, id: \.self) { m in
                        Segment(label: "\(m)", selected: !custom && !model.draftCountUp && !model.draftUseRange && model.draftMinutes == m, accent: accent) {
                            custom = false; model.draftCountUp = false; model.draftUseRange = false; model.draftMinutes = m
                        }
                    }
                    Segment(label: custom ? "\(model.draftMinutes)′" : "···", selected: custom && !model.draftCountUp && !model.draftUseRange, accent: accent) {
                        custom = true; model.draftCountUp = false; model.draftUseRange = false
                    }
                    .help("Custom length")
                }
                .padding(2)
                .background(Capsule().fill(Theme.card))
                Text("min").font(TypeScale.meta).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                OptionChip(label: "Up", symbol: "arrow.up", selected: model.draftCountUp, accent: accent) {
                    model.draftCountUp.toggle(); if model.draftCountUp { model.draftUseRange = false; custom = false }
                }
                .help("Count up: no timer, stops when you stop it")
                OptionChip(label: "Block", symbol: "clock", selected: model.draftUseRange, accent: accent) {
                    model.draftUseRange.toggle()
                    if model.draftUseRange {
                        model.draftCountUp = false; custom = false
                        model.draftFrom = Date(); model.draftTo = Date().addingTimeInterval(2 * 3600)
                    }
                }
                .help("Time block: from one time to another")
            }
            if custom && !model.draftCountUp && !model.draftUseRange {
                HStack(spacing: Space.s) {
                    Text("Length").font(TypeScale.body).foregroundStyle(Theme.muted)
                    Stepper("\(model.draftMinutes) min", value: $model.draftMinutes, in: 5...240, step: 5)
                        .font(TypeScale.body).foregroundStyle(Theme.text)
                }
            }
            if model.draftUseRange {
                HStack(spacing: Space.s) {
                    Text("From").font(TypeScale.body).foregroundStyle(Theme.muted)
                    DatePicker("", selection: $model.draftFrom, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                    Text("to").font(TypeScale.body).foregroundStyle(Theme.muted)
                    DatePicker("", selection: $model.draftTo, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                }
            }
            if let block = model.scheduled {
                HStack(spacing: Space.s) {
                    Image(systemName: "alarm.fill").foregroundStyle(accent)
                    Text("\(block.title.isEmpty ? "\(block.category.label) · Lock in" : block.title)  \(block.start.formatted(date: .omitted, time: .shortened))–\(block.end.formatted(date: .omitted, time: .shortened))")
                        .font(TypeScale.body).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    IconButton(symbol: "xmark", help: "Cancel the booking") { model.setScheduled(nil) }
                }
            }
        }
    }

    private func tideBanner(_ mood: Activity) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: mood == .exam ? "pencil.and.list.clipboard" : "book.closed.fill").foregroundStyle(Theme.study)
            VStack(alignment: .leading, spacing: 2) {
                Text(mood == .exam ? "Exam practice in Tide" : "Studying in Tide").font(TypeScale.bodyStrong).foregroundStyle(Theme.text)
                Text("Tide is tracking this · today \(Duration.short(model.tide.todayMinutes))").font(TypeScale.meta).foregroundStyle(Theme.muted)
            }
            Spacer()
            IconButton(symbol: "xmark", help: "Done studying") { model.tideMood = nil }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Theme.study.opacity(0.12)))
    }

    private var footer: some View {
        HStack(spacing: Space.s) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1)
            Spacer()
            Toggle(isOn: $model.settings.breaksEnabled) { Text("Breaks").font(TypeScale.meta).foregroundStyle(Theme.muted) }
                .toggleStyle(.switch).controlSize(.mini).tint(accent)
                .help("Pomodoro breaks after each block")
        }
    }

    private var statusColor: Color {
        if case .connected = model.thingsStatus { return Theme.good }
        return Theme.muted.opacity(0.6)
    }

    private var statusText: String {
        let queued = model.pendingLogs > 0 ? " · \(model.pendingLogs) waiting" : ""
        switch model.thingsStatus {
        case .connected: return "Things connected\(queued)"
        case .offline: return "Things isn't running\(queued)"
        case .unknown: return "Looking for Things…"
        }
    }
}

/// The next to-do for this mode. Tap to aim the primary button at it; tap again for Lock in.
struct NextUpRow: View {
    @ObservedObject var model: AppModel
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        let tasks = model.draftArea != nil && !model.pickerShowsToday ? model.areaTasks : model.todayTasks
        let accent = Theme.color(model.draftCategory)
        if let picked = model.selectedTask {
            row(picked, index: nil, count: nil, selected: true, accent: accent)
        } else if !tasks.isEmpty {
            let i = min(max(0, model.nextIndex), tasks.count - 1)
            row(tasks[i], index: i, count: tasks.count, selected: false, accent: accent)
        }
    }

    private func row(_ task: ThingsTask, index: Int?, count: Int?, selected: Bool, accent: Color) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16)).foregroundStyle(selected ? accent : Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(TypeScale.bodyStrong).foregroundStyle(Theme.text).lineLimit(1)
                Text(meta(task, index: index, count: count, selected: selected)).font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            if let count, let index, count > 1 {
                IconButton(symbol: "arrow.right", help: "Next to-do") { model.nextIndex = (index + 1) % count }
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(selected ? accent.opacity(0.14) : (hover ? Theme.cardHi : Theme.card))
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(selected ? accent.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.pick(selected ? nil : task) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(selected ? "Picked. Tap to Lock in without a to-do instead" : "Tap to focus on this to-do")
    }

    private func meta(_ t: ThingsTask, index: Int?, count: Int?, selected: Bool) -> String {
        var parts: [String] = []
        if selected { parts.append("Focusing on this") }
        else if let area = model.draftArea, !model.pickerShowsToday { parts.append("Next in \(area)") } else { parts.append("Next today") }
        if t.trackedMinutes > 0 { parts.append("\(Duration.short(t.trackedMinutes)) so far") }
        if let index, let count, count > 1 { parts.append("\(index + 1)/\(count)") }
        return parts.joined(separator: " · ")
    }
}

/// Search all of Things, or type something new and press return.
struct SearchBox: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        let typing = model.draftTitle.trimmingCharacters(in: .whitespaces).count >= 2
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                TextField("", text: $model.draftTitle, prompt: Text("Search Things, or type a new task").foregroundColor(Theme.muted.opacity(0.8)))
                    .textFieldStyle(.plain).font(TypeScale.body).foregroundStyle(Theme.text)
                    .focused($focused)
                    .onChange(of: model.draftTitle) { _, q in model.search(q) }
                    .onSubmit {
                        if let first = model.searchResults.first, typing { model.pick(first); model.draftTitle = "" }
                        else if !model.draftTitle.isEmpty { model.startFromDraft() }
                    }
                if !model.draftTitle.isEmpty {
                    IconButton(symbol: "xmark.circle.fill", help: "Clear") { model.draftTitle = "" }
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(focused ? Theme.color(model.draftCategory).opacity(0.6) : .clear))
            if typing {
                if model.searchResults.isEmpty {
                    Text("No to-do matches. Press return to focus on “\(model.draftTitle)”.")
                        .font(TypeScale.meta).foregroundStyle(Theme.muted).padding(.horizontal, Space.m).padding(.top, Space.xs)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.searchResults.prefix(5)) { t in
                            ResultRow(task: t) { model.pick(t); model.draftTitle = "" }
                        }
                    }
                }
            }
        }
    }
}

struct ResultRow: View {
    let task: ThingsTask
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).font(TypeScale.body).foregroundStyle(Theme.text).lineLimit(1)
                    let place = [task.context, task.area != task.context ? task.area : nil].compactMap { $0 }.joined(separator: " · ")
                    if !place.isEmpty { Text(place).font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1) }
                }
                Spacer()
                if task.trackedMinutes > 0 { Text(Duration.short(task.trackedMinutes)).font(TypeScale.meta).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Radius.control - 2, style: .continuous).fill(hover ? Theme.cardHi : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .onHover { hover = $0 }
    }
}

/// The mode dropdown: icon, name, where its to-dos come from, time today.
struct ModeMenu: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Category.allCases) { c in
                ModeMenuRow(model: model, category: c) {
                    model.draftCategory = c
                    model.selectedTask = nil
                    close()
                }
            }
        }
        .padding(Space.xs)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(Color(hex: 0x2E241F)))
        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(.white.opacity(0.07)))
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
    }
}

struct ModeMenuRow: View {
    @ObservedObject var model: AppModel
    let category: Category
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        let accent = Theme.color(category)
        let current = model.draftCategory == category
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: category.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.label).font(TypeScale.bodyStrong).foregroundStyle(Theme.text)
                    Text(subtitle).font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                if current { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(accent) }
            }
            .padding(.horizontal, Space.s)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .onHover { hover = $0 }
    }

    private var subtitle: String {
        let place = model.area(for: category).map { "To-dos from \($0)" } ?? (category == .chilling ? "No to-dos, just vibes" : "To-dos from Today")
        let m = model.stats.todayByCategory[category] ?? 0
        return m > 0 ? "\(place) · \(Duration.short(m)) today" : place
    }
}

// MARK: - Controls

/// Press feedback for every custom button.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A small round icon button with a hover fill.
struct IconButton: View {
    let symbol: String
    var tint: Color? = nil
    var size: CGFloat = 28
    var help: String = ""
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint ?? (hover ? Theme.text : Theme.muted))
                .frame(width: size, height: size)
                .background(Circle().fill(hover ? Theme.cardHi : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help)
    }
}

/// A secondary option: quiet text until chosen, then tinted with the mode's accent.
struct OptionChip: View {
    let label: String
    var symbol: String? = nil
    var selected: Bool
    var accent: Color
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
                Text(label).font(Theme.rounded(12, selected ? .semibold : .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(selected ? accent : (hover ? Theme.text : Theme.muted))
            .padding(.horizontal, Space.m)
            .frame(height: 28)
            .background(Capsule().fill(selected ? accent.opacity(0.16) : (hover ? Theme.cardHi : Theme.card)))
            .overlay(Capsule().strokeBorder(selected ? accent.opacity(0.45) : .clear))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// One segment of the length control.
struct Segment: View {
    let label: String
    var selected: Bool
    var accent: Color
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        Button(action: action) {
            Text(label).font(Theme.rounded(12, selected ? .bold : .medium)).monospacedDigit()
                .foregroundStyle(selected ? Theme.bg : (hover ? Theme.text : Theme.muted))
                .frame(width: 36, height: 26)
                .background(Capsule().fill(selected ? accent : (hover ? Theme.cardHi : .clear)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
    }
}

/// The big filled button.
struct PrimaryButton: View {
    let label: String
    let symbol: String
    var accent: Color
    var width: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                Text(label).font(Theme.rounded(15, .bold))
            }
            .foregroundStyle(Theme.bg)
            .frame(width: width, height: 44)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .padding(.horizontal, width == nil ? 0 : Space.l)
            .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(accent))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

/// A quiet round secondary control with a caption under it.
struct GhostControl: View {
    let symbol: String
    var caption: String
    var label: String? = nil
    var tooltip: String? = nil
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                HStack(spacing: 1) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                    if let label { Text(label).font(Theme.rounded(13, .bold)) }
                }
                .foregroundStyle(hover ? Theme.text : Theme.muted)
                .frame(width: 44, height: 44)
                .background(Circle().fill(hover ? Theme.cardHi : Theme.card))
                Text(caption).font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
            }
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(tooltip ?? caption)
    }
}
