import sys, json, math, random
import numpy as np
sys.path.insert(0, __import__("os").path.dirname(__file__))
from synth import *

def strikes(T, events, master):
    b = Buf(T)
    for sig, t0, g in events: b.add(sig, t0, g)
    return b.x * master

def partials(spec, a=0.003, jitter=1.0):
    return sum_pad([mode(f * jitter, g, d, a) for f, g, d in spec])

def sum_pad(sigs):
    n = max(len(s) for s in sigs); y = np.zeros(n)
    for s in sigs: y[:len(s)] += s
    return y

def silence(T=0.01): return np.zeros(int(RATE * T))

MASTER.update({
 "twinbell_tick": .8, "twinbell_tock": .8, "twinbell_alarm": 1.27,
 "metronome_tickOdd": .16, "metronome_tickEven": .16, "metronome_weightDetent": 1.8, "metronome_wind": 1.8,
 "stopwatch_alarm": 1.4, "chess_plunger": .7, "chess_alarm": 1.57,
 "pendulum_tick": .55, "pendulum_tock": .55, "pendulum_chain": 1.8,
 "incense_detent": 2.0, "incense_threadDrop": 1/3,
 "musicbox_minutePluck": .18, "egg_tick": .56, "egg_tock": .56,
 "library_tickOdd": 2.1, "library_tickEven": 2.1, "library_alarm": 1.4,
 "wood_tickOdd": .18, "wood_tickEven": .18, "wood_ratchet": .73, "wood_alarm": 2.86,
 "deep_tick": .68, "deep_tock": .68, "brass_tickOdd": .72, "brass_tickEven": .72,
 "digital_tickOdd": .45, "digital_set": .09, "digital_set5": .09, "digital_alarm": .4,
 "chime_set5": .38, "chime_set1": 2.3, "hourglass_ambientLoop": .5,
})
# ---------- baseline tomato (from render_audio.py) ----------
save("tomato_tickOdd", click(3300, 6, .22, .018))
save("tomato_tickEven", click(4100, 6, .22, .018))
save("tomato_ratchet", click(5200, 6, .3, .012))
ev = []
for k in range(34):
    t0 = k * .056 + (.006 if k % 2 else 0); env = (34 - k) / 9 if k > 25 else 1
    j = 1 + ((k % 3) - 1) * .002
    ev.append((partials([(2350, .5 * env + 1e-4, .22), (3790, .24 * env + 1e-4, .12), (5230, .12 * env + 1e-4, .07)], jitter=j), t0, 1))
save("tomato_bell", strikes(2.15, ev, .32))

# ---------- A1 hourglass ----------
def grain(g, seed, f=6500, Q=1.5): return click(f, Q, g, .004, T=.003, seed=seed)
save("hourglass_tickOdd", strikes(.08, [(grain(.05, 11), 0, 1), (grain(.035, 12), .013, 1), (grain(.025, 13), .031, 1), (grain(.018, 14), .052, 1)], 1))
save("hourglass_tickEven", strikes(.08, [(grain(.045, 21), 0, 1), (grain(.03, 22), .019, 1), (grain(.02, 23), .041, 1)], 1))
rng = random.Random(5)
save("hourglass_pour", strikes(.13, [(grain(.08 * (1 - k / 12), 40 + k, 4800 if k % 2 else 5600, 1.2), k * .009 + rng.uniform(-.003, .003) + .003, 1) for k in range(10)], 1))
save("hourglass_flip", sum_pad([mode(190, .25, .09, .002), click(900, .7, .2, .03, kind="lp"), mode(2210, .05, .25, .002), mode(5480, .02, .12, .002)]))
glass = lambda: sum_pad([partials([(1320, .30, 1.6), (1322.5, .15, 1.6), (3062, .12, .7), (5610, .05, .3), (8752, .015, .12)], a=.001), click(7000, 2, .06, .004)])
save("hourglass_alarm", strikes(2.8, [(glass(), 0, 1), (glass(), .42, .8), (glass(), .84, .65)], .35))
hiss = biquad(biquad(noise(4, 77, taper=False), "bp", 3800, .9), "lp", 7000, .707)
t = np.arange(len(hiss)) / RATE
save("hourglass_ambientLoop", .012 * hiss * (1 + .2 * np.sin(2 * math.pi * .25 * t)))

# ---------- A2 twin-bell alarm clock ----------
save("twinbell_tick", sum_pad([click(2400, 5, .14, .012), mode(1180, .02, .03, .001)]))
save("twinbell_tock", sum_pad([click(2250, 5, .12, .012), mode(1150, .018, .03, .001)]))
save("twinbell_wind", sum_pad([click(3600, 4, .22, .010), mode(820, .015, .05, .001)]))
rng = random.Random(9); ev = []
A = [(1870, .45, .35), (4490, .2, .15), (7940, .08, .08)]; B = [(2210, .45, .35), (5300, .2, .15), (9390, .08, .08)]
for k in range(48):
    g = min(1, .4 + .15 * k) * rng.uniform(.85, 1.15) * (1 if k < 40 else 1 - (k - 39) * .1)
    j = 1 + ((k % 3) - 1) * .002
    ev.append((partials(A if k % 2 == 0 else B, a=.001, jitter=j), k * .05, g)); ev.append((click(6000, 2, .05, .003, seed=100 + k), k * .05, g))
save("twinbell_alarm", strikes(2.8, ev, .22))

# ---------- A3 pyramid metronome ----------
def tok(f0, g=1.0): return sum_pad([mode(f0, .10 * g, .05, .0008), mode(f0 * 2.572, .04 * g, .025, .0008), mode(f0 * 4.644, .015 * g, .012, .0008), click(3000, 1.2, .05 * g, .004)])
save("metronome_tickOdd", tok(1060)); save("metronome_tickEven", tok(1028, .92))
save("metronome_weightDetent", click(6200, 3, .12, .006)); save("metronome_wind", click(2800, 3, .2, .012))
mbell = lambda: partials([(2640, .35, .9), (5730, .12, .35), (8650, .05, .15)], a=.001)
ev = [(tok(1060, 1.6), i * .5, 1) for i in range(8)] + [(mbell(), 0, 1), (mbell(), 2.0, 1), (mbell(), 4.0, 1.1)]
save("metronome_alarm", strikes(5.0, ev, .4))

# ---------- A4 stopwatch ----------
save("stopwatch_tickOdd", sum_pad([click(5600, 3, .07, .006), mode(3900, .008, .015, .0005)]))
save("stopwatch_tickEven", sum_pad([click(5400, 3, .065, .006), mode(3850, .008, .015, .0005)]))
save("stopwatch_bezel", strikes(.03, [(click(4200, 5, .18, .008), 0, 1), (click(7000, 3, .08, .004, seed=7), .002, 1)], 1))
save("stopwatch_crown", sum_pad([click(2500, .7, .25, .02, kind="lp"), mode(1450, .04, .03, .0008)]))
L = lambda: partials([(1320, .32, 1.2), (3604, .10, .45), (7088, .03, .18)], a=.001)
H = lambda: partials([(1980, .28, 1.0), (5405, .08, .35), (10633, .02, .12)], a=.001)
ev = [(L(), 0, 1), (L(), .42, 1), (H(), 1.05, 1), (L(), 1.21, 1), (H(), 1.66, 1), (L(), 1.82, 1), (H(), 2.45, 1), (H(), 2.75, 1), (H(), 3.05, 1)]
save("stopwatch_alarm", strikes(4.3, ev, .3))

# ---------- A5 chess clock ----------
save("chess_tickOdd", sum_pad([click(2900, 4, .10, .010), mode(640, .03, .025, .001)]))
save("chess_tickEven", sum_pad([click(2800, 4, .10, .010), mode(620, .03, .025, .001)]))
save("chess_knob", click(4400, 6, .2, .010))
plunger = lambda: strikes(.1, [(click(1800, .8, .35, .025, kind="lp"), 0, 1), (mode(420, .12, .06, .001), 0, 1), (click(3500, 3, .12, .006, seed=9), .018, 1)], 1)
save("chess_plunger", plunger())
ding = partials([(1046.5, .30, 1.4), (2884, .07, .4), (5655, .02, .15)], a=.001)
dong = partials([(784, .30, 1.6), (2161, .07, .45), (4237, .02, .15)], a=.001)
save("chess_alarm", strikes(2.8, [(mode(3100, .10, .12, .0005), 0, 1), (plunger(), .25, 1), (ding, .55, 1), (dong, 1.05, 1)], .35))

# ---------- A6 pendulum wall clock ----------
save("pendulum_tick", sum_pad([click(1500, 3, .07, .008), mode(310, .06, .08, .002), mode(740, .025, .04, .002)]))
save("pendulum_tock", sum_pad([click(1380, 3, .063, .008), mode(300, .054, .08, .002), mode(720, .022, .04, .002)]))
save("pendulum_chain", strikes(.05, [(click(2600, 5, .14, .012), 0, 1), (click(5200, 2, .1, .005, seed=51), 0, 1), (click(5200, 2, .07, .005, seed=52), .009, 1), (click(5200, 2, .05, .005, seed=53), .018, 1)], 1))
wn = biquad(noise(.35, 61, taper=False), "lp", 600, .707); tt = np.arange(len(wn)) / RATE
whir = .05 * wn * (.5 + .5 * np.sin(2 * math.pi * 28 * tt)) * np.minimum(1, (len(wn) - np.arange(len(wn))) / (RATE * .05))
rod = lambda: sum_pad([partials([(196, .10, 3.5), (1229, .30, 2.2), (1230.6, .12, 2.2), (3440, .12, .9), (6740, .04, .35)], a=.0015), click(4000, 2, .06, .004)])
save("pendulum_alarm3", strikes(6.6, [(whir, 0, 1 / .35), (click(2000, 3, .1, .01), .38, 1 / .35), (rod(), .6, 1), (rod(), 2.0, 1), (rod(), 3.4, 1)], .35))

# ---------- A7 incense fire clock ----------
save("incense_tickOdd", strikes(.03, [(click(3800, 1, .025, .003, T=.002, seed=31), 0, 1), (click(3800, 1, .025, .003, T=.002, seed=32), .014, 1)], 1))
save("incense_tickEven", silence())
save("incense_detent", click(1800, 2, .1, .008))
m1 = biquad(noise(.12, 71), "bp", 2500, .8); m1 = np.pad(m1, (0, int(RATE * .2))) * expenv(len(m1) + int(RATE * .2), .2, .25, .01)
m2 = biquad(noise(.4, 72), "lp", 1200, .707) * expenv(int(RATE * .4), .12, .4, .05)
save("incense_light", sum_pad([m1, m2]))
plate = lambda: sum_pad([partials([(1020, .3, 1.8), (2290, .18, 1.1), (3780, .1, .6), (5600, .05, .3)], a=.0008), click(6000, 1.5, .15, .003)])
P = plate(); ev = []
for t0, d0, r, n in [(0, .32, .72, 9), (.11, .27, .70, 8)]:
    t = t0
    for k in range(n): ev.append((P, t, r ** k)); t += d0 * r ** k
last = max(e[1] for e in ev)
ev += [(P, last + .03 * (i + 1), .05) for i in range(6)]
save("incense_alarm", strikes(last + 2.2, ev, .3))
save("incense_threadDrop", plate() * .3)

# ---------- A8 music box ----------
def tine(f, g=1.0):
    parts = [(f, .3 * g, 1.6), (6.27 * f, .06 * g, .25), (17.55 * f, .015 * g, .06)]
    return sum_pad([partials([p for p in parts if p[0] < 16000], a=.002), click(5000, 2, .04 * g, .004)])
save("musicbox_fly", click(7000, 2, .02, .004))
save("musicbox_key", sum_pad([click(4600, 8, .2, .009), mode(6800, .015, .02, .0005)]))
save("musicbox_minutePluck", tine(1568, .35))
rng = random.Random(3); notes = [1318.5, 1568, 1760, 2093, 1760, 1568, 1318.5, 1174.7, 1046.5]
ev = [(tine(f * 2 ** (rng.uniform(-3, 3) / 1200)), i * .22, 1.1 if i == 8 else 1) for i, f in enumerate(notes)] + [(tine(1568, .6), 8 * .22, 1)]
save("musicbox_alarm", strikes(8 * .22 + 2.0, ev, .3))

# ---------- A9 chrome egg ----------
save("egg_tick", sum_pad([click(3000, 4, .12, .012), mode(1900, .02, .06, .001), mode(4400, .008, .03, .001)]))
save("egg_tock", sum_pad([click(2850, 4, .12, .012), mode(1880, .02, .06, .001), mode(4350, .008, .03, .001)]))
save("egg_wind", sum_pad([click(4800, 5, .26, .011), mode(1900, .01, .04, .001)]))
ev = []
for k in range(40):
    g = 1 if k < 32 else (40 - k) / 9; j = 1 + ((k % 3) - 1) * .002
    ev.append((partials([(2900, .45 * g + 1e-4, .3), (6800, .18 * g + 1e-4, .12), (10500, .06 * g + 1e-4, .06)], a=.001, jitter=j), k * .05, 1))
save("egg_alarm", strikes(2.4, ev, .25))

# ---------- B1 library ----------
save("library_tickOdd", click(1100, 1.4, .05, .012)); save("library_tickEven", click(1060, 1.4, .045, .012))
save("library_ratchet", click(2400, 2, .1, .008))
mar = lambda f: partials([(f, .22, .9), (4 * f, .03, .15), (10 * f, .006, .05)], a=.006)
save("library_alarm", strikes(2.0, [(mar(659.3), 0, 1), (mar(784), .38, 1), (mar(1046.5), .76, 1)], .3))

# ---------- B2 woodblock ----------
wb = lambda f, g=1: sum_pad([mode(f, .09 * g, .045, .0008), mode(2.572 * f, .035 * g, .02, .0008), mode(4.644 * f, .012 * g, .01, .0008), click(2500, 1.5, .04 * g, .003)])
save("wood_tickOdd", wb(1180)); save("wood_tickEven", wb(1120))
save("wood_ratchet", sum_pad([click(1900, 3, .2, .01), mode(760, .05, .03, .001)]))
tb = lambda f: sum_pad([mode(f, .25, .12, .0008), mode(2.572 * f, .09, .05, .0008), mode(4.644 * f, .03, .025, .0008), click(3000, 1.5, .08, .003)])
ev = [(tb([880, 690, 520][i % 3]), i * .12, 1) for i in range(12)] + [(tb(520), 1.56, 1.3)]
save("wood_alarm", strikes(2.0, ev, .35))

# ---------- B3 deep grandfather ----------
save("deep_tick", sum_pad([click(1250, 2.5, .07, .01), mode(280, .07, .1, .002), mode(560, .02, .05, .002)]))
save("deep_tock", sum_pad([click(1180, 2.5, .065, .01), mode(270, .065, .1, .002), mode(540, .018, .05, .002)]))
save("deep_ratchet", sum_pad([click(2200, 4, .24, .015), mode(380, .05, .04, .001)]))
gong = lambda: sum_pad([partials([(147, .12, 4), (440, .2, 3), (905, .22, 2.2), (906.8, .1, 2.2), (1520, .1, 1.2), (2480, .04, .5)], a=.002), click(2500, 2, .05, .005)])
save("deep_alarm", strikes(7.6, [(gong(), 0, 1), (gong(), 1.6, .85), (gong(), 3.2, .75)], .35))

# ---------- B4 brass carriage clock ----------
save("brass_tickOdd", sum_pad([click(3800, 5, .08, .01), mode(2650, .012, .09, .0008), mode(6100, .005, .04, .0005)]))
save("brass_tickEven", sum_pad([click(3650, 5, .075, .01), mode(2600, .011, .09, .0008), mode(6000, .005, .04, .0005)]))
save("brass_ratchet", sum_pad([click(5000, 6, .22, .01), mode(2650, .01, .06, .001)]))
hb = lambda: sum_pad([partials([(1568, .3, 2.2), (1570, .1, 2.2), (3763, .04, .6), (4704, .1, .9), (7840, .02, .25)], a=.0015), click(6000, 2, .05, .003)])
save("brass_alarm", strikes(4.0, [(hb(), 0, 1), (hb(), .5, .9), (hb(), 1.0, .85), (hb(), 1.5, .8)], .28))

# ---------- B5 retro digital ----------
save("digital_tickOdd", sq(2048, .03, .002, edge=.0003)); save("digital_tickEven", silence())
save("digital_set", sq(2730, .12, .018, edge=.001))
save("digital_set5", strikes(.07, [(sq(3100, .12, .018, edge=.001), 0, 1), (sq(3100, .12, .018, edge=.001), .04, 1)], 1))
beep = sq(2730, .5, .06, edge=.001)
save("digital_alarm", strikes(4.5, [(beep, g * 1.0 + i * .12, 1) for g in range(5) for i in range(4)], .5))

# ---------- B6 silent chime ----------
save("chime_tick", silence())
save("chime_set5", sum_pad([mode(2637, .04, .25, .002), mode(6150, .008, .08, .002)]))
save("chime_set1", click(1500, 1, .03, .006))
bowl = lambda: sum_pad([partials([(523, .25, 6), (524.2, .12, 6), (1417, .15, 3.5), (1418.6, .07, 3.5), (2652, .07, 1.8), (2654, .035, 1.8)], a=.004), click(1500, .7, .05, .01, kind="lp")])
save("chime_alarm", strikes(8.6, [(bowl(), 0, 1), (bowl(), 2.5, .6)], .35))

json.dump(REPORT, open(OUT.parent / "report.json", "w"), indent=1)
for r in REPORT: print(r)
