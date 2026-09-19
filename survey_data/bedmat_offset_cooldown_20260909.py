#!/usr/bin/env python3
"""BedMat sensor offset characterisation - unattended overnight run.

QUESTION: the mat sensor (S2, generic 100k NTC B3950) reads high against the
slab RTD (S5, 4-wire Pt100 on MAX31865). With the heater off and the mat bonded
to the slab with Dowsil 736, any genuine thermal gradient decays as the assembly
approaches ambient, so the surviving difference is sensor error.

Deciding between the two corrections (M308 U / V, RRF 3.5+):
    adjustedReading = (rawReading * (1.0 + V)) + U
  - delta constant across the range  -> fixed offset, correct with U
  - delta varies with temperature    -> beta/slope error, needs V

Runs indefinitely. Ambient drifts (garage heating, shutter), so three
independent references are logged alongside; windows where they are not flat
must be discarded during analysis.
"""
import subprocess, json, time, datetime, os

CSV  = "/home/trev/hevort_project/survey_data/bedmat_offset_cooldown_20260909.csv"
POLL = 30

def duet(*c):
    try:
        return subprocess.run(["duet", *c], capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return ""

def sample():
    out = duet('M409 K"sensors.analog[2].lastReading"',
               'M409 K"sensors.analog[5].lastReading"',
               'M409 K"sensors.analog[0].lastReading"',
               'M409 K"sensors.analog[4].lastReading"',
               'M409 K"global.chamberPV"',
               'M409 K"heat.heaters[0].state"',
               'M409 K"heat.heaters[0].avgPwm"')
    v = {}
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        v[d.get("key", "")] = d.get("result")
    return v

if not os.path.exists(CSV):
    with open(CSV, "w") as f:
        f.write("timestamp,epoch,mat_S2_C,slab_S5_C,delta_C,"
                "hotend_S0_C,elecbay_S4_C,chamber_air_C,heater_state,pwm\n")

print(f"bedmat offset logging -> {CSV}", flush=True)
i = 0
while True:
    v = sample()
    mat  = v.get('sensors.analog[2].lastReading')
    slab = v.get('sensors.analog[5].lastReading')
    hot  = v.get('sensors.analog[0].lastReading')
    bay  = v.get('sensors.analog[4].lastReading')
    cham = v.get('global.chamberPV')
    st   = v.get('heat.heaters[0].state')
    pwm  = v.get('heat.heaters[0].avgPwm')
    now  = datetime.datetime.now()
    delta = round(mat - slab, 3) if (isinstance(mat, (int, float)) and isinstance(slab, (int, float))) else ""
    chamC = round(cham / 10.0, 1) if isinstance(cham, (int, float)) else ""
    with open(CSV, "a") as f:
        f.write(f"{now:%Y-%m-%d %H:%M:%S},{int(now.timestamp())},{mat},{slab},{delta},"
                f"{hot},{bay},{chamC},{st},{pwm}\n")
    if i % 20 == 0:      # every 10 min
        print(f"{now:%H:%M:%S}  mat={mat}  slab={slab}  DELTA={delta}  "
              f"hotend={hot}  bay={bay}  chamber={chamC}", flush=True)
    i += 1
    time.sleep(POLL)
