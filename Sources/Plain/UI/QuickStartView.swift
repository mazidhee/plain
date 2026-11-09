import AppKit
import SwiftUI

/// The ⌃⌥F panel: type a sentence, or pick a Things to-do, and go.
struct QuickStartView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var animator = Animator.shared
    @StateObject private var textBox = Box("")
    private var text: String { get { textBox.value } nonmutating set { textBox.value = newValue } }
    @StateObject private var highlightedBox = Box(0)
    private var highlighted: Int { get { highlightedBox.value } nonmutating set { highlightedBox.value = newValue } }
    @FocusState private var focused: Bool
    var close: () -> Void = {}

    private var parsed: QuickParser.Result { QuickParser.parse(text) }
    private var typing: Bool { text.trimmingCharacters(in: .whitespaces).count >= 2 }
    /// Scoped to the mode's Things area when it has one (Work → Work area), else today / search.
    private var tasks: [ThingsTask] {
        if typing { return Array(model.searchResults.prefix(6)) }
        return Array((model.draftArea != nil ? model.areaTasks : model.todayTasks).prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PixelView(grid: Wren.frame(.work, tick: animator.frameTick), palette: Wren.palette, pixel: 2)
                TextField("", text: $textBox.value, prompt: Text("Reading system design docs 40 min study").foregroundColor(Theme.faint))
                    .textFieldStyle(.plain)
                    .font(Theme.rounded(20, .medium))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: text) { _, q in
                        highlighted = -1
                        let p = QuickParser.parse(q)
                        if let c = p.category, c != model.draftCategory { model.draftCategory = c }
                        model.search(p.title)
                    }
            }
            HStack(spacing: 8) {
                tag(parsed.category?.label ?? model.draftCategory.label, color: Theme.color(parsed.category ?? model.draftCategory))
                tag("\(parsed.minutes ?? model.draftMinutes) min", color: Theme.accent)
                if !parsed.title.isEmpty && highlighted < 0 {
                    Text("“\(parsed.title)”").font(Theme.rounded(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Text("↩ start · ↑↓ pick a to-do · esc").font(Theme.rounded(10)).foregroundStyle(Theme.faint)
            }
            if !tasks.isEmpty {
                Divider().overlay(Theme.line)
                Text(typing ? "MATCHING TO-DOS" : (model.draftArea.map { "NEXT IN \($0.uppercased())" } ?? "TODAY IN THINGS")).font(Theme.rounded(10, .bold)).foregroundStyle(Theme.faint).kerning(0.6)
                ForEach(Array(tasks.enumerated()), id: \.element.id) { i, task in
                    HStack {
                        Circle().strokeBorder(Theme.muted, lineWidth: 1.3).frame(width: 12, height: 12)
                        Text(task.title).font(Theme.rounded(13)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        if task.trackedMinutes > 0 {
                            Text(Duration.short(task.trackedMinutes)).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(i == highlighted ? Theme.cardHi : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { highlighted = i; submit() }
                }
            }
        }
        .padding(16)
        .frame(width: 560)
        .frame(height: 420, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
        .onAppear {
            text = ""
            highlighted = -1
            focused = true
            model.refreshTasks()
        }
        .onKeyPress(.downArrow) { highlighted = min(tasks.count - 1, highlighted + 1); return .handled }
        .onKeyPress(.upArrow) { highlighted = max(-1, highlighted - 1); return .handled }
        .onExitCommand(perform: close)
    }

    private func tag(_ s: String, color: Color) -> some View {
        Text(s).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.bg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color))
    }

    private func submit() {
        let task = highlighted >= 0 && highlighted < tasks.count ? tasks[highlighted] : nil
        guard task != nil || !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.quickStart(text, task: task)
        close()
    }
}

/// A floating key panel that hosts the quick start view.
final class QuickStartPanel: NSPanel {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 120), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func makeContent() {
        // A fresh view each time, so the field starts empty and focused.
        let host = NSHostingView(rootView: QuickStartView(model: model, close: { [weak self] in self?.orderOut(nil) }))
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        makeContent()
        let size = contentView?.fittingSize ?? NSSize(width: 560, height: 120)
        setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - screen.visibleFrame.height * 0.22,
                        width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
