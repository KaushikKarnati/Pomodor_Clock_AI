import SwiftUI
import AVFoundation
import UIKit
import QuartzCore

@main struct FocusTalkApp: App {
    @State private var store = FocusStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView(store: store).preferredColorScheme(.dark)
                .lockDisplayRefreshRate()
                .onChange(of: scenePhase) { _, phase in
                    store.setForeground(phase == .active)
                    if phase == .active {
                        DisplayRateManager.shared.start()
                    } else {
                        DisplayRateManager.shared.stop()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                    store.audio.stop()
                }
        }
    }
}

/// An engine that locks the display refresh rate based on device capabilities:
/// - 120 FPS on ProMotion Super Retina XDR displays (iPhone Pro models, iPad Pro)
/// - 60 FPS on standard 60Hz displays (standard iPhone models)
@MainActor
final class DisplayRateManager {
    static let shared = DisplayRateManager()

    private var displayLink: CADisplayLink?
    private(set) var maxDeviceRefreshRate: Int = 60
    private(set) var isProMotion: Bool = false

    private init() {}

    func start() {
        guard displayLink == nil else { return }

        let screenMax: Int = {
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                return scene.screen.maximumFramesPerSecond
            }
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                return scene.screen.maximumFramesPerSecond
            }
            return UIScreen.main.maximumFramesPerSecond
        }()

        maxDeviceRefreshRate = screenMax > 0 ? screenMax : 60
        isProMotion = maxDeviceRefreshRate >= 120

        let link = CADisplayLink(target: self, selector: #selector(frameStep(_:)))
        if isProMotion {
            // Lock and prioritize 120 FPS on Super Retina XDR ProMotion displays
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        } else {
            // Standard 60 FPS on non-ProMotion displays
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }

        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frameStep(_ link: CADisplayLink) {
        // Keeps the display driver synced to the requested frame rate range for locked rendering
    }
}

/// SwiftUI ViewModifier that starts the DisplayRateManager on appear
struct DeviceDisplayRateConfigurator: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                DisplayRateManager.shared.start()
            }
    }
}

extension View {
    func lockDisplayRefreshRate() -> some View {
        modifier(DeviceDisplayRateConfigurator())
    }
}

