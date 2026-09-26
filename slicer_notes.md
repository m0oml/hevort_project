# HevORT — slicer notes

Consolidated 19/09/2026 from the Claude session memory of
`/home/trev/.config/preFlight`. **This file is authoritative** for slicer work;
the memory files under
`~/.claude/projects/-home-trev-hevort-project/memory/` are short guardrails that
point back here.

## Which slicer

The HevORT is sliced in **preFlight** — preflight3d.com, a PrusaSlicer fork,
built from source, **v1.4.0** (`7561ccf`, installed 26/09/2026; was 1.3.0 `f74dc69`).
Not OrcaSlicer.

OrcaSlicer 2.4.2 is installed as well but drives Trev's *other* machines (Voron,
Saladfork). A request for "a slicer profile" on this machine is ambiguous and has
already gone the wrong way once — **go to preFlight unless Orca is named.**

## Where things are — all on the WORKSTATION, not the Pi

Slicing happens entirely on this workstation. The Pi has no slicer, no presets
and no source (verified 19/09/2026).

```
~/preFlight-1.4.0-run/        ACTIVE preFlight 1.4.0 (src/preflight + python/ + resources/, 420M)
~/.local/bin/preflight        -> ~/preFlight-1.4.0-run/src/preflight
~/.local/bin/preflight-1.3.0  -> ~/preFlight/build/src/preflight   (rollback)
~/preFlight/                  v1.3.0 source + build tree (13G) - old, kept for rollback
~/.config/preFlight/          LIVE presets — the single source of truth
~/hevort_project/slicer_brief.txt   machine spec (current, 15/09/2026)
~/appimage/orca               OrcaSlicer 2.4.2 AppImage
~/.config/OrcaSlicer/user/default/   active Orca user dir
```

`~/.config/OrcaSlicer/user/` also holds `7eb55bcf-*` and `2062991811` — both
**stale**. `default/` is the live one.

`~/hevort_project/preFlight/` is a second, *unbuilt* checkout of the same commit
that came over from the Pi with the rest of the project. `~/preFlight` is the
real one. Do not confuse them.

`~/hevort_project/filament_preflight/` is a snapshot from 01/09/2026 and has
drifted ~144 lines per file from the live presets. It is history, not config.
Read `~/.config/preFlight/` for current values.

## Preset naming — the prefix is the printer

In `~/.config/preFlight`, the leading word of a preset filename is the physical
printer it belongs to. **HevORT and Saladfork are different machines.**

"All the HevORT filament profiles" means the `HevORT *.ini` files *only*, even
where the same material exists under the other prefix — both
`HevORT Qidi ABS-GF25.ini` and `Saladfork Qidi ABS-GF25.ini` exist.

Scope bulk edits by the prefix named; **never fan a change out to another
printer's presets without asking.**

Current set: printer `HevORT 0.6`; prints `HevORT 0.20/0.25/0.30/0.35mm`;
filaments `HevORT <material>`; physical printer `Hevort` -> `hevort.local`.

## Presets ↔ machine

Rebuilt from the **13/09/2026** brief. `config.g` on the Pi is authoritative
where the two disagree.

- `autoemit_temperature_commands=0` — `printstart.g` owns all heating.
- Chamber via `M98 P"0:/macros/chamber_heat.g"` before `G28`.
  Chamber off at end of print.
- `G29 S1` commented out pending a re-mesh.

> **The presets predate the brief they cite.** `slicer_brief.txt` was updated
> 15/09/2026 and contradicts the assumptions the presets were built on. The
> stale copy at `~/Downloads/` was deleted 19/09/2026; the current one is
> `~/hevort_project/slicer_brief.txt` (identical to `/opt/dsf/sd/sys/`'s, which
> Trev keeps there for easy retrieval). What changed:
>
> | Preset assumption (13/09) | Actual (15/09) |
> |---|---|
> | E steps UNCALIBRATED, `M92 E420` | **CALIBRATED `M92 E536`**, extruder 600mA |
> | bed controlled off mat sensor S2 | **controlled off SLAB RTD S5** — slicer bed temp *is* granite temp (see limits below) |
> | chamber "ASK TREV, do not exceed 75°C" | **no ceiling, hotter is better**; prints at 60°C |
> | — | fed 50 mm³/s at 220°C without skipping, but melt limit unmeasured: **keep max volumetric ≤ ~40 mm³/s** |
>
> **Bed temperature limits — from `config.g`, 19/09/2026.** The 15/09 brief is
> WRONG on these (it says mat soft 165 / hard 180); `config.g` is authoritative:
>
> ```
> M143 H0 P0 T5 S150 A0   ; SLAB (RTD S5) 150C — A0 LATCHES a heater fault
> M143 H0 P1 T2 S180 A2   ; mat soft 180C — A2 clamps PWM to 0, self-recovering
> M143 H0 P2 T2 S205 A0   ; mat hard  205C — A0 latches a heater fault
> ```
>
> The mat itself is rated 210°C, so 205 is the hard stop with margin. The
> binding constraint for the slicer is the **slab at 150** — that is the sensor
> the heater runs off, so a bed target at or above it faults the heater and
> needs `M562 P0` to clear. **Max settable bed ~140°C** (150 minus working
> margin). Trev prints at **105°C**. The earlier "keep to ~110" was the print
> temperature mistaken for a ceiling — it is not one.

> Pressure advance is MEASURED, not a starting point: **0.02**, found 21/09/2026
> via Ellis' pattern method, run in Orca (see `print_tuning_guide.txt` line
> 1023). Supersedes the earlier 0.03 coupled-tuning guess — that number was
> never actually measured on a print. Set live on the machine and in both the
> preFlight and Orca ABS filament profiles the same day.
>
> Order of work is PA, then flow (EM), then retraction — per Ellis' own stated
> prerequisites (`extrusion_multiplier.html`: "you should tune pressure advance
> first"), not the reverse as this file previously said. PA affects how the EM
> test cubes' walls look, so it has to be settled first.
>
> Extrusion multiplier: **0.97**, found 21/09/2026 via Orca's built-in Flow Rate
> calibration plate (11 objects, ±0.05 around the old 0.98 guess) — supersedes
> the coupled-tuning guess, same as PA. Set in both the Orca and preFlight ABS
> filament profiles. Unlike PA, this one is flagged PENDING a confirmation
> print in preFlight itself before being trusted fully — Ellis notes different
> slicers can compute flow differently, so a value measured in Orca isn't
> guaranteed to be exactly right in preFlight. Retraction is still a starting
> point, the remaining item.

## Extruder limits are coupled to pressure advance

On RRF the extruder limits are **not independent**. RRF applies the PA
correction as an instantaneous velocity step of `M572 S × M201 E`, so per
`gcodes.txt`:

```
max M201 E = (M566 E in mm/s) / (M572 S in seconds)
```

Set at PA 0.03 (19/09/2026), still valid unchanged now PA is measured at 0.02
(21/09/2026) — the constraint only got looser (`60 mm/s ÷ 0.02s = 3000` max
`M201 E`, vs the `2000` actually in use), so nothing here needed to move:
`M201 E2000` / `M566 E3600` (60 mm/s) / `M203 E6000` (100 mm/s — ~18 mm/s
steady at 44 mm³/s, plus the 60 mm/s PA step, plus margin).

Two consequences that are easy to miss:

- Raising `M201 E` without raising `M566 E` silently clips the PA correction.
  Raising it without raising `M203 E` clips it too — the PA spike sits **on top
  of** the steady feed rate, not instead of it.
- Retraction is **acceleration**-limited, not speed-limited: over a 0.3 mm
  retract the peak is `sqrt(M201 E × 0.3)` — 8.7 mm/s at E250, 24.5 mm/s at
  E2000. `M207 F` was never being reached, so retraction behaviour changes
  whenever `M201 E` moves.

**Whenever PA changes, recompute all three.** PA 0.05 caps `M201 E` at 1200
unless `M566 E` rises with it. This bit once already: `M566 E300` was
recommended alongside `M201 E2000` after correctly identifying a 60 mm/s PA
step — an incoherent pair that would have capped effective acceleration at
167 mm/s², *worse* than the E250 it replaced. Trev caught it from `gcodes.txt`.

## preFlight quirks

(1.4.0: the CLI now **exits 0** after slicing — the 1.3.0 segfault-on-exit below was not
seen again. The `bed_temperature_extruder=0` crash was not retested.)

- The CLI **segfaults on exit** after writing the G-code. Harmless — check the
  output file exists rather than trusting the exit status.
- It **crashes before export** if a print preset has `bed_temperature_extruder=0`
  or `wipe_tower_extruder=0`.

## The Orca conversion (18/09/2026)

The preFlight presets were also converted to Orca 2.4.2, living in
`~/.config/OrcaSlicer/user/default/`: machine `HevORT 0.6` (inherits
`MyRRF 0.4 nozzle`), processes `HevORT 0.20/0.25/0.30/0.35mm`, filaments
`HevORT <material>`.

**preFlight remains primary — the Orca set is a conversion, not a re-tune.**

- Any Orca process or filament preset for this machine must list **both**
  `HevORT 0.6` and `MyRRF 0.4 nozzle` in `compatible_printers`, or Orca rejects
  it as "process not compatible with printer".
- Orca has no `autoemit_temperature_commands`, so the `M140 S0` / `M104 S0`
  suppression in the start block is what keeps `printstart.g` owning all heating.

## Part cooling — ABS and ASA (24/09/2026)

The CPAP (fan 1, `X1`, no firmware cap) was over-cooling ABS/ASA: the profiles
ran 10–100% and ramped to full when a layer took under 30 s, which every small
calibration part does. Ellis (`cooling_and_layer_times.html`) wants ABS cooled
in a hot chamber but at a **constant** speed — his 40–80% figures are for a
5015 blower, and a CPAP moves far more air.

Set in preFlight and Orca, ABS and ASA only: fan **30% constant** (min = max),
bridges/overhangs **50%**, first 3 layers off (unchanged), minimum layer time
**15 s** (was 3). STARTING POINTS, not measured — adjust in 10% steps by
layer adhesion, cracking and warp. Other materials untouched.

## Bed compensation is now meshed per print (25/09/2026)

`printstart.g` meshes the bed itself when the slicer sends a first-layer
footprint (`L/F/W/D`, which both slicers already pass), over just the part's
area at the temperature the print runs at — see `project_notes.txt`. A hand-sent
`M98` with no footprint meshes the whole bed; nothing loads the named heightmaps
any more.

The Orca machine profile briefly bypassed `printstart.g` (and the map) on
25/09/2026 for a no-map test; **reverted the same day** to the standard one-line
`M98 P"0:/sys/printstart.g" B.. C.. T.. L.. F.. W.. D..` call.

Orca's `{ }` placeholder syntax collides with RRF meta-command expressions, so
never inline RRF logic in a slicer start block — keep it in `printstart.g`.

## preFlight 1.4.0 — built on trev-pc, installed on both machines (26/09/2026)

New engine (Luminary replaces libslic3r). **Checked against 1.3.0 with the live
HevORT profiles, four parts (40mm cube, cpap mount, c13 brace, DIN rail mount):**
same layer counts and estimated times on all; total extruded volume identical to
0.001mm on the cube and the DIN part; toolpaths differ only in curve sampling
(~0.01mm point positions, 54 of ~12000 short segments merged on the DIN part) plus
a bridge-fan `M106 S128` ramp line placed a few lines apart. Output from this
machine and trev-pc is byte-identical apart from the "generated by" line.

Where: built on **trev-pc** (192.168.32.6, i7-6900K, 16 threads with Hyper-Threading
enabled 26/09/2026) at `~/preFlight-1.4.0`; runs in place there
(`~/.local/bin/preflight`). Here it is the 420M unit above, streamed over with tar.
The slicer profiles in `~/.config/preFlight` are NOT yet copied to trev-pc.

Building it — the traps:
- `./build_deps.sh` then `./build.sh -jobs 14` (deps ~20 min, main build much faster
  than on the 4-core Garage-PC).
- **Needs Python 3.14** (Debian 13 has 3.13). `build.sh` uses `python3.14` on PATH.
  Here it is uv's standalone CPython 3.14.7 (`~/.local/share/uv/python/`); it was
  copied to trev-pc the same way with `~/.local/bin/python3.14` symlinked. A failed
  first configure caches the wrong Python: fix with `./build.sh -clean` (removes only
  the app build dir, not the deps).
- trev-pc's login shell is **fish** and it has no `rsync`, `bc` or `/usr/bin/time`:
  use `ssh trev-pc bash -s` and tar over ssh.
- Prerequisites installed there: cmake ninja-build autoconf automake libtool texinfo
  m4 libgtk-3-dev libwebkit2gtk-4.1-dev libglu1-mesa-dev libdbus-1-dev libssl-dev
  libcurl4-openssl-dev libssh2-1-dev libpng-dev libxkbcommon-dev libwayland-dev
  libepoxy-dev libfontconfig-dev.
- The binary has RUNPATH `$ORIGIN/../python/lib` and finds `../resources`, so
  `src/preflight` + `python/` + `resources/` is a relocatable unit.

## First-layer line width 120% -> 130% (26/09/2026)

Widths are percentages of the 0.6 nozzle and are identical across the 0.20/0.25/0.30
profiles (only layer height differs); first layer is a fixed 0.3mm in all three.
Bumped ONLY the first-layer width, 0.72 -> 0.78mm, on the 0.20/0.25/0.30 profiles in
BOTH slicers (preFlight `first_layer_extrusion_width`, Orca `initial_layer_line_width`).
External 0.66, perimeters 0.72, solid infill 0.66, top 0.60 unchanged; the 0.35mm
profile was NOT touched. preFlight infill is 0.75mm but Orca's is 0.69mm (a standing
mismatch), and Orca's ABS volumetric cap is 20 mm3/s vs preFlight's 40.
A wider first layer at the same nozzle height squishes more, so the G31 height tuning
(global.trigZ, currently -0.174) may want a small nudge once this has been printed.
