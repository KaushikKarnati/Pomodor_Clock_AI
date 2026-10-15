# FocusTalk release preparation

## Store copy

Name: FocusTalk (availability not yet checked)
Subtitle: Talk. Plan. Focus.
Category: Productivity
Price: Free

Description:
Tell FocusTalk what's on your plate, turn it into a manageable plan, and focus on one thing at a time.

Wind the mechanical tomato timer with a swipe. Hear its clockwork tick, feel gentle matching haptics, and take a break when the bell rings. Speak or type your tasks, review an on-device AI plan, and adjust each block before you begin.

• A tactile tomato timer with mechanical sounds and haptics
• On-device voice transcription and Apple Intelligence planning on supported devices
• Manual plans when AI is unavailable
• Pausing, extra time, breaks, and optional automatic progression
• Lock Screen countdown and local completion notifications
• Private session history stored on your iPhone

No account, ads, subscriptions, or external AI service. Apple Intelligence availability depends on your device and system settings. Sound, haptics, and notifications respect system settings. Initial release supports English and iOS 26 or later.

Keywords: focus,timer,pomodoro,voice,planning,tasks,productivity,study,work,breaks

## Review notes

Launch and choose “Try an example” to see a prepared plan without microphone or Apple Intelligence access. The timer starts automatically when a plan is saved or accepted. Manual dial adjustments wait for Start. Pause and resume remain available. Plan allows manual editing. The microphone displays on-device transcription in a glass bubble on the home screen. A successful new plan starts automatically. Typing, manual editing, settings, and history all remain on that screen. AI is optional; unavailable devices retain full manual timer and plan features. No login is required.

Audio and haptics run in the foreground. Local notifications alert at scheduled boundaries when permitted; a Live Activity shows the current block and becomes stale at its boundary until the app can update it. The app does not claim unrestricted background execution.

## Privacy disclosure draft

The app does not collect or transmit user data to the developer. Tasks, session history, and settings are stored locally. Microphone audio is transcribed on device and not written to audio files. Apple system model asset downloads may require connectivity. There is no advertising, analytics SDK, or external AI endpoint. Device backups are controlled by system settings.

A privacy manifest is bundled. Confirm the final App Store Connect privacy questionnaire against the actual signed build and any future changes.

## Owner-only release inputs

1. Ram Karnati’s team is configured (P3RW4ZXXPR). Bundle identifiers are `com.ramkarnati.focustalk` and `com.ramkarnati.focustalk.widget`. Confirm these for public release.
2. Confirm rights to distribute the supplied tomato artwork and sound definitions, and reserve the app name.
3. Supply a public support URL, privacy-policy URL, developer contact, and review contact. No invented contact details are included.
4. Complete physical-iPhone acceptance and TestFlight testing before authorizing App Store submission.

A development-signed archive is prepared locally. No App Store Connect upload, TestFlight distribution, or public submission has been performed.
