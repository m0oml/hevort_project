; ================================================================================
; Bed Mesh Macro - Grid Levelling (G29 S0)
; Probes a grid over the bed with the ALPS strain-gauge probe (K0) and saves the
; result to 0:/sys/heightmap.csv. printstart.g loads it with G29 S1.
;
; This is the step AFTER G32 (bed.g). G32 corrects the bed PLANE via the three Z
; motors; this corrects what is left - slab, FR4 and PEI surface irregularity.
; Running a mesh over an untrammed bed just bakes the tilt into the map, so this
; macro RUNS G32 itself and verifies it converged before probing any grid.
;
; PREREQUISITES - mesh values are meaningless until these are real:
;   - G31 Z trigger height is a PLACEHOLDER (0.7). Set it properly first.
;   - M558 probe mode P5 vs P9 still unresolved (config.g currently P9).
;   - Granite slab not yet fitted - the FR4-on-frame surface will not resemble
;     the final bed, so treat any map taken now as a rehearsal, not a datum.
; ================================================================================

; --- 1. Kinematic state validation ---
if !exists(sensors.probes[0])
    abort "mesh.g: no Z probe configured - check M558 K0 in config.g"

if !move.axes[0].homed || !move.axes[1].homed || !move.axes[2].homed
    M98 P"0:/sys/homeall.g"                                      ; Ensure axes are homed before probing

; --- 2. Tram the bed plane first (G32 -> bed.g) ---
; Always run it rather than trusting a previous result. move.calibration reads 0
; both when G32 has never run and when it converged perfectly, so an inherited
; value cannot distinguish "already level" from "never levelled" - run and check.
M118 P0 S"[MESH] tramming bed (G32) before mesh probing"
G32                                                              ; Iterative 3-point tilt correction
if result != 0
    abort "mesh.g: G32 failed - bed not trammed, mesh aborted"
M400                                                             ; Ensure corrections are applied before reading the result

; bed.g's loop exits on EITHER convergence (<0.02mm) OR the 15-iteration limit,
; so completing G32 is not proof it converged. Re-check the residual here: this
; is the deviation G32 saw on its final pass, and 0.02 is bed.g's own criterion.
if !exists(move.calibration.initial.deviation)
    abort "mesh.g: G32 reported no calibration result - check M671 is present in config.g"
if abs(move.calibration.initial.deviation) >= 0.02
    abort {"mesh.g: G32 did not converge - residual " ^ move.calibration.initial.deviation ^ "mm, needs <0.02mm. Check Z motor travel, M671 geometry and probe repeatability."}
M118 P0 S{"[MESH] G32 converged, residual " ^ move.calibration.initial.deviation ^ "mm"}

; --- 3. Grid definition ---
; Probe offsets are X0 Y0 (nozzle-coincident strain gauge), so the grid can use
; the full reachable envelope less a small edge margin. M208 is X0:400 Y0:390;
; Y is held to 16:380 to match the reachable band already proven in bed.g.
; P7:7 = 49 points, ~63mm X / ~61mm Y spacing. That suits a rigid granite slab.
; With M558 A8 averaging each point costs several seconds - raise to P9:9 or
; P11:11 only if the saved map shows real structure between existing points.
M557 X10:390 Y16:380 P7:7                                        ; 7x7 grid over the reachable bed

; --- 4. Probe setup ---
M561                                                             ; Clear any active bed transform - never mesh on top of a mesh
M558 K0 H5:2 F600:300 T3000 A8 S0.02                             ; Normal dive height; restate in case bed.g left it wide

; M569.7 fires the brake port at the same time as driver enable, but RRF gives
; no automatic delay in this direction - force enable and wait before moving Z.
M17 Z                                                            ; Enable Z, releasing brakes
G4 P800                                                          ; Wait for brake solenoids to fully release
G1 Z5 F1000                                                      ; Lift to dive height before the first travel

; --- 5. Probe the grid ---
M118 P0 S"[MESH] probing 7x7 grid - this takes a few minutes"
G29 S0                                                           ; Probe grid, activate and save to 0:/sys/heightmap.csv
if result != 0
    M561                                                         ; Do not leave a partial transform active
    abort "mesh.g: G29 failed - mesh not saved"

; --- 6. Report and re-datum ---
; Meshing does not move the bed plane, but Z0 was set at whatever point homing
; last probed. Re-establish it at bed centre so the mesh is referenced correctly.
var xCenter = move.axes[0].min + (move.axes[0].max - move.axes[0].min) / 2 - sensors.probes[0].offsets[0]
var yCenter = move.axes[1].min + (move.axes[1].max - move.axes[1].min) / 2 - sensors.probes[0].offsets[1]
G1 X{var.xCenter} Y{var.yCenter} F9000                           ; Move to bed centre
G30                                                              ; Re-set Z0 datum at bed centre
if result != 0
    abort "mesh.g: centre G30 failed - probe did not trigger"

M118 P0 S{"[MESH] saved - mean " ^ move.compensation.meshDeviation.mean ^ "mm, deviation " ^ move.compensation.meshDeviation.deviation ^ "mm"}
