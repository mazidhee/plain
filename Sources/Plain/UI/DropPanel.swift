import AppKit
import SwiftUI

/// A card that drops down under the menu bar icon without activating Plain.
///
/// Why not the popover: showing an NSPopover makes Plain the active app, and when it closes
/// macOS hands focus back to whichever app was active before, so Tide (or Things) jumped back
/// to the front a few seconds after you'd switched away. A non-activating panel never takes
/// focus, so closing it can't move focus anywhere.
final class DropPanel: NSPanel {
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    // Lets the prompt's text field take typing (without activating Plain).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Shows `content` under `anchor` (the status item's window frame, in screen coordinates).
    func show<V: View>(_ content: V, under anchor: NSRect, autoHide: TimeInterval? = nil) {
        hideWork?.cancel()
        let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        contentView = host
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        var x = anchor.midX - size.width / 2
        if let f = screen?.visibleFrame { x = min(max(f.minX + 8, x), f.maxX - size.width - 8) }
        setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
        if let autoHide {
            let work = DispatchWorkItem { [weak self] in self?.dismiss() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: work)
        }
    }

    func dismiss() {
        hideWork?.cancel()
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.orderOut(nil) })
    }
}

/// The dark card the drop panel shows.
struct DropCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Space.l)
            .frame(width: 360)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

/// "Focusing on …" after a session starts from a link or a time block.
struct StartedToast: View {
    @ObservedObject var model: AppModel
    @ObservedObject var animator = Animator.shared

    var body: some View {
        DropCard {
            HStack(spacing: Space.m) {
                PixelView(grid: Wren.frame(model.activity, tick: animator.frameTick), palette: Wren.palette, pixel: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.plan?.displayTitle ?? "Focus").font(TypeScale.bodyStrong).foregroundStyle(Theme.text).lineLimit(2)
                    Text("\(model.plan?.category.label ?? "") · \(model.isTracker ? "counting up" : "\(model.plan?.minutes ?? 0) min")")
                        .font(TypeScale.meta).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                PixelClock(text: model.clockText, pixel: 3, ink: Theme.textInk)
            }
        }
    }
}
