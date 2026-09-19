; ================================================================================
; Home All Axes - Sequential X, Y, then Z
; AWD CoreXY with physical endstops, Z via probe at bed centre
; X and Y both home to min (left / front)
; Axes homed one at a time - on CoreXY a combined move keeps both motors driving
; after the first endstop triggers
; Drops all four AWD drivers to open loop for homing, restores closed loop before
; the Z probe (per Duet 1HCL documentation)
; ================================================================================

; --- Drop to open loop ---
M569 P70.0 S1 D2                                                ; X1 open loop
M569 P71.0 S1 D2                                                ; X2 open loop
M569 P72.0 S1 D2                                                ; Y1 open loop
M569 P73.0 S1 D2                                                ; Y2 open loop

; --- 1. Enable Z and wait for brakes to physically release before moving ---
; M569.7 fires the brake port at the same time as driver enable, but RRF gives
; no automatic delay in this direction (S param on M569.7 only covers the
; engage-on-disable side). Force enable and wait before the first Z move.
M17 Z                                                            ; Enable Z, releasing brakes
G4 P800                                                          ; Wait for brake solenoids to fully release

; --- 2. Z Clearance ---
G91                                                             ; Relative positioning
G1 H2 Z5 F6000                                                  ; Lift Z to clear nozzle from bed
G90                                                             ; Absolute positioning

; --- 3. Home X (dual-pass coarse/fine) ---
var xTravel = move.axes[0].max - move.axes[0].min + 5
G91                                                             ; Relative positioning
G1 H1 X{-var.xTravel} F6000                                     ; Coarse home X
G1 X5 F6000                                                     ; Back off 5mm (no H2 - CoreXY H2 is single-motor move, drives wrong way)
G1 H1 X{-var.xTravel} F600                                      ; Fine home X
G90                                                             ; Absolute positioning

; --- 4. Home Y (dual-pass coarse/fine) ---
var yTravel = move.axes[1].max - move.axes[1].min + 5
G91                                                             ; Relative positioning
G1 H1 Y{-var.yTravel} F6000                                     ; Coarse home Y
G1 Y5 F6000                                                     ; Back off 5mm (no H2 - CoreXY H2 is single-motor move, drives wrong way)
G1 H1 Y{-var.yTravel} F600                                      ; Fine home Y
G90                                                             ; Absolute positioning

; --- 5. Restore closed loop ---
M400                                                            ; Wait for all moves to complete
G4 P200                                                         ; Wait for motors to settle
M569 P70.0 S1 D4                                                ; X1 closed loop
M569 P71.0 S1 D4                                                ; X2 closed loop
M569 P72.0 S1 D4                                                ; Y1 closed loop
M569 P73.0 S1 D4                                                ; Y2 closed loop

; --- 6. Home Z (probe at bed centre) ---
var xCenter = move.axes[0].min + (move.axes[0].max - move.axes[0].min) / 2 - sensors.probes[0].offsets[0]
var yCenter = move.axes[1].min + (move.axes[1].max - move.axes[1].min) / 2 - sensors.probes[0].offsets[1]
G1 X{var.xCenter} Y{var.yCenter} F6000                          ; Move to bed centre
G30                                                             ; Probe Z datum




