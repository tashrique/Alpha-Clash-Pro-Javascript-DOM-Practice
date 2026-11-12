import SwiftUI
import WidgetKit

/// A small widget for the iPhone home screen and the CarPlay widget page (iOS 26).
/// The app writes the song's lines with wall-clock times; we turn them into a timeline
/// so the system switches lines on schedule without waking the app.
struct LyricEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let line: String
    let next: String
    let isPlaying: Bool
}

struct LyricProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricEntry {
        LyricEntry(date: .now, title: "Song title", artist: "Artist", line: "Lyrics show up here", next: "", isPlaying: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricEntry) -> Void) {
        completion(entries(now: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricEntry>) -> Void) {
        let now = Date.now
        let list = entries(now: now)
        // The app reloads us on song change / pause / seek. Otherwise wait until the song ends.
        completion(Timeline(entries: list, policy: list.count > 1 ? .atEnd : .never))
    }

    private func entries(now: Date) -> [LyricEntry] {
        guard let snap = WidgetSnapshot.load(), !snap.trackTitle.isEmpty else {
            return [LyricEntry(date: now, title: "LyricDash", artist: "", line: "Nothing playing", next: "", isPlaying: false)]
        }
        let lines = snap.lines
        func entry(_ i: Int, at date: Date) -> LyricEntry {
            LyricEntry(
                date: date,
                title: snap.trackTitle,
                artist: snap.artist,
                line: lines.indices.contains(i) ? lines[i].text : "♪",
                next: lines.indices.contains(i + 1) ? lines[i + 1].text : "",
                isPlaying: snap.isPlaying
            )
        }

        // Current line now, then one entry per upcoming line (capped to keep the timeline small).
        let currentIndex = lines.lastIndex { $0.date <= now } ?? -1
        var result = [entry(currentIndex, at: now)]
        guard snap.isPlaying else { return result }
        for i in lines.indices where i > currentIndex && result.count < 150 {
            result.append(entry(i, at: lines[i].date))
        }
        return result
    }
}

struct NowPlayingLyricWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: LyricProvider()) { entry in
            LyricWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [.black, Color(red: 0.05, green: 0.2, blue: 0.1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Lyrics")
        .description("The current Spotify lyric line.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct LyricWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LyricEntry

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text(entry.title).font(.caption2).lineLimit(1)
                Text(entry.line).font(.headline).lineLimit(2)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: entry.isPlaying ? "music.note" : "pause.fill")
                    Text(entry.title).lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)

                Spacer(minLength: 0)
                Text(entry.line)
                    .font(family == .systemSmall ? .headline : .title3.bold())
                    .lineLimit(family == .systemSmall ? 4 : 3)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                if !entry.next.isEmpty {
                    Text(entry.next).font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
