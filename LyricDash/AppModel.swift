import Foundation

/// User settings. Views bind to the same keys with `@AppStorage`.
enum Prefs {
    enum Key {
        static let chimeEnabled = "chimeEnabled"
        static let chimeStyle = "chimeStyle"
        static let chimeVolume = "chimeVolume"
        static let autoStart = "autoStartOnCarPlay"
        static let autoStop = "autoStopOnCarPlay"
        static let lyricOffset = "lyricOffset"
        static let customChimeFile = "customChimeFile"
    }

    private static var d: UserDefaults { .standard }

    static var chimeEnabled: Bool { d.object(forKey: Key.chimeEnabled) as? Bool ?? true }
    static var chimeStyle: ChimePlayer.Style {
        ChimePlayer.Style(rawValue: d.string(forKey: Key.chimeStyle) ?? "") ?? .rise
    }
    static var chimeVolume: Double { d.object(forKey: Key.chimeVolume) as? Double ?? 0.8 }
    static var autoStart: Bool { d.object(forKey: Key.autoStart) as? Bool ?? true }
    static var autoStop: Bool { d.object(forKey: Key.autoStop) as? Bool ?? true }
    /// Seconds. Positive shows lines earlier (use it if lyrics feel late).
    static var lyricOffset: Double { d.double(forKey: Key.lyricOffset) }
    static var customChimeFile: String? { d.string(forKey: Key.customChimeFile) }
}

/// One place that owns all long-lived objects, so the UI and the Shortcuts intents share state.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let auth: SpotifyAuth
    let background: BackgroundKeeper
    let liveActivity: LiveActivityController
    let engine: NowPlayingEngine
    let carPlay: CarPlayMonitor

    private init() {
        auth = SpotifyAuth()
        background = BackgroundKeeper()
        liveActivity = LiveActivityController()
        engine = NowPlayingEngine(
            client: SpotifyClient(auth: auth),
            lyrics: LyricsService(),
            background: background,
            liveActivity: liveActivity
        )
        carPlay = CarPlayMonitor()

        carPlay.onConnect = { [weak self] in
            guard let self else { return }
            if Prefs.autoStart { self.engine.start() }
            if Prefs.chimeEnabled {
                Task { await ChimePlayer.shared.play(Prefs.chimeStyle, volume: Prefs.chimeVolume) }
            }
        }
        carPlay.onDisconnect = { [weak self] in
            if Prefs.autoStop { self?.engine.stop() }
        }
    }
}
