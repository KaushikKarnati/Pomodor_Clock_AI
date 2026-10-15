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

## Distribution status

These assets were supplied through the user's reference artifact. Authorship, asset licensing, and public redistribution rights have not been independently verified. Owner confirmation is required before App Store distribution. No third-party runtime JavaScript is executed by the iOS app; the retained HTML is reference-only and excluded from the app bundle.
