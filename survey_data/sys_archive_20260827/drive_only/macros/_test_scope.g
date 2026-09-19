; Test: does a FAILED M261.1 inside a nested block leak its var across iterations?
while iterations < 3
    if true
        M261.1 P3 A9 F3 R0 B5 V"tv"
        if { var.tv = null }
            echo "iter " ^ iterations ^ ": read failed, var exists and is null"
    G4 P300
echo "test complete"
