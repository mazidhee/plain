import AVFoundation

enum NoiseKind: String, CaseIterable, Codable, Identifiable {
    case white, pink, brown, rain, ocean, stream, fire
    var id: String { rawValue }
    var label: String { self == .fire ? "Fireplace" : rawValue.capitalized }
    var isNature: Bool { self == .rain || self == .ocean || self == .stream || self == .fire }
    static var noises: [NoiseKind] { allCases.filter { !$0.isNature } }
    static var nature: [NoiseKind] { allCases.filter(\.isNature) }
}

/// Generated noise: no files. One AVAudioSourceNode fills buffers; gain ramps per sample, so fades never click.
final class NoiseEngine {
    private var engine: AVAudioEngine?
    private var node: AVAudioSourceNode?
    private let state = NoiseState()

    var isRunning: Bool { engine?.isRunning ?? false }

    func play(_ kind: NoiseKind) {
        state.kind = kind
        if engine == nil { build() }
        guard let engine, !engine.isRunning else { return }
        do { try engine.start() } catch { NSLog("Plain: noise engine failed: \(error)") }
    }

    func setKind(_ kind: NoiseKind) { state.kind = kind }

    /// Target gain 0...1; the render thread glides there over ~`seconds`.
    func setGain(_ gain: Double, over seconds: Double) {
        state.setTarget(Float(gain), seconds: seconds, sampleRate: 44_100)
    }

    var gain: Double { Double(state.target) }

    func stop() {
        engine?.stop()
    }

    private func build() {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let state = self.state
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let (l, r) = state.next()
                for (i, buffer) in buffers.enumerated() {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = i == 0 ? l : r
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        if ProcessInfo.processInfo.environment["PLAIN_TEST_MUTE"] != nil { engine.mainMixerNode.outputVolume = 0 }
        self.engine = engine
        self.node = node
    }
}

/// Lives on the audio thread. Plain stored values: a torn read only shifts a fade by a sample.
final class NoiseState {
    var kind: NoiseKind = .brown
    private(set) var target: Float = 0
    private var current: Float = 0
    private var step: Float = 0.0001
    private var seed: UInt32 = 0x1234_5678
    // Pink (Paul Kellet), brown and rain filters, per channel.
    private var pink = [[Float]](repeating: [0, 0, 0, 0, 0, 0, 0], count: 2)
    private var brown: [Float] = [0, 0]
    private var rainLow: [Float] = [0, 0]
    private var dropEnv: [Float] = [0, 0]
    private var dropTone: [Float] = [0, 0]
    private var phase: Double = 0
    private var low2: [Float] = [0, 0]
    private var high: [Float] = [0, 0]
    private var crackle: [Float] = [0, 0]

    func setTarget(_ gain: Float, seconds: Double, sampleRate: Double) {
        target = max(0, min(1, gain))
        let frames = max(1, Float(seconds * sampleRate))
        step = max(0.000_002, abs(target - current) / frames)
    }

    @inline(__always) private func rand() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24) * 2 - 1
    }

    func next() -> (Float, Float) {
        if current < target { current = min(target, current + step) } else if current > target { current = max(target, current - step) }
        let g = current * current // perceptual curve
        return (sample(0) * g, sample(1) * g)
    }

    private func sample(_ ch: Int) -> Float {
        let w = rand()
        switch kind {
        case .white:
            return w * 0.18
        case .pink:
            var b = pink[ch]
            b[0] = 0.99886 * b[0] + w * 0.0555179
            b[1] = 0.99332 * b[1] + w * 0.0750759
            b[2] = 0.96900 * b[2] + w * 0.1538520
            b[3] = 0.86650 * b[3] + w * 0.3104856
            b[4] = 0.55000 * b[4] + w * 0.5329522
            b[5] = -0.7616 * b[5] - w * 0.0168980
            let out = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
            b[6] = w * 0.115926
            pink[ch] = b
            return out * 0.06
        case .brown:
            brown[ch] = (brown[ch] + 0.02 * w) / 1.02
            return brown[ch] * 2.4
        case .rain:
            // Soft filtered hiss plus sparse droplets ringing briefly.
            rainLow[ch] += 0.08 * (w - rainLow[ch])
            if rand() > 0.9993 { dropEnv[ch] = 0.5 + 0.5 * abs(rand()); dropTone[ch] = 0 }
            dropEnv[ch] *= 0.9965
            dropTone[ch] += 0.21 + 0.05 * Float(ch)
            let drop = sin(dropTone[ch]) * dropEnv[ch] * 0.18 * w
            return rainLow[ch] * 0.55 + (w - rainLow[ch]) * 0.035 + drop
        case .ocean:
            // Brown surf swelling and drawing back every ~9 s, the two sides slightly apart.
            if ch == 0 { phase += 1.0 / 44_100 }
            let swell = 0.5 + 0.5 * sin(2 * .pi * (phase / 9.0) + Double(ch) * 0.7)
            brown[ch] = (brown[ch] + 0.02 * w) / 1.02
            rainLow[ch] += 0.05 * (w - rainLow[ch])
            let surf = Float(pow(swell, 2.2))
            return brown[ch] * (0.9 + 2.2 * surf) + rainLow[ch] * 0.35 * surf
        case .stream:
            // Bright trickle plus little bubbles.
            low2[ch] += 0.3 * (w - low2[ch])
            high[ch] = low2[ch] - rainLow[ch]
            rainLow[ch] += 0.02 * (low2[ch] - rainLow[ch])
            if rand() > 0.9985 { dropEnv[ch] = 0.3 + 0.3 * abs(rand()); dropTone[ch] = 0 }
            dropEnv[ch] *= 0.9985
            dropTone[ch] += 0.06 + 0.04 * dropEnv[ch]
            return high[ch] * 0.22 * (0.8 + 0.2 * sin(dropTone[ch] * 0.05)) + sin(dropTone[ch]) * dropEnv[ch] * 0.08
        case .fire:
            // Low rumble with crackles and pops.
            brown[ch] = (brown[ch] + 0.02 * w) / 1.02
            if rand() > 0.9992 { crackle[ch] = 0.6 + 0.4 * abs(rand()) }
            crackle[ch] *= 0.985
            high[ch] = w - low2[ch]
            low2[ch] += 0.4 * (w - low2[ch])
            return brown[ch] * 1.3 + high[ch] * crackle[ch] * 0.5
        }
    }
}
