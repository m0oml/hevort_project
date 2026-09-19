; ======================================================================================
; Daemon Script - HevORT Chamber PLC Communication + Water Pump
; Polls Siemens S7-1200 every 5 seconds via Modbus RTU over RS485
;
; Register Map (Holding Registers):
;   R0 = Chamber_SP         (Duet->PLC, tenths degC)
;   R1 = Duet_Heartbeat     (Duet->PLC, 0-32767)
;   R2 = Duet_Control_Bits  (Duet->PLC, Bit0=Printer_Active)
;   R3 = Chamber_PV         (PLC->Duet, tenths degC)
;   R4 = Status_Bits        (PLC->Duet, see vars.g for bit definitions)
; ======================================================================================

while true

    ; --- 0. Ensure globals and serial port are ready ---
    ; Guards against daemon.g starting before config.g has completed (SBC mode)
    if { !exists(global.chamberHeartbeat) }
        M98 P"/sys/vars.g"
        G4 S10

    ; --- 1. Heartbeat Counter ---
    ; Increments each cycle so PLC can detect stale comms
    set global.chamberHeartbeat = { global.chamberHeartbeat + 1 }
    if { global.chamberHeartbeat > 32767 }
        set global.chamberHeartbeat = 0

    ; --- 2. Printer Active Bit ---
    ; Set Bit 0 when printing, simulating, or paused
    ; Paused counts as active - hotend stays hot and needs cooling
    if { state.status == "processing" || state.status == "simulating" || state.status == "paused" }
        if { mod(global.duetControl, 2) == 0 }
            set global.duetControl = { global.duetControl + 1 }
    else
        if { mod(global.duetControl, 2) == 1 }
            set global.duetControl = { global.duetControl - 1 }

    ; --- 3. Write to PLC ---
    ; Write all 5 registers in one transaction (partial writes may zero remainder)
    M260.1 P2 A1 F16 R0 B{global.chamberSP, global.chamberHeartbeat, global.duetControl, 0, 0}

    ; --- 4. Read from PLC ---
    ; Inlined from plc_read.g: DSF 3.7.0-beta.1 fails to declare a new local var
    ; ("Cannot add local variable because there is no open code block") when it
    ; happens inside a file invoked via M98 from within an active while loop.
    M261.1 P2 A1 F3 R0 B5 V"plcRegs"
    if { var.plcRegs != null }
        set global.chamberPV = { var.plcRegs[3] }
        set global.chamberStatus = { var.plcRegs[4] }

    ; --- 5. Water Pump Gate ---
    ; Pump runs only when hotend is above 50C
    ; Below 50C hotend: pump forced off regardless of coolant temp
    if { heat.heaters[1].current > 50 }
        M106 P2 H3 T25:40                               ; Hand control to coolant temp sensor S3
    else
        M106 P2 S0                                      ; Hotend cold - pump off

    ; --- 6. Poll Interval ---
    G4 S5                                               ; 5 second poll cycle

; while ends