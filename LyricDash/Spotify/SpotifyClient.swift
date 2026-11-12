import Foundation

struct SpotifyTrack: Equatable {
    let id: String
    let name: String
    let artists: [String]
    let album: String
    let durationMs: Int

    var primaryArtist: String { artists.first ?? "" }
    var artistLine: String { artists.joined(separator: ", ") }
}

struct PlaybackSnapshot {
    let track: SpotifyTrack?
    let progressMs: Int
    let isPlaying: Bool
    /// When the response arrived; used to extrapolate progress between polls.
    let receivedAt: Date
}

/// Minimal Spotify Web API client: just "what's playing and where are we in the song".
@MainActor
struct SpotifyClient {
    let auth: SpotifyAuth

    func currentlyPlaying() async throws -> PlaybackSnapshot? {
        try await currentlyPlaying(retryingAuth: true)
    }

    private func currentlyPlaying(retryingAuth: Bool) async throws -> PlaybackSnapshot? {
        let token = try await auth.validAccessToken(forceRefresh: !retryingAuth)
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8

        let sentAt = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        // Assume Spotify measured progress roughly halfway through the round trip.
        let receivedAt = sentAt.addingTimeInterval(Date().timeIntervalSince(sentAt) / 2)

        switch http?.statusCode ?? 0 {
        case 200:
            break
        case 204:
            return nil // nothing playing
        case 401 where retryingAuth:
            return try await currentlyPlaying(retryingAuth: false)
        case 429:
            let retry = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
            throw SpotifyError.rateLimited(retryAfter: retry)
        case let code:
            throw SpotifyError.badResponse(code)
        }

        let body = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
        let track = body.item.map {
            SpotifyTrack(
                id: $0.id ?? "\($0.name)-\($0.duration_ms)",
                name: $0.name,
                artists: $0.artists?.map(\.name) ?? [],
                album: $0.album?.name ?? "",
                durationMs: $0.duration_ms
            )
        }
        return PlaybackSnapshot(
            track: track,
            progressMs: body.progress_ms ?? 0,
            isPlaying: body.is_playing,
            receivedAt: receivedAt
        )
    }

    private struct CurrentlyPlayingResponse: Decodable {
        struct Item: Decodable {
            struct Named: Decodable { let name: String }
            let id: String?
            let name: String
            let duration_ms: Int
            let artists: [Named]?
            let album: Named?
        }
        let is_playing: Bool
        let progress_ms: Int?
        let item: Item?
    }
}
