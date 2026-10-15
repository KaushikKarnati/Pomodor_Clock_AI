import SwiftUI
import AVFoundation
import UIKit

@main struct FocusTalkApp: App {
    @State private var store = FocusStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView(store: store).preferredColorScheme(.dark)
                // System alerts (permissions, Control Center) make the scene inactive, not backgrounded;
                // treating them as background cut off the first spoken line and the first wind-up.
                .onChange(of: scenePhase) { _, phase in
                    store.setForeground(phase != .background)
                }
        }
    }
}
