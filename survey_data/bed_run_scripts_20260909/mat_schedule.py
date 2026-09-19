#!/usr/bin/env python3
"""Mat schedule: hold 80C 1h -> ramp to 90C at 1C/min -> hold 90C 1h -> shut down."""
import subprocess, json, time, sys, datetime

CSV       = "/tmp/claude-1000/-home-trev-hevort-project/b2927c74-6f61-403b-a63d-2987053d472c/scratchpad/bed_soak_20260909.csv"
HOLD1_C   = 80.0
HOLD1_S   = 3600
RAMP_TO   = 90.0
RAMP_RATE = 1.0      # degC per minute
HOLD2_S   = 3600
REACH_TOL = 0.5
POLL      = 30
LAG_WARN  = 1.5      # warn if mat falls this far behind commanded setpoint

def duet(*c):
    try:
        return subprocess.run(["duet", *c], capture_output=True, text=True, timeout=60).stdout
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

def now():
    return datetime.datetime.now().strftime("%H:%M:%S")

def guard(st, mat, slab, where):
    if st == "fault":
        print(f"ABORT: heater fault during {where} - mat={mat} slab={slab}", flush=True)
        sys.exit(1)

# --- 1. hold 80C for an hour -------------------------------------------------
duet("-q", f"M140 S{HOLD1_C}")
print(f"{now()} STAGE 1: mat {HOLD1_C}C, hold {HOLD1_S//60} min", flush=True)
while True:
    st, mat, pwm, slab = sample(); log(HOLD1_C, st, mat, pwm, slab); guard(st, mat, slab, "stage 1 approach")
    if mat is not None and mat >= HOLD1_C - REACH_TOL:
        print(f"{now()} reached {HOLD1_C}C (mat={mat} slab={slab}) - hold starts", flush=True)
        break
    time.sleep(POLL)

t_end = time.time() + HOLD1_S
while time.time() < t_end:
    st, mat, pwm, slab = sample(); log(HOLD1_C, st, mat, pwm, slab); guard(st, mat, slab, "stage 1 hold")
    time.sleep(POLL)
st, mat, pwm, slab = sample()
print(f"{now()} END 80C hold: mat={mat} slab={slab}", flush=True)

# --- 2. ramp 80 -> 90 at 1C/min ---------------------------------------------
print(f"{now()} STAGE 2: ramp {HOLD1_C} -> {RAMP_TO}C at {RAMP_RATE}C/min", flush=True)
sp = HOLD1_C
while sp < RAMP_TO - 1e-9:
    sp = round(min(sp + RAMP_RATE, RAMP_TO), 1)
    duet("-q", f"M140 S{sp}")
    t_next = time.time() + 60
    while time.time() < t_next:
        st, mat, pwm, slab = sample(); log(sp, st, mat, pwm, slab); guard(st, mat, slab, "ramp")
        if mat is not None and sp - mat > LAG_WARN:
            print(f"{now()} LAGGING: commanded {sp}C but mat only {mat}C (pwm={pwm})", flush=True)
        time.sleep(POLL)
    print(f"{now()} ramp: setpoint {sp}C, mat={mat}C, slab={slab}C", flush=True)

# --- 3. hold 90C for an hour -------------------------------------------------
print(f"{now()} STAGE 3: mat {RAMP_TO}C, hold {HOLD2_S//60} min", flush=True)
while True:
    st, mat, pwm, slab = sample(); log(RAMP_TO, st, mat, pwm, slab); guard(st, mat, slab, "stage 3 approach")
    if mat is not None and mat >= RAMP_TO - REACH_TOL:
        print(f"{now()} reached {RAMP_TO}C (mat={mat} slab={slab}) - hold starts", flush=True)
        break
    time.sleep(POLL)

t_end = time.time() + HOLD2_S
while time.time() < t_end:
    st, mat, pwm, slab = sample(); log(RAMP_TO, st, mat, pwm, slab); guard(st, mat, slab, "stage 3 hold")
    time.sleep(POLL)

# --- 4. shut down ------------------------------------------------------------
duet("-q", "M140 S0")
time.sleep(5)
st, mat, pwm, slab = sample()
log(0, st, mat, pwm, slab)
print(f"{now()} SHUTDOWN: heater off, state={st} mat={mat}C slab={slab}C", flush=True)
