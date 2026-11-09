import SwiftUI

/// Pixel squares around a rounded frame, lit clockwise from the top centre.
/// Counting down, the lit part is the time left and it drains; it reads at a glance.
struct PixelRing: View {
    var fraction: Double
    var lit: Color
    var unlit: Color = Theme.line
    var cell: CGFloat = 6
    var gap: CGFloat = 3

    var body: some View {
        Canvas { ctx, size in
            let pts = Self.perimeter(size: size, step: cell + gap, inset: cell / 2)
            let n = pts.count
            let on = Int((Double(n) * min(1, max(0, fraction))).rounded())
            for (i, p) in pts.enumerated() {
                let r = CGRect(x: p.x - cell / 2, y: p.y - cell / 2, width: cell, height: cell)
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(i < on ? lit : unlit))
            }
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }

    /// Cell centres along the frame, clockwise from top centre, skipping the corners for a rounded look.
    static func perimeter(size: CGSize, step: CGFloat, inset: CGFloat) -> [CGPoint] {
        let w = size.width - inset * 2, h = size.height - inset * 2
        let cols = max(2, Int(w / step)), rows = max(2, Int(h / step))
        let dx = w / CGFloat(cols), dy = h / CGFloat(rows)
        var top: [CGPoint] = [], right: [CGPoint] = [], bottom: [CGPoint] = [], left: [CGPoint] = []
        for c in 1..<cols { top.append(CGPoint(x: inset + CGFloat(c) * dx, y: inset)) }
        for r in 1..<rows { right.append(CGPoint(x: inset + w, y: inset + CGFloat(r) * dy)) }
        for c in stride(from: cols - 1, through: 1, by: -1) { bottom.append(CGPoint(x: inset + CGFloat(c) * dx, y: inset + h)) }
        for r in stride(from: rows - 1, through: 1, by: -1) { left.append(CGPoint(x: inset, y: inset + CGFloat(r) * dy)) }
        let mid = top.count / 2
        return Array(top[mid...]) + right + bottom + left + Array(top[..<mid])
    }
}

/// The calm focus screen: subtle header, a big pixel clock in its ring, Pause first.
struct RunningScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var attachBox = Box(false)
    private var attaching: Bool { get { attachBox.value } nonmutating set { attachBox.value = newValue } }

    private var onBreak: Bool { model.phase == .breakTime }
    private var accent: Color { onBreak ? Theme.good : (model.plan.map { Theme.color($0.category) } ?? Theme.accent) }

    var body: some View {
        VStack(spacing: Space.l) {
            header
            if model.isTracker { countUp } else { countdown }
            controls
            if model.isTracker || model.plan?.lockIn == true, model.plan?.taskID == nil, !onBreak { attach }
            soundRow
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: 6) {
                Image(systemName: onBreak ? "cup.and.saucer.fill" : (model.plan?.category.symbol ?? "bolt.fill"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                Text(kicker).font(TypeScale.meta).foregroundStyle(Theme.muted)
            }
            if !onBreak, let plan = model.plan, !(plan.lockIn && plan.taskID == nil), !plan.title.isEmpty {
                Text(plan.displayTitle).font(TypeScale.heading).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
    }

    private var kicker: String {
        if onBreak { return "Break · \(model.breakMinutes) min" }
        guard let plan = model.plan else { return "" }
        var parts = [plan.category.label]
        if plan.lockIn && plan.taskID == nil { parts.append("Lock in") }
        if let t = model.trackedIncludingNow, t > 0 { parts.append("\(Duration.short(t)) on this to-do") }
        return parts.joined(separator: " · ")
    }

    private var countdown: some View {
        ZStack {
            PixelRing(fraction: 1 - model.progress, lit: model.isPaused ? Theme.muted : accent)
            VStack(spacing: Space.s) {
                PixelClock(text: model.clockText, pixel: 6, ink: model.isPaused ? Theme.pausedInk : Theme.textInk)
                Text(model.isPaused ? "Paused" : "Ends \(Date().addingTimeInterval(model.remaining).formatted(date: .omitted, time: .shortened))")
                    .font(TypeScale.meta).foregroundStyle(model.isPaused ? accent : Theme.muted)
            }
        }
        .frame(width: 312, height: 120)
    }

    /// Count-up looks different on purpose: no frame to drain, a track that grows a cell a minute.
    private var countUp: some View {
        let minutes = Int(model.elapsed / model.machine.secondsPerMinute)
        let lap = minutes % 30
        return VStack(spacing: Space.m) {
            HStack(alignment: .center, spacing: Space.m) {
                Image(systemName: "arrow.up").font(.system(size: 20, weight: .heavy)).foregroundStyle(accent)
                PixelClock(text: model.clockText, pixel: 6, ink: model.isPaused ? Theme.pausedInk : Theme.textInk)
            }
            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5).fill(i < lap ? accent : (i == lap && !model.isPaused ? accent.opacity(0.45) : Theme.line))
                        .frame(width: 6, height: 6)
                }
            }
            Text(countUpCaption(minutes)).font(TypeScale.meta).foregroundStyle(model.isPaused ? accent : Theme.muted)
        }
        .frame(height: 120)
    }

    private func countUpCaption(_ minutes: Int) -> String {
        if model.isPaused { return "Paused" }
        let since = model.machine.startedAt.map { "Since \($0.formatted(date: .omitted, time: .shortened))" } ?? "Counting up"
        let laps = minutes >= 30 ? " · \(minutes / 30)×30 min" : ""
        return model.plan?.tiedToTide == true ? "\(since) · stops when you leave Tide" : "\(since)\(laps)"
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: Space.m) {
            if onBreak {
                PrimaryButton(label: "Skip break", symbol: "forward.fill", accent: accent, width: 160) { model.cancel() }
            } else if model.isTracker {
                PrimaryButton(label: model.isPaused ? "Resume" : "Pause", symbol: model.isPaused ? "play.fill" : "pause.fill", accent: accent, width: 140) { model.togglePause() }
                GhostControl(symbol: "stop.fill", caption: "Stop") { model.finishEarly() }
                GhostControl(symbol: "xmark", caption: "Cancel") { model.cancel() }
            } else {
                GhostControl(symbol: "plus", caption: "Add 5", label: "5") { model.extend() }
                PrimaryButton(label: model.isPaused ? "Resume" : "Pause", symbol: model.isPaused ? "play.fill" : "pause.fill", accent: accent, width: 140) { model.togglePause() }
                GhostControl(symbol: "checkmark", caption: "Finish") { model.finishEarly() }
                GhostControl(symbol: "xmark", caption: "Cancel", tooltip: "Cancel. A minute or more is still saved.") { model.cancel() }
            }
        }
        .labelsHiddenGhost()
    }

    private var attach: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if attaching {
                SearchBox(model: model)
                    .onChange(of: model.selectedTask) { _, t in
                        if let t { model.attach(t); model.pick(nil); attaching = false }
                    }
            } else {
                Button { attaching = true } label: {
                    Label("Attach a to-do", systemImage: "link").font(TypeScale.meta).foregroundStyle(Theme.muted)
                }
                .buttonStyle(PressableStyle())
                .help("The time goes onto that to-do in Things when you finish")
            }
        }
        .frame(maxWidth: .infinity, alignment: attaching ? .leading : .center)
    }

    private var soundRow: some View {
        let sound = model.sound
        return HStack(spacing: Space.s) {
            Image(systemName: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.system(size: 11))
                .foregroundStyle(sound.isPlaying ? accent : Theme.muted)
            Text(sound.summary).font(TypeScale.meta).foregroundStyle(Theme.muted).lineLimit(1)
            Spacer()
            IconButton(symbol: sound.musicOn ? "pause.fill" : "play.fill", size: 26, help: sound.musicOn ? "Pause the music" : "Play the music") { sound.toggleMusic() }
            IconButton(symbol: "forward.end.fill", size: 26, help: "Next station") { sound.nextStation() }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Theme.card))
    }
}

private extension View {
    /// Ghost controls carry their meaning in tooltips, so the row stays one clean line.
    func labelsHiddenGhost() -> some View { self }
}

/// After a block: what happened, what was logged, and what next.
struct SummaryScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let s = model.lastCompleted
        let accent = s.map { Theme.color($0.category) } ?? Theme.accent
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(headline(s)).font(TypeScale.title).foregroundStyle(Theme.text)
                if let s {
                    Text("\(Duration.short(s.minutes)) · \(s.label == s.title && s.lockIn != true ? "\(s.category.label) · \(s.title)" : s.label)")
                        .font(TypeScale.body).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                if let note = model.summaryNote {
                    Label(note, systemImage: "tray.and.arrow.down").font(TypeScale.meta).foregroundStyle(Theme.muted)
                }
                if let tracked = model.summaryTracked, tracked > 0 {
                    Label("\(Duration.short(tracked)) tracked on this to-do", systemImage: "clock").font(TypeScale.meta).foregroundStyle(accent)
                }
                if model.markedDone {
                    Label("Marked done in Things", systemImage: "checkmark.circle.fill").font(TypeScale.meta).foregroundStyle(Theme.good)
                }
            }
            HStack(spacing: Space.m) {
                if model.summaryTaskID != nil && !model.markedDone {
                    PrimaryButton(label: "Mark done in Things", symbol: "checkmark.circle.fill", accent: accent) { model.markDoneInThings() }
                } else {
                    PrimaryButton(label: "Go again", symbol: "arrow.clockwise", accent: accent) { model.again() }
                }
                GhostControl(symbol: "cup.and.saucer.fill", caption: "Break") { model.startBreak() }
                GhostControl(symbol: "house.fill", caption: "Home") { model.dismissSummary() }
            }
        }
    }

    private func headline(_ s: CompletedSession?) -> String {
        guard let s else { return "Done." }
        if s.openEnded == true { return "Tracked." }
        return s.endedEarly ? "Wrapped up early." : "Nice work."
    }
}
