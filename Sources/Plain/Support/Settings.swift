import Foundation
import ServiceManagement

/// A hotkey choice. Carbon key codes and modifier masks.
struct HotKeyPreset: Identifiable, Equatable {
    var id: String
    var label: String
    var keyCode: UInt32
    var modifiers: UInt32

    // cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000
    static let all: [HotKeyPreset] = [
        HotKeyPreset(id: "ctrl-opt-f", label: "⌃⌥F", keyCode: 3, modifiers: 0x1000 | 0x800),
        HotKeyPreset(id: "ctrl-opt-space", label: "⌃⌥Space", keyCode: 49, modifiers: 0x1000 | 0x800),
        HotKeyPreset(id: "opt-cmd-f", label: "⌥⌘F", keyCode: 3, modifiers: 0x800 | 0x100),
        HotKeyPreset(id: "ctrl-cmd-f", label: "⌃⌘F", keyCode: 3, modifiers: 0x1000 | 0x100),
        HotKeyPreset(id: "ctrl-opt-p", label: "⌃⌥P", keyCode: 35, modifiers: 0x1000 | 0x800),
    ]

    static func named(_ id: String) -> HotKeyPreset { all.first { $0.id == id } ?? all[0] }
}

/// User preferences, saved in UserDefaults (com.mazidhee.plain).
final class Settings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var islandEnabled: Bool { didSet { d.set(islandEnabled, forKey: "islandEnabled") } }
    @Published var tidePrompt: Bool { didSet { d.set(tidePrompt, forKey: "tidePrompt") } }
    @Published var editorNudge: Bool { didSet { d.set(editorNudge, forKey: "editorNudge") } }
    @Published var hotkeyEnabled: Bool { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var hotkey: String { didSet { d.set(hotkey, forKey: "hotkey") } }
    @Published var durations: [Int] { didSet { d.set(durations, forKey: "durations") } }
    @Published var defaultMinutes: Int { didSet { d.set(defaultMinutes, forKey: "defaultMinutes") } }
    @Published var breaksEnabled: Bool { didSet { d.set(breaksEnabled, forKey: "breaksEnabled") } }
    @Published var shortBreak: Int { didSet { d.set(shortBreak, forKey: "shortBreak") } }
    @Published var longBreak: Int { didSet { d.set(longBreak, forKey: "longBreak") } }
    @Published var autoSound: Bool { didSet { d.set(autoSound, forKey: "autoSound") } }
    @Published var thingsLogging: Bool { didSet { d.set(thingsLogging, forKey: "thingsLogging") } }
    @Published var colorIcon: Bool { didSet { d.set(colorIcon, forKey: "colorIcon") } }
    @Published var menuBarTime: Bool { didSet { d.set(menuBarTime, forKey: "menuBarTime") } }
    @Published var chimeEnabled: Bool { didSet { d.set(chimeEnabled, forKey: "chimeEnabled") } }
    /// Record how long each app is in front (local only).
    @Published var appTracking: Bool { didSet { d.set(appTracking, forKey: "appTracking") } }
    /// Scene behind Wren: "auto" follows the app in front and the session.
    @Published var scene: String { didSet { d.set(scene, forKey: "scene") } }
    /// Things area per category (category raw value → area title), so Work lists your work to-dos.
    @Published var categoryAreas: [String: String] { didSet { d.set(categoryAreas, forKey: "categoryAreas") } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !applyingLogin else { return }
            setLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var loginStatus = ""
    private var applyingLogin = false

    init() {
        d.register(defaults: [
            "islandEnabled": false, "tidePrompt": true, "editorNudge": true, "hotkeyEnabled": true,
            "hotkey": "ctrl-opt-f", "durations": [25, 40, 50], "defaultMinutes": 25, "breaksEnabled": false,
            "shortBreak": 5, "longBreak": 15, "autoSound": true, "thingsLogging": true, "colorIcon": true,
            "menuBarTime": true, "chimeEnabled": true, "scene": "auto", "appTracking": true,
        ])
        islandEnabled = d.bool(forKey: "islandEnabled")
        tidePrompt = d.bool(forKey: "tidePrompt")
        editorNudge = d.bool(forKey: "editorNudge")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        hotkey = d.string(forKey: "hotkey") ?? "ctrl-opt-f"
        durations = (d.array(forKey: "durations") as? [Int]) ?? [25, 40, 50]
        defaultMinutes = d.integer(forKey: "defaultMinutes")
        breaksEnabled = d.bool(forKey: "breaksEnabled")
        shortBreak = d.integer(forKey: "shortBreak")
        longBreak = d.integer(forKey: "longBreak")
        autoSound = d.bool(forKey: "autoSound")
        thingsLogging = d.bool(forKey: "thingsLogging")
        colorIcon = d.bool(forKey: "colorIcon")
        menuBarTime = d.bool(forKey: "menuBarTime")
        chimeEnabled = d.bool(forKey: "chimeEnabled")
        scene = d.string(forKey: "scene") ?? "auto"
        appTracking = d.bool(forKey: "appTracking")
        categoryAreas = (d.dictionary(forKey: "categoryAreas") as? [String: String]) ?? [:]
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshLoginStatus()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginStatus = error.localizedDescription
        }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        applyingLogin = true
        launchAtLogin = status == .enabled
        applyingLogin = false
        switch status {
        case .enabled: loginStatus = "Opens at login"
        case .requiresApproval: loginStatus = "Approve Plain in System Settings › General › Login Items"
        case .notRegistered: if loginStatus.isEmpty || loginStatus.hasPrefix("Opens") || loginStatus.hasPrefix("Approve") { loginStatus = "" }
        case .notFound: loginStatus = "Install Plain in /Applications to open at login"
        @unknown default: break
        }
    }
}
