; ======================================================================================
; Configuration file for Duet 3 6HC (Firmware 3.6.x)
; Machine: HevORT (CoreXY, 415x415x440mm, AWD assisted open-loop)
; ======================================================================================

; ======================= General ======================
G90                                                     ; Absolute coordinates
M83                                                     ; Relative extruder moves
M550 P"Hevort"                                          ; Set printer name
M669 K1                                                 ; CoreXY kinematics

; ======================= Network ======================
G4 S2                                                   ; Wait 2s for CAN expansion boards

; ================ Drive Mapping & Limits ==============

; --- Onboard Drivers ---
; Z axis: conventional steppers on onboard drivers
; Layout confirmed 15/08/2026 by isolating each driver via M584 single-driver
; remap and forcing individual moves:
;   Z0: front-right   Z1: rear   Z2: front-left (by elimination, unconfirmed)
M569 P0.0 S0 D2                                         ; Drive 0.0: Z0 (front-right)
M569 P0.1 S0 D2                                         ; Drive 0.1: Z1 (rear)
M569 P0.2 S0 D2                                         ; Drive 0.2: Z2 (front-left)
; Extruder: onboard driver 0.5 (closest to edge)
M569 P0.5 S1 D2                                         ; Drive 0.5: Extruder

; --- Closed-Loop Encoders (AWD) ---
; Must be configured BEFORE setting drive mode
; Tuned 15/08/2026 per Duet 1HCL procedure (P -> A -> V -> D -> I)
; E6:10 set from measured worst residual 4.71 full steps across verified envelope
M569.1 P70.0 T3 E6:10 R30 I1000 D0.05 V500 A100000      ; X1: magnetic encoder
M569.1 P71.0 T3 E6:10 R30 I1000 D0.05 V500 A100000      ; X2: magnetic encoder
M569.1 P72.0 T3 E6:10 R30 I1000 D0.05 V500 A100000      ; Y1: magnetic encoder
M569.1 P73.0 T3 E6:10 R30 I1000 D0.05 V500 A100000      ; Y2: magnetic encoder

; --- CAN AWD Drivers (closed loop) ---
; Homing files drop to D2 and restore D4 per Duet 1HCL documentation
; Layout (top-down, front of printer at bottom):
;   Back-left:  73.0 Y2  |  Back-right:  70.0 X1
;   Front-left: 71.0 X2  |  Front-right: 72.0 Y1
M569 P70.0 S1 D4                                        ; Drive 70.0: X1 (back-right)
M569 P71.0 S1 D4                                        ; Drive 71.0: X2 (front-left)
M569 P72.0 S1 D4                                        ; Drive 72.0: Y1 (front-left)
M569 P73.0 S1 D4                                        ; Drive 73.0: Y2 (back-left)

; --- Axis Mapping ---
M584 X70.0:71.0 Y72.0:73.0 Z0.0:0.1:0.2 E0.5            ; X (AWD), Y (AWD), Z (triple), E
M350 X16 Y16 Z16 E16 I1                                 ; 16x microstepping with interpolation
M92 X80 Y80 Z800 E420                                   ; Steps per mm

; --- Motor Currents ---
M906 X2000 Y2000 Z1050 E1000                            ; Motor current (mA)
M917 X100 Y100                                          ; AWD holding current 100% - required for closed loop (Duet 1HCL doc)
M906 I100 T1800                                         ; Idle current factor 100% (Z and E), 30 min idle timeout

; --- Axis Limits (PLACEHOLDER - update after homing verified) ---
M208 X0:400 Y0:390 Z-10:300                             ; Axis limits - negative Z min allows probing an out-of-tram bed below the Z0 datum

; --- Speeds and Accelerations (conservative - tune after input shaper) ---
M566 X900 Y900 Z12 E120                                 ; Jerk (mm/min)
M203 X30000 Y30000 Z1000 E3600                          ; Max speeds (mm/min) - X/Y 500mm/s verified, saturates 600-700
M201 X35000 Y35000 Z20 E250                             ; Accelerations (mm/s^2) - 35000 verified, headroom to ~48000

; --- Input Shaping ---
; Ring-down 121-147Hz, both axes, 8 unshaped captures across D2/D4 and I500/I1000 - structural.
; ZVD over MZV: same 1/F duration (7.9ms), +-20% band vs +-10%.
; Verified 19/08/2026: X ring-down rms 0.12 -> 0.08, 121Hz peak 0.14 -> 0.03, accel clipping eliminated.
M593 P"zvd" F127                                                        ; Cancel ~127Hz gantry ringing
M955 P0 C"spi.cs3+spi.cs2" I65

; --- Z Brake Control ---
; Brakes are power-to-release (24V releases, de-energised engages)
; OUT1 switches to GND (low-side): output HIGH = 24V to coil = released
; Brakes auto-engage on motor disable via M569.7
; S200 = 200ms delay before driver disables after brake engages (placeholder - tune on hardware)
M569.7 P0.0 C"out1" S200                                ; Z brakes on OUT1 (commoned across Z0/Z1/Z2 — single brake config covers all three via shared output)

; =================== Endstops & Probes ================
M574 X1 P"io2.in" S1                                    ; X endstop (min, left) - Omron EE-SX67x
M574 Y1 P"io5.in" S1                                    ; Y endstop (min, front) - Omron EE-SX67x
M574 Z1 S2                                              ; Z endstop via probe

; Z Probe
M950 P1 C"io6.out"                                      ; GPIO 1: ALPS probe enable (deploy/retract macros)
M42 P1 S0                                               ; Force enable LOW at boot - don't rely on GPIO default state
M558 K0 P9 C"io6.in" H5:2 F600:300 T3000 A8 S0.02
G31 P500 X0 Y0 Z-0.025                                  ; Trigger height measured COLD 21/08/2026, paper feeler 0.10mm (micrometer)
                                                        ; NEGATIVE by design: ALPS is a strain gauge, the nozzle presses ~0.025mm
                                                        ; into the bed before the trigger threshold is crossed. Uncertainty +/-0.025.
                                                        ; REDO at printing temperature once the hotend PT1000 is replaced.
M671 X424.75:201:-22.75 Y-8.75:415:-8.75 S40            ; Z0 front-right, Z1 rear, Z2 front-left; max 40mm correction

; =================== Thermal Sensors ===================
M912 P0 S-5.2                                           ; Set MCU calibration offset BEFORE defining the sensor
M308 S0 P"temp0" Y"pt1000" A"Hotend"                    ; Hotend PT1000
M308 S1 P"temp1" Y"thermistor" A"Coolant" T10000 B3950  ; Coolant NTC 10K B3950 (Barrow G1/4 stop fitting) - was bed slab
;M308 S2 P"temp2" Y"thermistor" A"BedMat" T10000 B3950   ; Bed heater mat surface 10K B3950 - safety limit only
M308 S4 P"spi.cs0" Y"rtd-max31865" A"ElecBay"           ; Elec bay RTD Pt100 4-wire, SPI daughterboard ch0
M308 S5 P"spi.cs1" Y"rtd-max31865" A"Bed"               ; Bed slab RTD Pt100 4-wire, SPI daughterboard ch1 - PID source
M308 S10 Y"mcu-temp" A"MCU Temp"                        ; MCU temperature sensor
M308 S11 Y"drivers" A"Driver Temp"                      ; Driver temperature (0/100/130C states)

; =================== Heaters ===========================
; Hotend Heater (H1) on OUT0 (highest rated output, 15A)
M950 H1 C"out0" T0                                      ; Hotend heater on out0, sensor S0
M143 H1 P0 T0 S350 A0                                   ; Hotend safety limit 350C (no secondary sensor)
M307 H1 R3.394 K0.346:0.369 D4.88 E1.35 S1.00 B0 V24.0  ; Hotend PID model

; Bed Heater (H0) SSR control on OUT7
; PID controlled from bed slab RTD S5 (spi.cs1)
; Independent over-temp cutout on mat surface sensor S2 (temp2), limit 125C
M950 H0 C"out7" T5 Q1                                   ; Bed heater SSR on out7, PID from S5
M143 H0 P0 T5 S200 A0                                   ; Bed primary limit 200C on sensor S5
;M143 H0 P1 T2 S125 A0                                   ; Bed mat safety cutout 125C on sensor S2
M307 H0 A100.0 C200.0 D5.0 B0                           ; Bed PID model (calculated for 20mm granite slab)

; Map bed heater
M140 P0 H0                                              ; Map to bed slot

; ========================= Fans ========================
; Fan 0: Duet enclosure fan (Noctua NF-A4x10 24V PWM) on OUT4
; Thermostatic on MCU and driver temps
M950 F0 C"!out4" Q500                                   ; Fan 0: enclosure fan, 500Hz PWM
M106 P0 H10:11 T25:45                                   ; Thermostatic control on MCU/driver temps

; Fan 1: WS7040 CPAP (part cooling) on OUT9 with tach
M950 F1 C"out9" Q500                                    ; Fan 1: CPAP, 500Hz PWM, 
M106 P1 S0 L0 X1 H-1                                    ; Manual/slicer control, no thermostatic

; Fan 2: Water pump on OUT2 (Lowara D5 Vario - manual speed dial, no PWM input)
; Thermostatic on/off from hotend sensor S0: on above 40C, off below
M950 F2 C"out2+out5.tach" Q500                          ; Fan 2: water pump, on/off gate
M106 P2 C"Pump" S0 L0 X1 H0 T40:41                              ; On above 40C hotend, off below

; Fan 3: Electronics bay / radiator fan (24V 4-pin PWM) on OUT6, inverted PWM
; Single fan pulls bay exhaust through the radiator - highest of the two sensors wins
M950 F3 C"!out6" Q500                                   ; Fan 3: bay/rad fan, 500Hz PWM, inverted
M106 P3 S0 L0 X1 H4:1 T30:50                            ; Thermostatic 30-50C on ElecBay RTD (S4) + Coolant (S1)

; ======================== Tools =======================
M563 P0 D0 H1 F1                                        ; Tool 0: Extruder 0, Heater 1 (hotend), Fan 1 (CPAP)
M568 P0 R0 S0                                           ; Standby/Active temps to 0C

; ======================= Inputs ========================
; IO4 free (was flow switch - removed, pump has no flow sensing)

; Filament sensor on IO3 (TBD - placeholder)
; M950 J1 C"io3.in"                                     ; Input 1: filament sensor (uncomment when fitted)

; Pause button on IO7 (NO - make to pause)
M950 J2 C"io7.in"                                       ; Input 2: pause button
M581 T2 P2 S1 R0                                        ; Trigger 2 on pause button make, during print only

; Stop button on IO8 (NC - break to stop)
M950 J3 C"!io8.in"                                      ; Input 3: stop button
M581 T3 P3 S0 R0                                        ; Trigger 3 on stop button break

; ======================= Outputs ======================
; OUT8: PLC safety relay R1 coil
; HIGH = relay latched = PLC %I0.0 healthy = heater enabled
; Drops on any Duet stop/estop condition via trigger macros
; Initialise HIGH at startup - machine in known good state
M950 P0 C"out8"                                         ; GPIO 0: PLC safety relay coil
M42 P0 S0                                               ; Hold OUT8 low until stop button confirmed

if { sensors.gpIn[3].value = 1 }
    M42 P0 S1
    M118 P0 S"[BOOT] Stop button OK - PLC relay enabled"
else
    M118 P0 S"[BOOT] Stop button open - PLC relay held off, press pause to reset"

; ======================= Modbus =======================
; RS485 to Siemens S7-1200 PLC for chamber heating control
; IO1 dedicated to RS485 - RS485_EN jumper fitted on board
M575 P3 B9600 S7                                        ; Serial 3: RS485, 9600 baud, Modbus RTU (P2 in RRF 3.6.x)

; ===================== Finalization ===================
M98 P"vars.g"  