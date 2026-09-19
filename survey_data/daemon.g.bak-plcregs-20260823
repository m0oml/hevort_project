; ======================================================================================
; Daemon Script - HevORT Chamber PLC Communication
; Polls Siemens S7-1200 every 5 seconds via Modbus RTU over RS485
;
; Register Map (Holding Registers):
;   R0 = Chamber_SP         (Duet->PLC, tenths degC)
;   R1 = Duet_Heartbeat     (Duet->PLC, 0-32767)
;   R2 = Duet_Control_Bits  (Duet->PLC, unused - retained to preserve register map)
;   R3 = Chamber_PV         (PLC->Duet, tenths degC)
;   R4 = Status_Bits        (PLC->Duet, see vars.g for bit definitions)
;
; Water pump and bay/radiator fan are now thermostatic in config.g (Fan 2, Fan 3).
; No fan or pump logic belongs in this file.
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

    ; --- 2. Write to PLC ---
    ; Write all 5 registers in one transaction (partial writes may zero remainder)
    M260.1 P3 A1 F16 R0 B{global.chamberSP, global.chamberHeartbeat, global.duetControl, 0, 0}

    ; --- 3. Read from PLC ---
    ; Inlined from plc_read.g: DSF 3.7.0-beta.1 fails to declare a new local var
    ; ("Cannot add local variable because there is no open code block") when it
    ; happens inside a file invoked via M98 from within an active while loop.
    ; A failed M261.1 still declares plcRegs (as null) and the declaration is NOT
    ; cleaned up on the error path, so every later iteration fails with
    ; "variable 'plcRegs' already exists" and the read never recovers - even once
    ; the PLC is answering again. Nesting the read in its own block does not help;
    ; only a fresh run of the file clears the scope. So bail out and let RRF
    ; restart daemon.g. Verified on RRF/DSF 3.7.0-beta.3, 20/08/2026.
    if { exists(var.plcRegs) }
        break

    M261.1 P3 A1 F3 R0 B5 V"plcRegs"
    if { var.plcRegs != null }
        set global.chamberPV = { var.plcRegs[3] }
        set global.chamberStatus = { var.plcRegs[4] }

    ; --- 4. Poll Interval ---
    G4 S5                                               ; 5 second poll cycle

; while ends