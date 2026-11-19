"""Replay everyday light changes through malachite's whole auto-brightness chain.

Light sensor -> ambient lux (tools/sim_ambient_lux.py, a port of
AutomaticBrightnessController) -> curve (BrightnessMappingStrategy, Android's
monotone cubic Spline) -> screen hysteresis (+10 % / -20 % of brightness) ->
high-brightness cap below the HBM lux -> RampAnimator in HLG space with the
display config's slow rates and time caps -> panel nits.

Every value is read from the device tree, so the run checks what the build ships:

    python tools/sim_auto_brightness.py [path/to/device_xiaomi_malachite] [--scale 0.5]

--scale is the animator duration scale (Developer options); the tester's phone uses
0.5, which halves every ramp. Prints, per scenario, each brightness change, how long
its ramp takes, and how often the brightness reversed direction within 10 s (the
"jerky" case). Frameworks/base lineage-23.2 (Android 16) is the reference.
"""
import math
import os
import random
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim_ambient_lux import ABC  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_TREE = os.path.join(HERE, '..', 'src', 'device_xiaomi_malachite')


def f32(v):
    return struct.unpack('f', struct.pack('f', float(v)))[0]


class MonotoneCubicSpline:
    """android.util.Spline.MonotoneCubicSpline, float maths included."""

    def __init__(self, x, y):
        x = [f32(v) for v in x]
        y = [f32(v) for v in y]
        n = len(x)
        d = [f32((y[i + 1] - y[i]) / (x[i + 1] - x[i])) for i in range(n - 1)]
        m = [f32(0)] * n
        m[0] = d[0]
        for i in range(1, n - 1):
            m[i] = f32((d[i - 1] + d[i]) * 0.5)
        m[n - 1] = d[n - 2]
        for i in range(n - 1):
            if d[i] == 0:
                m[i] = m[i + 1] = f32(0)
            else:
                a, b = m[i] / d[i], m[i + 1] / d[i]
                h = math.hypot(a, b)
                if h > 3:
                    t = 3 / h
                    m[i], m[i + 1] = f32(m[i] * t), f32(m[i + 1] * t)
        self.x, self.y, self.m = x, y, m

    def __call__(self, v):
        x, y, m = self.x, self.y, self.m
        if v <= x[0]:
            return y[0]
        if v >= x[-1]:
            return y[-1]
        i = 0
        while v >= x[i + 1]:
            i += 1
            if v == x[i]:
                return y[i]
        h = x[i + 1] - x[i]
        t = (v - x[i]) / h
        return ((y[i] * (1 + 2 * t) + h * m[i] * t) * (1 - t) * (1 - t)
                + (y[i + 1] * (3 - 2 * t) + h * m[i + 1] * (t - 1)) * t * t)


def hlg(v):
    """BrightnessUtils.convertLinearToGamma for the 0..1 range."""
    v12 = 12 * v
    if v12 <= 1:
        return 0.5 * math.sqrt(v12)
    return 0.17883277 * math.log(v12 - 0.28466892) + 0.55991073


def hlg_inv(g):
    if g <= 0.5:
        return (g / 0.5) ** 2 / 12
    return (math.exp((g - 0.55991073) / 0.17883277) + 0.28466892) / 12


def load(tree):
    ov = open(os.path.join(tree, 'overlay', 'FrameworkResOverlayMalachite', 'res', 'values',
                           'config.xml'), encoding='utf-8').read()
    dc = open(os.path.join(tree, 'configs', 'display_id_4627039422300187648.xml'),
              encoding='utf-8').read()

    def arr(name):
        blk = re.search(r'name="%s">(.*?)</(?:integer-)?array>' % name, ov, re.S).group(1)
        return [float(v) for v in re.findall(r'<item>([\d.]+)</item>', blk)]

    def integer(name):
        return int(re.search(r'name="%s">(\d+)<' % name, ov).group(1))

    def tag(name):
        return float(re.search(r'<%s>([\d.]+)</%s>' % (name, name), dc).group(1))

    def thresholds(kind):
        blk = re.search(r'<%s>(.*?)</%s>' % (kind, kind), dc, re.S).group(1)
        pts = re.findall(r'<threshold>([\d.]+)</threshold><percentage>([\d.]+)</percentage>', blk)
        return ([float(a) for a, _ in pts], [float(b) / 100 for _, b in pts],
                float(re.search(r'<minimum>([\d.]+)</minimum>', blk).group(1)))

    pts = re.findall(r'<value>([\d.]+)</value>\s*<nits>([\d.]+)</nits>', dc)
    backlight = [float(v) for v, _ in pts]
    map_nits = [float(n) for _, n in pts]
    smin = float(re.search(r'name="config_screenBrightnessSettingMinimumFloat"[^>]*>([\d.]+)<', ov).group(1))
    smax = float(re.search(r'name="config_screenBrightnessSettingMaximumFloat"[^>]*>([\d.]+)<', ov).group(1))
    assert abs(backlight[0] - smin) < 1e-6 and abs(backlight[-1] - smax) < 1e-6, \
        'map ends differ from the settings range; DisplayDeviceConfig would clamp the map'
    lux = [0.0] + arr('config_autoBrightnessLevels')
    nits = arr('config_autoBrightnessDisplayValuesNits')
    assert len(nits) == len(lux), 'config_autoBrightnessDisplayValuesNits needs one more entry than the levels'
    brightness = [(b - backlight[0]) / (backlight[-1] - backlight[0]) for b in backlight]
    return dict(
        lux=lux, nits=nits, map_nits=map_nits, brightness=brightness,
        up=integer('config_autoBrightnessBrighteningLightDebounce'),
        down=integer('config_autoBrightnessDarkeningLightDebounce'),
        horizon_long=int(tag('ambientLightHorizonLong')),
        horizon_short=int(tag('ambientLightHorizonShort')),
        slow_up=tag('screenBrightnessRampSlowIncrease'),
        slow_down=tag('screenBrightnessRampSlowDecrease'),
        cap_up=tag('screenBrightnessRampIncreaseMaxMillis') / 1000,
        cap_down=tag('screenBrightnessRampDecreaseMaxMillis') / 1000,
        hbm_point=tag('transitionPoint'), hbm_lux=tag('minimumLux'),
        bright=thresholds('brighteningThresholds'), dark=thresholds('darkeningThresholds'))


class Device(ABC):
    """AutomaticBrightnessController with the tree's thresholds, plus the screen side."""

    def __init__(self, c, scale):
        super().__init__(c['up'], c['down'], c['horizon_long'], c['horizon_short'])
        self.c, self.scale = c, scale
        n2b = MonotoneCubicSpline(c['map_nits'], c['brightness'])
        b2n = MonotoneCubicSpline(c['brightness'], c['map_nits'])
        curve = MonotoneCubicSpline(c['lux'], [b2n(n2b(v)) for v in c['nits']])
        self.n2b, self.b2n = n2b, b2n
        self.target_of = lambda lx: n2b(curve(lx))
        self.screen = None        # mScreenAutoBrightness
        self.changes = []         # (t ms, lux, target nits, ramp seconds)
        self.cur = None           # RampAnimator current value (HLG)
        self.goal = None          # target (HLG)
        self.rate = 0.0
        self.animating = False

    def thr(self, v):
        def ref(v, levels, pcts):
            if v < levels[0]:
                return 0.0
            i = 0
            while i < len(levels) - 1 and v >= levels[i + 1]:
                i += 1
            return pcts[i]
        bl, bp, bmin = self.c['bright']
        dl, dp, dmin = self.c['dark']
        b = max(v * (1 + ref(v, bl, bp)), v + bmin)
        d = max(min(v * (1 - ref(v, dl, dp)), v - dmin), 0)
        return b, d

    def set_lux(self, v, t):
        super().set_lux(v, t)
        new = self.target_of(self.lux)
        if self.lux < self.c['hbm_lux']:
            new = min(new, self.c['hbm_point'])
        if self.screen is not None and self.screen * 0.8 < new < self.screen * 1.1:
            return                                    # inside the screen hysteresis
        self.screen = new
        self.animate(new, t)

    def animate(self, target_linear, t):
        target = hlg(target_linear)
        if self.cur is None:
            self.cur = self.goal = target
            return
        up = target > self.cur
        rate = self.c['slow_up'] if up else self.c['slow_down']
        cap = self.c['cap_up'] if up else self.c['cap_down']
        if abs(target - self.cur) / rate > cap:
            rate = abs(target - self.cur) / cap
        if (not self.animating or rate > self.rate
                or (target <= self.cur <= self.goal) or (self.goal <= self.cur <= target)):
            self.rate = rate
        self.goal = target
        self.animating = target != self.cur
        secs = abs(target - self.cur) / self.rate * self.scale
        self.changes.append((t, self.lux, self.b2n(target_linear), secs, up))

    def frame(self, dt):
        if not self.animating:
            return
        step = dt * self.rate / self.scale
        self.cur = min(self.cur + step, self.goal) if self.goal > self.cur else max(self.cur - step, self.goal)
        self.animating = self.cur != self.goal

    def nits(self):
        return self.b2n(hlg_inv(self.cur))


def run(c, profile, scale, seconds, noise=0.02, seed=1):
    """profile(t_seconds) -> lux. Sensor every 55 ms (the phone's rate), frames at 60 Hz."""
    rnd = random.Random(seed)
    dev = Device(c, scale)
    t = 0
    frame_ms = 1000 / 60
    next_frame = 0.0
    trace = []
    while t <= seconds * 1000:
        while dev.pending is not None and dev.pending < t:
            dev.msg(dev.pending)
        lux = max(profile(t / 1000) * (1 + rnd.gauss(0, noise)), 0)
        dev.sensor(t, lux)
        while next_frame <= t:
            dev.frame(frame_ms / 1000)
            next_frame += frame_ms
            trace.append(dev.nits())
        t += 55
    return dev, trace


def scenarios():
    def step(*pairs):
        def f(s):
            v = pairs[0][1]
            for at, lx in pairs:
                if s >= at:
                    v = lx
            return v
        return f

    def trees(s):        # walking under trees: sun and shade every 0.5-3 s
        r = random.Random(int(s // 1.7))
        return 15000 if r.random() < 0.5 else 2500

    def street_lamps(s):  # night drive: 1 lux, a lamp for 1.5 s every 4 s
        return 30 if (s % 4) < 1.5 else 1

    def tv(s):            # dark room lit by a TV: 5-25 lux, new scene every 0.7 s
        r = random.Random(int(s / 0.7))
        return 5 + 20 * r.random()

    return [
        ('indoors, steady 250 lux', step((0, 250)), 60),
        ('room 150 -> window 1500 -> room 150', step((0, 150), (10, 1500), (30, 150)), 60),
        ('lamp on/off in a bedroom 3 -> 60 -> 3 lux', step((0, 3), (10, 60), (30, 3)), 60),
        ('out of the sun 30000 -> shade 3000 -> indoors 200', step((0, 30000), (10, 3000), (25, 200)), 50),
        ('sunset 1000 -> 30 lux over 5 min', lambda s: 1000 * (30 / 1000) ** min(s / 300, 1), 300),
        ('hand shadow 1.5 s at 300 lux', step((0, 300), (10, 15), (11.5, 300)), 30),
        ('hand shadow 3 s at 300 lux', step((0, 300), (10, 15), (13, 300)), 30),
        ('walking under trees 2500/15000 lux', trees, 60),
        ('night drive, lamp every 4 s (1/30 lux)', street_lamps, 60),
        ('dark room lit by a TV (5-25 lux)', tv, 60),
        ('tester 10-01: lamp 2600 / room 50 every 3.3 s', lambda s: 2600 if int(s / 3.3) % 2 else 50, 20),
    ]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    scale = 1.0
    if '--scale' in sys.argv:
        scale = float(sys.argv[sys.argv.index('--scale') + 1])
        args = [a for a in args if a != sys.argv[sys.argv.index('--scale') + 1]]
    tree = args[0] if args else DEFAULT_TREE
    c = load(tree)
    print(f'tree {os.path.abspath(tree)}; animator scale {scale}')
    print(f"debounce {c['up']}/{c['down']} ms, horizon {c['horizon_long']}/{c['horizon_short']} ms, "
          f"slow ramps {c['slow_up']}/{c['slow_down']} HLG/s, caps {c['cap_up']}/{c['cap_down']} s")
    for name, prof, secs in scenarios():
        dev, trace = run(c, prof, scale, secs)
        ch = dev.changes
        rev = sum(1 for a, b in zip(ch, ch[1:]) if b[0] - a[0] < 10000 and a[4] != b[4])
        print(f'== {name}: {len(ch)} changes, {rev} reversals within 10 s, ends at {trace[-1]:.0f} nits')
        for t, lx, n, s, _ in ch[:12]:
            print(f'   {t / 1000:7.2f} s  lux {lx:8.1f} -> {n:6.1f} nits, ramp {s:4.1f} s')
        if len(ch) > 12:
            print(f'   ... {len(ch) - 12} more')


if __name__ == '__main__':
    main()
