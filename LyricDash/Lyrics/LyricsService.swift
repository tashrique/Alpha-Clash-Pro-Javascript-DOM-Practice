import Foundation

struct LyricsResult {
    let synced: [LyricLine]
    let hasPlainOnly: Bool
    let instrumental: Bool
}

/// Looks up time-synced lyrics on LRCLIB (https://lrclib.net), a free, open lyrics database.
///
/// Spotify has no public lyrics API, so we can't read the lyrics Spotify shows in its own app.
/// LRCLIB matches by title + artist + album + duration, which works for most popular songs.
actor LyricsService {
    private var cache: [String: LyricsResult] = [:]
    private let base = "https://lrclib.net/api"

    private struct Record: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
        let duration: Double?
    }

    func lyrics(for track: SpotifyTrack) async -> LyricsResult? {
        if let cached = cache[track.id] { return cached }

        let seconds = Double(track.durationMs) / 1000
        var record = await fetchExact(track, seconds: seconds)
        if record?.syncedLyrics == nil {
            record = await search(track, seconds: seconds) ?? record
        }
        guard let record else { return nil }

        let result = LyricsResult(
            synced: record.syncedLyrics.map(LRCParser.parse) ?? [],
            hasPlainOnly: record.syncedLyrics == nil && record.plainLyrics != nil,
            instrumental: record.instrumental ?? false
        )
        cache[track.id] = result
        return result
    }

    private func fetchExact(_ track: SpotifyTrack, seconds: Double) async -> Record? {
        var c = URLComponents(string: "\(base)/get")!
        c.queryItems = [
            .init(name: "track_name", value: track.name),
            .init(name: "artist_name", value: track.primaryArtist),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(Int(seconds.rounded()))),
        ]
        return await request(c.url!, as: Record.self)
    }

    /// Fuzzy fallback: pick the synced result whose duration is closest to Spotify's.
    private func search(_ track: SpotifyTrack, seconds: Double) async -> Record? {
        var c = URLComponents(string: "\(base)/search")!
        c.queryItems = [
            .init(name: "track_name", value: Self.cleanTitle(track.name)),
            .init(name: "artist_name", value: track.primaryArtist),
        ]
        guard let results = await request(c.url!, as: [Record].self) else { return nil }
        return results
            .filter { $0.syncedLyrics != nil && abs(($0.duration ?? 0) - seconds) < 4 }
            .min { abs(($0.duration ?? 0) - seconds) < abs(($1.duration ?? 0) - seconds) }
    }

    private func request<T: Decodable>(_ url: URL, as type: T.Type) async -> T? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("LyricDash/1.0 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(type, from: result.0)
    }

    /// "Song - Remastered 2011" / "Song (feat. X)" -> "Song"
    private static func cleanTitle(_ title: String) -> String {
        var t = title
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        if let r = t.range(of: " (") { t = String(t[..<r.lowerBound]) }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
