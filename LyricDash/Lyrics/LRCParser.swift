import Foundation

struct LyricLine: Hashable {
    /// Seconds from the start of the song.
    let time: TimeInterval
    let text: String
}

/// Parses synced lyrics in LRC format: `[mm:ss.xx] line text`.
enum LRCParser {
    private static let tag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)

    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue } // metadata like [ar:...] has no time tag
            let text = ns.substring(from: last.range.upperBound).trimmingCharacters(in: .whitespaces)

            // A line can carry several time tags when it repeats.
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    fraction = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                lines.append(LyricLine(time: minutes * 60 + seconds + fraction, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// Index of the line that should be showing at `time`, or nil before the first line.
    static func index(at time: TimeInterval, in lines: [LyricLine]) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }
}
