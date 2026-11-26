import AppKit
import Foundation

/// The app's two small sounds, synthesized in code (no audio files): a light mechanical rattle as
/// the board's flaps land, and soft ticks for the sleep countdown.
///
/// Each can be turned off in the panel. Both stay quiet when "Play user interface sound effects"
/// is off in System Settings › Sound.
@MainActor
public enum Sounds {
    public enum Kind: String, CaseIterable, Sendable {
        case flip, countdown

        var defaultsKey: String { "\(rawValue)Sound" }
    }

    public static func isEnabled(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.defaultsKey) as? Bool ?? true
    }

    static func setEnabled(_ kind: Kind, _ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: kind.defaultsKey)
    }

    /// The system's "Play user interface sound effects" setting (on unless turned off).
    static var systemAllowsUISounds: Bool {
        (UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? Int) != 0
    }

    /// The rattle for a board change, one click per flap landing, timed like the animation.
    /// With Reduce motion the board just fades, so it's a single click.
    public static func playFlip(from old: String, to new: String, reduceMotion: Bool = false) {
        guard isEnabled(.flip), systemAllowsUISounds else { return }
        if reduceMotion {
            if old != new { play(Synth.rattle(at: [0], style: FlipSoundStyle.saved)) }
            return
        }
        let oldChars = SplitFlapBoard.pad(old)
        let newChars = SplitFlapBoard.pad(new)
        var times: [Double] = []
        for i in 0..<SplitFlapBoard.tileCount where oldChars[i] != newChars[i] {
            let start = SplitFlapTiming.stagger * Double(i)
            for step in 1...3 { times.append(start + SplitFlapTiming.flip * Double(step)) }
        }
        guard !times.isEmpty else { return }
        play(Synth.rattle(at: times, style: FlipSoundStyle.saved))
    }

    /// The flip times for a whole-board change, for previews.
    static var fullBoardTimes: [Double] {
        (0..<SplitFlapBoard.tileCount).flatMap { i in
            (1...3).map { SplitFlapTiming.stagger * Double(i) + SplitFlapTiming.flip * Double($0) }
        }
    }

    /// Plays a style once when it's picked, so you hear what you chose.
    public static func previewFlip(_ style: FlipSoundStyle) {
        guard systemAllowsUISounds else { return }
        let times = (0..<7).flatMap { i in
            (1...3).map { SplitFlapTiming.stagger * Double(i) + SplitFlapTiming.flip * Double($0) }
        }
        play(Synth.rattle(at: times, style: style))
    }

    /// One countdown tick.
    public static func playTick() {
        guard isEnabled(.countdown), systemAllowsUISounds else { return }
        play(Synth.tick)
    }

    /// The soft tone just before the Mac sleeps.
    public static func playSleepTone() {
        guard isEnabled(.countdown), systemAllowsUISounds else { return }
        play(Synth.sleepTone)
    }

    /// Writes the sounds as WAV files, to listen to them outside the app.
    public static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in FlipSoundStyle.allCases {
            try Synth.rattle(at: fullBoardTimes, style: style)
                .write(to: directory.appendingPathComponent("flip-\(style.rawValue).wav"))
        }
        try Synth.tick.write(to: directory.appendingPathComponent("tick.wav"))
        try Synth.sleepTone.write(to: directory.appendingPathComponent("sleep-tone.wav"))
    }

    /// Sounds still playing, kept alive until they finish.
    private static var playing: [NSSound] = []

    private static func play(_ wav: Data) {
        guard let sound = NSSound(data: wav) else { return }
        playing.removeAll { !$0.isPlaying }
        playing.append(sound)
        sound.play()
    }
}

/// The click each flap makes as it lands. Picked in the panel; Original by default.
public enum FlipSoundStyle: String, CaseIterable, Sendable {
    case original, paper, mechanical, wooden

    public var title: String {
        switch self {
        case .original: "Original"
        case .paper: "Paper flap"
        case .mechanical: "Mechanical tick"
        case .wooden: "Wooden tock"
        }
    }

    static let defaultsKey = "flipSoundStyle"

    public static var saved: FlipSoundStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(FlipSoundStyle.init(rawValue:)) ?? .original
    }
}

/// Builds the sounds as small in-memory WAV files.
enum Synth {
    static let rate = 44_100.0

    /// One click per time, in the given style.
    static func rattle(at times: [Double], style: FlipSoundStyle) -> Data {
        guard style != .original else { return rattle(at: times) }
        let clickLength = style == .wooden ? 0.09 : 0.06
        let length = Int(((times.max() ?? 0) + clickLength + 0.01) * rate)
        var samples = [Float](repeating: 0, count: length)
        var random = SeededNoise(seed: 0xF11B)
        for time in times {
            let gain = 0.85 + 0.15 * random.next()          // 0.7...1.0
            let click = self.click(style, length: clickLength, random: &random)
            let start = Int(time * rate)
            for (i, value) in click.enumerated() where start + i < length {
                samples[start + i] += gain * value
            }
        }
        // Same loudness for every style, a little under the original's peak; fade the tail.
        let peak = samples.map(abs).max() ?? 0
        if peak > 0 { samples = samples.map { $0 * 0.15 / peak } }
        let fade = Int(0.01 * rate)
        for i in 0..<min(fade, length) { samples[length - 1 - i] *= Float(i) / Float(fade) }
        return wav(samples)
    }

    private static func click(_ style: FlipSoundStyle, length: Double, random: inout SeededNoise) -> [Float] {
        let count = Int(length * rate)
        func env(_ t: Double, _ tau: Double) -> Double { exp(-t / tau) }
        func tone(_ f: Double, _ t: Double, _ tau: Double) -> Double { sin(2 * .pi * f * t) * env(t, tau) }
        switch style {
        case .original:
            return []
        case .paper:
            let noise = bandNoise(count, 1_500, 6_000, &random)
            let f = 180 + 15 * Double(random.next())
            return (0..<count).map { i in
                let t = Double(i) / rate
                return Float(Double(noise[i]) * env(t, 0.006) * 0.8 + tone(f, t, 0.012) * 0.5)
            }
        case .mechanical:
            let noise = bandNoise(count, 4_000, 12_000, &random)
            let f = 3_100 + 120 * Double(random.next())
            return (0..<count).map { i in
                let t = Double(i) / rate
                return Float(Double(noise[i]) * env(t, 0.0015) + tone(f, t, 0.018) * 0.35 + tone(520, t, 0.006) * 0.3)
            }
        case .wooden:
            let noise = bandNoise(count, 800, 3_000, &random)
            let f = 820 + 40 * Double(random.next())
            return (0..<count).map { i in
                let t = Double(i) / rate
                return Float(tone(f, t, 0.025) * 0.7 + tone(2.02 * f, t, 0.012) * 0.25
                             + tone(260, t, 0.02) * 0.4 + Double(noise[i]) * env(t, 0.002) * 0.3)
            }
        }
    }

    /// White noise through a band-pass filter (RBJ biquad) covering low...high Hz.
    private static func bandNoise(_ count: Int, _ low: Double, _ high: Double,
                                  _ random: inout SeededNoise) -> [Float] {
        let center = (low * high).squareRoot()
        let q = center / (high - low)
        let w0 = 2 * .pi * center / rate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        let (b0, b2) = (alpha / a0, -alpha / a0)
        let (a1, a2) = (-2 * cos(w0) / a0, (1 - alpha) / a0)
        var (x1, x2, y1, y2) = (0.0, 0.0, 0.0, 0.0)
        return (0..<count).map { _ in
            let x = Double(random.next())
            let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            (x2, x1, y2, y1) = (x1, x, y1, y)
            return Float(y)
        }
    }

    /// A short, slightly varied click per time: noise through a resonance, decaying in a few ms,
    /// like a plastic flap hitting the one below it. (The Original style.)
    static func rattle(at times: [Double]) -> Data {
        let length = Int(((times.max() ?? 0) + 0.05) * rate)
        var samples = [Float](repeating: 0, count: length)
        var generator = SeededNoise(seed: 0x7A11)
        for (n, time) in times.enumerated() {
            let start = Int(time * rate)
            let loudness: Float = 0.10 + 0.05 * Float((n * 7) % 5) / 4
            let pitch = 2_300.0 + Double((n * 13) % 7) * 120
            for i in 0..<Int(0.012 * rate) where start + i < length {
                let t = Double(i) / rate
                let envelope = Float(exp(-t / 0.0018))
                let ring = Float(sin(2 * .pi * pitch * t))
                samples[start + i] += loudness * envelope * (0.6 * generator.next() + 0.4 * ring)
            }
        }
        return wav(samples)
    }

    /// A soft wooden tick.
    static let tick: Data = {
        let count = Int(0.06 * rate)
        let samples = (0..<count).map { i -> Float in
            let t = Double(i) / rate
            let envelope = exp(-t / 0.012) * min(1, t / 0.001)
            return Float(0.22 * envelope * (sin(2 * .pi * 1_050 * t) + 0.3 * sin(2 * .pi * 2_100 * t)))
        }
        return wav(samples)
    }()

    /// Two gentle falling notes.
    static let sleepTone: Data = {
        let note = 0.16
        let count = Int(2 * note * rate + 0.25 * rate)
        let samples = (0..<count).map { i -> Float in
            let t = Double(i) / rate
            var value = 0.0
            for (k, frequency) in [784.0, 523.25].enumerated() {
                let local = t - Double(k) * note
                guard local > 0 else { continue }
                let envelope = min(1, local / 0.008) * exp(-local / 0.12)
                value += 0.14 * envelope * sin(2 * .pi * frequency * local)
            }
            return Float(value)
        }
        return wav(samples)
    }()

    /// 16-bit mono PCM WAV.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        return data
    }
}

/// Repeatable noise, so the rattle sounds the same each time.
struct SeededNoise {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
    }
}
