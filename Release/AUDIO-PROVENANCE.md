# Audio and artwork provenance

Reference supplied by the owner: https://claude.ai/artifact/8Dcr8vLuphJva3R7XrTfdJ
Retrieved October 15, 2026. The unmodified retrieved HTML is retained in `Reference/ClaudeArtifact.html`.

The reference embeds a 680 × 680 WebP tomato. `tomato.png` is a decoded copy; the original WebP is retained. The native dial follows the reference geometry: center x 341.5, seam center y 361.8, ellipse radii 282 and 83.1. The app icon places that artwork on the app's dark background.

## Sound inventory

| Effect | Original definition | Native resource / trigger |
|---|---|---|
| Alternating tick | Bandpass 3300 / 4100 Hz, Q 6; gain .22 exponentially falls to .0001 over .018 s; shared .03 s linearly tapered noise | `tickOdd.wav`, `tickEven.wav`; once per remaining-second change while running in foreground |
| Winding ratchet | Same noise, bandpass 5200 Hz, Q 6; gain .3 falls to .0001 over .012 s | `ratchet.wav`; dial notch changes |
| Mechanical bell | 34 strikes, .056 s apart plus .006 s on odd strikes; partials 2350 / 3790 / 5230 Hz, gains .5 / .24 / .12, decay .22 / .12 / .07 s; ±.2% pitch variation; final-strike fade; master gain .32 | `bell.wav`; elapsed block, plus local notification when backgrounded |
| Spoken replies | Browser speech synthesis, preferred Ava/Samantha, rate 1.02 | Removed at user request; no spoken output |

`Tools/render_audio.py` renders the reference formulas to 48 kHz mono PCM WAV. Original Web Audio noise is random; the native renderer uses one fixed seeded noise realization. This preserves the synthesis parameters but is not a claim of identical random samples. Platform resampling, speaker output, notification volume can differ. Physical-device listening comparison is still required before declaring perceptual parity.

The haptics are an explicitly requested native addition: alternating transient intensities .22/.18 with sharpness .65/.8; ratchet intensity .35 and sharpness .9. Hardware capability and the user's haptics setting are respected. They are foreground-only and suppressed during microphone capture and audio interruption.

## Selectable sound packs (added 2026-10-15)

Winding, ticking and alarm sounds are chosen separately in Settings. Classic keeps the original files above. Every other option is original and procedurally rendered, with no samples or third-party audio: `Tools/sound_packs/recipes.py` renders seeded noise, biquad filters and modal partials (the same primitives as `Tools/render_audio.py`), and `Tools/sound_packs/finalize.py` writes `Resources/Sounds/*.wav` (48 kHz mono 16-bit PCM).

| Role | Options | Finishing applied |
|---|---|---|
| Winding | Felt, Wooden, Chrome spring, Sand pour, Mainspring, Brass, Deep wood | Sand pour and Brass trimmed to 60 ms so fast dial turns stay crisp |
| Ticking | None, Felt, Woodblock, Chrome egg, Sand patter, Twin-bell clock, Grandfather, Brass | Felt low-passed at 1.8 kHz (level preserved) so it sounds muffled |
| Alarm | Marimba, Temple blocks, Egg timer bell, Glass chime, Twin bells, Gong, Handbell, Singing bowl | Gong trimmed to 4.5 s and bowl to 5 s with 1.2 s fades; Marimba +5 dB to sit near the others |

All alarms are under 30 s and are bundled, so each is also a valid notification sound. Ticks are skipped while an alarm is ringing. Physical-device listening checks (speaker, AirPods, Silent switch, pocket audibility) are still required for each pack.

## Distribution status

These assets were supplied through the user's reference artifact. Authorship, asset licensing, and public redistribution rights have not been independently verified. Owner confirmation is required before App Store distribution. No third-party runtime JavaScript is executed by the iOS app; the retained HTML is reference-only and excluded from the app bundle.
