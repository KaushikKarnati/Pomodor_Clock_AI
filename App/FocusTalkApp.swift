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
                // Act only on real background/foreground changes: active <-> inactive needs no resync.
                .onChange(of: scenePhase) { old, phase in
                    if phase == .background { store.setForeground(false) }
                    else if old == .background { store.setForeground(true) }
                    else if phase == .active { store.resumeAudio() }
                }
        }
    }
}
