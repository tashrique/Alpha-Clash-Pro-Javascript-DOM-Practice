import SwiftUI
import WidgetKit

@main
struct LyricDashWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LyricLiveActivity()
        NowPlayingLyricWidget()
    }
}
