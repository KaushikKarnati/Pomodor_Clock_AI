import SwiftUI

struct TomatoView: View {
    var minutes: Double
    var canAdjust: Bool
    var isBreak: Bool = false
    var isListening: Bool = false
    var isRattling: Bool = false
    var onChange: (Int) -> Void
    var onRatchet: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var dragStart: Double?
    @State private var dragValue: Double?
    @State private var lastNotch: Int?
    @State private var displayed = 0.0
    @State private var target = 0.0
    @State private var winding: Task<Void, Never>?
    @State private var floatY: CGFloat = -3.5
    @State private var rattleOffset: CGFloat = 0

    var shown: Double { min(60, max(0, dragValue ?? displayed)) }

    var glowColor: Color {
        isBreak ? Color(red: 48/255, green: 209/255, blue: 88/255) : Color(red: 255/255, green: 72/255, blue: 50/255)
    }

    var glowOpacity: Double {
        if isListening { return 1.0 }
        return minutes > 0 ? 0.85 : 0.45
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                // Radial Halo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.35), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: side * 0.46
                        )
                    )
                    .frame(width: side * 1.08, height: side * 1.08)
                    .opacity(glowOpacity)
                    .scaleEffect(isListening && !reduceMotion ? 1.07 : 1.0)
                    .animation(isListening && !reduceMotion ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isListening)

                // Tomato Artwork + Dial Markings inside Float / Rattle Wrapper
                ZStack {
                    // Soft drop shadow without expensive image alpha mask recomputation
                    Ellipse()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: side * 0.72, height: side * 0.22)
                        .blur(radius: 18)
                        .offset(y: side * 0.34)

                    Image("tomato")
                        .resizable()
                        .scaledToFit()

                    DialMarkings(minutes: shown)
                }
                .frame(width: side * 0.86, height: side * 0.86)
                .offset(y: (reduceMotion || dragStart != nil) ? 0 : floatY)
                .rotationEffect(.degrees(rattleOffset))
                .scaleEffect(dragStart != nil && !reduceMotion ? 1.015 : (isListening && !reduceMotion ? 1.03 : 1.0))
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: dragStart != nil)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        guard canAdjust else { return }
                        if dragStart == nil {
                            winding?.cancel()
                            winding = nil
                            dragStart = displayed
                            lastNotch = Int(displayed.rounded())
                        }
                        let pixelsPerMinute = 282 * (.pi * 2 / 60) * (side / 680)
                        let next = min(60, max(0, (dragStart ?? 0) - value.translation.width / pixelsPerMinute))
                        dragValue = next
                        let notch = Int(next.rounded())
                        if notch != lastNotch {
                            lastNotch = notch
                            onRatchet()
                        }
                    }
                    .onEnded { _ in
                        guard let value = dragValue else { return }
                        let snapped = value.rounded()
                        dragValue = nil
                        dragStart = nil
                        lastNotch = nil
                        target = snapped
                        displayed = snapped
                        onChange(Int(snapped))
                    }
            )
            .onAppear {
                displayed = minutes
                target = minutes
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                        floatY = 3.5
                    }
                }
            }
            .onChange(of: minutes) { _, newValue in
                wind(to: newValue)
            }
            .onChange(of: isRattling) { _, rattling in
                if rattling && !reduceMotion {
                    triggerRattle()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    winding?.cancel()
                    winding = nil
                    dragStart = nil
                    dragValue = nil
                    lastNotch = nil
                    displayed = minutes
                }
            }
            .onDisappear {
                winding?.cancel()
                winding = nil
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("Tomato timer")
            .accessibilityLabel("Tomato timer")
            .accessibilityValue("\(Int(shown.rounded())) minutes")
            .accessibilityHint(canAdjust ? "Swipe left or right to set duration" : "Use session controls to change this timer")
            .accessibilityAdjustableAction { direction in
                guard canAdjust else { return }
                let value = Int(shown.rounded()) + (direction == .increment ? 1 : -1)
                onRatchet()
                onChange(min(60, max(0, value)))
            }
        }
    }

    private func triggerRattle() {
        Task { @MainActor in
            for _ in 0..<16 {
                rattleOffset = 1.4
                try? await Task.sleep(for: .milliseconds(45))
                rattleOffset = -1.4
                try? await Task.sleep(for: .milliseconds(45))
            }
            rattleOffset = 0
        }
    }

    private func wind(to value: Double) {
        target = min(60, max(0, value))
        guard dragValue == nil else { return }
        let gap = abs(target - displayed)
        guard gap > 0.01 else { return }
        winding?.cancel()
        winding = nil
        guard !reduceMotion, scenePhase == .active else {
            displayed = target
            return
        }
        if gap <= 0.75 {
            withAnimation(.linear(duration: min(1, gap * 60))) {
                displayed = target
            }
            return
        }
        let from = displayed, destination = target
        let duration = min(1.25, 0.3 + gap * 0.025)
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) {
            displayed = destination
        }
        winding = Task { @MainActor in
            let steps = max(1, Int(gap))
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
                guard !Task.isCancelled else { return }
                if Int(from + (destination - from) * Double(step) / Double(steps)) != Int(from) {
                    onRatchet()
                }
            }
            winding = nil
        }
    }
}

private struct DialMarkings: View, Animatable {
    var minutes: Double
    nonisolated var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    private static let angles = (0..<60).map { minute in
        let angle = Double(minute) / 60 * .pi * 2
        return (minute: minute, sine: sin(angle), cosine: cos(angle))
    }

    private static let cachedTexts: [Int: Text] = {
        var map: [Int: Text] = [:]
        for minute in stride(from: 0, to: 60, by: 5) {
            map[minute] = Text("\(minute)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        return map
    }()

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 680
            context.scaleBy(x: scale, y: scale)
            let rho = minutes / 60 * .pi * 2
            let sinRho = sin(rho), cosRho = cos(rho)
            for angle in Self.angles {
                let minute = angle.minute
                let cosine = angle.cosine * cosRho + angle.sine * sinRho
                guard cosine >= 0.06 else { continue }
                let sine = angle.sine * cosRho - angle.cosine * sinRho
                let major = minute % 5 == 0
                let x = 341.5 + 282 * sine, y = 361.8 + 83.1 * cosine
                let length: Double = major ? 19 : 13
                let width = (major ? 5.2 : 3.6) * max(0.3, cosine)
                var ctx = context
                let t = min(1, max(0, (cosine - 0.06) / 0.36))
                ctx.opacity = 0.95 * t * t * (3 - 2 * t)
                ctx.fill(Path(roundedRect: CGRect(x: x - width / 2, y: y - 8 - length, width: width, height: length), cornerRadius: width / 2), with: .color(.white))
                if major, let text = Self.cachedTexts[minute] {
                    ctx.translateBy(x: 341.5 + 282 * 0.985 * sine, y: 361.8 + 83.1 * 0.985 * cosine - 50)
                    ctx.scaleBy(x: max(0.2, cosine), y: 1)
                    ctx.draw(text, at: .zero)
                }
            }
        }
    }
}
