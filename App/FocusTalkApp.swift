import SwiftUI
import AVFoundation
import UIKit

@main struct FocusTalkApp: App {
    @State private var store = FocusStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView(store: store).preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    store.setForeground(phase == .active)
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                    store.audio.stop()
                }
        }
    }
}
