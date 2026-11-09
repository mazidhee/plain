import AppKit
import Combine
import SwiftUI

/// A borderless, non-activating panel above the menu bar, on every Space.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }

    // Lets the Tide prompt's text field take typing without activating Plain.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Decides what the island shows and keeps the panel sized to it, so it never blocks the menu bar.
final class IslandController {
    let state: IslandState
    let panel = IslandPanel()
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()
    private var hovering = false
    private var collapseWork: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?
    private var doneWork: DispatchWorkItem?
    private var lastPhase: SessionMachine.Phase = .idle

    init(model: AppModel) {
        self.model = model
        state = IslandState(geometry: NotchGeometry.current() ?? NotchGeometry(screenFrame: .zero, notch: nil, menuBarHeight: 24))
        let host = NSHostingView(rootView: IslandView(state: state, model: model, onHover: { [weak self] in self?.hover($0) }))
        host.wantsLayer = true
        panel.contentView = host

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.update() } }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshGeometry()
        }
    }

    func refreshGeometry() {
        if let g = NotchGeometry.current() { state.geometry = g }
        place(for: state.mode, animated: false)
    }

    /// The mode the model asks for, ignoring hover.
    private func desiredMode() -> IslandMode {
        guard model.settings.islandEnabled else { return .hidden }
        if model.prompt != nil, model.phase == .idle {
            if case .tide = model.prompt { return .prompt }
            return .nudge
        }
        if model.isRunning { return hovering ? .expanded : .compact }
        if model.phase == .summary && doneWork != nil { return .done }
        return .hidden
    }

    func update() {
        // Flash a "done" pill for a few seconds when a focus block ends.
        if model.phase == .summary && lastPhase == .focus {
            doneWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.doneWork = nil; self?.update() }
            doneWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
        }
        if model.phase != .summary { doneWork?.cancel(); doneWork = nil }
        lastPhase = model.phase

        // Prompts dismiss themselves unless hovered.
        if model.prompt != nil && dismissWork == nil {
            scheduleDismiss(after: model.prompt == .tide ? 45 : 15)
        } else if model.prompt == nil {
            dismissWork?.cancel(); dismissWork = nil
        }

        let mode = desiredMode()
        if mode != state.mode { transition(to: mode) }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.hovering { self.scheduleDismiss(after: 10); return }
            self.dismissWork = nil
            self.model.prompt = nil
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private var spring: Animation {
        Animator.shared.reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    func transition(to mode: IslandMode) {
        let old = state.mode
        let oldSize = state.size(for: old), newSize = state.size(for: mode)
        let growing = newSize.width * newSize.height >= oldSize.width * oldSize.height
        if old == .hidden {
            // Start as a sliver the size of the notch, then grow out of it.
            place(for: mode, animated: false)
            panel.orderFrontRegardless()
            withAnimation(spring) { state.mode = mode }
        } else if growing {
            place(for: mode, animated: false, union: old)
            withAnimation(spring) { state.mode = mode }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.state.mode == mode else { return }
                self.place(for: mode, animated: false)
            }
        } else {
            withAnimation(spring) { state.mode = mode }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.state.mode == mode else { return }
                if mode == .hidden { self.panel.orderOut(nil) } else { self.place(for: mode, animated: false) }
            }
        }
        if mode != .hidden { panel.orderFrontRegardless() }
    }

    /// Sizes the panel to the pill (or the union of two modes while animating), hanging from the top.
    private func place(for mode: IslandMode, animated: Bool, union other: IslandMode? = nil) {
        var size = state.size(for: mode)
        if let other {
            let o = state.size(for: other)
            size = CGSize(width: max(size.width, o.width), height: max(size.height, o.height))
        }
        // Room for the shadow, except for the slim pill, which must not cover anything below it.
        if !(mode == .compact || mode == .done) || other != nil { size.height += 24 }
        let g = state.geometry
        let frame = NSRect(x: (g.centerX - size.width / 2).rounded(), y: g.topY - size.height, width: size.width.rounded(), height: size.height)
        panel.setFrame(frame, display: true, animate: animated)
    }

    /// The pill's frame in global coordinates (without the shadow margin), for checks.
    var pillFrame: NSRect {
        let s = state.size(for: state.mode)
        let g = state.geometry
        return NSRect(x: g.centerX - s.width / 2, y: g.topY - s.height, width: s.width, height: s.height)
    }

    private func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            hovering = true
            update()
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.hovering = false
                self?.update()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }
}
