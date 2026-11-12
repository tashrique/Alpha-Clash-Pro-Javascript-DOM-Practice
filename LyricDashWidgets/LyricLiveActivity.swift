import ActivityKit
import SwiftUI
import WidgetKit

/// The lyric Live Activity.
/// - `.small` family: CarPlay Dashboard (iOS 26) and Apple Watch Smart Stack.
/// - `.medium` family: iPhone Lock Screen / banner.
/// - Dynamic Island on the phone.
struct LyricLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivityAttributes.self) { context in
            LyricActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note").foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.trackTitle).font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.currentLine).font(.headline).lineLimit(2)
                        Text(context.state.nextLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.currentLine).font(.caption2).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(.green)
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

struct LyricActivityView: View {
    @Environment(\.activityFamily) private var family
    let state: LyricActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        switch family {
        case .small: carPlayView
        default: lockScreenView
        }
    }

    /// Big, glanceable text for the car screen.
    private var carPlayView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: state.isPlaying ? "music.note" : "pause.fill")
                Text(state.trackTitle).lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.green)

            Text(isStale ? "Lyrics paused. Open LyricDash." : state.currentLine)
                .font(.title3.weight(.bold))
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .contentTransition(.opacity)

            if !state.nextLine.isEmpty && !isStale {
                Text(state.nextLine)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(8)
    }

    private var lockScreenView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "music.note").foregroundStyle(.green)
                Text(state.trackTitle).font(.caption.weight(.semibold)).lineLimit(1)
                Text(state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            Text(isStale ? "Lyrics paused. Open LyricDash." : state.currentLine)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .contentTransition(.opacity)
            if !state.nextLine.isEmpty && !isStale {
                Text(state.nextLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding()
        .foregroundStyle(.white)
    }
}
