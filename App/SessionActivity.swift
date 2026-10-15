import ActivityKit
import Foundation
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date? = nil
        var title: String
        var end: Date
        var sessionEnd: Date
        var isRunning: Bool
        var remaining: Double
        var position: String
        /// Asset name of the selected timer object's miniature in the widget catalog.
        /// Optional so activities started by an older build still decode.
        var objectMini: String? = nil
        var isBreak: Bool? = nil
        /// Automatic progression: the countdown covers the whole session, and nothing can update the
        /// block name while the app is suspended, so the widget shows session-level information.
        var auto: Bool? = nil
    }
    var sessionID: String
}
