import AVFoundation
import Foundation

/// Plays the "CarPlay connected" sound. Built-in chimes are synthesized in code (no audio
/// files to ship); you can also pick your own sound file in the app.
/// Spotify is ducked (turned down) while the chime plays, then restored.
@MainActor
final class ChimePlayer {
    static let shared = ChimePlayer()

    enum Style: String, CaseIterable, Identifiable {
        case rise, glass, pulse, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .rise: "Rise"
            case .glass: "Glass"
            case .pulse: "Pulse"
            case .custom: "My sound"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var customPlayer: AVAudioPlayer?
    private var lastPlayed = Date.distantPast

    private init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    static var customSoundURL: URL? {
        guard let name = Prefs.customChimeFile else { return nil }
        let url = URL.documentsDirectory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }

    /// - Parameter force: ignore the de-duplication window (used by the Preview button).
    func play(_ style: Style, volume: Double, force: Bool = false) async {
        // The in-app CarPlay monitor and a Shortcuts automation can both fire on connect.
        guard force || Date().timeIntervalSince(lastPlayed) > 20 else { return }
        lastPlayed = Date()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
            return
        }

        var duration = 0.0
        if style == .custom, let url = Self.customSoundURL, let player = try? AVAudioPlayer(contentsOf: url) {
            customPlayer = player
            player.volume = Float(volume)
            player.play()
            duration = min(player.duration, 8)
        } else {
            let buffer = Self.synthesize(style == .custom ? .rise : style, format: format)
            do {
                if !engine.isRunning { try engine.start() }
            } catch {
                print("Audio engine error: \(error)")
                return
            }
            node.volume = Float(volume)
            node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            node.play()
            duration = Double(buffer.frameLength) / format.sampleRate
        }

        try? await Task.sleep(for: .seconds(duration + 0.25))
        customPlayer?.stop()
        customPlayer = nil
        node.stop()
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Synthesis

    private struct Note {
        let freq: Double
        let start: Double
        let decay: Double // seconds to fade to ~0
    }

    private static func synthesize(_ style: Style, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let notes: [Note]
        var bell = false
        switch style {
        case .glass:
            bell = true
            notes = [Note(freq: 880.0, start: 0, decay: 1.6), Note(freq: 1318.5, start: 0.18, decay: 1.6)]
        case .pulse:
            notes = [0.0, 0.16, 0.32].map { Note(freq: 659.25, start: $0, decay: 0.18) }
        case .rise, .custom:
            notes = [(523.25, 0.0), (659.25, 0.12), (783.99, 0.24), (1046.5, 0.36)]
                .map { Note(freq: $0.0, start: $0.1, decay: 0.9) }
        }

        let sr = format.sampleRate
        let total = (notes.map { $0.start + $0.decay }.max() ?? 1) + 0.1
        let frames = AVAudioFrameCount(total * sr)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]

        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            var sample = 0.0
            for n in notes where t >= n.start {
                let lt = t - n.start
                let attack = min(lt / 0.008, 1)
                let env = attack * exp(-5 * lt / n.decay)
                var s = sin(2 * .pi * n.freq * lt) + 0.25 * sin(4 * .pi * n.freq * lt)
                if bell { s += 0.35 * sin(2 * .pi * n.freq * 2.76 * lt) * exp(-3 * lt) }
                sample += s * env
            }
            out[i] = Float(sample)
        }

        // Normalize so every style is about the same loudness.
        var peak: Float = 0.0001
        for i in 0..<Int(frames) { peak = max(peak, abs(out[i])) }
        let gain = 0.8 / peak
        for i in 0..<Int(frames) { out[i] *= gain }
        return buffer
    }
}
