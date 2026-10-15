import SwiftUI
import WidgetKit
import ActivityKit

@main struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            HStack(spacing: 24) {
                MechanicalDial(state: context.state).frame(width: 76, height: 76)
                Spacer(minLength: 0)
                RemainingTime(state: context.state).font(.system(size: 40, weight: .medium, design: .rounded)).minimumScaleFactor(0.6).frame(maxWidth: 190)
            }
            .padding(.horizontal, 26).padding(.vertical, 20)
            .activityBackgroundTint(Color(red: 0.045, green: 0.055, blue: 0.065))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 28) {
                        MechanicalDial(state: context.state).frame(width: 64, height: 64)
                        RemainingTime(state: context.state).font(.system(size: 34, weight: .medium, design: .rounded)).minimumScaleFactor(0.6)
                    }.padding(.vertical, 10)
                }
            } compactLeading: {
                MechanicalDial(state: context.state).frame(width: 24, height: 24)
            } compactTrailing: {
                RemainingTime(state: context.state).font(.system(size: 13, weight: .medium, design: .rounded)).frame(width: 62).minimumScaleFactor(0.65)
            } minimal: {
                MechanicalDial(state: context.state).frame(width: 22, height: 22)
            }.keylineTint(.red)
        }
    }
}
private struct RemainingTime: View {
    var state: SessionActivityAttributes.ContentState
    var body: some View {
        Group {
            if state.isRunning {
                Text(timerInterval: (state.start ?? Date.distantPast)...state.end, countsDown: true)
                    .contentTransition(.numericText(countsDown: true))
            } else {
                let seconds = Int(max(0, state.remaining).rounded(.up))
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            }
        }.monospacedDigit().foregroundStyle(.white)
            .accessibilityLabel(state.isRunning ? "Time remaining" : "Paused, time remaining")
    }
}
private struct MechanicalDial: View {
    var state: SessionActivityAttributes.ContentState
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.3, blue: 0.22), .red, Color(red: 0.35, green: 0.025, blue: 0.02)], center: .topLeading, startRadius: 0, endRadius: size))
                Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                ForEach(0..<24) { tick in
                    Capsule().fill(.white.opacity(tick % 2 == 0 ? 0.9 : 0.45))
                        .frame(width: max(1, size * 0.018), height: size * (tick % 2 == 0 ? 0.11 : 0.06))
                        .offset(y: -size * 0.38).rotationEffect(.degrees(Double(tick) * 15))
                }
                Group {
                    if state.isRunning {
                        ProgressView(timerInterval: (state.start ?? state.end.addingTimeInterval(-max(1, state.remaining)))...state.end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    } else {
                        ProgressView(value: min(1, max(0, state.remaining / max(1, state.end.timeIntervalSince(state.start ?? state.end.addingTimeInterval(-state.remaining))))))
                    }
                }.progressViewStyle(.circular).tint(.white).padding(size * 0.22)
                Circle().fill(.white.opacity(0.9)).frame(width: max(2, size * 0.06))
            }.frame(width: size, height: size)
        }.accessibilityHidden(true)
    }
}
