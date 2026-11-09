import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var model: AppModel
    @StateObject private var durationsTextBox = Box("")
    private var durationsText: String { get { durationsTextBox.value } nonmutating set { durationsTextBox.value = newValue } }

    var body: some View {
        Form {
            Section("Island") {
                Toggle("Show the notch island during sessions (preview)", isOn: $settings.islandEnabled)
                Toggle("Ask “What are we doing?” when Tide opens", isOn: $settings.tidePrompt)
                Text("Without the island, the question drops down from the menu bar icon.").font(.caption).foregroundStyle(.secondary)
                Toggle("Nudge a work session after 2 min in a code editor or terminal", isOn: $settings.editorNudge)
            }
            Section("Sessions") {
                Picker("Quick start hotkey", selection: $settings.hotkey) {
                    ForEach(HotKeyPreset.all) { Text($0.label).tag($0.id) }
                }
                Toggle("Hotkey enabled", isOn: $settings.hotkeyEnabled)
                TextField("Duration presets (minutes)", text: $durationsTextBox.value)
                    .onSubmit(saveDurations)
                Stepper("Default length: \(settings.defaultMinutes) min", value: $settings.defaultMinutes, in: 5...180, step: 5)
                Toggle("Pomodoro breaks", isOn: $settings.breaksEnabled)
                Stepper("Short break: \(settings.shortBreak) min", value: $settings.shortBreak, in: 1...30)
                Stepper("Long break (every 4th): \(settings.longBreak) min", value: $settings.longBreak, in: 5...60)
                Toggle("Soft chime at the end", isOn: $settings.chimeEnabled)
            }
            Section("Sound") {
                Toggle("Fade sound in and out with sessions", isOn: $settings.autoSound)
                SoundBar(sound: model.sound)
            }
            Section("Things 4") {
                Toggle("Log focus time to Things 4", isOn: $settings.thingsLogging)
                Text("Each mode only offers to-dos from its Things area. Auto matches by name: Work → “Work”, Study and Exam → “Learning” or “Study”.").font(.caption).foregroundStyle(.secondary)
                ForEach(Category.allCases) { c in
                    Picker(c.label, selection: Binding(
                        get: { settings.categoryAreas[c.rawValue] ?? "" },
                        set: { settings.categoryAreas[c.rawValue] = $0.isEmpty ? nil : $0; model.refreshAreaTasks() }
                    )) {
                        Text("Auto\(model.area(for: c).map { " (\($0))" } ?? " (Today list)")").tag("")
                        Text("Today list").tag("-")
                        ForEach(model.areaTitles, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text(thingsText).font(.caption).foregroundStyle(.secondary)
            }
            Section("Tide and app time") {
                Toggle("Record time per app in front (local only)", isOn: $settings.appTracking)
                Text("Away time isn't counted: five quiet minutes or sleep stop the clock. Nothing goes to Things.").font(.caption).foregroundStyle(.secondary)
                Text(model.tide.available
                     ? "Reading Tide's study log (read-only): \(TideLog.logURL?.path ?? "")"
                     : "Tide study log: \(model.tide.problem ?? "not found")").font(.caption).foregroundStyle(.secondary)
            }
            Section("Scene") {
                Picker("Background", selection: $settings.scene) {
                    ForEach(SceneKind.allCases) { Text($0 == .auto ? "Auto (follows what you're doing)" : $0.label).tag($0.rawValue) }
                }
                Text("Auto: code den when an editor or terminal is in front, library for study, beach on breaks.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Colour character (off: monochrome template icon)", isOn: $settings.colorIcon)
                Toggle("Show minutes left next to the character", isOn: $settings.menuBarTime)
                Toggle("Open Plain at login", isOn: $settings.launchAtLogin)
                if !settings.loginStatus.isEmpty { Text(settings.loginStatus).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onAppear {
            durationsText = settings.durations.map(String.init).joined(separator: ", ")
            settings.refreshLoginStatus()
            model.refreshAreaTasks()
        }
        .onDisappear(perform: saveDurations)
    }

    private var thingsText: String {
        let path = ThingsClient.configURL.path
        switch model.thingsStatus {
        case .connected: return "Connected via \(path). \(model.pendingLogs) entries waiting."
        case .offline(let why): return "\(why) Entries wait in a local queue (\(model.pendingLogs) now) and retry every 3 minutes."
        case .unknown: return "Reads the token from \(path)."
        }
    }

    private func saveDurations() {
        let values = durationsText.split(whereSeparator: { ", ".contains($0) }).compactMap { Int($0) }.filter { (1...240).contains($0) }
        if !values.isEmpty { settings.durations = Array(values.prefix(4)) }
    }
}
