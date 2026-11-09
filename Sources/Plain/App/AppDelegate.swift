import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var island: IslandController?
    private var quickStart: QuickStartPanel?
    private var settingsWindow: NSWindow?
    private var hotKey: HotKey?
    private let watcher = AppWatcher()
    private var cancellables = Set<AnyCancellable>()
    private var lastIconKey = ""

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Animator.shared.start()
        model.startTicking()
        model.refreshTasks()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("Plain focus timer")

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingController(rootView: PopoverView(model: model, openSettings: { [weak self] in self?.openSettings() }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        island = IslandController(model: model)

        // Animate the menu bar character on the shared clock, and when the activity changes.
        Animator.shared.$tick.merge(with: Just(0)).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        model.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.updateIcon(); self?.syncAnimator(); self?.syncDrop() } }.store(in: &cancellables)

        // Hotkey, re-registered when the setting changes.
        model.settings.$hotkey.combineLatest(model.settings.$hotkeyEnabled)
            .sink { [weak self] id, on in self?.registerHotKey(id, on) }.store(in: &cancellables)

        watcher.onTide = { [weak self] in
            guard let self, self.model.settings.tidePrompt, self.model.canPrompt() else { return }
            self.model.showPrompt(.tide)
            // Without the island, the question drops down from the menu bar instead, without taking focus.
            if !self.model.settings.islandEnabled {
                self.showDrop(DropCard { TidePrompt(model: self.model) })
                self.dropShowsPrompt = true
            }
        }
        watcher.onEditorDwell = { [weak self] in
            // Quiet: with the island off this only marks the menu bar icon.
            guard let self, self.model.settings.editorNudge, self.model.canPrompt(cooldown: 30 * 60) else { return }
            let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "your editor"
            self.model.showPrompt(.editor(appName: name))
        }
        watcher.onActivate = { [weak self] id in self?.model.frontBundleID = id }
        model.frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        watcher.start()

        // A session started from Things (plain://) or a time block drops the popover down for a moment.
        model.onExternalStart = { [weak self] in
            guard let self else { return }
            guard !self.popover.isShown else { return }
            self.dropShowsPrompt = false
            self.showDrop(StartedToast(model: self.model), autoHide: 4)
        }

        if let path = ProcessInfo.processInfo.environment["PLAIN_REPORT_ISLAND"] { reportIsland(to: path) }
        if ProcessInfo.processInfo.environment["PLAIN_TEST_PANEL"] != nil { showTestPanel() }
    }

    /// Test hook (PLAIN_TEST_PANEL): the popover's content in a fixed, non-activating panel, so a
    /// scripted pointer can drive it while other apps keep focus.
    private var testPanel: DropPanel?
    private func showTestPanel() {
        let panel = DropPanel()
        let host = NSHostingView(rootView: PopoverView(model: model, openSettings: { [weak self] in self?.openSettings() })
            .frame(maxHeight: .infinity, alignment: .top))
        panel.contentView = host
        panel.level = .floating
        let size = NSSize(width: 368, height: 780)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 8, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        testPanel = panel
    }

    /// The Tide prompt card goes away once it's answered or dismissed.
    private func syncDrop() {
        if dropShowsPrompt, model.prompt == nil {
            dropShowsPrompt = false
            drop.dismiss()
        }
    }

    private func syncAnimator() {
        let fps = model.activity.fps
        if Animator.shared.fps != fps { Animator.shared.fps = fps }
    }

    private func registerHotKey(_ id: String, _ on: Bool) {
        hotKey = nil
        guard on else { return }
        let preset = HotKeyPreset.named(id)
        hotKey = HotKey(keyCode: preset.keyCode, modifiers: preset.modifiers) { [weak self] in self?.showQuickStart() }
        if hotKey == nil { NSLog("Plain: hotkey \(preset.label) is taken by another app") }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let tick = Animator.shared.frameTick
        let color = model.settings.colorIcon
        let activity = model.activity
        let showTime = model.settings.menuBarTime && model.isRunning
        var title = ""
        if showTime {
            title = model.isTracker
                ? " ↑\(Int((model.elapsed / model.machine.secondsPerMinute).rounded(.down)))m"
                : " \(Int((model.remaining / model.machine.secondsPerMinute).rounded(.up)))m"
        }
        if model.prompt != nil && !model.settings.islandEnabled { title = " ✦" }
        let key = "\(activity.rawValue)-\(tick)-\(color)-\(title)"
        guard key != lastIconKey else { return }
        lastIconKey = key
        let grid = Wren.frame(activity, tick: tick, bob: model.sound.musicOn)
        button.image = color
            ? PixelRenderer.nsImage(isDarkBar(button) ? grid.outlined(with: "O") : grid, palette: Wren.palette)
            : PixelRenderer.nsImage(grid, palette: Wren.palette, alphaMap: Wren.templateAlpha, template: true)
        if button.title != title {
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .baselineOffset: 0.5,
            ])
        }
    }

    private func isDarkBar(_ button: NSStatusBarButton) -> Bool {
        button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: Popover, quick start, settings

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { showPopover() }
    }

    private let drop = DropPanel()
    private var dropShowsPrompt = false

    /// A non-activating card under the menu bar icon.
    func showDrop<V: View>(_ content: V, autoHide: TimeInterval? = nil) {
        guard let anchor = statusItem.button?.window?.frame else { return }
        drop.show(content, under: anchor, autoHide: autoHide)
    }

    /// Opens the popover. `activate: false` drops it down without taking focus from the app in front.
    func showPopover(activate: Bool = true) {
        guard !popover.isShown else { return }
        drop.dismiss()
        if let button = statusItem.button {
            model.refreshTasks()
            if activate { NSApp.activate(ignoringOtherApps: true) }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if activate { popover.contentViewController?.view.window?.makeKey() }
        }
    }

    func showQuickStart() {
        if quickStart == nil { quickStart = QuickStartPanel(model: model) }
        quickStart?.show()
    }

    func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: model.settings, model: model)))
            w.title = "Plain Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: string) else { return }
        model.handle(url: url)
    }

    /// Debug: writes the notch and island frames to a file every few seconds (PLAIN_REPORT_ISLAND=<path>).
    private func reportIsland(to path: String) {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let island = self.island else { return }
            let text = """
            \(NotchGeometry.describe())
            mode=\(island.state.mode) panelFrame=\(island.panel.frame) visible=\(island.panel.isVisible) level=\(island.panel.level.rawValue)
            pillFrame=\(island.pillFrame)
            phase=\(self.model.phase) remaining=\(Int(self.model.remaining)) elapsed=\(Int(self.model.elapsed)) prompt=\(String(describing: self.model.prompt))
            front=\(self.model.frontBundleID ?? "nil") leftTide=\(String(describing: self.model.leftTideAt)) tracker=\(self.model.isTracker) tied=\(self.model.plan?.tiedToTide ?? false)
            statusItem=\(self.statusItem.button?.window?.frame ?? .zero) drop=\(self.drop.isVisible) dropFrame=\(self.drop.frame) popoverShown=\(self.popover.isShown) popoverFrame=\(self.testPanel?.frame ?? self.popover.contentViewController?.view.window?.frame ?? .zero) active=\(NSApp.isActive)
            sound: \(self.model.sound.debugState)
            plan: title=\(self.model.plan?.title ?? "-") task=\(self.model.plan?.taskID ?? "-") lockIn=\(self.model.plan?.lockIn ?? false) open=\(self.model.plan?.openEnded ?? false) mode=\(self.model.draftCategory.rawValue) selected=\(self.model.selectedTask?.title ?? "-") scheduled=\(String(describing: self.model.scheduled?.start)) summary=\(self.model.summaryNote ?? "-") quickStartVisible=\(self.quickStart?.isVisible ?? false)

            """
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
