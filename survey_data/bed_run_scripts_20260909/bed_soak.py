#!/usr/bin/env python3
"""Staged bed soak after M303 completes. Logs mat + slab every 30s."""
import subprocess, json, time, sys, datetime

CSV = "/tmp/claude-1000/-home-trev-hevort-project/b2927c74-6f61-403b-a63d-2987053d472c/scratchpad/bed_soak_20260909.csv"
STAGES = [(45, 10), (50, 20), (55, 30)]   # (setpoint C, hold minutes)
FINAL  = 60
REACH_TOL   = 0.5    # counts as "at temperature"
REACH_LIMIT = 600    # 10 min per attempt before raising max PWM
POLL = 30
PWM_START   = 0.25   # current M307 S value
PWM_STEP    = 0.05   # raise by 5% when a stage cannot reach temperature
PWM_CAP     = 0.50   # never exceed 50% (700W of the mat's 1400W)
max_pwm     = PWM_START

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

with open(CSV, "w") as f:
    f.write("timestamp,setpoint_C,mat_C,slab_C,pwm,state\n")

# --- wait for the tune to finish -------------------------------------------
print("waiting for M303 to complete", flush=True)
while True:
    st, mat, pwm, slab = sample()
    log("tuning", st, mat, pwm, slab)
    if st == "fault":
        print("ABORT: heater fault during tuning - not starting soak", flush=True)
        sys.exit(1)
    if st != "tuning":
        break
    time.sleep(POLL)
print(f"tune finished (state={st}) - starting soak", flush=True)

# Use the tuned model under PID rather than bang-bang. The model is not right
# for the final installed configuration, but PID gives real fault detection.
duet("-q", "M307 H0 B0")
chk = duet('M307 H0')
print("heater model now: " + " ".join(chk.split()), flush=True)

# --- staged soak ------------------------------------------------------------
def run_stage(target, hold_min):
    duet("-q", f"M140 S{target}")
    print(f"STAGE {target}C - hold {hold_min} min", flush=True)
    waited = 0
    while waited < REACH_LIMIT:
        st, mat, pwm, slab = sample()
        log(target, st, mat, pwm, slab)
        if st == "fault":
            print(f"ABORT: heater fault at {target}C", flush=True)
            sys.exit(1)
        if mat is not None and mat >= target - REACH_TOL:
            print(f"reached {target}C (mat={mat} slab={slab}) after {waited}s", flush=True)
            break
        time.sleep(POLL); waited += POLL
        if waited >= REACH_LIMIT:
            global max_pwm
            if max_pwm < PWM_CAP - 1e-9:
                max_pwm = round(min(max_pwm + PWM_STEP, PWM_CAP), 2)
                duet("-q", f"M307 H0 S{max_pwm}")
                print(f"RAISED max PWM to {max_pwm} - {target}C not reached "
                      f"(mat={mat}) after {waited}s", flush=True)
                waited = 0
            else:
                print(f"WARN: at PWM cap {PWM_CAP} and still short of {target}C "
                      f"(mat={mat}) - holding anyway", flush=True)
                break
    held = 0
    while held < hold_min * 60:
        st, mat, pwm, slab = sample()
        log(target, st, mat, pwm, slab)
        if st == "fault":
            print(f"ABORT: heater fault holding {target}C", flush=True)
            sys.exit(1)
        time.sleep(POLL); held += POLL
    st, mat, pwm, slab = sample()
    print(f"END {target}C hold: mat={mat} slab={slab}", flush=True)

for target, mins in STAGES:
    run_stage(target, mins)

duet("-q", f"M140 S{FINAL}")
print(f"FINAL: setpoint {FINAL}C - heater left ON, logging continues", flush=True)
while True:
    st, mat, pwm, slab = sample()
    log(FINAL, st, mat, pwm, slab)
    if st == "fault":
        print(f"ABORT: heater fault at {FINAL}C", flush=True)
        sys.exit(1)
    time.sleep(POLL)
