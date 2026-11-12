import AVFoundation
import XCTest
@testable import LyricDash

final class LRCParserTests: XCTestCase {
    func testParsesTimestampsAndText() {
        let lrc = """
        [ar:Test Artist]
        [ti:Test Song]
        [00:01.50] first line
        [00:04.25]second line
        [01:02.123] third line
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 3, "metadata tags must be skipped")
        XCTAssertEqual(lines[0].time, 1.5, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "first line")
        XCTAssertEqual(lines[1].text, "second line")
        XCTAssertEqual(lines[2].time, 62.123, accuracy: 0.001)
    }

    func testRepeatedTagsAndSorting() {
        let lrc = """
        [00:10.00][00:30.00] repeated line
        [00:20.00] middle line
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.map(\.time), [10, 20, 30])
        XCTAssertEqual(lines.map(\.text), ["repeated line", "middle line", "repeated line"])
    }

    func testEmptyLineIsKeptAsBreak() {
        let lines = LRCParser.parse("[00:05.00]\n[00:06.00] after break")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "")
    }

    func testIndexLookup() {
        let lines = [1.0, 5.0, 9.0].map { LyricLine(time: $0, text: "\($0)") }
        XCTAssertNil(LRCParser.index(at: 0.5, in: lines))
        XCTAssertEqual(LRCParser.index(at: 1.0, in: lines), 0)
        XCTAssertEqual(LRCParser.index(at: 7.0, in: lines), 1)
        XCTAssertEqual(LRCParser.index(at: 100, in: lines), 2)
        XCTAssertNil(LRCParser.index(at: 3, in: []))
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTrip() throws {
        let snap = WidgetSnapshot(
            trackTitle: "Song",
            artist: "Artist",
            lines: [.init(date: Date(timeIntervalSince1970: 100), text: "a")],
            isPlaying: true,
            savedAt: Date()
        )
        snap.save()
        let loaded = try XCTUnwrap(WidgetSnapshot.load())
        XCTAssertEqual(loaded.trackTitle, "Song")
        XCTAssertEqual(loaded.lines, snap.lines)
    }
}

final class ChimeTests: XCTestCase {
    func testEveryStyleSynthesizesNormalizedAudio() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        for style in ChimePlayer.Style.allCases {
            let buffer = ChimePlayer.synthesize(style, format: format)
            XCTAssertGreaterThan(buffer.frameLength, 4_410, "\(style) too short")
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            let peak = samples.map(abs).max() ?? 0
            XCTAssertEqual(peak, 0.8, accuracy: 0.01, "\(style) not normalized")
        }
    }
}

final class SpotifyAuthTests: XCTestCase {
    @MainActor
    func testAuthorizeURLUsesPKCE() throws {
        let auth = SpotifyAuth()
        guard !auth.clientID.isEmpty else {
            throw XCTSkip("No SPOTIFY_CLIENT_ID configured in this build")
        }
        let url = try auth.makeAuthorizeURL()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("redirect_uri"), "lyricdash://callback")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge")?.count, 43) // base64url SHA-256, no padding
    }
}

/// Live call to LRCLIB. Only checks that synced lyrics come back and parse; never prints them.
final class LyricsServiceIntegrationTests: XCTestCase {
    func testFetchesSyncedLyricsForAPopularSong() async throws {
        let track = SpotifyTrack(
            id: "0VjIjW4GlUZAMYd2vXMi3b",
            name: "Blinding Lights",
            artists: ["The Weeknd"],
            album: "After Hours",
            durationMs: 200_040
        )
        guard let result = await LyricsService().lyrics(for: track) else {
            throw XCTSkip("LRCLIB unreachable from this machine")
        }
        XCTAssertGreaterThan(result.synced.count, 10, "expected synced lines")
        XCTAssertEqual(result.synced, result.synced.sorted { $0.time < $1.time })
    }
}
