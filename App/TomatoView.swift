import SwiftUI

/// The tactile timer on the home screen. Every object is set by the same horizontal twist,
/// and every style animates from one `displayed` value, so winding and running stay smooth.
struct TimerObjectView: View {
    var object: TimerObjectID = .tomato
    var minutes: Double
    var canAdjust: Bool
    var isBreak: Bool = false
    var isListening: Bool = false
    var isRattling: Bool = false
    var isRunning: Bool = false
    /// The block the dial currently controls; captured when a drag starts.
    var blockID: UUID? = nil
    /// Returns whether the store accepted the new minutes.
    var onChange: (Int, UUID?) -> Bool
    var onRatchet: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var dragStart: Double?
    @State private var dragValue: Double?
    @State private var lastNotch: Int?
    @State private var dragBlockID: UUID?
    @State private var displayed = 0.0
    @State private var target = 0.0
    @State private var winding: Task<Void, Never>?
    /// The wind animation in flight, so a drag that interrupts it starts from what is on screen.
    @State private var windCurve: (from: Double, to: Double, start: Date, duration: Double)?
    @State private var rattleOffset: CGFloat = 0

    private var info: TimerObjectInfo { TimerObjectInfo.info(object) }

    var shown: Double { min(60, max(0, dragValue ?? displayed)) }

    var glowColor: Color {
        let glow = isBreak ? info.breakGlow : info.focusGlow
        return Color(red: glow.red, green: glow.green, blue: glow.blue)
    }

    var glowOpacity: Double {
        if isListening { return 1.0 }
        return minutes > 0 ? 0.85 : 0.45
    }

    /// Minute spacing under the finger matches the band the person is turning.
    private func pixelsPerMinute(side: CGFloat) -> CGFloat {
        let radius: Double
        if case .twist(let band) = info.style { radius = band.rx } else { radius = TimerObjectInfo.tomatoBand.rx }
        return radius * (.pi * 2 / 60) * (side * 0.86 / 680)
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

                // Artwork + dial inside the float / rattle wrapper
                ZStack {
                    // Soft drop shadow without expensive image alpha mask recomputation
                    Ellipse()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: side * (info.style == .hourglass ? 0.56 : 0.72), height: side * 0.22)
                        .blur(radius: 18)
                        .offset(y: side * 0.34)

                    ObjectArtwork(info: info, minutes: shown, flowing: isRunning && dragValue == nil)
                        .id(object)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: object)
                .frame(width: side * 0.86, height: side * 0.86)
                // Idle float. A phase animator restarts each cycle; a repeatForever animation was
                // replaced (and stopped for good) by the drag spring on the first twist.
                .phaseAnimator([false, true]) { view, up in
                    view.offset(y: (reduceMotion || dragStart != nil) ? 0 : (up ? 3.5 : -3.5))
                } animation: { _ in .easeInOut(duration: 3) }
                .rotationEffect(.degrees(rattleOffset))
                .scaleEffect(dragStart != nil && !reduceMotion ? 1.015 : (isListening && !reduceMotion ? 1.03 : 1.0))
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: dragStart != nil)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: isListening)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(info.style == .hourglass ? AnyShape(Rectangle()) : AnyShape(Circle()))
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        guard canAdjust else { return }
                        if dragStart == nil {
                            winding?.cancel()
                            winding = nil
                            var start = displayed
                            if let curve = windCurve, Date.now.timeIntervalSince(curve.start) < curve.duration {
                                start = Self.windValue(from: curve.from, to: curve.to,
                                                       elapsed: Date.now.timeIntervalSince(curve.start), duration: curve.duration)
                            }
                            windCurve = nil
                            dragStart = start
                            dragBlockID = blockID
                            lastNotch = Int(start.rounded())
                        }
                        let next = min(60, max(0, (dragStart ?? 0) - value.translation.width / pixelsPerMinute(side: side)))
                        dragValue = next
                        let notch = Int(next.rounded())
                        if notch != lastNotch {
                            let crossed = abs(notch - (lastNotch ?? notch))
                            lastNotch = notch
                            onRatchet(max(1, crossed))
                        }
                    }
                    .onEnded { _ in
                        guard let value = dragValue else { return }
                        let start = dragStart ?? displayed
                        let startBlock = dragBlockID
                        dragStart = nil
                        lastNotch = nil
                        dragBlockID = nil
                        // A nudge changes nothing: it must not round 24:37 up to 25:00 or skip a block
                        // with seconds left. Spring back to the live time, which kept running meanwhile.
                        guard let snapped = Self.dragResult(start: start, end: value) else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)) {
                                dragValue = nil
                                displayed = minutes
                                target = minutes
                            }
                            return
                        }
                        dragValue = nil
                        target = snapped
                        displayed = snapped
                        if !onChange(Int(snapped), startBlock) {
                            // Rejected (plan limit) or the block changed mid-drag: wind back to the real time.
                            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) {
                                displayed = minutes
                                target = minutes
                            }
                        }
                    }
            )
            .onAppear {
                displayed = minutes
                target = minutes
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
                // A touch the system cancels (alert, incoming call) never reaches onEnded.
                if phase != .active, dragStart != nil || dragValue != nil {
                    dragStart = nil
                    dragValue = nil
                    lastNotch = nil
                    dragBlockID = nil
                    displayed = minutes
                    target = minutes
                }
                if phase == .background {
                    winding?.cancel()
                    winding = nil
                    displayed = minutes
                }
            }
            .onDisappear {
                winding?.cancel()
                winding = nil
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("Tomato timer")
            .accessibilityLabel("\(info.name) timer")
            .accessibilityValue("\(Int(shown.rounded())) minutes")
            .accessibilityHint(canAdjust ? "Swipe left or right to set duration" : "Use session controls to change this timer")
            .accessibilityAdjustableAction { direction in
                guard canAdjust else { return }
                let value = Int(shown.rounded()) + (direction == .increment ? 1 : -1)
                onRatchet(1)
                _ = onChange(min(60, max(0, value)), blockID)
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
            windCurve = nil
            withAnimation(.linear(duration: min(1, gap * 60))) {
                displayed = target
            }
            return
        }
        let from = displayed, destination = target
        let duration = min(1.25, 0.3 + gap * 0.025)
        windCurve = (from, destination, .now, duration)
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) {
            displayed = destination
        }
        let crossings = Self.windClickTimes(from: from, to: destination, duration: duration)
        winding = Task { @MainActor in
            var elapsed = 0.0
            for time in crossings {
                try? await Task.sleep(for: .seconds(max(0, time - elapsed)))
                elapsed = time
                guard !Task.isCancelled else { return }
                onRatchet(1)
            }
            winding = nil
        }
    }

    /// When the eased wind crosses each whole minute. The curve (0.16, 1, 0.3, 1) has y(s) = 1 - (1 - s)^3,
    /// so the parameter for progress p is s = 1 - (1 - p)^(1/3); x(s) gives the time fraction.
    /// The minutes a drag from `start` to `end` sets, or nil for a nudge: under half a minute of
    /// travel, or landing back on the starting minute.
    static func dragResult(start: Double, end: Double) -> Double? {
        let snapped = end.rounded()
        guard abs(end - start) >= 0.5, snapped != start.rounded() else { return nil }
        return snapped
    }

    /// The value on screen `elapsed` seconds into a wind: the inverse of the curve `windClickTimes` uses.
    static func windValue(from: Double, to destination: Double, elapsed: Double, duration: Double) -> Double {
        let t = min(1, max(0, elapsed / duration))
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let s = (low + high) / 2
            let x = 3 * (1 - s) * (1 - s) * s * 0.16 + 3 * (1 - s) * s * s * 0.3 + s * s * s
            if x < t { low = s } else { high = s }
        }
        let s = (low + high) / 2
        return from + (destination - from) * (1 - pow(1 - s, 3))
    }

    static func windClickTimes(from: Double, to destination: Double, duration: Double) -> [Double] {
        guard abs(destination - from) > 0.001 else { return [] }
        let minutes: [Int]
        if destination > from {
            let first = Int(from.rounded(.down)) + 1, last = Int(destination.rounded(.down))
            minutes = first <= last ? Array(first...last) : []
        } else {
            let first = Int(from.rounded(.up)) - 1, last = Int(destination.rounded(.up))
            minutes = first >= last ? Array(stride(from: first, through: last, by: -1)) : []
        }
        return minutes.map { minute in
            let p = min(1, max(0, (Double(minute) - from) / (destination - from)))
            let s = 1 - pow(1 - p, 1.0 / 3)
            let x = 3 * (1 - s) * (1 - s) * s * 0.16 + 3 * (1 - s) * s * s * 0.3 + s * s * s
            return x * duration
        }
    }
}

/// Draws one object at the current (animated) minute value.
private struct ObjectArtwork: View {
    let info: TimerObjectInfo
    var minutes: Double
    var flowing: Bool

    var body: some View {
        switch info.style {
        case .twist(let band):
            ZStack {
                Image(info.artwork)
                    .resizable()
                    .scaledToFit()
                DialMarkings(minutes: minutes, band: band)
            }
        case .hourglass:
            HourglassArtwork(level: minutes / 60, flowing: flowing)
        case .clockFace(let face):
            ZStack {
                Image(info.artwork)
                    .resizable()
                    .scaledToFit()
                ClockFaceDial(minutes: minutes, face: face)
            }
        }
    }
}

/// The rotating minute band printed around a twist timer's seam (tomato, apple, lemon, egg).
private struct DialMarkings: View, Animatable {
    var minutes: Double
    var band: BandGeometry
    nonisolated var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    private static let angles = (0..<60).map { minute in
        let angle = Double(minute) / 60 * .pi * 2
        return (minute: minute, sine: sin(angle), cosine: cos(angle))
    }

    private static let darkInk = Color(red: 38 / 255, green: 34 / 255, blue: 30 / 255)

    private static func numerals(_ color: Color) -> [Int: Text] {
        var map: [Int: Text] = [:]
        for minute in stride(from: 0, to: 60, by: 5) {
            map[minute] = Text("\(minute)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        return map
    }
    private static let lightTexts = DialMarkings.numerals(.white)
    private static let darkTexts = DialMarkings.numerals(DialMarkings.darkInk)

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 680
            context.scaleBy(x: scale, y: scale)
            let rho = minutes / 60 * .pi * 2
            let sinRho = sin(rho), cosRho = cos(rho)
            let k = band.scale
            let ink: Color = band.darkInk ? Self.darkInk : .white
            let texts = band.darkInk ? Self.darkTexts : Self.lightTexts
            for angle in Self.angles {
                let minute = angle.minute
                let cosine = angle.cosine * cosRho + angle.sine * sinRho
                guard cosine >= 0.06 else { continue }
                let sine = angle.sine * cosRho - angle.cosine * sinRho
                let major = minute % 5 == 0
                let x = band.cx + band.rx * sine, y = band.cy + band.ry * cosine
                let length: Double = (major ? 19 : 13) * k
                let width = (major ? 5.2 : 3.6) * max(0.3, cosine) * k
                var ctx = context
                let t = min(1, max(0, (cosine - 0.06) / 0.36))
                ctx.opacity = 0.95 * t * t * (3 - 2 * t)
                ctx.fill(Path(roundedRect: CGRect(x: x - width / 2, y: y - 8 * k - length, width: width, height: length), cornerRadius: width / 2), with: .color(ink))
                if major, let text = texts[minute] {
                    ctx.translateBy(x: band.cx + band.rx * 0.985 * sine, y: band.cy + band.ry * 0.985 * cosine - 50 * k)
                    ctx.scaleBy(x: max(0.2, cosine) * k, y: k)
                    ctx.draw(text, at: .zero)
                }
            }
        }
    }
}

/// Sand drains from the top bulb into a growing pile. Layer positions are in the artwork's
/// 680-unit frame, measured by Tools/objects/hourglass_layers.py.
private struct HourglassArtwork: View, Animatable {
    var level: Double
    var flowing: Bool
    nonisolated var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    private static let sandTop = 150.0
    private static let neck = 326.0
    private static let pileTip = 486.0
    private static let pileBottom = 570.0
    private static let pileCenterX = 341.5

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 680
            let clamped = min(1, max(0, level))
            // The upper bulb narrows toward the neck, so its surface falls slowly at first.
            let surface = Self.neck - (Self.neck - Self.sandTop) * pow(clamped, 0.45)
            let poured = 1 - clamped
            let pileScaleY = 0.25 + 1.45 * poured.squareRoot()
            // The stream art runs to the bulb floor; end it just inside the scaled pile's tip.
            let streamEnd = Self.pileBottom - (Self.pileBottom - Self.pileTip) * pileScaleY + 4
            ZStack {
                Image("hourglass-base").resizable()
                Image("hourglass-sand-top").resizable()
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: surface * unit)
                            Color.black
                        }
                    }
                Image("hourglass-pile").resizable()
                    .scaleEffect(x: 0.62 + 0.5 * pow(poured, 0.34), y: pileScaleY,
                                 anchor: UnitPoint(x: Self.pileCenterX / 680, y: Self.pileBottom / 680))
                    .mask { Image("hourglass-bottom-mask").resizable() }
                Image("hourglass-stream").resizable()
                    .mask {
                        VStack(spacing: 0) {
                            Color.black.frame(height: streamEnd * unit)
                            Color.clear
                        }
                    }
                    .opacity(flowing && clamped > 0.001 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: flowing)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A 60-minute "time remaining" dial on the alarm clock's blank face: the red wedge shrinks
/// back toward 12 o'clock as the block runs.
private struct ClockFaceDial: View, Animatable {
    var minutes: Double
    var face: FaceGeometry
    nonisolated var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    private static let ink = Color(red: 38 / 255, green: 34 / 255, blue: 30 / 255)
    private static let wedge = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    private static let numerals: [Int: Text] = {
        var map: [Int: Text] = [:]
        for minute in stride(from: 0, to: 60, by: 5) {
            map[minute] = Text("\(minute)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(ClockFaceDial.ink)
        }
        return map
    }()

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 680
            context.scaleBy(x: scale, y: scale)
            let center = CGPoint(x: face.cx, y: face.cy)
            let radius = face.radius
            let value = min(60, max(0, minutes))
            func point(_ minute: Double, _ r: Double) -> CGPoint {
                let angle = (minute * 6 - 90) * .pi / 180
                return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            }
            if value > 0.01 {
                var wedge = Path()
                wedge.move(to: center)
                wedge.addArc(center: center, radius: radius * 0.62, startAngle: .degrees(-90), endAngle: .degrees(-90 + value * 6), clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(Self.wedge.opacity(0.92)))
            }
            for minute in 0..<60 {
                let major = minute % 5 == 0
                var tick = Path()
                tick.move(to: point(Double(minute), radius * (major ? 0.82 : 0.87)))
                tick.addLine(to: point(Double(minute), radius * 0.94))
                context.stroke(tick, with: .color(Self.ink.opacity(major ? 0.9 : 0.5)), style: StrokeStyle(lineWidth: major ? 4.5 : 2, lineCap: .round))
            }
            for (minute, text) in Self.numerals {
                context.draw(text, at: point(Double(minute), radius * 0.72), anchor: .center)
            }
            var hand = Path()
            hand.move(to: center)
            hand.addLine(to: point(value, radius * 0.66))
            context.stroke(hand, with: .color(Self.ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26)), with: .color(Self.ink))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(Color(white: 0.85)))
        }
    }
}
