import AppIntents

/// Use in Shortcuts > Automation > CarPlay > "Connects". Plays your connect sound
/// without opening the app.
struct PlayConnectSoundIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play CarPlay Connect Sound"
    static let description = IntentDescription("Plays your LyricDash chime. Add it to a \"When CarPlay connects\" automation.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await ChimePlayer.shared.play(Prefs.chimeStyle, volume: Prefs.chimeVolume)
        return .result()
    }
}

/// Starts the lyrics session (polling + Live Activity on the CarPlay Dashboard).
struct StartLyricsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start CarPlay Lyrics"
    static let description = IntentDescription("Starts showing Spotify lyrics as a Live Activity on CarPlay.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.engine.start()
        return .result()
    }
}

struct StopLyricsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop CarPlay Lyrics"

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.engine.stop()
        return .result()
    }
}

struct LyricDashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartLyricsIntent(),
            phrases: ["Start lyrics in \(.applicationName)", "Show lyrics with \(.applicationName)"],
            shortTitle: "Start Lyrics",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: StopLyricsIntent(),
            phrases: ["Stop lyrics in \(.applicationName)"],
            shortTitle: "Stop Lyrics",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: PlayConnectSoundIntent(),
            phrases: ["Play connect sound in \(.applicationName)"],
            shortTitle: "Connect Sound",
            systemImageName: "speaker.wave.2"
        )
    }
}
