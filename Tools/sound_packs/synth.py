"""Prototype renderer for alternative FocusTalk sound packs.
Primitives mirror Tools/render_audio.py: seeded linearly tapered noise, RBJ biquads
(bandpass = constant 0 dB peak, alpha = sin(w)/(2Q)), exponential gain ramps to 1e-4,
and modal partials with exponential attack then exponential decay (the bell's shape)."""
import math, wave, struct, random, json, pathlib, sys
import numpy as np

RATE = 48000
OUT = pathlib.Path(__file__).resolve().parent / "wav"  # prototypes; finalize.py picks from here
OUT.mkdir(exist_ok=True)

def noise(T, seed=1046, taper=True):
    rng = random.Random(seed)
    n = int(RATE * T)
    return np.array([rng.uniform(-1, 1) * ((1 - i / n) if taper else 1) for i in range(n)])

def biquad(x, kind, f, Q):
    w = 2 * math.pi * f / RATE; al = math.sin(w) / (2 * Q); c = math.cos(w)
    if kind == "bp":   b = (al, 0, -al)
    elif kind == "lp": b = ((1 - c) / 2, 1 - c, (1 - c) / 2)
    elif kind == "hp": b = ((1 + c) / 2, -(1 + c), (1 + c) / 2)
    a0 = 1 + al; a1 = -2 * c; a2 = 1 - al
    b0, b1, b2 = (v / a0 for v in b); a1 /= a0; a2 /= a0
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o; y[i] = o
    return y

def expenv(n, g, d, a=0.0):
    t = np.arange(n) / RATE
    if a > 0:
        att = 1e-4 * (g / 1e-4) ** np.clip(t / a, 0, 1)
        dec = g * (1e-4 / g) ** np.clip((t - a) / max(1e-6, d - a), 0, 1)
        return np.where(t < a, att, dec)
    return g * (1e-4 / g) ** np.clip(t / d, 0, 1)

def click(f, Q, g, d, T=0.03, seed=1046, kind="bp", noiseT=None):
    """render_audio.py tick: tapered noise -> biquad -> exp ramp g->1e-4 over d."""
    nz = noise(noiseT or T, seed)
    n = int(RATE * (d + 0.01)); x = np.zeros(n); m = min(n, len(nz)); x[:m] = nz[:m]
    return biquad(x, kind, f, Q) * expenv(n, g, d)

def mode(f, g, d, a=0.003, phase=0.0):
    """bell partial: exp attack 1e-4 -> g over a, exp decay to 1e-4 over d (total d+.02 s)."""
    n = int(RATE * (d + 0.02)); t = np.arange(n) / RATE
    return expenv(n, g, d, a) * np.sin(2 * math.pi * f * t + phase)

def sq(f, g, dur, harmonics=(1, 3, 5), edge=0.0005):
    """band-limited square-ish beep: odd harmonics at 1/k gain, raised-cosine edges."""
    n = int(RATE * dur); t = np.arange(n) / RATE
    y = sum(np.sin(2 * math.pi * f * k * t) / k for k in harmonics if f * k < 20000)
    e = int(RATE * edge); w = np.ones(n)
    if e: r = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, e)); w[:e] = r; w[-e:] = r[::-1]
    return g * y * w

class Buf:
    def __init__(self, T): self.x = np.zeros(int(RATE * T))
    def add(self, sig, t0, gain=1.0):
        j = int(round(t0 * RATE)); m = min(len(sig), len(self.x) - j)
        if m > 0: self.x[j:j + m] += gain * sig[:m]
        return self

def a_weight_db(x):
    X = np.abs(np.fft.rfft(x, n=1 << int(math.ceil(math.log2(max(len(x), 2048))))))
    f = np.fft.rfftfreq(1 << int(math.ceil(math.log2(max(len(x), 2048)))), 1 / RATE)
    f2 = f ** 2
    ra = (12194 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2) + 1e-30)
    w = ra * 10 ** (2.0 / 20)
    return 10 * math.log10(np.sum((X * w) ** 2) + 1e-30)

def centroid(x):
    N = 1 << int(math.ceil(math.log2(max(len(x), 2048))))
    X = np.abs(np.fft.rfft(x, n=N)); f = np.fft.rfftfreq(N, 1 / RATE)
    return float(np.sum(f * X ** 2) / (np.sum(X ** 2) + 1e-30))

def weighted(x):
    """A-weighting * 2nd-order 400 Hz high-pass (rough phone-speaker roll-off), applied in frequency domain."""
    N = 1 << int(math.ceil(math.log2(len(x) + 4096)))
    X = np.fft.rfft(x, n=N); f = np.fft.rfftfreq(N, 1 / RATE); f2 = f ** 2
    ra = (12194 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2) + 1e-30) * 10 ** (2.0 / 20)
    hp = f2 / np.sqrt((400 ** 2 - f2) ** 2 + (400 * f / 0.707) ** 2 + 1e-30)
    return np.fft.irfft(X * ra * hp, n=N)[:len(x) + 4096]

def loud(x):
    y = weighted(x)
    total = 10 * math.log10(np.sum(y ** 2) + 1e-30)
    w = int(RATE * .4); c = np.concatenate([[0], np.cumsum(y ** 2)])
    mom = 10 * math.log10(max(1e-30, max((c[i + w] - c[i]) / w for i in range(0, max(1, len(y) - w), 480)) if len(y) > w else c[-1] / w))
    return round(total, 1), round(mom + 100, 1)

REPORT = []
MASTER = {}
def save(name, x):
    x = np.asarray(x, dtype=float) * MASTER.get(name, 1.0)
    pk = float(np.max(np.abs(x))) if len(x) else 0.0
    assert pk < 1, (name, pk)
    with wave.open(str(OUT / (name + ".wav")), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", round(v * 32767)) for v in x))
    REPORT.append(dict(name=name, seconds=round(len(x) / RATE, 3), peak=round(pk, 4),
                       rms=round(float(np.sqrt(np.mean(x ** 2))) if len(x) else 0, 5),
                       energyA_dB=round(a_weight_db(x), 1) if len(x) else None,
                       centroid_Hz=round(centroid(x)) if len(x) else None,
                       spkEnergy_dB=loud(x)[0] if pk else None, spkMomentary_dB=loud(x)[1] if pk else None))
