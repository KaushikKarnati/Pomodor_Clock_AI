import SwiftUI
import WidgetKit
import ActivityKit

/// What the Live Activity can honestly show. The app can't update the activity while suspended,
/// so block-level details are only shown when they can't go out of date:
/// - manual progression: the countdown is the current block; at its end the card turns stale.
/// - automatic progression: the countdown is the whole session, so the card shows the session.
private struct Presentation {
    let state: SessionActivityAttributes.ContentState
    let isStale: Bool

    var sessionLevel: Bool { state.auto == true }
    var isBreak: Bool { !sessionLevel && state.isBreak == true }
    var tint: Color { isStale ? .gray : (isBreak ? breakGreen : focusRed) }
    /// Once stale, the whole session is over (not just a block that needs the app to continue).
    var sessionDone: Bool { isStale && (sessionLevel || state.isLastBlock == true) }

    var kind: String {
        if isStale { return sessionDone ? "SESSION DONE" : "TIME’S UP" }
        if !state.isRunning { return "PAUSED" }
        if sessionLevel { return "FOCUS SESSION" }
        return isBreak ? "BREAK" : "FOCUS"
    }
}

@main struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            let presentation = Presentation(state: context.state, isStale: context.isStale)
            HStack(spacing: 16) {
                ObjectDial(presentation: presentation).frame(width: 64, height: 64)
                BlockLabel(presentation: presentation)
                Spacer(minLength: 0)
                RemainingTime(presentation: presentation)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .activityBackgroundTint(Color(red: 0.045, green: 0.055, blue: 0.065))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let presentation = Presentation(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ObjectDial(presentation: presentation).frame(width: 52, height: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RemainingTime(presentation: presentation)
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .frame(maxWidth: 120, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    BlockLabel(presentation: presentation)
                }
            } compactLeading: {
                ObjectDial(presentation: presentation).frame(width: 24, height: 24)
            } compactTrailing: {
                RemainingTime(presentation: presentation)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 64, alignment: .trailing)
            } minimal: {
                ObjectDial(presentation: presentation).frame(width: 22, height: 22)
            }.keylineTint(presentation.tint)
        }
    }
}

private let focusRed = Color(red: 1, green: 69 / 255, blue: 58 / 255)
private let breakGreen = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)

/// A valid timer range even if a stale or older payload has start after end
/// (`ClosedRange` traps when lowerBound > upperBound).
private func timerRange(_ state: SessionActivityAttributes.ContentState) -> ClosedRange<Date> {
    let start = state.start ?? state.end.addingTimeInterval(-max(1, state.remaining))
    return min(start, state.end)...state.end
}

private struct BlockLabel: View {
    let presentation: Presentation
    var body: some View {
        let state = presentation.state
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.kind)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(presentation.tint)
            Group {
                if presentation.isStale {
                    Text(presentation.sessionDone ? "Nice work." : "Open FocusTalk for the next block")
                } else if presentation.sessionLevel && state.isRunning {
                    Text("Ends \(Text(state.sessionEnd, style: .time))")
                } else {
                    // Manual progression, or paused: nothing advances, so the block name stays accurate.
                    // (A paused session's end time would drift further into the past.)
                    Text(state.title)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RemainingTime: View {
    let presentation: Presentation
    var body: some View {
        let state = presentation.state
        Group {
            if presentation.isStale {
                Text("0:00")
            } else if state.isRunning {
                Text(timerInterval: timerRange(state), countsDown: true)
            } else {
                let seconds = Int(min(max(0, state.remaining), 24 * 3600).rounded(.up))
                Text(seconds >= 3600
                     ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                     : String(format: "%02d:%02d", seconds / 60, seconds % 60))
            }
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .multilineTextAlignment(.trailing)
        // A whole-session countdown reads h:mm:ss; shrink rather than truncate.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// A miniature of the selected timer object inside a system-driven progress ring.
private struct ObjectDial: View {
    let presentation: Presentation
    var body: some View {
        let state = presentation.state
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Group {
                    if presentation.isStale {
                        ProgressView(value: 0.0)
                    } else if state.isRunning {
                        ProgressView(timerInterval: timerRange(state), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    } else {
                        let range = timerRange(state)
                        ProgressView(value: min(1, max(0, state.remaining / max(1, range.upperBound.timeIntervalSince(range.lowerBound)))))
                    }
                }
                .progressViewStyle(.circular)
                .tint(presentation.tint)
                Image(state.objectMini ?? "mini-tomato")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .opacity(presentation.isStale ? 0.6 : 1)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}
