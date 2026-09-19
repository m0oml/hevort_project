# HevORT — how to drive this machine

Duet 3 6HC in **SBC/DSF mode** on a Raspberry Pi 4. RRF + DSF 3.7.0-rc.1
(upgraded 08/09/2026 from beta.3), **SBC over USB** since 27/08/2026 (was SPI).

**You are running on the workstation, not on the Pi** (changed 19/09/2026 — this
file was written for a session that ran on the Pi itself). You reach the machine
over SSH as `hevort.local` (192.168.32.70, key-based, user `trev`, passwordless
`sudo`). Rebooting the Pi no longer kills your shell — it kills the SSH
connection, and your working copy and notes survive.

## Where things are

Two machines now. Keep them straight.

**Workstation (here) —** `~/hevort_project`, pulled from the Pi 19/09/2026:

```
~/hevort_project/
  CLAUDE.md          this file
  project_notes.txt  merged project.txt + project-long.txt, 19/09/2026
  slicer_notes.md    preFlight/Orca presets, PA-coupled extruder limits
  slicer_brief.txt   machine spec for the slicer, 15/09/2026 (copy of sys/)
  gcodes.txt         full Duet/RRF G-code documentation (550KB)
  is.txt             input shaping sessions and method
  frame_survey_20260821.txt   geometry, shim schedule
  survey_data/       heightmaps, accelerometer captures, thermal series
  archived_project_20260919/  pre-merge project.txt + project-long.txt
  preFlight/         unbuilt checkout from the Pi — NOT the one you build
~/preFlight/         the real preFlight source + build tree (13G)
~/.config/preFlight/ LIVE slicer presets — see slicer_notes.md
```

**Pi (`hevort.local`) —** the machine's own files. Absolute paths, over SSH:

```
/opt/dsf/sd/sys/     config.g, bed.g, mesh.g, home*.g, probe macros
/opt/dsf/sd/macros/  chamber, Frame/ (input shaping), Speed/
~/                   duet, hevort_config_watch.sh, hevort_smart_blank.sh,
                     duet_bug_report_20260829.txt
```

**The Pi no longer has a copy of this project.** `~/hevort_project` was archived
and deleted from the Pi on 19/09/2026 once the transfer was checksum-verified.
**This machine holds the only working copy** — back it up accordingly. The
pristine Pi snapshot is `~/hevort_project_pi_20260919.tar.gz` (99MB, sha256
`d3c93665ddbdbe1290ef7b25aa32891b691e38a9e78f341e089967145fb1d551`), which holds
`CLAUDE.md` and `project_notes.txt` as they were *before* the rewrite for
workstation use.

Both halves are now backed up to git — see **Backup** below. Google Drive is no
longer part of this setup.

Slicing happens **entirely on the workstation** — the Pi has no slicer, no
presets and no source. See `slicer_notes.md`.

`survey_data/` is the single copy. The old `/home/trev/hevort_survey_data/` is
gone and nothing cites it any more — `project_notes.txt` and `is.txt` both
point at `~/hevort_project/survey_data/`. Write new survey data here.

`gcodes.txt` moved out of `/opt/dsf/sd/sys/` into this directory on 29/08/2026 and
is deliberately NOT committed — it is a local convenience copy of documentation
that is public on the Duet3D site, so `.gitignore` excludes it rather than
republishing someone else's docs. Do not "restore" it to `sys/`.

Last refreshed 15/09/2026. To refresh it, back up the old copy and run:

```bash
lynx -dump -nolist -width=80 https://docs.duet3d.com/User_manual/Reference/Gcodes > ~/hevort_project/gcodes.txt
```

## Sending G-code — over SSH

`duet` lives on the **Pi**, at `/usr/local/bin/duet` -> `~/duet`. It is on the
non-interactive SSH `PATH`, so no absolute path is needed. It sends everything
down **one** DCS connection.

**Prefer the stdin form.** Object-model queries contain double quotes and
nesting them through an SSH argument is where this goes wrong:

```bash
ssh hevort.local duet <<'EOF'
M114
M409 K"state.status"
EOF
```

The quoted heredoc (`<<'EOF'`) stops the local shell touching the codes at all.
Verified working 19/09/2026 — returns one JSON line per query.

The argument form works too but every inner quote needs escaping:

```bash
ssh hevort.local 'duet "M114" "M409 K\"state.status\""'
ssh hevort.local 'duet -q "G1 Z20 F600"'     # -q discards replies
```

Reading machine files, the DCS journal and `sudo` all work unprompted:

```bash
ssh hevort.local 'cat /opt/dsf/sd/sys/config.g'
ssh hevort.local 'journalctl -u duetcontrolserver -n 50 --no-pager'
ssh hevort.local 'sudo systemctl restart duetcontrolserver'
```

**One SSH invocation per batch, not per code.** The batching rule below is about
DCS connections and is unchanged by SSH; opening a new SSH connection per code
is the same mistake wearing a hat, and adds ~200ms each.

**Do NOT run `CodeConsole -c '<code>'` once per command.** Each invocation opens a
fresh socket to DuetControlServer, allocates a code channel and tears it down.
Tight loops of those correlate with unexplained M112 halts. `M929` logging caught
the mechanism on 22/08/2026: `Transfer timeout while waiting for TfrRdy pin`. That
was the SPI era; the link is USB now, but **batching is still the rule**.

**Batching is for cheap query codes ONLY. NEVER batch or chain `M997`.**
On 08/09/2026 this was issued as one line:
`M997 B70 M997 B71 M997 B72 M997 B73`
It hung for over 20 minutes and ALL FOUR M23CLs needed manual recovery.
Nothing serialises those flashes — `duet` returns before the machine finishes
(see below), so B71/B72/B73 are issued while B70 has already dropped off CAN
into its bootloader. `M997`'s `B` takes ONE address (gcodes.txt: "the CAN
address of the board to be updated, default 0"); the `:` list in `M997 S1:4`
is MODULES, not boards.
Flash ONE board. Wait for it to re-enumerate. Confirm with `M115 B<addr>`.
Only then the next. Four boards is four separate, verified operations.

**`duet` returns from a long macro BEFORE the machine finishes it.** `mesh.g`
returns "The operation was canceled" roughly 90s early. Do not archive
`heightmap.csv` on that return — you will copy the PREVIOUS map. Wait for the
`[MESH] saved` line in the DCS journal:
`ssh hevort.local 'journalctl -u duetcontrolserver -n 200 --no-pager | grep MESH'`

## Resets

- **`M999`** resets the Duet and re-runs `config.g`. Almost always what you want.
- **`sudo reboot` restarts only the Pi.** The 6HC has its own power and does *not*
  reset, so `config.g` does not re-run. Over SSH this now only drops the
  connection — your session and notes survive. Wait for the Pi to come back
  (`ssh hevort.local true` until it succeeds) rather than assuming.
- DSF config (`/opt/dsf/conf/config.json`) needs
  `ssh hevort.local 'sudo systemctl restart duetcontrolserver'`, not `M999`. That
  also reloads `daemon.g` without resetting the board — lighter than `M999` when
  you only need a macro reloaded.
- `UsbDevice` must stay the `/dev/serial/by-id/` path. The node moves between
  `ttyACM0/1/2` on almost every reconnect; a hardcoded path crash-loops DCS.

## Editing files — ASK FIRST

**Propose the diff and wait before writing to `config.g` or any `sys/` macro.**
Given 27/08/2026: *"please dont write to config without asking"*. Reading, backing
up and running codes is fine unasked. `config.g` is **hand-edited by choice** —
there is no `M501` and no `config-override.g`; do not propose them. The
consequence: an autotune result (`M307`) lives in RAM only and must be transcribed
by hand before the next reset.

Those files are on the Pi, so the local file tools cannot reach them. Read with
`ssh hevort.local 'cat /opt/dsf/sd/sys/<f>'`; back up on the Pi
(`cp <f> <f>.bak`) before any write, and write there too. Do not pull a machine
file here, edit it, and push it back — the Pi is the only copy of the machine
config, and `hevort-config-watch` is watching it.

`/opt/dsf/sd/sys` and `/opt/dsf/sd/macros` are committed to git on every change
by `hevort-config-watch` on the Pi — see **Backup** below. The machine itself is
authoritative; git is the history of it, not a second copy to edit.

- Machine files and documents → `/opt/dsf/sd/sys/`, edited in place.
- Scratch, throwaway backups → your scratchpad. Never `sys/`.
- Don't leave multiple versions of a document in `sys/` — supersede in place.
  Git carries the history; parallel copies in the tree just create ambiguity.

## Backup

Two git repositories, one writer each, both public. Nothing is on Google Drive
any more and nothing runs on a timer.

| Repo | Holds | Written by | Watcher |
|---|---|---|---|
| [`m0oml/hevort_project`](https://github.com/m0oml/hevort_project) | this directory | workstation | `hevort-project-watch` |
| [`m0oml/hevort_config`](https://github.com/m0oml/hevort_config) | `/opt/dsf/sd/{sys,macros}` | Pi | `hevort-config-watch` |

**One writer per repo is deliberate.** Two unattended watchers pushing to one
branch would race on every push — git rejects a stale HEAD regardless of which
paths changed — and an auto-retry that mishandles it loses a change silently.

`hevort_config`'s working tree **is** `/opt/dsf/sd`. Editing a file there and
letting the watcher commit it is the whole workflow; there is nothing to sync.

### Checking on them

```bash
systemctl status hevort-project-watch          # workstation
cat ~/hevort_project_watch.status              # last outcome, one line
ssh hevort.local 'systemctl status hevort-config-watch'
ssh hevort.local 'cat ~/hevort_config_watch.status'
```

Commits are labelled by change type: `+added`, `~modified`, `-deleted`.

### What they guarantee, and what they don't

- **Commit on change, not on a timer.** The duetBackup plugin this replaced
  committed every 6 hours, so anything changed twice inside a window only ever
  reached GitHub in its final state. Intermediate states are now preserved.
- **Reconcile on start.** The gap an on-change watcher leaves is its own
  downtime. Each one commits anything outstanding *before* it begins watching,
  so a reboot or crash is not a silent hole.
- **Drain after commit.** inotify only delivers events while a watch is active,
  and there is no watch during the commit and push. Changes landing in that
  window were being lost outright — caught in testing 19/09/2026. Each watcher
  now re-checks the tree after committing instead of assuming it saw everything.
- **A blocked commit is loud.** A `pre-commit` hook in both repos refuses any
  commit containing a token, private key or AWS key. On the Pi a block also puts
  `GIT BLOCKED` on the printer's display, because that failure otherwise looks
  like nothing is wrong.
- **They do not gate anything.** A bad `config.g` is committed within seconds.
  These are a record, not a review step.

### Not committed

`hevort_config` excludes `sys/heightmap.csv` (the working copy RRF recalls from
the named `heightmap_bed*_ch*.csv` maps) and the capture directories RRF creates
on demand, `sys/accelerometer/` and `sys/closed-loop/` — those are output, not
config. Captures are renamed and copied across into `survey_data/` here, where
the project watcher picks them up.

`hevort_project` excludes `preFlight/` (161M upstream checkout, `f74dc69`),
`gcodes.txt` and `print_tuning_guide.txt` (third-party docs, linked in the
README rather than mirrored).

### Keys

Each machine has its own GitHub SSH key — `~/.ssh/id_ed25519_github`, separate
from the LAN key. Either can be revoked without affecting the other. They have
no passphrase, which is what lets the watchers run unattended.

## Traps that have cost hours

- **A dropped SSH connection does NOT stop the machine.** Tested 19/09/2026: with
  no TTY allocated, sshd sends no `SIGHUP`, so a remote command whose client went
  away **keeps running** — it is orphaned, not killed. The codes are already
  queued in DCS regardless. So a drop mid-`G28`/`mesh.g` means the machine is
  still moving and you have simply lost the reply stream. **Do not re-issue the
  command** — you will double-issue it. Reconnect and read the state back
  (`M409 K"state.status"`, the DCS journal) before doing anything else.
  For anything long, prefer launching detached and polling:
  `ssh hevort.local 'setsid nohup <cmd> >/tmp/x.log 2>&1 </dev/null &'`
  (verified to survive the disconnect), then read `/tmp/x.log`.
- **`M558` silently wipes the `G31` trigger height.** Re-issue `G31` immediately
  after any `M558`, in that order. Verify `triggerHeight` is `-0.134`.
- `G30 S-1` reports the **raw** trigger height; `G29` stores it with `G31 Z`
  already subtracted. Comparing them looks like a 0.7mm fault and isn't.
- RRF heightmap **row 0 = Ymin = FRONT**. Positive = bed high = gantry sits low.
- **The Z datum moves 10.7 µm per °C of chamber temperature.** Never mesh or tram
  while the chamber is still moving. The hotend is NOT the driver — it was pinned
  at 150°C while the datum moved 307µm.
- **The chamber sensor reads AIR.** Opening the door decouples it from the frame
  and slab: air read 35.7°C, and climbed to 37.5°C once the door was shut. Judge
  readiness by the air being STEADY with the door SHUT, never by the number.
- **`M190` is not a settle.** It releases the moment the sensor enters its 2°C
  band and the slab then keeps climbing — +3.6°C over a 60 target, +1.9 over 80,
  +1.2 over 105, taking 5–23 minutes to come back. A "bed 60" map taken on the
  `M190` return was really probed at 63.1. Gate a mesh on the slab being within
  ±0.5°C **and** moving <0.15°C between 30s samples, three running, plus the air
  steady to <0.2°C. Ten of the day's maps rode on this.
- **A hot chamber pins the slab above its own setpoint.** Inlet air is ~94°C, so
  bed 80 with chamber 65 equilibrates at ~81 with the heater at zero duty. That
  is what a real print does — capture it there and label by SETPOINT.
- **The chamber sets the bed's shape, not the bed.** Same bed, chamber off vs 65:
  106µm rms. Same chamber, 20°C of bed: 34µm. Any door-open map against any
  door-shut map is 106–182µm apart. `printstart.g` tests `param.C` before
  `param.B` for this reason — see THERMAL MAP SET in project_notes.txt.
- The ALPS probe historically could not complete more than ~21–25 points in a hot
  chamber. A 7x7 completed at 60°C on 29/08/2026 after `deployprobe.g` was changed
  to cycle the enable. On 16/09/2026 the retry fired twice: once before the
  nozzle was rammed hot, once in a clean 60°C-bed 7x7. **Resolved 19/09/2026** —
  ten consecutive 49-point meshes, every pair repeating under 10µm.
- **The ALPS false-triggers from a ~125Hz hotend resonance driven by the Z
  motors** (project_notes.txt item 17). Z dive speeds of 5 and 10mm/s put a motor
  harmonic on 125Hz. Fix 17/09/2026: probe speed `F450:450` (7.5mm/s) in config.g
  and mesh.g, plus ALPS `SAMPLE_THRESHOLD` 72000. Do not go back to 5 or 10mm/s.
  G31 re-measured cold by slip gauge 17/09/2026: Z-0.050 (was -0.030). Same
  at 150C hotend. Superseded 18/09/2026 by printed squish sweeps: Z-0.134.
  The slip gauge reads the GAP; the gauge triggers on FORCE, after the nozzle
  has loaded the bed — so it measures high. Trust the printed first layer.
  The first sweep gave -0.170, but that was run against `heightmap_bed100_ch60.csv`
  whose mean sits 36.5µm off at bed90/ch50. Re-meshed at the real conditions,
  the sweep landed on -0.134 — predicted to the digit from the map difference.
  A map surveyed at the wrong thermal state shows up as a trigger-height error.
- A strain gauge reads **zero at rest**. Logging `sensors.probes[0].value` between
  probes measures nothing; the trigger height is the signal.
- **`daemon.g` uses `while { iterations < 1 }` deliberately** — a loop block that
  runs once. Do not "fix" it to `while true`: a persistent scope turns a failed
  `M261.1` into a full emergency stop. Full write-up in
  `duet_bug_report_20260829.txt` **on the Pi** — it was not pulled over here.
- Bed mesh: **`M18` between runs.** Motors left on hold bed strain and corrupt
  twist by up to 0.1mm.
- Retensioning belts **racks the gantry** unless it is held square. The rack is
  invisible to the mesh and reads as slack belts.
- Belt tension ~40 N, set by **pluck** (`T = 4L²f²µ`). The RC2 meter tops out at
  29.4 N and cannot set it.
- Compare vibration states in **displacement**, not acceleration rms.
- Do NOT write new sweep macros — use `/opt/dsf/sd/macros/Frame/`. `is_xpos.g` and
  `is_diag.g` write FIXED filenames and silently overwrite; archive first.
- Careful with `pkill -f` / `pgrep -f` — the pattern matches **your own command
  line** and will kill the shell running it. Use PIDs from `ps`, or an anchored
  path that cannot appear in your own invocation.
- Never leave a hot nozzle parked at trigger height over one spot; it locally
  heats the bed. Retract in the same batched call as the probe.

## Reference — read these before asking

- **`~/hevort_project/project_notes.txt`** — machine spec, current state,
  outstanding work, gotchas, resolved work and reference data. **Start here.**
  Merged 19/09/2026 from the old `sys/project.txt` + `sys/project-long.txt`
  split — Part 1 is the former (current state, outstanding work), Part 2 the
  latter (resolved work, reference data, no to-do lists). Moved out of `sys/`
  deliberately: it fed a Claude-Web-via-Drive workflow that predates this
  session and had become slow and cumbersome, per Trev. It is NOT pushed to
  Drive any more — originals backed up at
  `~/hevort_project/archived_project_20260919/`.
- **`~/hevort_project/slicer_notes.md`** — which slicer (preFlight, not Orca),
  where the presets live, the `HevORT`/`Saladfork` prefix rule, the PA-coupled
  extruder limits (`M201 E`/`M566 E`/`M203 E`), preFlight 1.3.0 quirks and the
  Orca conversion. Consolidated 19/09/2026. **Read before any slicer work.**
- **`~/hevort_project/gcodes.txt`** — full Duet/RRF G-code documentation (550KB).
  Moved here from `sys/` on 29/08/2026.
  Look commands up here rather than guessing or going to the web. It does NOT
  document `daemon.g`; that is in the Duet3D "GCode meta commands" page.
- **`~/hevort_project/print_tuning_guide.txt`** — Ellis' Print Tuning Guide, all
  62 pages, pulled 19/09/2026. Line-numbered contents at the top. Text only —
  the photographs it leans on for squish and PA judgements are NOT included, and
  it is Klipper-first, so its macros do not transfer even where the values do.
- `~/hevort_project/is.txt` — input shaping sessions and method.
- `~/hevort_project/frame_survey_20260821.txt` — geometry, shim schedule.
- `~/hevort_project/survey_data/` — heightmaps, accelerometer captures, thermal
  series. Benchmark map: `mesh_7x7_cold_20260823_2201.csv`.

## Retired 19/09/2026 — the Pi's Claude session

The Pi used to run its own Claude Code session: user unit
`claude-remote.service` starting `~/claude_remote.sh` inside a tmux session
called `claude`, which ran `claude --remote-control hevort` in a restart loop.
**Stopped, disabled and removed 19/09/2026** when the project moved to the
workstation. The unit file and the script are gone from the Pi; all three
artifacts (unit, script, log) are archived at
`~/hevort_project/archived_claude_remote_20260919/`. `claude_remote.log` was
left on the Pi as history.

User **lingering is still on** (`loginctl show-user trev` -> `Linger=yes`) and
must stay — `hevort-smart-blank.service` is a user unit and needs it. Do not
"tidy up" linger on the strength of the Claude session being gone.

If you ever want that session back, the archived unit and script are a working
pair: copy them back, `systemctl --user daemon-reload`, then
`systemctl --user enable --now claude-remote.service`.
