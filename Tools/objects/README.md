# Timer object artwork

The apple, chrome egg, lemon, hourglass and alarm clock were generated on 2026-10-15 with Higgsfield (GPT Image 2.5, 2048 px, transparent background) from text prompts describing the existing tomato's studio-product style. `source/` holds the selected originals. Confirm the image service's commercial-use terms for your plan before App Store release.

Pipeline (Python 3 + Pillow), run from the repository root:

```sh
python3 Tools/objects/prep_objects.py Tools/objects/source Resources/tomato.png /tmp/objects   # normalize + measure seams
python3 Tools/objects/band_preview.py /tmp/objects                                                 # optional: band-preview.png
python3 Tools/objects/hourglass_layers.py /tmp/objects                                             # split hourglass layers
python3 Tools/objects/export_assets.py Tools/objects/source /tmp/objects                           # write asset catalogs
```

- `prep_objects.py` normalizes each object into the tomato's 680-unit frame (same visual size, bottom-aligned) and fits the twist seam as the front half of an ellipse. The tomato's hand-tuned band (341.5, 361.8, 282, 83.1) is mapped onto each seam. The resulting `geometry.json` values are the `BandGeometry` numbers in `Core/TimerTheme.swift`. Egg and lemon use dark markings.
- `hourglass_layers.py` splits the hourglass into a base (frame, back post, see-through glass), top sand, bottom pile, falling stream and a bottom-bulb mask. The generator painted an opaque white backdrop inside the glass; neutral glass pixels are converted to translucent white highlights so the glass reads correctly on the dark app background. Where sand was removed, glass is filled by mirroring the opposite bulb across the neck. `HourglassArtwork` in `App/TomatoView.swift` drains the sand from these layers.
- The alarm clock's blank face is measured at centre (337.5, 401), radius ≈ 183; `ClockFaceDial` draws a 60-minute dial there.
