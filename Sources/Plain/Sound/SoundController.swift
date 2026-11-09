import AppKit
import AVFoundation
import Combine

/// Two layers that play together: a SomaFM station (music) and an ambience (noise or nature).
final class SoundController: ObservableObject {
    private let d = UserDefaults.standard

    /// Station id, or nil for no music.
    @Published var station: String? {
        didSet { d.set(station ?? "", forKey: "sound.station"); if station != oldValue { musicChanged(from: oldValue) } }
    }
    /// Noise or nature sound, or nil for none.
    @Published var ambience: NoiseKind? {
        didSet { d.set(ambience?.rawValue ?? "", forKey: "sound.ambience"); if ambience != oldValue { ambienceChanged() } }
    }
    @Published var musicVolume: Double { didSet { d.set(musicVolume, forKey: "sound.musicVolume"); if musicOn { radio.fade(to: Float(musicVolume), over: 0.15) } } }
    @Published var ambienceVolume: Double { didSet { d.set(ambienceVolume, forKey: "sound.ambienceVolume"); if isPlaying && ambience != nil { noise.setGain(ambienceVolume, over: 0.15) } } }
    /// The session's sound is on (either layer).
    @Published private(set) var isPlaying = false
    /// The music layer is paused on its own (ambience keeps going).
    @Published private(set) var musicPaused = false
    @Published private(set) var status = ""

    /// PLAIN_TEST_MUTE: everything runs (engine, streams) but nothing is heard.
    // (muting lives in NoiseEngine and RadioPlayer)
    private let noise = NoiseEngine()
    private let radio = RadioPlayer()
    private let chimeEngine = AVAudioEngine()
    private let chimeNode = AVAudioPlayerNode()
    private var chimeReady = false

    init() {
        let st = UserDefaults.standard.string(forKey: "sound.station") ?? "sonicuniverse"
        station = st.isEmpty ? nil : st
        let amb = UserDefaults.standard.string(forKey: "sound.ambience") ?? "rain"
        ambience = NoiseKind(rawValue: amb)
        musicVolume = UserDefaults.standard.object(forKey: "sound.musicVolume") as? Double ?? 0.55
        ambienceVolume = UserDefaults.standard.object(forKey: "sound.ambienceVolume") as? Double ?? 0.3
        radio.onStatus = { [weak self] s in self?.status = s }
    }

    /// For test reports: is audio really flowing?
    var debugState: String {
        "playing=\(isPlaying) music=\(station ?? "-") musicOn=\(musicOn) radio=\(radio.isPlaying) radioStatus=\(status) ambience=\(ambience?.rawValue ?? "-") engine=\(noise.isRunning)"
    }

    var currentStation: Station? { station.flatMap { id in Station.all.first { $0.id == id } } }
    var musicOn: Bool { isPlaying && station != nil && !musicPaused }
    var hasAnything: Bool { station != nil || ambience != nil }

    /// "Sonic Universe + Rain"
    var summary: String {
        let parts = [currentStation?.name, ambience?.label].compactMap { $0 }
        return parts.isEmpty ? "Silence" : parts.joined(separator: " + ")
    }

    /// Starts both layers from silence.
    func fadeIn(seconds: Double = 4) {
        guard hasAnything else { return }
        isPlaying = true
        if let k = ambience {
            noise.setGain(0, over: 0.01)
            noise.play(k)
            noise.setGain(ambienceVolume, over: seconds)
        }
        if let st = currentStation, !musicPaused {
            radio.play(st)
            radio.fade(to: Float(musicVolume), over: seconds)
        }
    }

    func fadeOut(seconds: Double = 3) {
        guard isPlaying else { return }
        isPlaying = false
        noise.setGain(0, over: seconds)
        radio.fade(to: 0, over: seconds) { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.radio.pause()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.3) { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.noise.stop()
        }
    }

    func toggle() { isPlaying ? fadeOut(seconds: 1.2) : fadeIn(seconds: 1.5) }

    /// Play/pause the song without touching the ambience.
    func toggleMusic() {
        if station == nil { station = Station.all[0].id }
        if !isPlaying { musicPaused = false; fadeIn(seconds: 1.2); return }
        musicPaused.toggle()
        if musicPaused {
            radio.fade(to: 0, over: 0.8) { [weak self] in if self?.musicPaused == true { self?.radio.pause() } }
        } else if let st = currentStation {
            radio.play(st)
            radio.fade(to: Float(musicVolume), over: 1.2)
        }
    }

    /// Skips to the next station in the list.
    func nextStation() {
        let all = Station.all
        let i = station.flatMap { id in all.firstIndex { $0.id == id } } ?? -1
        station = all[(i + 1) % all.count].id
    }

    private func musicChanged(from old: String?) {
        guard isPlaying else { return }
        radio.stop()
        musicPaused = false
        if let st = currentStation {
            radio.play(st)
            radio.fade(to: Float(musicVolume), over: 1.2)
        } else if ambience == nil {
            isPlaying = false
        }
    }

    private func ambienceChanged() {
        guard isPlaying else { return }
        if let k = ambience {
            if noise.isRunning { noise.setKind(k) } else { noise.play(k) }
            noise.setGain(ambienceVolume, over: 0.8)
        } else {
            noise.setGain(0, over: 0.8)
            if station == nil { isPlaying = false }
        }
    }

    // MARK: Chime

    /// A soft two-note bell, synthesised.
    func chime() {
        let rate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        if !chimeReady {
            chimeEngine.attach(chimeNode)
            chimeEngine.connect(chimeNode, to: chimeEngine.mainMixerNode, format: format)
            chimeReady = true
        }
        let seconds = 2.6
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let notes: [(Double, Double)] = [(659.25, 0), (987.77, 0.22)] // E5 then B5
        for ch in 0..<2 {
            let data = buffer.floatChannelData![ch]
            for i in 0..<Int(frames) {
                let t = Double(i) / rate
                var v = 0.0
                for (f, start) in notes where t >= start {
                    let tt = t - start
                    let env = min(1, tt * 80) * exp(-tt * 2.4)
                    v += env * (sin(2 * .pi * f * tt) * 0.6 + sin(2 * .pi * f * 2.01 * tt) * 0.18 + sin(2 * .pi * f * 3.0 * tt) * 0.06)
                }
                data[i] = Float(v * 0.22)
            }
        }
        do {
            if !chimeEngine.isRunning { try chimeEngine.start() }
            chimeNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
            chimeNode.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) { [weak self] in
                self?.chimeNode.stop()
                self?.chimeEngine.stop()
            }
        } catch {
            NSSound(named: "Glass")?.play()
        }
    }
}
