; ================================================================================
; Bed Compensation Macro (G32) - Triple Z-Screw Tilt Correction
; Uses M671 leadscrew geometry (set in config.g) to independently correct
; each of the three Z motors so the bed plane is level.
; Leadscrew driver layout confirmed 15/08/2026 by single-driver M584 isolation:
;   Z0: front-right   Z1: front-left   Z2: rear
; (physical leadscrew X/Y coordinates for M671 still needed separately - the
; points below are the chosen PROBE points, not the leadscrew positions)
; This does NOT run a mesh (G29) - that is a separate step after G32 confirms
; the plane is level.
; ================================================================================

; --- Ensure machine is homed before probing ---
if !move.axes[0].homed || !move.axes[1].homed || !move.axes[2].homed
    G28

; --- Probe three points, correct via M671 geometry ---
; deployprobe.g / retractprobe.g are called automatically by RRF around each
; G30, no manual M42 needed here
; Explicit Z lift before each XY travel move - bed tilt is unknown on a first
; run, and RRF does not automatically retract Z before travelling between
; G30 points (only the M558 H5 dive height applies to the final approach into
; each individual probe trigger)
G1 H2 Z15 F1000                                                  ; Lift clear before first probe point
G30 P0 X400 Y16 Z-99999 H0                                       ; Probe point 0
G1 H2 Z15 F1000                                                  ; Lift clear before travelling to next point
G30 P1 X2 Y16 Z-99999 H0                                         ; Probe point 1
G1 H2 Z15 F1000                                                  ; Lift clear before travelling to next point
G30 P2 X201 Y380 Z-99999 H0 S3                                   ; Probe point 2 - S3 triggers 3-factor correction
