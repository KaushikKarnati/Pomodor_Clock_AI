# Reliability and rendering follow-up — October 15, 2026

Based on repository commit `89894c2`. Layout, colors, typography, artwork, control placement, and screen structure remain unchanged. Errors use the existing caption/toast/input surfaces; the plan's existing text now reflects remaining time. No editor or history browser was added.

## Correctness

- Dial increases update and validate the plan budget before committing, so a 25-to-30-minute adjustment survives reload. Over-limit adjustments leave the session unchanged.
- A FIFO background writer replaces unordered detached saves. Write failures reach the store; queued saves receive a bounded iOS background-task allowance. This does not guarantee saving through abrupt process termination or device power loss.
- Spoken-reply preferences round-trip through JSON, including `false`; legacy settings without the key default to enabled.
- Local acceptance commands run before clearing the proposed plan. New AI plans start automatically; replacements of active sessions require explicit acceptance. AI and notification failures appear in the existing caption; speech failures reveal the existing typed input.
- Current/future timeline dates follow remaining time instead of restarting the whole schedule at every render. Paused finish estimates explicitly assume resuming now. Past rows show the original schedule because actual historical start timestamps were never recorded.
- Start over archives the active session. Failed extensions report the time limit. Untrusted extreme durations are rejected before summing them.

## Rendering and work reduction

- The foreground clock schedules at displayed-second boundaries instead of polling five times per second. No timer polling runs while idle, paused, or backgrounded. Resume reconciles elapsed deadlines.
- Removed the permanently running no-op `CADisplayLink`. SwiftUI retains native animation scheduling and the existing ProMotion eligibility setting.
- Small dial steps use native interpolation; the speech-silence progress uses one native animation instead of 30 root-state updates.
- Precomputed dial angles replace per-mark trigonometry with two trigonometric calls per rendered frame. Appearance and geometry formulas are equivalent.
- Microphone preparation, teardown, and ambient setup share a serial background queue. Cancellation checks prevent stale setup callbacks from starting an old recording. This avoids unordered audio-session mutations and moves configuration off the main actor.
- Resolved the `Animatable` actor-isolation warning.

## Verification

- `swift test`: 15 tests passed. Includes deadline reconciliation, settings round-trip, dial budget/reload, unchanged state on rejected adjustment, stable timeline, overflow rejection, 100 queued saves, and failed-write recovery.
- Xcode simulator tests: 9 store tests and 7 UI tests passed, including the actual preference reload and typed acceptance regressions. Total across both suites: 31 tests passed.
- Release simulator Analyze: passed. No Swift source warnings; Xcode emits the standard skipped AppIntents metadata notice because this app does not use AppIntents.
- Store cadence regression: passed, observing 2–3 updates over 2.4 seconds rather than 5 Hz, plus unchanged clock state during idle, pause, and background intervals.
- Simulator screenshots from the initial passing UI run were visually inspected for the home and running states. These are visual inspections, not pixel-diff or physical-device frame-time measurements.

The store tests inject planning, persistence, audio, and notification services. Passing them does not prove real Apple Intelligence, microphone, Bluetooth, interruption, notification audibility, or Live Activity behavior on hardware. No device deployment, TestFlight upload, or App Store release was performed. Sustained FPS, energy, thermal behavior, and subjective smoothness still need physical-device Instruments and hands-on testing.

## Audio activation follow-up

The explicit session transitions now use iOS 27 asynchronous activate/deactivate APIs. iOS 26 retains synchronous APIs exclusively on the background audio worker, enforced by queue preconditions. The FIFO waits for asynchronous completions before starting later transitions. Player creation, preparation, playback, and stopping also run on that worker because player APIs can implicitly activate the audio session. Haptics stay on the main actor. No UI changes were made.

Verification: 11 store/audio-queue tests and the existing session-flow UI test passed (12 targeted tests). Simulator and signed physical-device Release builds passed. Code signature verification passed; the updated app was installed and launched on Karnatty. A 15-second launch-console capture contained no instance of the reported warning and ended at its intentional timeout; this does not verify every audio or microphone interaction. Real microphone start/stop, speech playback, and interruption scenarios still require hands-on verification.

## Fast dial clicks: minimal playback follow-up

After reverting the scheduled-player experiment following device feedback, the existing single ratchet player now finishes its current click instead of rewinding mid-sound. Dial movement reports crossed notches; immediate playback repeats the unchanged 22 ms sample at most three times for a jump. Sound requests are independent of the 30 ms haptic throttle. No player pool, scheduled playback, delayed backlog, layout, or animation changes are introduced.

Verification: 13 store/audio tests and the manual-dial UI test passed (14 targeted tests). New tests cover non-interruption of an active click, bounded repetitions, stopping, and returning to a single click. Signed Release build and signature verification passed; installed on Karnatty. Audible fast-swipe behavior and perceived smoothness still require user verification on the phone; mocked playback tests do not establish acoustic performance.
