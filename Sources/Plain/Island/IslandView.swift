import SwiftUI

enum IslandMode: Equatable {
    case hidden, compact, expanded, prompt, nudge, done
}

/// What the island shows and how big it is.
final class IslandState: ObservableObject {
    @Published var mode: IslandMode = .hidden
    @Published var geometry: NotchGeometry

    init(geometry: NotchGeometry) { self.geometry = geometry }

    static let earWidth: CGFloat = 78

    /// The pill's size for a mode.
    func size(for mode: IslandMode) -> CGSize {
        let h = geometry.barHeight
        let base = geometry.hasNotch ? geometry.notchWidth : 120
        switch mode {
        case .hidden: return CGSize(width: max(base, 10), height: geometry.hasNotch ? h : 0)
        case .compact, .done: return CGSize(width: base + Self.earWidth * 2, height: h)
        case .expanded: return CGSize(width: max(base + 240, 470), height: h + 116)
        case .prompt: return CGSize(width: max(base + 260, 500), height: h + 146)
        case .nudge: return CGSize(width: max(base + 300, 500), height: h + 54)
        }
    }

    /// The largest size, which the panel takes while animating.
    var maxSize: CGSize {
        [IslandMode.expanded, .prompt, .nudge].map(size(for:)).reduce(CGSize.zero) {
            CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
        }
    }
}

/// A notch silhouette: flat top that flares into the menu bar, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let tr = min(topRadius, w / 4), br = min(bottomRadius, (h - tr) / 2, (w - 2 * tr) / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: tr, y: tr), control: CGPoint(x: tr, y: 0))
        p.addLine(to: CGPoint(x: tr, y: h - br))
        p.addQuadCurve(to: CGPoint(x: tr + br, y: h), control: CGPoint(x: tr, y: h))
        p.addLine(to: CGPoint(x: w - tr - br, y: h))
        p.addQuadCurve(to: CGPoint(x: w - tr, y: h - br), control: CGPoint(x: w - tr, y: h))
        p.addLine(to: CGPoint(x: w - tr, y: tr))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - tr, y: 0))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var model: AppModel
    @ObservedObject var animator = Animator.shared
    var onHover: (Bool) -> Void = { _ in }

    var body: some View {
        let mode = state.mode
        let size = state.size(for: mode)
        let tr: CGFloat = state.geometry.hasNotch ? 7 : 0
        let br: CGFloat = mode == .compact || mode == .done || mode == .hidden ? (state.geometry.hasNotch ? 11 : 15) : 26
        ZStack(alignment: .top) {
            NotchShape(topRadius: tr, bottomRadius: br)
                .fill(Color.black)
                .shadow(color: .black.opacity(mode == .compact || mode == .hidden ? 0 : 0.35), radius: 14, y: 6)
            content(mode)
                .padding(.horizontal, tr + 10)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(NotchShape(topRadius: tr, bottomRadius: br))
                .opacity(mode == .hidden ? 0 : 1)
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover(perform: onHover)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Pieces

    @ViewBuilder private func content(_ mode: IslandMode) -> some View {
        VStack(spacing: 0) {
            ears(mode)
            switch mode {
            case .expanded: expanded.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            case .prompt: TidePrompt(model: model).transition(.opacity)
            case .nudge: nudge.transition(.opacity)
            default: EmptyView()
            }
        }
    }

    /// The strip level with the notch: Wren on the left, the clock on the right.
    private func ears(_ mode: IslandMode) -> some View {
        let h = state.geometry.barHeight
        return HStack(spacing: 0) {
            PixelView(grid: Wren.frame(earActivity(mode), tick: animator.frameTick), palette: Wren.palette, pixel: 1)
                .frame(width: 26, height: h)
            Spacer(minLength: state.geometry.notchWidth)
            Group {
                switch mode {
                case .done:
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.good)
                        Text("\(model.lastCompleted?.minutes ?? 0)m").font(Theme.rounded(12, .bold)).foregroundStyle(.white)
                    }
                case .prompt, .nudge:
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(Theme.accent)
                default:
                    if model.isRunning {
                        PixelClock(text: (model.isTracker ? "^" : "") + model.clockText, pixel: 2,
                                   color: model.isPaused ? Theme.muted : (model.phase == .breakTime ? Theme.good : Theme.text))
                    }
                }
            }
            .frame(width: 62, height: h, alignment: .trailing)
        }
        .frame(height: h)
        .overlay(alignment: .bottom) {
            if (mode == .compact) && model.isRunning {
                // A hairline of progress along the bottom of the pill.
                GeometryReader { g in
                    Capsule().fill(progressColor.opacity(0.85))
                        .frame(width: max(2, g.size.width * model.progress), height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
        }
    }

    private func earActivity(_ mode: IslandMode) -> Activity {
        switch mode {
        case .prompt: return .chilling
        case .nudge: return .work
        case .done: return .breakTime
        default: return model.activity
        }
    }

    private var progressColor: Color {
        model.phase == .breakTime ? Theme.good : (model.plan.map { Theme.color($0.category) } ?? Theme.accent)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                PixelView(grid: Wren.frame(model.activity, tick: animator.frameTick, bob: model.sound.musicOn),
                          palette: Wren.palette, pixel: 3)
                    .frame(width: 66, height: 54)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1d1714)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.phase == .breakTime ? "☕️ Tea break" : "\(model.plan?.category.emoji ?? "") \(model.plan?.displayTitle ?? "")")
                        .font(Theme.rounded(15, .bold)).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 6) {
                        if let c = model.plan?.category, model.phase == .focus {
                            Text(c.label).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.color(c))
                        }
                        if let t = model.trackedIncludingNow {
                            Text("· \(Duration.short(t)) so far").font(Theme.rounded(11)).foregroundStyle(Theme.muted)
                        }
                        if model.isPaused { Text("· paused").font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.accent) }
                    }
                    PixelProgress(value: model.progress, tint: progressColor, height: 6).padding(.top, 6)
                }
            }
            HStack(spacing: 6) {
                RoundButton(symbol: model.isPaused ? "play.fill" : "pause.fill", prominent: true, size: 28) { model.togglePause() }
                if model.phase == .focus {
                    RoundButton(symbol: "plus", label: "5", size: 28) { model.extend() }
                    RoundButton(symbol: "checkmark", size: 28) { model.finishEarly() }.help("Finish now")
                } else {
                    RoundButton(symbol: "forward.fill", size: 28) { model.cancel() }.help("Skip break")
                }
                Spacer(minLength: 10)
                SoundMenu(sound: model.sound)
                SoundBar(sound: model.sound, compact: true).frame(width: 120)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 6)
    }

    private var nudge: some View {
        HStack(spacing: 8) {
            Text(nudgeText).font(Theme.rounded(13, .semibold)).foregroundStyle(.white).lineLimit(1)
            Spacer()
            ForEach([25, 50], id: \.self) { m in
                Chip(label: "\(m) min", selected: m == 25) { model.startFromNudge(minutes: m) }
            }
            Chip(label: "3 × 50") { model.startFromNudge(minutes: 50, rounds: 3) }
            Button { model.prompt = nil } label: { Image(systemName: "xmark").foregroundStyle(Theme.faint) }.buttonStyle(.plain)
        }
        .padding(.top, 12)
        .padding(.horizontal, 6)
    }

    private var nudgeText: String {
        if case .editor(let name) = model.prompt { return "Deep in \(name)? Make it a session." }
        return "Make it a work session?"
    }
}

/// Compact source picker for the island.
struct SoundMenu: View {
    @ObservedObject var sound: SoundController

    var body: some View {
        Menu {
            Section("SomaFM radio") {
                Button("No music") { sound.station = nil }
                ForEach(Station.all) { s in Button(s.name) { sound.station = s.id } }
            }
            Section("Ambience") {
                Button("None") { sound.ambience = nil }
                ForEach(NoiseKind.allCases) { k in Button(k.label) { sound.ambience = k } }
            }
        } label: {
            Text(sound.summary).font(Theme.rounded(11, .medium)).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(Theme.muted)
    }
}

/// “What are we doing?” — shown when Tide comes to the front.
/// “What are we doing?” — shown when Tide comes to the front. It never starts a pomodoro:
/// study modes only set Wren's mood (Tide logs that time itself), chilling starts a count-up tracker.
struct TidePrompt: View {
    @ObservedObject var model: AppModel
    @ObservedObject var animator = Animator.shared
    @StateObject private var textBox = Box("")
    private var text: String { get { textBox.value } nonmutating set { textBox.value = newValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                PixelView(grid: Wren.frame(.study, tick: animator.frameTick), palette: Wren.palette, pixel: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What are we doing?").font(Theme.rounded(17, .bold)).foregroundStyle(.white)
                    Text(tideLine).font(Theme.rounded(11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { model.prompt = nil } label: { Image(systemName: "xmark").foregroundStyle(Theme.faint) }.buttonStyle(.plain)
            }
            FlowRow(spacing: 6) {
                ForEach(AppModel.TideChoice.allCases, id: \.self) { choice in
                    Chip(label: choice.label, tint: choice == .chilling ? Theme.color(.chilling) : Theme.color(.study)) {
                        model.tideChoice(choice, note: text)
                    }
                }
            }
            TextField("", text: $textBox.value, prompt: Text("Optional note… “Ch. 4 organic chem”").foregroundColor(Theme.faint))
                .textFieldStyle(.plain).font(Theme.rounded(12)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Theme.card))
            Text("Study modes: Tide keeps the time, Wren just joins in. Chilling counts up until you leave Tide.")
                .font(Theme.rounded(10)).foregroundStyle(Theme.faint)
        }
        .padding(.top, 10)
        .padding(.horizontal, 6)
    }

    private var tideLine: String {
        guard model.tide.available else { return "Tide's open." }
        return model.tide.todayMinutes > 0 ? "Studied in Tide today: \(Duration.short(model.tide.todayMinutes))" : "Nothing studied in Tide yet today."
    }
}

/// Lays children out in rows, wrapping as needed.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
