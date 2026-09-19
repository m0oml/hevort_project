# hevort_project

Build notes, survey data and tuning history for a **HevORT** — a CoreXY printer
running RepRapFirmware on a Duet 3 6HC in SBC/DSF mode on a Raspberry Pi 4,
with four M23CL closed-loop motors on CAN, a granite-slab bed and a heated
chamber.

This is a working log, not a guide. It is published because the measurements in
it were expensive to take and may save someone else the same work.

## What's here

| Path | What it is |
|---|---|
| `project_notes.txt` | machine spec, current state, outstanding work, resolved work, reference data. **Start here.** |
| `CLAUDE.md` | how to drive the machine — G-code over SSH, resets, and the traps that have cost hours |
| `slicer_notes.md` | preFlight/Orca presets, preset naming, PA-coupled extruder limits |
| `slicer_brief.txt` | the machine spec the slicer presets were built from |
| `is.txt` | input shaping sessions and method |
| `frame_survey_20260821.txt` | frame geometry and shim schedule |
| `survey_data/` | heightmaps, accelerometer captures, thermal series — the evidence behind the notes |
| `archived_*/` | superseded copies kept for history |

## Some things that took a while to learn

- **The Z datum moves ~10.7 µm per °C of chamber temperature.** Never mesh or
  tram while the chamber is still moving.
- **`M190` is not a settle.** It releases as the sensor enters its 2 °C band
  while the slab keeps climbing — a "bed 60" map taken on the `M190` return was
  really probed at 63.1 °C.
- **The chamber sets the bed's shape, not the bed.** Same bed, chamber off vs
  65 °C: 106 µm rms. Same chamber, 20 °C of bed: 34 µm.
- **`M558` silently wipes the `G31` trigger height.** Re-issue `G31` after any
  `M558`.
- **On RRF the extruder limits are coupled to pressure advance.** `M201 E`,
  `M566 E` and `M203 E` have to be recomputed together — see `slicer_notes.md`.

## Deliberately not in this repo

- **Duet/RRF G-code reference** — read it at
  [docs.duet3d.com](https://docs.duet3d.com/User_manual/Reference/Gcodes)
- **Ellis' Print Tuning Guide** — read it at
  [ellis3dp.com](https://ellis3dp.com/Print-Tuning-Guide/)
- **preFlight slicer source** — [github.com/oozebot/preFlight](https://github.com/oozebot/preFlight),
  pinned at `f74dc69` (v1.3.0)

Machine configuration (`config.g`, macros) lives in its own repository.
