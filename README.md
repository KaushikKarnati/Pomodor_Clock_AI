# FocusTalk

Native SwiftUI iPhone app based on the supplied Claude artifact, including its tomato artwork and mechanically synthesized sound effects, plus tick and ratchet haptics.

## Open and run

Open `FocusTalk.xcodeproj`, select the **FocusTalk** scheme and an iPhone simulator, and Run. Deployment target: iOS 26. The development environment used Xcode 27.0.

Ram Karnati’s development team is configured for both targets. The app was installed on the authorized connected iPhone 17 Pro. Signing credentials remain in the local keychain and are not included in this project. If you use a different team, change Signing & Capabilities for both targets.

## Features

- Native dial, plan preview, timer, pause/extend/skip/end, and locally persisted session history. Manual multi-block editing and browsing/reusing history are not exposed in the current UI.
- Apple on-device Speech recognition with editable text and manual fallback. Finishing speech automatically requests a plan. The home-screen mic opens a live glass transcription bubble; no voice sheet.
- Foundation Models structured planning with availability handling, budget validation, cancellation, and automatic start after successful generation.
- Original source-derived bell, alternating ticks, ratchet, and mechanical haptics. Settings control spoken replies, haptics, and automatic progression; the spoken-reply preference survives relaunch.
- Six selectable timer objects: tomato, apple, lemon, chrome egg (twist timers with a rotating minute band), hourglass (sand drains from layered artwork) and twin-bell alarm clock (a 60-minute wedge on its face). Choosing an object also picks its matching sounds.
- Separate Winding, Ticking (including None) and Alarm sound menus with preview. The chosen alarm is also the notification sound. All sounds are procedurally rendered (`Tools/sound_packs`).
- The Live Activity shows a miniature of the selected object inside a progress ring, plus the block name and focus/break state.
- Persisted timer deadlines, local notifications, and ActivityKit Lock Screen / Dynamic Island presentation.

## Tests

```sh
swift test
xcodebuild -project FocusTalk.xcodeproj -scheme FocusTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

Core tests use an injected clock through explicit dates. UI tests use separate local test storage and exercise real native views. `--ui-testing` and `--reset-ui-state` are Debug-only test arguments; normal user storage is not reset.

`swift test` also checks that every sound and image the catalog names is bundled and registered in the Xcode project. `Tools/objects/README.md` documents how the object artwork was generated and processed.

See `Release/VALIDATION.md` for actual results and unverified physical-device checks. `Release/AUDIO-PROVENANCE.md` documents the exact source parameters and differences. `Release/APP-STORE.md` contains store copy, privacy text, and owner release inputs.

## Architecture

`Core` holds Codable plan/session models and deterministic timer transitions. `App` holds SwiftUI views, an observable store, and separate planning, speech, audio, persistence and notification services. `Widget` contains the Live Activity. No server, package dependencies, analytics, login, or external AI API is used. Reference HTML is not bundled or executed.

The current speech implementation uses Apple's `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`; it deliberately refuses cloud transcription. Missing on-device recognition falls back to typing. Foundation Models is separate from speech transcription.

## Known platform boundaries

- Foreground speech, audio ticks, and haptics stop when the app is backgrounded or interrupted. Local notification sound follows iOS settings and is not a guarantee of an audible alarm in silent mode.
- Background block progression is computed from persisted deadlines. With automatic progression enabled, the Live Activity shows total remaining session time; otherwise it shows the current block. The dial uses system-driven circular progress, not a continuous custom rotation. No background execution or server push is assumed.
- AI and speech behavior, physical audio parity, and haptic feel need a supported physical iPhone. Simulator tests cannot establish those results.
- If saved data is unreadable, the original file is preserved and writes are blocked for that launch; the app reports the issue rather than replacing the file.

Accepting a plan or setting the tomato dial starts its timer immediately. New AI plans start automatically. Replacing an active session requires accepting the proposal through the existing controls or an explicit start command. Plan preview, settings, and typed input use the existing home-screen overlays. Errors appear through the existing caption/toast surfaces.

The main dial and countdown show the current block; automatic-progression Live Activities show the remaining session. Break durations do not imply equal-sized work intervals. End session uses the existing two-tap settings control. Timeline estimates follow remaining time; paused estimates assume resuming now, and completed rows retain the original schedule rather than claiming measured historical start times.

## Reliability and rendering

Session snapshots are encoded and atomically written on one FIFO background queue, with errors returned to the store and a bounded iOS background-task allowance for queued saves. A dial change validates its updated budget before committing it. No background execution is assumed for the timer.

The foreground timer updates at displayed-second boundaries; it does not poll when idle, paused, or backgrounded. Small dial movements and the speech-silence indicator use native interpolation. Dial trigonometry is precomputed, and SwiftUI manages display cadence without a permanently running empty display-link callback. ProMotion eligibility remains enabled; this is not a measured or guaranteed 120-FPS claim.

`swift test` covers timer/model invariants and ordered disk writes. The shared Xcode scheme also runs injected store tests and native UI tests, including spoken-preference relaunch and accepting an existing plan with a typed start command. Store tests isolate notifications, AI, audio, and persistence; they do not establish real-device AI, speech, or audio performance.
