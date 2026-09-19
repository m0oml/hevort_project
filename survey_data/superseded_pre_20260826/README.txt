SUPERSEDED DATA - archived 26/08/2026
=====================================================================
Everything in here describes a machine that NO LONGER EXISTS. Do not
compare current measurements against it without reading this first.

WHAT CHANGED ON 26/08/2026, and why it invalidates all of this:

1. BELT TENSION. Belts were running ~20 N. They are now 45 N (123 Hz on
   a 260mm span). Requirement for this gantry is 26 N minimum, ~53 N
   recommended - so every measurement in here was taken BELOW the
   no-slack minimum. That is the single cause of the "thump" that the
   22-25/08 data spent days chasing.

2. MOTOR PAIRS FIGHTING EACH OTHER - BUT NOT IN THIS DATA. The four
   closed-loop motors held opposing standing preload burning 366 units
   of PID authority at STANDSTILL. IMPORTANT: that was INTRODUCED BY THE
   BELT REFIT on 26/08 - clamping the belt with the paired motors at
   whatever phase they sat at. It did NOT exist before the belts came
   off, so NOTHING IN THIS ARCHIVE carries it. Only
   accel_belt123hz_20260826 (top level) does.

CONCLUSIONS REACHED FROM THIS DATA THAT WERE LATER RETRACTED:
 - "There is a torque sweet spot / torque is the variable"  - WRONG,
   it was slack belts. Rail clamping makes no measurable difference
   (loose vs torqued measured identical, 0.4% apart).
 - "The rails or blocks are damaged, order replacements"    - WRONG,
   rails hand-run end to end with belts off are perfect, including
   under deliberate racking. DO NOT ORDER RAILS.
 - "Debris on a rail, crushed out"                          - WRONG,
   debris does not vanish and return, nor appear in X-only travel.
 - "Section 3 shim schedule is 1.447x too big"              - WRONG,
   that came from twist measured with motors left energised, which
   holds bed strain and corrupts the metric by up to 0.1mm.

METHOD ERROR THAT AFFECTS EVERY COMPARISON IN HERE:
 States were compared using ACCELERATION rms, which weights harmless
 200Hz content the same as damaging 40Hz content. Compare in
 DISPLACEMENT instead:  d = a * 9.81 / (2*pi*f)^2.
 Hours were spent chasing a "35% worse than benchmark" gap that did not
 exist once converted.

WHAT IS STILL VALID AND WAS KEPT AT THE TOP LEVEL:
 accel_rearright_shim_belts25      the old 2.5-dial benchmark
 accel_belt1p9 / 2p3 / bothrails0p5  the tension series and the bad band
 accel_ALLSCREWSLOOSE              clamping makes no difference
 accel_belt1p9_OPENLOOP            open loop identical to closed
 accel_yrail_fulltravel / xrail_test  rails are clean

CURRENT REFERENCE DATA (top level, 26/08/2026):
 accel_45N_synced_20260826_run1/run2   the reference state, 8.4 um mean
 accel_NEWBASELINE_20260826            400/500 mm/s x 20/30k
 accel_ACCELSWEEP_400mms_20260826      400 mm/s x 20/25/30/35k, X and Y

Full story: /opt/dsf/sd/sys/frame_survey_20260821.txt
