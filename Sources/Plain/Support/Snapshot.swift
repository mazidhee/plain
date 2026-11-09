import AppKit
import SwiftUI

/// `Plain --snapshot <dir>`: renders the popover, the island and the art to PNGs.
enum Snapshot {
    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 21, minute: 10, second: 0, of: Date())!
        let tasks = [
            ThingsTask(id: "t1", title: "System design: read chapter 6", trackedMinutes: 80, context: "Interview prep"),
            ThingsTask(id: "t2", title: "Organic chemistry past paper", trackedMinutes: 25, context: "Uni"),
            ThingsTask(id: "t3", title: "Reply to Maya about the deck", trackedMinutes: 0, context: nil),
            ThingsTask(id: "t4", title: "Plain: island hover polish", trackedMinutes: 140, context: "Side projects"),
        ]
        let sessions = demoSessions(now: base)

        func running(_ plan: SessionPlan, elapsedMinutes: Double, paused: Bool = false) -> SessionMachine {
            var m = SessionMachine()
            m.start(plan, at: base.addingTimeInterval(-elapsedMinutes * 60))
            if paused { m.pause(at: base) }
            return m
        }
        let studyPlan = SessionPlan(title: "System design: read chapter 6", category: .study, minutes: 40, taskID: "t1", trackedBefore: 80)
        let studyRun = running(studyPlan, elapsedMinutes: 15.8)

        // Popover states.
        // Home, once per mode, with each mode's own area to-dos.
        let areaTasks: [Category: [ThingsTask]] = [
            .work: [ThingsTask(id: "w1", title: "Ship the onboarding flow review", trackedMinutes: 95, context: "Q4 launch"),
                    ThingsTask(id: "w2", title: "Reply to the design feedback thread"), ThingsTask(id: "w3", title: "Write the API migration plan", trackedMinutes: 30, context: "Platform")],
            .study: [ThingsTask(id: "s1", title: "Graph algorithms: Dijkstra drills", trackedMinutes: 40, context: "Algorithms"),
                     ThingsTask(id: "s2", title: "System design: read chapter 6", trackedMinutes: 80, context: "Interview prep")],
            .exam: [ThingsTask(id: "e1", title: "Organic chemistry past paper 2024", trackedMinutes: 25, context: "Uni")],
            .reading: [ThingsTask(id: "r1", title: "Finish Designing Data-Intensive Apps ch. 3", context: "Books")],
        ]
        for c in Category.allCases {
            model.preview(machine: SessionMachine(), now: base, tasks: c == .chilling ? [] : tasks, sessions: sessions)
            model.previewAreas(["Work", "Learning", "Books"], tasks: areaTasks[c] ?? [], category: c)
            render(PopoverView(model: model), to: dir.appendingPathComponent("home-\(c.rawValue).png"))
        }
        model.preview(machine: SessionMachine(), now: base, tasks: tasks, sessions: sessions)
        model.previewAreas(["Work", "Learning", "Books"], tasks: areaTasks[.work]!, category: .work)
        render(PopoverView(model: model, menuOpen: true), to: dir.appendingPathComponent("home-mode-menu.png"))
        model.selectedTask = areaTasks[.work]![0]
        render(PopoverView(model: model), to: dir.appendingPathComponent("home-task-picked.png"))
        model.selectedTask = nil
        model.previewAreas([], tasks: [], category: .work)
        // Running: a pomodoro on a to-do, Lock in, paused, count-up, break.
        var lock = SessionMachine()
        lock.start(SessionPlan(title: "", category: .work, minutes: 50, lockIn: true), at: base.addingTimeInterval(-18 * 60 - 25))
        model.preview(machine: lock, now: base, tasks: tasks, sessions: sessions)
        render(PopoverView(model: model), to: dir.appendingPathComponent("running-lockin.png"))
        var countUp = SessionMachine()
        countUp.start(SessionPlan(title: "", category: .work, minutes: 0, openEnded: true, lockIn: true), at: base.addingTimeInterval(-47 * 60 - 12))
        model.preview(machine: countUp, now: base, tasks: tasks, sessions: sessions)
        render(PopoverView(model: model), to: dir.appendingPathComponent("running-countup.png"))
        var brk = SessionMachine()
        brk.start(studyPlan, at: base.addingTimeInterval(-2400)); _ = brk.tick(at: base)
        _ = brk.startBreak(short: 5, long: 15, at: base.addingTimeInterval(-90))
        model.preview(machine: brk, now: base, tasks: tasks, sessions: sessions)
        model.setPreviewBreak(5)
        render(PopoverView(model: model), to: dir.appendingPathComponent("running-break.png"))
        model.preview(machine: running(studyPlan, elapsedMinutes: 15.8, paused: true), now: base, tasks: tasks, sessions: sessions)
        render(PopoverView(model: model), to: dir.appendingPathComponent("running-paused.png"))
        model.preview(machine: studyRun, now: base, tasks: tasks, sessions: sessions)
        render(PopoverView(model: model), to: dir.appendingPathComponent("running-pomodoro.png"))
        var done = SessionMachine()
        done.start(studyPlan, at: base.addingTimeInterval(-2400))
        _ = done.tick(at: base)
        model.preview(machine: done, now: base, tasks: tasks, sessions: sessions, summary: "Logged 40 min on the to-do", summaryTaskID: "t1", summaryTracked: 120)
        render(PopoverView(model: model), to: dir.appendingPathComponent("summary-task.png"))
        var lockDone = SessionMachine()
        lockDone.start(SessionPlan(title: "", category: .work, minutes: 50, lockIn: true), at: base.addingTimeInterval(-3000)); _ = lockDone.tick(at: base)
        model.preview(machine: lockDone, now: base, tasks: tasks, sessions: sessions, summary: "Saved in Plain's stats.")
        render(PopoverView(model: model), to: dir.appendingPathComponent("summary-lockin.png"))
        model.preview(machine: SessionMachine(), now: base, tasks: tasks, sessions: sessions)
        let day = cal.startOfDay(for: base)
        func seg(_ id: String, _ name: String, _ h0: Double, _ h1: Double) -> AppUsage.Segment {
            AppUsage.Segment(bundleID: id, name: name, start: day.addingTimeInterval(h0 * 3600), end: day.addingTimeInterval(h1 * 3600))
        }
        model.previewSegments = [seg(AppWatcher.tideBundleID, "Tide", 9, 10.4), seg("com.mitchellh.ghostty", "Ghostty", 10.4, 12.2),
                                 seg("com.microsoft.VSCode", "Code", 13, 14.6), seg("com.apple.Safari", "Safari", 14.6, 15.3),
                                 seg(AppWatcher.tideBundleID, "Tide", 19, 19.5), seg("com.apple.mail", "Mail", 20, 20.3)]
        render(PopoverView(model: model, route: .stats), to: dir.appendingPathComponent("popover-stats.png"))
        var tracker = SessionMachine()
        tracker.start(SessionPlan(title: "Chilling in Tide", category: .chilling, minutes: 0, openEnded: true, localOnly: true, tiedToTide: true),
                      at: base.addingTimeInterval(-12 * 60 - 5))
        model.preview(machine: tracker, now: base, tasks: tasks, sessions: sessions)
        render(PopoverView(model: model), to: dir.appendingPathComponent("running-tide-chill.png"))
        model.preview(machine: SessionMachine(), now: base, tasks: tasks, sessions: sessions, prompt: .tide)
        render(PopoverView(model: model), to: dir.appendingPathComponent("popover-tide-prompt.png"))
        model.preview(machine: SessionMachine(), now: base, tasks: tasks, sessions: sessions)
        model.preview(machine: SessionMachine(), now: base, tasks: tasks, sessions: sessions)
        model.draftTitle = "chem paper"
        model.search("chem paper")
        render(PopoverView(model: model), to: dir.appendingPathComponent("popover-search.png"))
        model.draftTitle = ""
        render(PopoverView(model: model, route: .sound), to: dir.appendingPathComponent("popover-sound.png"))

        // Island over a mock menu bar with the real notch size.
        let geo = NotchGeometry.current().flatMap { $0.hasNotch ? $0 : nil }
            ?? NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notch: CGRect(x: 663, y: 950, width: 185, height: 32), menuBarHeight: 32)
        func island(_ mode: IslandMode, _ name: String) {
            let state = IslandState(geometry: geo)
            state.mode = mode
            render(IslandShowcase(state: state, model: model), to: dir.appendingPathComponent(name))
        }
        model.preview(machine: studyRun, now: base, tasks: tasks, sessions: sessions)
        island(.compact, "island-compact.png")
        island(.expanded, "island-expanded.png")
        model.preview(machine: SessionMachine(), now: base, tasks: tasks, sessions: sessions, prompt: .tide)
        island(.prompt, "island-tide-prompt.png")
        model.preview(machine: SessionMachine(), now: base, tasks: tasks, sessions: sessions, prompt: .editor(appName: "Ghostty"))
        island(.nudge, "island-nudge.png")

        // Art sheets.
        render(CharacterSheet(), to: dir.appendingPathComponent("character-sheet.png"))
        render(MenuBarSheet(), to: dir.appendingPathComponent("menubar.png"))
        render(RoomSheet(model: model), to: dir.appendingPathComponent("rooms.png"))
        render(SceneSheet(), to: dir.appendingPathComponent("scenes.png"))

        // README screenshot: the popover mid-session beside the expanded island.
        model.preview(machine: studyRun, now: base, tasks: tasks, sessions: sessions)
        let state = IslandState(geometry: geo)
        state.mode = .expanded
        render(Hero(state: state, model: model), to: dir.appendingPathComponent("screenshot.png"))
        print("Snapshots written to \(dir.path)")
    }

    static func demoSessions(now: Date) -> [CompletedSession] {
        let cal = Calendar.current
        var out: [CompletedSession] = []
        let plan: [(Int, Int, Int, Category, String)] = [
            (0, 9, 50, .work, "Plain: island spring"), (0, 14, 40, .study, "System design ch. 5"), (0, 19, 25, .exam, "Chem mock paper"),
            (-1, 10, 50, .work, "API docs"), (-1, 16, 25, .reading, "Dune"), (-2, 11, 40, .study, "Flashcards"),
            (-3, 9, 50, .work, "Refactor"), (-4, 20, 25, .chilling, "Lo-fi wind down"),
        ]
        for (day, hour, minutes, cat, title) in plan {
            let end = cal.date(byAdding: .day, value: day, to: cal.date(bySettingHour: hour, minute: 0, second: 0, of: now)!)!
            out.append(CompletedSession(title: title, category: cat, start: end.addingTimeInterval(Double(-minutes * 60)), end: end, minutes: minutes, plannedMinutes: minutes))
        }
        return out
    }

    /// Lays a view out in an offscreen window and writes a 2x PNG.
    static func render<V: View>(_ view: V, to url: URL) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.lastPathComponent) \(Int(size.width))x\(Int(size.height))")
    }
}

/// A slice of desktop: wallpaper, a menu bar with the notch, and the island hanging from it.
struct IslandShowcase: View {
    @ObservedObject var state: IslandState
    @ObservedObject var model: AppModel
    var width: CGFloat = 760
    var height: CGFloat = 250

    var body: some View {
        let g = state.geometry
        let bar = g.barHeight
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x3a5068), Color(hex: 0x9b7c8f), Color(hex: 0xe1b48e)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.black.opacity(0.28)).frame(height: bar)
                .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                Text("  Ghostty   File   Edit   View").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("Mon 9 Nov  21:10  ").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: bar)
            // The physical notch, for reference.
            NotchShape(topRadius: 0, bottomRadius: 8).fill(Color.black).frame(width: g.notchWidth, height: bar)
            IslandView(state: state, model: model)
                .frame(width: state.size(for: state.mode).width, height: state.size(for: state.mode).height)
        }
        .frame(width: width, height: height)
    }
}

struct CharacterSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Activity.allCases, id: \.self) { a in
                HStack(spacing: 14) {
                    Text(a.label).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.text).frame(width: 80, alignment: .leading)
                    ForEach(0..<6, id: \.self) { t in
                        PixelView(grid: Wren.frame(a, tick: t), palette: Wren.palette, pixel: 6)
                            .background(Color(hex: 0x2b221d))
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.bg)
    }
}

/// The monochrome menu bar version at true size and zoomed, on light and dark bars.
struct MenuBarSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 18) {
                    ForEach(Activity.allCases, id: \.self) { a in
                        VStack(spacing: 6) {
                            let img = PixelRenderer.nsImage(Wren.frame(a, tick: 2), palette: Wren.palette, alphaMap: Wren.templateAlpha,
                                                            tint: dark ? RGBA(0xFFFFFF) : RGBA(0x000000))
                            Image(nsImage: img).frame(width: 22, height: 24)
                            Image(nsImage: img).interpolation(.none).resizable().frame(width: 88, height: 72)
                            Text(a.label).font(.system(size: 10)).foregroundStyle(dark ? .white : .black)
                        }
                    }
                }
                .padding(12)
                .background(dark ? Color(hex: 0x1e1e22) : Color(hex: 0xe9e7ea))
            }
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 18) {
                    ForEach(Activity.allCases, id: \.self) { a in
                        VStack(spacing: 6) {
                            let g = Wren.frame(a, tick: 2)
                            let img = PixelRenderer.nsImage(dark ? g.outlined(with: "O") : g, palette: Wren.palette)
                            Image(nsImage: img).frame(width: 22, height: 24)
                            Image(nsImage: img).interpolation(.none).resizable().frame(width: 88, height: 72)
                            Text("colour").font(.system(size: 10)).foregroundStyle(dark ? .white : .black)
                        }
                    }
                }
                .padding(12)
                .background(dark ? Color(hex: 0x1e1e22) : Color(hex: 0xe9e7ea))
            }
        }
    }
}

struct RoomSheet: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let cols = [GridItem(.fixed(288)), GridItem(.fixed(288)), GridItem(.fixed(288))]
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(Array(DayPeriod.allCases.enumerated()), id: \.offset) { i, p in
                let acts: [Activity] = [.study, .work, .breakTime, .exam, .chilling, .idle]
                VStack(spacing: 4) {
                    PixelView(grid: RoomScene.frame(activity: acts[i], tick: 5, period: p, musicPlaying: false), palette: RoomScene.palette(p), pixel: 3)
                    Text("\(p.rawValue) · \(acts[i].label)").font(Theme.rounded(11)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(16)
        .background(Theme.bg)
    }
}

/// README screenshot: a menu bar with Wren's icon, and the popover hanging under it.
struct SceneSheet: View {
    var body: some View {
        let scenes: [(SceneKind, Activity)] = [(.room, .work), (.code, .work), (.library, .study), (.beach, .breakTime)]
        VStack(spacing: 12) {
            ForEach([DayPeriod.day, .night], id: \.self) { p in
                HStack(spacing: 12) {
                    ForEach(scenes, id: \.0) { scene, act in
                        VStack(spacing: 4) {
                            PixelView(grid: RoomScene.frame(activity: act, tick: 5, period: p, musicPlaying: false, scene: scene), palette: RoomScene.palette(p), pixel: 3)
                            Text("\(scene.label) · \(p.rawValue)").font(Theme.rounded(11)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.bg)
    }
}

struct Hero: View {
    @ObservedObject var state: IslandState
    @ObservedObject var model: AppModel
    @ObservedObject var animator = Animator.shared

    var body: some View {
        let icon = PixelRenderer.nsImage(Wren.frame(model.activity, tick: 2).outlined(with: "O"), palette: Wren.palette)
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: 0x2c3a52), Color(hex: 0x7c6380), Color(hex: 0xe0ac86)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Text("Tide").font(.system(size: 13, weight: .bold))
                    Text("File"); Text("Edit"); Text("View"); Text("Window")
                    Spacer()
                    HStack(spacing: 3) {
                        Image(nsImage: icon)
                        Text("24m").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.18)))
                    Image(systemName: "wifi"); Image(systemName: "battery.75")
                    Text("Mon 9 Nov  21:10")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Color.black.opacity(0.32))
                Spacer()
            }
            PopoverView(model: model)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
                .padding(.top, 42)
                .padding(.trailing, 112)
        }
        .frame(width: 980, height: 560)
    }
}

/// `Plain --make-icon <png>`: the app icon, Wren at his laptop on a warm tile, 1024 px.
enum AppIcon {
    static func write(to url: URL) {
        let size = 1024
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.interpolationQuality = .none
        // Rounded tile with a warm lamp-lit gradient (macOS icon grid: 824 px tile, 100 px inset).
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let colors = [RGBA(0x3a2a30).nsColor.cgColor, RGBA(0x6b4237).nsColor.cgColor, RGBA(0xd98b52).nsColor.cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        // Lamp glow.
        let glow = CGGradient(colorsSpace: space, colors: [RGBA(0xffe3a3, alpha: 0.45).nsColor.cgColor, RGBA(0xffe3a3, alpha: 0).nsColor.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
        // Desk.
        ctx.setFillColor(RGBA(0x53351f).nsColor.cgColor)
        ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 196))
        ctx.setFillColor(RGBA(0x9b6a45).nsColor.cgColor)
        ctx.fill(CGRect(x: 100, y: 268, width: 824, height: 28))
        // Wren, 28 px per cell, sitting on the desk.
        let grid = Wren.frame(.work, tick: 1)
        if let cg = PixelRenderer.cgImage(grid, palette: Wren.palette, scale: 28) {
            let w = CGFloat(grid.width * 28), h = CGFloat(grid.height * 28)
            ctx.draw(cg, in: CGRect(x: (1024 - w) / 2, y: 296, width: w, height: h))
        }
        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
