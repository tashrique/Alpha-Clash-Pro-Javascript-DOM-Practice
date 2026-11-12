import Foundation
import Observation
import WidgetKit

/// Polls Spotify, fetches synced lyrics, works out which line is current, and pushes it to
/// the Live Activity (CarPlay Dashboard / Lock Screen / Dynamic Island) and the widget.
@MainActor
@Observable
final class NowPlayingEngine {
    private(set) var isRunning = false
    private(set) var track: SpotifyTrack?
    private(set) var isPlaying = false
    private(set) var lines: [LyricLine] = []
    private(set) var currentIndex: Int?
    private(set) var status = "Stopped"

    private let client: SpotifyClient
    private let lyrics: LyricsService
    private let background: BackgroundKeeper
    private let liveActivity: LiveActivityController

    // Spotify progress at `anchorDate`. Between polls we extrapolate from here.
    @ObservationIgnored private var anchorProgress: TimeInterval = 0
    @ObservationIgnored private var anchorDate = Date()
    @ObservationIgnored private var lyricsStatus = ""
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init(client: SpotifyClient, lyrics: LyricsService, background: BackgroundKeeper, liveActivity: LiveActivityController) {
        self.client = client
        self.lyrics = lyrics
        self.background = background
        self.liveActivity = liveActivity
    }

    // MARK: Public

    var currentLine: String {
        guard let currentIndex, lines.indices.contains(currentIndex) else {
            return lines.isEmpty ? lyricsStatus : "♪"
        }
        return Self.display(lines[currentIndex].text)
    }

    var nextLine: String {
        let next = (currentIndex ?? -1) + 1
        return lines.indices.contains(next) ? Self.display(lines[next].text) : ""
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        status = "Starting…"
        background.start()
        liveActivity.start(initial: .idle)
        pollTask = Task { [weak self] in await self?.pollLoop() }
        tickTask = Task { [weak self] in await self?.tickLoop() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTask?.cancel()
        tickTask?.cancel()
        pollTask = nil
        tickTask = nil
        background.stop()
        liveActivity.end()
        status = "Stopped"
        isPlaying = false
        publishWidget()
    }

    // MARK: Loops

    private var estimatedProgress: TimeInterval {
        isPlaying ? anchorProgress + Date().timeIntervalSince(anchorDate) : anchorProgress
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            var delay = 4.0
            do {
                let snapshot = try await client.currentlyPlaying()
                await apply(snapshot)
                delay = isPlaying ? 4 : 8
            } catch SpotifyError.rateLimited(let retry) {
                status = "Spotify asked us to slow down"
                delay = max(retry, 10)
            } catch SpotifyError.notSignedIn {
                status = "Connect Spotify in the app"
                delay = 15
            } catch {
                status = "Offline? \(error.localizedDescription)"
                delay = 8
            }
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func tickLoop() async {
        while !Task.isCancelled {
            refreshLine()
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: State updates

    private func apply(_ snapshot: PlaybackSnapshot?) async {
        guard let snapshot, let newTrack = snapshot.track else {
            if track != nil || isPlaying {
                track = nil
                isPlaying = false
                lines = []
                currentIndex = nil
                lyricsStatus = ""
                publishWidget()
            }
            status = "Nothing playing on Spotify"
            pushLiveActivity()
            return
        }

        let reported = Double(snapshot.progressMs) / 1000
        let drift = abs(reported - (anchorProgress + snapshot.receivedAt.timeIntervalSince(anchorDate)))
        let playStateChanged = snapshot.isPlaying != isPlaying
        let trackChanged = newTrack.id != track?.id

        anchorProgress = reported
        anchorDate = snapshot.receivedAt
        isPlaying = snapshot.isPlaying
        status = isPlaying ? "Playing" : "Paused"

        if trackChanged {
            track = newTrack
            lines = []
            currentIndex = nil
            lyricsStatus = "Finding lyrics…"
            pushLiveActivity()

            let result = await lyrics.lyrics(for: newTrack)
            guard track?.id == newTrack.id else { return } // song changed while we were fetching
            lines = result?.synced ?? []
            lyricsStatus = switch result {
            case .some(let r) where r.instrumental: "Instrumental"
            case .some(let r) where r.hasPlainOnly: "No synced lyrics for this song"
            case .some(let r) where !r.synced.isEmpty: ""
            default: "No lyrics found"
            }
        }

        refreshLine(force: true)
        if trackChanged || playStateChanged || (isPlaying && drift > 2) {
            publishWidget() // seek, pause/resume, or new song: rebuild the widget timeline
        }
    }

    private func refreshLine(force: Bool = false) {
        guard isRunning else { return }
        let index = LRCParser.index(at: estimatedProgress + Prefs.lyricOffset, in: lines)
        if index != currentIndex || force {
            currentIndex = index
            pushLiveActivity()
        }
    }

    private func pushLiveActivity() {
        liveActivity.update(.init(
            trackTitle: track?.name ?? "LyricDash",
            artist: track?.artistLine ?? status,
            currentLine: track == nil ? "Play something on Spotify" : currentLine,
            nextLine: nextLine,
            isPlaying: isPlaying,
            hasSyncedLyrics: !lines.isEmpty
        ))
    }

    /// Hands the widget the whole song with wall-clock times so it can flip lines by itself.
    private func publishWidget() {
        var widgetLines: [WidgetSnapshot.Line] = []
        if let track {
            if isPlaying && !lines.isEmpty {
                // Line i shows when progress + offset == line.time
                let songStart = anchorDate.addingTimeInterval(-anchorProgress - Prefs.lyricOffset)
                widgetLines = lines.map { .init(date: songStart.addingTimeInterval($0.time), text: Self.display($0.text)) }
                let end = songStart.addingTimeInterval(Double(track.durationMs) / 1000)
                widgetLines.append(.init(date: end, text: "♪"))
            } else {
                widgetLines = [.init(date: .distantPast, text: currentLine)]
            }
        }
        WidgetSnapshot(
            trackTitle: track?.name ?? "",
            artist: track?.artistLine ?? "",
            lines: widgetLines,
            isPlaying: isPlaying,
            savedAt: Date()
        ).save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }

    private static func display(_ text: String) -> String {
        text.isEmpty ? "♪" : text
    }
}
