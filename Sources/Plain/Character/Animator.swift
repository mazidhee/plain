import AppKit
import Combine

/// One cheap clock for every animation: a few frames a second, stopped while the screen sleeps,
/// frozen on a still frame when Reduce Motion is on.
final class Animator: ObservableObject {
    static let shared = Animator()

    @Published private(set) var tick = 0
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var fps: Double = 4 { didSet { if fps != oldValue { restart() } } }

    private var timer: Timer?
    private var asleep = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = true; self?.restart()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = false; self?.restart()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self?.restart()
        })
        restart()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        guard !asleep, !reduceMotion, fps > 0 else { return }
        let t = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in self?.tick &+= 1 }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The tick a frame should use: always 0 under Reduce Motion.
    var frameTick: Int { reduceMotion ? 0 : tick }
}
