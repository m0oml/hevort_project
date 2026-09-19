; ================================================================================
; Bed Compensation Macro (G32) - Triple Z-Screw Tilt Correction
; Iterative 3-point tramming using ALPS probe (K0) and M671 pivot geometry.
; Requires M671 in config.g defining the POS8 bearing / MGN12 rail junctions.
; Probe point layout:
;   P0 - front-right (Z0, driver 0.0)   P1 - rear (Z1, 0.1)   P2 - front-left (Z2, 0.2)
; This order MUST match the M671 coordinate order in config.g - RRF pairs G30 P<n>
; to the n-th M671 entry, so a mismatch silently corrects the WRONG motor. It is
; invisible on a near-level bed (all three corrections come out equal) and only
; shows up as failure to converge once the bed is genuinely out of tram.
; Corner-to-driver mapping confirmed physically 21/08/2026 by M584 single-driver.
; This does NOT run a mesh (G29) - that is a separate step once G32 converges.
; ================================================================================

; --- 1. Kinematic state validation ---
M561                                                             ; Clear any active bed transform before tramming
if !move.axes[0].homed || !move.axes[1].homed || !move.axes[2].homed
    M98 P"homeall.g"                                             ; Ensure axes are homed before probing

; --- 2. Probe setup ---
; config.g's M558 H5 is tuned for normal operation once the bed is close to
; level. An untrammed bed can be further out than that, so widen the search
; window for tramming and restore it at the end.
; Two-value H (RRF 3.5+): the 40mm dive applies only to the first probe at each
; point - i.e. on arrival after a travel across a potentially untrammed bed.
; The A8 repeat probes at the same XY retract just 2mm, so averaging stays fast.
M558 K0 H40:2                                                    ; Dive: 40mm on arrival, 2mm between repeats

; Single clearance move before the first travel. Homing leaves the nozzle at
; trigger height, which is not safe to traverse an untrammed bed at. After each
; G30 completes RRF retracts to dive height automatically, so subsequent
; travels within the loop need no further Z handling.
; M569.7 fires the brake port at the same time as driver enable, but RRF gives
; no automatic delay in this direction - force enable and wait before moving Z.
M17 Z                                                            ; Enable Z, releasing brakes
G4 P1500                                                         ; Wait for brake solenoids to fully release (raised from 800ms 22/08/2026 - brakes failed to release in time, forced an E-stop)
G1 Z40 F1000                                                     ; Lower bed to dive height before first travel

; --- 3. Iterative alignment loop ---
while true
    ; Point 0: front-right, near Z0
    G0 X400 Y16 F9000                                            ; Travel to front-right probe point
    M400                                                          ; Wait for move to finish
    G4 P250                                                       ; Stabilisation delay
    G30 P0 X400 Y16 Z-99999                                       ; Probe and store as point 0
    G4 P250

    ; Point 1: rear, near Z1 (driver 0.1)
    G0 X201 Y380 F9000                                           ; Travel to rear probe point
    M400                                                          ; Wait for move to finish
    G4 P250
    G30 P1 X201 Y380 Z-99999                                      ; Probe and store as point 1
    G4 P250

    ; Point 2: front-left, near Z2 (driver 0.2)
    G0 X2 Y16 F9000                                              ; Travel to front-left probe point
    M400                                                          ; Wait for move to finish
    G4 P250
    G30 P2 X2 Y16 Z-99999 S3                                      ; Probe point 2, calculate 3-motor correction
    M400                                                          ; Sync moves before loop evaluation
    G4 P250

    ; Convergence check: deviation threshold 0.02mm (max 15 iterations)
    if abs(move.calibration.initial.deviation) < 0.02 || iterations > 15
        break

; --- 4. Z-datum re-establishment ---
; Levelling adjustments move the bed plane; Z must be re-homed at centre
M558 K0 H5:2                                                     ; Restore normal dive height
G4 P500                                                          ; Final settle time after corrections
G1 Z5 F1000                                                      ; Return to dive height - the loop leaves the nozzle
                                                                 ; only 2mm off the bed, too close to start a G30 from
var xCenter = move.axes[0].min + (move.axes[0].max - move.axes[0].min) / 2 - sensors.probes[0].offsets[0]
var yCenter = move.axes[1].min + (move.axes[1].max - move.axes[1].min) / 2 - sensors.probes[0].offsets[1]
G1 X{var.xCenter} Y{var.yCenter} F9000                           ; Move to bed centre
M400
G4 P1000                                                         ; Let the ALPS strain gauge fully release before the
                                                                 ; datum probe. 21/08/2026: this G30 failed with "probe
                                                                 ; already triggered before probing move started" after
                                                                 ; a converged loop - and because nothing checked the
                                                                 ; result, the Z datum was silently left unset and the
                                                                 ; whole following heightmap came out 0.25mm displaced.
G30                                                              ; Set Z0 datum at bed centre
if result != 0
    abort "bed.g: centre G30 FAILED - Z datum not set. Any mesh taken now is invalid."

