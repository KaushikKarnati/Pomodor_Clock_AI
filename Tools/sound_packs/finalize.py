"""Turns the procedural prototypes rendered by recipes.py into the app's selectable sounds.

Run from the repository root:
    python3 Tools/sound_packs/recipes.py      # renders prototypes into Tools/sound_packs/wav
    python3 Tools/sound_packs/finalize.py     # writes Resources/Sounds/*.wav

The Classic sounds stay as the original Resources/{ratchet,tickOdd,tickEven,bell}.wav.
Every output is 48 kHz mono 16-bit PCM, so alarms are also valid notification sounds (< 30 s)."""
import math, pathlib, struct, wave
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = pathlib.Path(__file__).resolve().parent / "wav"
OUT = ROOT / "Resources" / "Sounds"
RATE = 48000

# id: (prototype, trim seconds) — winding clicks must stay short so fast dial turns stay crisp.
WIND = {"felt": ("library_ratchet", None), "wooden": ("wood_ratchet", None), "chrome": ("egg_wind", None),
        "sand": ("hourglass_pour", 0.06), "mainspring": ("twinbell_wind", None), "brass": ("brass_ratchet", 0.06),
        "deep": ("deep_ratchet", None)}
# id: (odd, even, low-pass Hz or None)
TICK = {"felt": ("library_tickOdd", "library_tickEven", 1800), "woodblock": ("wood_tickOdd", "wood_tickEven", None),
        "chrome": ("egg_tick", "egg_tock", None), "sand": ("hourglass_tickOdd", "hourglass_tickEven", None),
        "twinBell": ("twinbell_tick", "twinbell_tock", None), "grandfather": ("deep_tick", "deep_tock", None),
        "brass": ("brass_tickOdd", "brass_tickEven", None)}
# id: (prototype, max seconds, gain dB). Long alarms are faded so spoken replies don't collide.
ALARM = {"marimba": ("library_alarm", None, 5.0), "templeBlocks": ("wood_alarm", None, -1.0), "eggBell": ("egg_alarm", None, 0.0),
         "glassChime": ("hourglass_alarm", None, 0.0), "twinBells": ("twinbell_alarm", None, 0.0), "gong": ("deep_alarm", 4.5, 0.0),
         "handbell": ("brass_alarm", None, 0.0), "bowl": ("chime_alarm", 5.0, 0.0)}

def read(name):
    with wave.open(str(SRC / f"{name}.wav")) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1 and w.getsampwidth() == 2
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32767

def write(name, x):
    peak = float(np.max(np.abs(x)))
    assert 0 < peak < 0.95, (name, peak)
    assert len(x) / RATE < 30, name
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", round(v * 32767)) for v in x))
    print(f"{name:26s} {len(x) / RATE:5.2f}s peak {peak:.3f}")

def trim(x, seconds, fade=0.012):
    if seconds is None or len(x) <= seconds * RATE: return x
    n = int(seconds * RATE); f = int(fade * RATE); y = x[:n].copy()
    y[-f:] *= 0.5 + 0.5 * np.cos(np.linspace(0, math.pi, f))
    return y

def lowpass(x, f, q=0.707):
    w = 2 * math.pi * f / RATE; al = math.sin(w) / (2 * q); c = math.cos(w); a0 = 1 + al
    b0, b1, b2 = (1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0; a1, a2 = -2 * c / a0, (1 - al) / a0
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o; y[i] = o
    return y

def rms(x): return float(np.sqrt(np.mean(x ** 2)))

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for key, (src, seconds) in WIND.items():
        write(f"wind-{key}", trim(read(src), seconds, fade=0.008))
    for key, (odd, even, cutoff) in TICK.items():
        for side, src in (("odd", odd), ("even", even)):
            x = read(src)
            if cutoff:
                y = lowpass(x, cutoff); x = y * (rms(x) / max(rms(y), 1e-9))  # keep the designed level
            write(f"tick-{key}-{side}", x)
    for key, (src, seconds, gain) in ALARM.items():
        x = trim(read(src), seconds, fade=1.2) * 10 ** (gain / 20)
        write(f"alarm-{key}", x)
