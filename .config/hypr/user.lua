-- Machine-specific settings and personal overrides.
-- Loaded last by hyprland.lua, so anything here wins over the defaults.
-- Pattern adapted from Tsugumori (github.com/Aleph1-9012/Tsugumori, MIT).
--
-- Examples:
-- hl.config({ input = { kb_layout = "us" } })
-- hl.unbind("SUPER + T")
-- hl.bind("SUPER + T", hl.dsp.exec_cmd("foot"))

-- Monitors: laptop + ultrawide

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
