import AppKit

/// Watches which app is in front, for the Tide prompt and the editor nudge.
final class AppWatcher {
    /// Tide's bundle id, read from its Info.plist (falls back to the known id).
    static let tideBundleID: String = {
        let url = URL(fileURLWithPath: "/Applications/Tide.app/Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: url), let id = dict["CFBundleIdentifier"] as? String { return id }
        return "app.tide.study"
    }()

    static let editorBundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.apple.dt.Xcode", "com.sublimetext.4", "com.panic.Nova", "com.apple.Terminal", "com.googlecode.iterm2",
        "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
        "com.exafunction.windsurf", "com.vscodium",
    ]

    static func isEditor(_ id: String?) -> Bool {
        guard let id else { return false }
        return editorBundleIDs.contains(id) || id.hasPrefix("com.jetbrains.") || id.hasPrefix("com.google.android.studio")
    }

    var onTide: (() -> Void)?
    var onActivate: ((String?) -> Void)?
    var onEditorDwell: (() -> Void)?
    /// How long an editor must stay in front before the nudge.
    var dwell: TimeInterval = 120

    private var editorTimer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.activated(app?.bundleIdentifier)
        }
    }

    private func activated(_ id: String?) {
        editorTimer?.invalidate()
        editorTimer = nil
        // Plain's own popover doesn't count as "what you're doing".
        if id != Bundle.main.bundleIdentifier { onActivate?(id) }
        if id == Self.tideBundleID { onTide?() }
        if Self.isEditor(id) {
            editorTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
                guard Self.isEditor(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return }
                self?.onEditorDwell?()
            }
        }
    }
}
