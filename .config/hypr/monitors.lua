-- Machine-specific: monitor layout for this laptop + ultrawide setup.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.monitor({
    output   = "HDMI-A-1",
    mode     = "3440x1440@99.98",
    position = "0x0",
    scale    = 1,
    bitdepth = 10,
})

hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@120",
    position = "3440x0",
    scale    = 1,
})
