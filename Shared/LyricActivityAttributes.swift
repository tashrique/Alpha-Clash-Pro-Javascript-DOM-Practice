import ActivityKit
import Foundation

/// The Live Activity that shows the current lyric line. On iOS 26 the system shows
/// Live Activities on the CarPlay Dashboard (next to the map), using the `.small` family.
struct LyricActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var trackTitle: String
        var artist: String
        var currentLine: String
        var nextLine: String
        var isPlaying: Bool
        var hasSyncedLyrics: Bool
    }

    var sessionName: String
}

extension LyricActivityAttributes.ContentState {
    static let idle = Self(
        trackTitle: "LyricDash",
        artist: "Waiting for Spotify",
        currentLine: "Play something on Spotify",
        nextLine: "",
        isPlaying: false,
        hasSyncedLyrics: false
    )
}
