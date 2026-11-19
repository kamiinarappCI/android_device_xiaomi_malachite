"""Replay light-sensor sequences through AutomaticBrightnessController's ambient-lux logic.

A line-by-line port of handleLightSensorEvent, the ring buffer prune/push,
calculateAmbientLux, the brightening/darkening debounce and HysteresisLevels from
malachite-project frameworks/base lineage-23.2 (Android 16), with malachite's
display config (horizons 3000/1000 ms, ambient thresholds). Prints when the ambient lux
the curve uses would change. Run: python tools/sim_ambient_lux.py
"""
import heapq
PRED=100
class ABC:
    def __init__(s, up, down, hl=3000, hs=1000, rate=250):
        s.up, s.down, s.hl, s.hs, s.rate = up, down, hl, hs, rate
        s.wi = hl  # mWeightingIntercept = ambientLightHorizonLong
        s.buf=[]   # [time, lux]
        s.lux=None; s.bt=s.dt=0; s.events=[]; s.pending=None
    def prune(s, horizon):
        while len(s.buf)>1 and s.buf[1][0] <= horizon: s.buf.pop(0)
        if s.buf and s.buf[0][0] < horizon: s.buf[0][0]=horizon
    def thr(s, v):
        def ref(v, lv, pc):
            if v < lv[0]: return 0.0
            i=0
            while i < len(lv)-1 and v >= lv[i+1]: i+=1
            return pc[i]
        b=max(v*(1+ref(v,[0,2,10,30,100,800],[1.0,.6,.5,.4,.3,.25])), v+2)
        d=max(min(v*(1-ref(v,[0,10,30,100,800],[.6,.5,.4,.35,.3])), v-1), 0)
        return b,d
    def set_lux(s, v, t):
        s.lux=max(v,0); s.bt,s.dt=s.thr(s.lux); s.events.append((t, s.lux))
    def calc(s, now, horizon):
        N=len(s.buf); end=0; hst=now-horizon
        for i in range(N-1):
            if s.buf[i+1][0] <= hst: end+=1
            else: break
        w=lambda x: x*(x*0.5+s.wi)
        tot=sm=0.0; et=PRED
        for i in range(N-1, end-1, -1):
            ev=s.buf[i][0]
            if i==end and ev<hst: ev=hst
            st=ev-now; wt=w(et)-w(st); tot+=wt; sm+=s.buf[i][1]*wt; et=st
        return sm/tot
    def next_b(s,t):
        e=t
        for tm,lx in reversed(s.buf):
            if lx <= s.bt: break
            e=tm
        return e+s.up
    def next_d(s,t):
        e=t
        for tm,lx in reversed(s.buf):
            if lx >= s.dt: break
            e=tm
        return e+s.down
    def update(s,t):
        if s.lux is None:
            s.set_lux(s.calc(t,s.hs),t)
        nb,nd=s.next_b(t),s.next_d(t)
        slow,fast=s.calc(t,s.hl),s.calc(t,s.hs)
        if (slow>=s.bt and fast>=s.bt and nb<=t) or (slow<=s.dt and fast<=s.dt and nd<=t):
            s.set_lux(fast,t); nb,nd=s.next_b(t),s.next_d(t)
        n=min(nb,nd); s.pending = n if n>t else t+s.rate
    def sensor(s,t,lux):
        s.pending=None
        s.prune(t-s.hl); s.buf.append([t,lux]); s.update(t)
    def msg(s,t):
        s.pending=None; s.prune(t-s.hl); s.update(t)

def run(profile, up, down, step=55):
    a=ABC(up,down); t=0; end=profile[-1][0]
    seg=0
    while t<=end:
        while seg+1<len(profile) and profile[seg+1][0]<=t: seg+=1
        lux=profile[seg][1]
        # handler messages due before this sample
        while a.pending is not None and a.pending < t: a.msg(a.pending)
        a.sensor(t,lux); t+=step
    return a.events

scen={
 'tester: 111 lux, lamp 9470 for 20 s, room 254 for 60 s, covered 0 for 30 s':
   [(0,111),(10000,9470),(30000,254),(90000,0),(120000,0)],
 'walk out of sunlight: 5000 -> 100 lux': [(0,5000),(10000,100),(40000,100)],
 'lamp off in a bedroom: 30 -> 2 lux': [(0,30),(10000,2),(40000,2)],
 'hand shadow 1.5 s: 254 -> 20 -> 254': [(0,254),(10000,20),(11500,254),(30000,254)],
 'hand shadow 2.2 s: 254 -> 20 -> 254': [(0,254),(10000,20),(12200,254),(30000,254)],
}

if __name__ == '__main__':
    for name,prof in scen.items():
        print('==',name)
        for up,down,label in [(2000,4000,'09-30 build 2000/4000'),(2000,2500,'fix     2000/2500'),(1500,2850,'before  1500/2850')]:
            ev=run(prof,up,down)
            chg=[(round(t/1000,2),round(l,1)) for t,l in ev]
            print(f'  {label}: ambient lux changes (s, lux): {chg[:8]}')
