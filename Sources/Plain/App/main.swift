import AppKit

let args = CommandLine.arguments

func argument(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if args.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
} else if let dir = argument(after: "--snapshot") {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    Snapshot.run(to: URL(fileURLWithPath: dir))
    exit(0)
} else if let path = argument(after: "--make-icon") {
    AppIcon.write(to: URL(fileURLWithPath: path))
    exit(0)
} else if args.contains("--geometry") {
    _ = NSApplication.shared
    print(NotchGeometry.describe())
    exit(0)
} else if args.contains("--radio-check") {
    _ = NSApplication.shared
    var ok = true
    let only = Set(args.drop { $0 != "--radio-check" }.dropFirst())
    for station in Station.all where only.isEmpty || only.contains(station.id) {
        let result = RadioPlayer.check(station)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        print("\(station.name): \(result) — \(station.urls[0].absoluteString)")
        if result != "playing" { ok = false }
    }
    exit(ok ? 0 : 1)
} else if args.contains("--things-check") {
    _ = NSApplication.shared
    exit(ThingsCheck.run() ? 0 : 1)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
