import Foundation

enum AppGroup {
    static var id: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// What the app hands to the home-screen / CarPlay widget.
///
/// Widgets can't be updated many times per second, so instead of pushing every line the
/// app writes the whole song with *wall-clock* times for each line. The widget turns that
/// into a WidgetKit timeline, and the system flips lines on its own, even if the app is asleep.
struct WidgetSnapshot: Codable {
    struct Line: Codable, Hashable {
        var date: Date
        var text: String
    }

    var trackTitle: String
    var artist: String
    var lines: [Line]
    var isPlaying: Bool
    var savedAt: Date

    static let key = "widgetSnapshot"
    static let widgetKind = "NowPlayingLyricWidget"

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults.set(data, forKey: Self.key)
    }
}
