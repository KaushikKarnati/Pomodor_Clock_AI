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
    }
    var sessionID: String
}
