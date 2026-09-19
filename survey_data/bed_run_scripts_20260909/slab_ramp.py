#!/usr/bin/env python3
"""Cascade controller: drive the SLAB to a target by creeping the mat setpoint.

The mat is the only thing RRF can control. The slab follows it with a long lag,
so this nudges the mat setpoint up (or down) in small steps at a slow interval
and lets the slab converge. Appends to the existing soak CSV.
"""
import subprocess, json, time, sys, datetime

CSV         = "/tmp/claude-1000/-home-trev-hevort-project/b2927c74-6f61-403b-a63d-2987053d472c/scratchpad/bed_soak_20260909.csv"
SLAB_TARGET = 60.0
DEADBAND    = 0.3     # slab within +-this of target = no change
MAT_START   = 80.0    # where the mat setpoint is now
MAT_MIN     = 45.0
MAT_MAX     = 82.0    # hard ceiling on mat setpoint
MAT_STEP    = 2.0     # coarse step while far from target
FINE_STEP   = 0.5     # step once within FINE_BAND of target
FINE_BAND   = 2.0     # slab within this of target -> use FINE_STEP
ADJUST_EVERY = 300    # seconds between adjustments (5 min)
POLL         = 30     # logging interval

def duet(*codes):
    try:
        return subprocess.run(["duet", *codes], capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return ""

def sample():
    out = duet('M409 K"heat.heaters[0]" F"v"', 'M409 K"sensors.analog[5].lastReading"')
    st, mat, pwm, slab = "?", None, None, None
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        k, r = d.get("key", ""), d.get("result")
        if k == "heat.heaters[0]" and isinstance(r, dict):
            st, mat, pwm = r.get("state", "?"), r.get("current"), r.get("avgPwm")
        elif "analog[5]" in k:
            slab = r
    return st, mat, pwm, slab

def log(sp, st, mat, pwm, slab):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(CSV, "a") as f:
        f.write(f"{ts},{sp},{mat},{slab},{pwm},{st}\n")

mat_sp = MAT_START
print(f"slab ramp started - target slab {SLAB_TARGET}C, mat setpoint {mat_sp}C, "
      f"step {MAT_STEP}C every {ADJUST_EVERY//60} min, mat ceiling {MAT_MAX}C", flush=True)

last_adjust = time.time()
at_target_since = None

while True:
    st, mat, pwm, slab = sample()
    log(mat_sp, st, mat, pwm, slab)

    if st == "fault":
        print(f"ABORT: heater fault - mat={mat} slab={slab}", flush=True)
        sys.exit(1)

    if slab is not None and time.time() - last_adjust >= ADJUST_EVERY:
        last_adjust = time.time()
        old = mat_sp
        step = FINE_STEP if abs(slab - SLAB_TARGET) <= FINE_BAND else MAT_STEP
        if slab < SLAB_TARGET - DEADBAND and mat_sp < MAT_MAX:
            mat_sp = round(min(mat_sp + step, MAT_MAX), 1)
        elif slab > SLAB_TARGET + DEADBAND and mat_sp > MAT_MIN:
            mat_sp = round(max(mat_sp - step, MAT_MIN), 1)

        if mat_sp != old:
            duet("-q", f"M140 S{mat_sp}")
            arrow = "up" if mat_sp > old else "down"
            print(f"{datetime.datetime.now():%H:%M:%S} mat setpoint {arrow} "
                  f"{old} -> {mat_sp}C  (slab={slab}C, target {SLAB_TARGET})", flush=True)
        elif mat_sp >= MAT_MAX and slab < SLAB_TARGET - DEADBAND:
            print(f"{datetime.datetime.now():%H:%M:%S} AT MAT CEILING {MAT_MAX}C "
                  f"and slab only {slab}C - holding, needs your call", flush=True)

        if slab is not None and abs(slab - SLAB_TARGET) <= DEADBAND:
            if at_target_since is None:
                at_target_since = time.time()
                print(f"{datetime.datetime.now():%H:%M:%S} SLAB AT TARGET "
                      f"{slab}C (mat setpoint {mat_sp}C)", flush=True)
        else:
            at_target_since = None

    time.sleep(POLL)
