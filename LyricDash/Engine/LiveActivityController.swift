import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<LyricActivityAttributes>?
    private var lastState: LyricActivityAttributes.ContentState?

    var isEnabledBySystem: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(initial: LyricActivityAttributes.ContentState) {
        guard isEnabledBySystem else { return }
        if let existing = Activity<LyricActivityAttributes>.activities.first {
            activity = existing
            return
        }
        do {
            activity = try Activity.request(
                attributes: LyricActivityAttributes(sessionName: "Drive"),
                content: .init(state: initial, staleDate: nil),
                pushType: nil
            )
            lastState = initial
        } catch {
            print("Live Activity failed to start: \(error)")
        }
    }

    func update(_ state: LyricActivityAttributes.ContentState) {
        guard let activity, state != lastState else { return }
        lastState = state
        // If the app gets killed, the activity goes stale after 2 minutes and shows that.
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        Task { await activity.update(content) }
    }

    func end() {
        let all = Activity<LyricActivityAttributes>.activities
        activity = nil
        lastState = nil
        Task {
            for a in all { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
