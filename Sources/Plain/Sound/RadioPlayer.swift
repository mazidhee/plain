import AVFoundation

/// A SomaFM station. Listener-supported: somafm.com.
struct Station: Identifiable, Equatable, Codable, Hashable {
    var id: String
    var name: String
    var blurb: String
    var genre: String = "Chill"

    /// Mirrors from SomaFM's own playlists; tried in order when one fails.
    var urls: [URL] {
        ["ice2", "ice6", "ice5", "ice4"].flatMap { host in
            ["\(id)-128-mp3", "\(id)-128-aac"].compactMap { URL(string: "https://\(host).somafm.com/\($0)") }
        }
    }

    static let all: [Station] = [
        Station(id: "sonicuniverse", name: "Sonic Universe", blurb: "Modern jazz", genre: "Jazz & soul"),
        Station(id: "bossa", name: "Bossa Beyond", blurb: "Bossa nova", genre: "Jazz & soul"),
        Station(id: "illstreet", name: "Illinois St Lounge", blurb: "Classic lounge", genre: "Jazz & soul"),
        Station(id: "7soul", name: "Seven Inch Soul", blurb: "Vintage soul 45s", genre: "Jazz & soul"),
        Station(id: "secretagent", name: "Secret Agent", blurb: "Spy lounge", genre: "Jazz & soul"),
        Station(id: "groovesalad", name: "Groove Salad", blurb: "Ambient grooves", genre: "Chill"),
        Station(id: "fluid", name: "Fluid", blurb: "Instrumental hip hop", genre: "Chill"),
        Station(id: "lush", name: "Lush", blurb: "Mellow vocals", genre: "Chill"),
        Station(id: "dronezone", name: "Drone Zone", blurb: "Deep ambient", genre: "Chill"),
        Station(id: "defcon", name: "DEF CON", blurb: "Hacker focus beats", genre: "Focus & retro"),
        Station(id: "beatblender", name: "Beat Blender", blurb: "Deep house", genre: "Focus & retro"),
        Station(id: "vaporwaves", name: "Vaporwaves", blurb: "Retro dreamy", genre: "Focus & retro"),
        Station(id: "u80s", name: "Underground 80s", blurb: "Synthpop", genre: "Focus & retro"),
        Station(id: "seventies", name: "Left Coast 70s", blurb: "Mellow 70s", genre: "Focus & retro"),
    ]

    static var genres: [String] { var seen: [String] = []; for s in all where !seen.contains(s.genre) { seen.append(s.genre) }; return seen }
}

/// Streams a station with AVPlayer, with volume glides for fades.
final class RadioPlayer {
    private var player: AVPlayer?
    private var station: Station?
    private var urlIndex = 0
    private var fadeTimer: Timer?
    private var statusObservation: NSKeyValueObservation?
    private(set) var volume: Float = 0
    static let muted = ProcessInfo.processInfo.environment["PLAIN_TEST_MUTE"] != nil
    var onStatus: ((String) -> Void)?

    var isPlaying: Bool { player?.timeControlStatus == .playing || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate }

    func play(_ station: Station) {
        if self.station == station, let player { player.play(); return }
        self.station = station
        urlIndex = 0
        start()
    }

    private func start() {
        guard let station, urlIndex < station.urls.count else { onStatus?("Station unavailable"); return }
        let item = AVPlayerItem(url: station.urls[urlIndex])
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if item.status == .failed {
                    self.urlIndex += 1
                    self.start()
                } else if item.status == .readyToPlay {
                    self.onStatus?("Live")
                }
            }
        }
        if player == nil {
            player = AVPlayer(playerItem: item)
            player?.automaticallyWaitsToMinimizeStalling = true
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.volume = Self.muted ? 0 : volume
        player?.play()
        onStatus?("Tuning in…")
    }

    func fade(to target: Float, over seconds: Double, then done: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        let start = volume
        let steps = max(1, Int(seconds * 20))
        var i = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            i += 1
            let p = Float(i) / Float(steps)
            self.volume = start + (target - start) * p
            self.player?.volume = Self.muted ? 0 : self.volume * self.volume
            if i >= steps { t.invalidate(); done?() }
        }
    }

    func pause() { player?.pause() }

    func stop() {
        fadeTimer?.invalidate()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        station = nil
    }

    /// Plays each station muted until it is ready, for `--radio-check`.
    static func check(_ station: Station, timeout: TimeInterval = 25) -> String {
        let player = AVPlayer(url: station.urls[0])
        player.volume = 0
        player.play()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            if player.currentItem?.status == .failed {
                let why = player.currentItem?.error?.localizedDescription ?? "?"
                player.replaceCurrentItem(with: nil)
                return "failed: \(why)"
            }
            if player.timeControlStatus == .playing, (player.currentItem?.currentTime().seconds ?? 0) > 0.5 {
                // Close the stream properly: SomaFM limits open connections per listener.
                player.pause(); player.replaceCurrentItem(with: nil)
                return "playing"
            }
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        return "timed out (\(player.currentItem?.status == .readyToPlay ? "ready" : "not ready"))"
    }
}
