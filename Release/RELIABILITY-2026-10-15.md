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
