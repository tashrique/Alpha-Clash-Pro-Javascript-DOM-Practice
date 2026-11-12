import SwiftUI

@main
struct LyricDashApp: App {
    init() {
        // Create the shared model at launch so the CarPlay monitor is listening right away.
        _ = AppModel.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
