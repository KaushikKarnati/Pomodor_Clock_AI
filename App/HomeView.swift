import SwiftUI
import AVFoundation

struct HomeView: View {
    @Bindable var store: FocusStore
    @State private var speech = SpeechService()
    @State private var words = ""
    @State private var showPlanSheet = false
    @State private var showMoreSheet = false
    @State private var showTypedInput = false
    @State private var endArmed = false
    @State private var endTimer: Task<Void, Never>?
    @State private var callingPulse = false
    @State private var barPhase: CGFloat = 0
    @State private var quietProgress: CGFloat = 1.0
    @State private var quietTimer: Task<Void, Never>?
    @FocusState private var wordsFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var phase: SessionPhase {
        if let s = store.session, !s.plan.blocks.isEmpty {
            if s.status == .running { return .running }
            if s.status == .paused { return .paused }
            if s.status == .finished || s.status == .ended { return .finished }
        }
        if store.proposal != nil { return .proposal }
        return .idle
    }

    private var isListening: Bool {
        speech.isRecording || speech.isPreparing
    }

    private var currentBlock: FocusBlock? {
        if let s = store.session, s.isActive {
            return s.current
        }
        return store.proposal?.blocks.first
    }

    private var isBreakBlock: Bool {
        currentBlock?.isBreak ?? false
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background Studio Backdrop
                studioBackground
                    .ignoresSafeArea()

                // Main App Structure
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    Spacer(minLength: 4)

                    // Hero Stage with Tomato
                    stageView(availableHeight: geometry.size.height)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 4)

                    // Readout Section (Kind, Time, Title, Sub, Next, Chip)
                    readoutView
                        .padding(.horizontal, 24)

                    Spacer(minLength: 8)

                    // Dock (Plan button, Talk button, Play/Pause button)
                    dockView
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating Toast Notification
                if let toast = store.toastMessage {
                    VStack {
                        toastView(toast)
                            .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(50)
                }

                // Modal Scrim + Plan Sheet
                if showPlanSheet {
                    scrimOverlay {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            showPlanSheet = false
                        }
                    }
                    .ignoresSafeArea()
                    .zIndex(30)

                    VStack {
                        Spacer()
                        planSheetView(maxHeight: geometry.size.height * 0.88)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(31)
                }

                // Modal Scrim + More Sheet (Session & Settings)
                if showMoreSheet {
                    scrimOverlay {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            showMoreSheet = false
                        }
                    }
                    .ignoresSafeArea()
                    .zIndex(30)

                    VStack {
                        Spacer()
                        moreSheetView(maxHeight: geometry.size.height * 0.88)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(31)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            speech.onFinished = { text in
                handleSpeechFinished(text)
            }
            if let message = store.error { store.reply = message }
        }
        .onChange(of: store.error) { _, message in
            if let message { store.reply = message }
        }
        .onChange(of: store.notice) { _, message in
            if let message { store.reply = message }
        }
        .onChange(of: speech.error) { _, message in
            if let message {
                store.reply = message
                store.toast(message)
                showTypedInput = true
            }
        }
        .onChange(of: speech.text) { _, text in
            words = text
            armQuietTimer()
        }
        .onChange(of: speech.isRecording) { _, recording in
            store.setListening(recording)
            if recording {
                armQuietTimer()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                stopListening()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            stopListening()
        }
    }

    // MARK: - Studio Background
    private var studioBackground: some View {
        ZStack {
            Color(red: 7/255, green: 8/255, blue: 11/255) // --bg-bottom

            LinearGradient(
                colors: [Color(red: 20/255, green: 24/255, blue: 30/255), Color(red: 7/255, green: 8/255, blue: 11/255)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Tomato Bloom
            RadialGradient(
                colors: [Color(red: 255/255, green: 72/255, blue: 50/255).opacity(0.22), Color.clear],
                center: UnitPoint(x: 0.5, y: 0.30),
                startRadius: 0,
                endRadius: 360
            )

            // Leaf Bloom
            RadialGradient(
                colors: [Color(red: 34/255, green: 160/255, blue: 128/255).opacity(0.12), Color.clear],
                center: UnitPoint(x: 0.0, y: 1.0),
                startRadius: 0,
                endRadius: 340
            )

            // Sky Bloom
            RadialGradient(
                colors: [Color(red: 96/255, green: 108/255, blue: 255/255).opacity(0.12), Color.clear],
                center: UnitPoint(x: 1.0, y: 0.96),
                startRadius: 0,
                endRadius: 340
            )
        }
        .drawingGroup()
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            // Tomato Brand
            HStack(spacing: 8) {
                ZStack {
                    Ellipse()
                        .fill(Color(red: 1.0, green: 69/255.0, blue: 58/255.0)) // #FF453A
                        .frame(width: 22, height: 18)
                        .offset(y: 2)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 48/255.0, green: 209/255.0, blue: 88/255.0)) // #30D158
                        .offset(x: 1, y: -6)
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

                Text("FocusTalk")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            // More Button (•••)
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showMoreSheet = true
                }
            } label: {
                HStack(spacing: 3) {
                    Circle().fill(Color.white).frame(width: 3.8, height: 3.8)
                    Circle().fill(Color.white).frame(width: 3.8, height: 3.8)
                    Circle().fill(Color.white).frame(width: 3.8, height: 3.8)
                }
                .frame(width: 40, height: 40)
                .liquidGlassCircle()
            }
            .accessibilityLabel("Session and settings")
        }
        .frame(minHeight: 44)
    }

    // MARK: - Stage (Tomato & Floating Caption)
    private func stageView(availableHeight: CGFloat) -> some View {
        let tomatoSize = max(180, min(availableHeight * 0.38, 360))

        return ZStack(alignment: .bottom) {
            // Tomato with Dial & Halo
            TomatoView(
                minutes: store.currentBlockMinutes,
                canAdjust: !isListening && !store.busy && phase != .proposal,
                isBreak: isBreakBlock,
                isListening: isListening,
                isRattling: store.isRattling,
                onChange: { newMinutes in
                    store.setManualMinutes(newMinutes)
                },
                onRatchet: { crossedNotches in
                    store.audio.ratchet(notches: crossedNotches, haptics: store.settings.haptics)
                }
            )
            .frame(width: tomatoSize, height: tomatoSize)

            // Caption overlay when listening, thinking, or showing reply
            if shouldShowCaption {
                captionBubble
                    .offset(y: 10)
            }
        }
    }

    private var shouldShowCaption: Bool {
        isListening || store.busy || !store.reply.isEmpty || showTypedInput || (store.proposal != nil && store.session?.isActive == true)
    }

    private var captionBubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isListening {
                Text(speech.text.isEmpty ? "Listening" : "You")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.70))

                Text(speech.text.isEmpty ? "Go ahead, I’m listening." : speech.text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(speech.text.isEmpty ? Color.white.opacity(0.70) : .white)
                    .lineLimit(3)
            } else if store.busy {
                if !store.said.isEmpty {
                    Text("You: \(store.said)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    ProgressView().tint(.white).scaleEffect(0.85)
                    Text("Planning your blocks…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            } else if showTypedInput {
                HStack {
                    Text("Your words")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                    Spacer()
                    Button {
                        showTypedInput = false
                        wordsFocused = false
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                TextField("Tasks and time available", text: $words)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .focused($wordsFocused)
                    .onSubmit {
                        submitTypedWords()
                    }
                Button("Plan") {
                    submitTypedWords()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 69/255, blue: 58/255))
            } else if !store.reply.isEmpty {
                if !store.said.isEmpty {
                    Text("You: \(store.said)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                }
                Text(store.reply)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)

                // Replan actions if session already active
                if store.proposal != nil && store.session?.isActive == true {
                    HStack(spacing: 8) {
                        Button("Use new plan") {
                            if let p = store.proposal {
                                store.apply(p, startImmediately: true)
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 1.0, green: 69/255, blue: 58/255))
                        .clipShape(Capsule())

                        Button("Keep current plan") {
                            store.proposal = nil
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 999)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 520, alignment: .leading)
        .liquidGlass(cornerRadius: 22)
        .padding(.horizontal, 20)
    }

    // MARK: - Readout Section
    private var readoutView: some View {
        VStack(spacing: 3) {
            // Kind
            Text(kindText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.70))
                .tracking(0.5)
                .frame(minHeight: 18)

            // Huge thin time countdown (Isolated leaf view for 60/120 FPS timer ticking)
            if phase != .idle {
                CountdownReadoutView(seconds: store.displaySeconds)
            }

            // Title
            Text(titleText)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Sub
            if !subText.isEmpty {
                Text(subText)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .lineLimit(3)
            }

            // Next
            if !nextText.isEmpty {
                Text(nextText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .padding(.top, 3)
            }

            // Play an example Chip (when idle)
            if phase == .idle && !isListening && !store.busy {
                Button {
                    store.runDemo()
                } label: {
                    Text("Play an example")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .liquidGlass(cornerRadius: 999)
                }
                .padding(.top, 8)
            }
        }
    }

    private var kindText: String {
        switch phase {
        case .idle:
            return ""
        case .proposal:
            return "Plan ready"
        case .running:
            if let b = store.session?.current {
                if b.isBreak {
                    return b.minutes >= 15 ? "Long break" : "Short break"
                } else {
                    let totalFocus = store.session?.plan.blocks.filter { !$0.isBreak }.count ?? 1
                    let curIdx = (store.session?.plan.blocks.prefix(store.session?.index ?? 0).filter { !$0.isBreak }.count ?? 0) + 1
                    return "Focus block \(curIdx) of \(totalFocus)"
                }
            }
            return "Focus"
        case .paused:
            return "Paused"
        case .finished:
            return "Done"
        }
    }

    private var titleText: String {
        switch phase {
        case .idle:
            return "What’s on your plate?"
        case .proposal:
            return "Your plan is ready"
        case .running, .paused:
            return store.session?.current?.title ?? "Focus"
        case .finished:
            return "Session done"
        }
    }

    private var subText: String {
        switch phase {
        case .idle:
            return "Tap the mic and say your tasks and how much time you have. Or twist the tomato to set a timer."
        case .proposal:
            let focusCount = store.proposal?.focusBlockCount ?? 1
            let totalMins = store.proposal?.totalMinutes ?? 30
            let endStr = formatTime(Date.now.addingTimeInterval(Double(totalMins * 60)))
            return "\(focusCount) focus block\(focusCount == 1 ? "" : "s"), done around \(endStr)."
        case .running, .paused:
            if let b = store.session?.current {
                if b.isBreak {
                    return b.minutes >= 15 ? "Step away from the screen for a proper rest." : "Stand up, stretch, refill your water."
                } else {
                    return b.goal.isEmpty ? "Focus on this task." : b.goal
                }
            }
            return ""
        case .finished:
            let completedCount = store.session?.completed.count ?? 0
            return "You showed up and completed \(completedCount) block\(completedCount == 1 ? "" : "s")."
        }
    }

    private var nextText: String {
        switch phase {
        case .idle:
            return ""
        case .proposal:
            return "Say “start” or tap play."
        case .running:
            if let s = store.session, s.index + 1 < s.plan.blocks.count {
                let nxt = s.plan.blocks[s.index + 1]
                let end = Date.now.addingTimeInterval(s.secondsLeft(at: .now))
                return "Next at \(formatTime(end)): \(nxt.title), \(nxt.minutes) min"
            }
            return "Last block of this session."
        case .paused:
            return "Tap play when you’re ready."
        case .finished:
            return "Tap the mic to plan the next one."
        }
    }

    // MARK: - Dock View
    private var dockView: some View {
        HStack(spacing: 22) {
            // Plan button
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showPlanSheet = true
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .liquidGlassCircle()

                    if store.proposal != nil {
                        Circle()
                            .fill(Color(red: 1.0, green: 69/255, blue: 58/255))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(red: 20/255, green: 24/255, blue: 30/255), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
            }
            .accessibilityLabel("Plan")

            // Talk button
            Button {
                handleTalkTap()
            } label: {
                ZStack {
                    if isListening {
                        // Expanding Pill State
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                ForEach(0..<4) { i in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                        .frame(width: 3.5, height: barHeight(for: i))
                                }
                            }
                            .frame(height: 22)

                            Text(speech.text.isEmpty ? "Cancel" : "Send")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 164, height: 76)
                        .background(Color(red: 1.0, green: 69/255, blue: 58/255))
                        .clipShape(Capsule())
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: max(0, 120 * quietProgress), height: 2)
                                .padding(.bottom, 11)
                        }
                    } else if store.busy {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 76, height: 76)
                            .background(Color(red: 1.0, green: 69/255, blue: 58/255))
                            .clipShape(Circle())
                    } else if store.voice.isSpeaking {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .background(Color(red: 1.0, green: 69/255, blue: 58/255))
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .background(Color(red: 1.0, green: 69/255, blue: 58/255))
                            .clipShape(Circle())
                    }
                }
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isListening)
            }
            .accessibilityLabel(isListening ? "Cancel listening" : "Talk")

            // Play / Pause / Again button
            Button {
                handlePlayTap()
            } label: {
                ZStack {
                    if phase == .proposal {
                        Circle()
                            .stroke(Color(red: 1.0, green: 69/255, blue: 58/255), lineWidth: 2)
                            .frame(width: 62, height: 62)
                            .scaleEffect(callingPulse ? 1.28 : 0.92)
                            .opacity(callingPulse ? 0 : 0.75)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: false), value: callingPulse)
                            .onAppear { callingPulse = true }
                    }

                    Image(systemName: playIconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .liquidGlassCircle()
                        .opacity(isPlayDisabled ? 0.38 : 1.0)
                }
            }
            .disabled(isPlayDisabled)
            .accessibilityLabel(playAccessibilityLabel)
        }
    }

    private var playIconName: String {
        switch phase {
        case .idle:
            return "play.fill"
        case .proposal:
            return "play.fill"
        case .running:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .finished:
            return "arrow.clockwise"
        }
    }

    private var isPlayDisabled: Bool {
        phase == .idle || isListening || store.busy
    }

    private var playAccessibilityLabel: String {
        switch phase {
        case .idle: return "Start"
        case .proposal: return "Start session"
        case .running: return "Pause"
        case .paused: return "Resume"
        case .finished: return "Start over"
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: [CGFloat] = [6, 18, 12, 22]
        return base[index]
    }

    // MARK: - Toast View
    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 999)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - Scrim Overlay
    private func scrimOverlay(onTap: @escaping () -> Void) -> some View {
        Color.black.opacity(0.42)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    // MARK: - Plan Sheet View
    private func planSheetView(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule()
                .fill(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.38))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(planSheetTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text(planSheetSummary)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
                Spacer()

                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showPlanSheet = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .frame(width: 36, height: 36)
                        .background(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.24), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let blocks = displayedBlocks, !blocks.isEmpty {
                        // Task Chips with Status Dots
                        taskChipsView(blocks: blocks)

                        // Timeline Rows
                        timelineView(blocks: blocks)

                        // Action Buttons
                        if phase == .proposal {
                            Button {
                                if let p = store.proposal {
                                    showPlanSheet = false
                                    store.apply(p, startImmediately: true)
                                }
                            } label: {
                                Text("Start session")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 1.0, green: 69/255, blue: 58/255))
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        // Empty state
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Tap the mic and say what you need to get done and how long you have. Each focus block and break shows up here with its start time.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.white.opacity(0.70))

                            Button {
                                showPlanSheet = false
                                store.runDemo()
                            } label: {
                                Text("Play the example")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 1.0, green: 69/255, blue: 58/255))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxHeight: maxHeight)
        .liquidGlass(cornerRadius: 32, isSheet: true)
    }

    private var displayedBlocks: [FocusBlock]? {
        if let p = store.proposal { return p.blocks }
        if let s = store.session { return s.plan.blocks }
        return nil
    }

    private var planSheetTitle: String {
        if store.proposal != nil { return "Your plan" }
        if let s = store.session { return s.status == .finished ? "Session done" : "Your session" }
        return "Your plan"
    }

    private var planSheetSummary: String {
        guard let blocks = displayedBlocks, !blocks.isEmpty else { return "Nothing planned yet." }
        let focusCount = blocks.filter { !$0.isBreak }.count
        let totalMins = blocks.reduce(0) { $0 + $1.minutes }
        let seconds = store.proposal == nil ? (store.session?.sessionSecondsLeft(at: .now) ?? Double(totalMins * 60)) : Double(totalMins * 60)
        if store.proposal == nil, let session = store.session, [.finished, .ended].contains(session.status) {
            return "\(session.completed.count) completed, \(session.skipped.count) skipped."
        }
        let end = formatTime(Date.now.addingTimeInterval(seconds))
        let qualifier = store.session?.status == .paused && store.proposal == nil ? " if resumed now" : ""
        return "\(focusCount) focus block\(focusCount == 1 ? "" : "s"). Done around \(end)\(qualifier)."
    }

    private func taskChipsView(blocks: [FocusBlock]) -> some View {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for block in blocks where !block.isBreak {
            if counts[block.title] == nil {
                order.append(block.title)
            }
            counts[block.title, default: 0] += 1
        }

        return FlowLayout(spacing: 8) {
            ForEach(order, id: \.self) { task in
                let count = counts[task] ?? 1
                HStack(spacing: 6) {
                    Text(task)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 3) {
                        ForEach(0..<count, id: \.self) { _ in
                            Circle()
                                .strokeBorder(Color(red: 1.0, green: 69/255, blue: 58/255), lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.24))
                .clipShape(Capsule())
            }
        }
    }

    private func timelineView(blocks: [FocusBlock]) -> some View {
        let activeIdx = store.proposal == nil ? store.session?.index : nil
        let isSessionActive = store.proposal == nil && store.session?.isActive == true
        let skippedSet = Set(store.session?.skipped ?? [])
        let completedSet = Set(store.session?.completed ?? [])

        var elapsed: Double = 0
        let baseDate = Date.now
        let scheduledDates = store.proposal == nil ? store.session?.timelineStartDates(at: baseDate) : nil
        var rowItems: [TimelineRowItem] = []
        rowItems.reserveCapacity(blocks.count)

        for (index, block) in blocks.enumerated() {
            let rowDate = scheduledDates.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? baseDate.addingTimeInterval(elapsed)
            let timeStr = formatTime(rowDate)
            elapsed += Double(block.minutes * 60)
            let isCurrent = (activeIdx == index && isSessionActive)
            let isSkipped = skippedSet.contains(block.id)
            let isDone = completedSet.contains(block.id)
            rowItems.append(TimelineRowItem(
                id: block.id,
                timeString: timeStr,
                isBreak: block.isBreak,
                title: block.title,
                goal: block.goal,
                minutes: block.minutes,
                isDone: isDone,
                isSkipped: isSkipped,
                isCurrent: isCurrent
            ))
        }

        return LazyVStack(spacing: 4) {
            ForEach(rowItems) { item in
                HStack(alignment: .top, spacing: 12) {
                    // Time column
                    Text(item.timeString)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.70))
                        .frame(width: 58, alignment: .trailing)
                        .padding(.top, 2)

                    // Vertical colored line
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.isBreak ? Color(red: 48/255, green: 209/255, blue: 88/255) : Color(red: 1.0, green: 69/255, blue: 58/255))
                        .frame(width: 4)
                        .opacity(item.isDone || item.isSkipped ? 0.3 : 0.85)

                    // Task & goal
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: item.isBreak ? .regular : .semibold))
                            .foregroundStyle(item.isDone || item.isSkipped ? Color.white.opacity(0.70) : .white)
                            .strikethrough(item.isSkipped)

                        if !item.goal.isEmpty {
                            Text(item.goal)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.70))
                        }
                    }

                    Spacer()

                    // Duration
                    Text("\(item.minutes) min")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.70))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(item.isCurrent ? Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.24) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - More Sheet View (Session and Settings)
    private func moreSheetView(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule()
                .fill(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.38))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header
            HStack {
                Text("Session and settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()

                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showMoreSheet = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .frame(width: 36, height: 36)
                        .background(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.24), in: Circle())
                }
                .accessibilityLabel("Close settings")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 16) {
                    // 2x2 Action Tiles
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        tileButton(icon: "plus", title: "Add 5 minutes", disabled: store.session?.isActive != true) {
                            store.extend()
                        }

                        tileButton(icon: "forward.fill", title: "Skip this block", disabled: store.session?.isActive != true) {
                            store.skip()
                        }

                        // End session tile with double-tap warning
                        Button {
                            if endArmed {
                                endArmed = false
                                endTimer?.cancel()
                                store.end()
                            } else {
                                endArmed = true
                                endTimer = Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(3))
                                    endArmed = false
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(endArmed ? .white : Color(red: 1.0, green: 69/255, blue: 58/255))

                                Text(endArmed ? "Tap again to end" : "End session")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                            .padding(14)
                            .background(endArmed ? Color(red: 1.0, green: 69/255, blue: 58/255) : Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.24))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .disabled(store.session?.isActive != true)
                        .accessibilityIdentifier(endArmed ? "Tap again to end" : "End session")
                        .accessibilityLabel(endArmed ? "Tap again to end" : "End session")

                        tileButton(icon: "arrow.clockwise", title: "Start over", disabled: phase == .idle) {
                            store.startOver()
                            showMoreSheet = false
                        }
                    }

                    // Settings Group (Toggles)
                    VStack(spacing: 0) {
                        settingToggle(title: "Read replies aloud", subtitle: "FocusTalk speaks its answers and each new block.", isOn: binding(\.voice))

                        Divider().background(Color.white.opacity(0.14))

                        settingToggle(title: "Ticking sound", subtitle: "The tomato ticks while a block runs, like the real timer.", isOn: binding(\.tick))

                        Divider().background(Color.white.opacity(0.14))

                        settingToggle(title: "Start the next block on its own", subtitle: "Turn this off to tap play after every chime.", isOn: binding(\.auto))
                    }
                    .padding(.horizontal, 16)
                    .background(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // "How you talk to it" Note
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How you talk to it")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Tap the mic and talk. FocusTalk sends what you said when you pause, then answers out loud. Or tap “Type instead” below to type your tasks.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.70))

                        HStack(spacing: 12) {
                            Button("Type instead") {
                                showMoreSheet = false
                                showTypedInput = true
                                wordsFocused = true
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 69/255, blue: 58/255))

                            Spacer()

                            if phase == .idle {
                                Button("Play the example") {
                                    showMoreSheet = false
                                    store.runDemo()
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.3))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxHeight: maxHeight)
        .liquidGlass(cornerRadius: 32, isSheet: true)
    }

    private func tileButton(icon: String, title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 1.0, green: 69/255, blue: 58/255))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .padding(14)
            .background(Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .opacity(disabled ? 0.38 : 1.0)
        }
        .accessibilityIdentifier(title)
        .accessibilityLabel(title)
        .disabled(disabled)
    }

    private func settingToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.70))
            }
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier(title)
        .accessibilityLabel(title)
        .tint(Color(red: 48/255, green: 209/255, blue: 88/255)) // #30D158
    }

    private func binding(_ keyPath: WritableKeyPath<FocusSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { val in
                var s = store.settings
                s[keyPath: keyPath] = val
                store.saveSettings(s)
            }
        )
    }

    // MARK: - Actions
    private func handleTalkTap() {
        if isListening {
            if speech.text.isEmpty {
                stopListening()
            } else {
                speech.finish()
            }
        } else if store.busy {
            store.cancelGeneration()
        } else if store.voice.isSpeaking {
            store.voice.stop()
        } else {
            startListening()
        }
    }

    private func startListening() {
        store.error = nil
        store.reply = ""
        speech.text = ""
        words = ""
        quietProgress = 1.0
        Task {
            await speech.start()
        }
    }

    private func stopListening() {
        quietTimer?.cancel()
        speech.stop()
        store.setListening(false)
    }

    private func armQuietTimer() {
        quietTimer?.cancel()
        quietProgress = 1.0
        guard isListening, !speech.text.isEmpty else { return }

        withAnimation(reduceMotion ? nil : .linear(duration: 1.8)) {
            quietProgress = 0
        }
        quietTimer = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1800)) } catch { return }
            guard !Task.isCancelled, isListening else { return }
            speech.finish()
        }
    }

    private func handleSpeechFinished(_ text: String) {
        stopListening()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        words = clean
        store.propose(words: clean, budget: 30)
    }

    private func submitTypedWords() {
        wordsFocused = false
        showTypedInput = false
        let clean = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        store.propose(words: clean, budget: 30)
    }

    private func handlePlayTap() {
        if phase == .proposal {
            if let p = store.proposal {
                store.apply(p, startImmediately: true)
            }
        } else if phase == .finished {
            store.startOver()
        } else {
            store.startPause()
        }
    }

    private func clockString(_ seconds: Double) -> String {
        let n = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", n / 60, n % 60)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}

/// Standalone leaf countdown readout view to isolate high-frequency timer ticks
struct CountdownReadoutView: View {
    let seconds: Int

    var body: some View {
        let mins = seconds / 60
        let secs = seconds % 60
        Text(String(format: "%02d:%02d", mins, secs))
            .font(.system(size: 60, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.vertical, 1)
    }
}

/// Precomputed immutable row item for LazyVStack timeline rendering
struct TimelineRowItem: Identifiable {
    let id: UUID
    let timeString: String
    let isBreak: Bool
    let title: String
    let goal: String
    let minutes: Int
    let isDone: Bool
    let isSkipped: Bool
    let isCurrent: Bool
}

enum SessionPhase {
    case idle
    case proposal
    case running
    case paused
    case finished
}

// FlowLayout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            currentX += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
            height = max(height, currentY + maxHeightInRow)
        }
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
        }
    }
}

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    var isSheet: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(isSheet ? Color(red: 28/255, green: 31/255, blue: 37/255).opacity(0.88)
                                           : Color(red: 46/255, green: 50/255, blue: 58/255).opacity(0.48))
                    }
                    .overlay {
                        RadialGradient(
                            colors: [Color.white.opacity(0.22), Color.clear],
                            center: UnitPoint(x: 0.25, y: -0.1),
                            startRadius: 0,
                            endRadius: 180
                        )
                        .clipShape(shape)
                    }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.40), location: 0.0),
                                    .init(color: Color.white.opacity(0.08), location: 0.28),
                                    .init(color: Color.clear, location: 0.50),
                                    .init(color: Color.white.opacity(0.08), location: 0.82),
                                    .init(color: Color.white.opacity(0.35), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                    }
                    .shadow(color: Color.black.opacity(isSheet ? 0.55 : 0.38), radius: isSheet ? 24 : 12, x: 0, y: isSheet ? 10 : 5)
            }
    }
}

struct LiquidGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle().fill(Color(red: 46/255, green: 50/255, blue: 58/255).opacity(0.48))
                    }
                    .overlay {
                        RadialGradient(
                            colors: [Color.white.opacity(0.22), Color.clear],
                            center: UnitPoint(x: 0.25, y: -0.1),
                            startRadius: 0,
                            endRadius: 50
                        )
                        .clipShape(Circle())
                    }
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.40), location: 0.0),
                                    .init(color: Color.white.opacity(0.08), location: 0.28),
                                    .init(color: Color.clear, location: 0.50),
                                    .init(color: Color.white.opacity(0.08), location: 0.82),
                                    .init(color: Color.white.opacity(0.35), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 28, isSheet: Bool = false) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isSheet: isSheet))
    }

    func liquidGlassCircle() -> some View {
        modifier(LiquidGlassCircleModifier())
    }
}
