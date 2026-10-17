-- Hyprland Lua config. Machine-specific monitors live in monitors.lua,
-- app choices in apps.lua, keybinds in binds.lua.

local apps = require("apps")

require("monitors")

-- Autostart
hl.on("hyprland.start", function()
    hl.exec_cmd(apps.terminal)
    hl.exec_cmd(apps.browser)
    hl.exec_cmd("waybar")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("Telegram")
    hl.exec_cmd("hypridle")
end)

-- Environment (NVIDIA + toolkit defaults)
hl.env("__GL_DITHERING", "1")
hl.env("__GL_FORCE_10BIT", "0")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GL_VRR_ALLOWED", "1")
hl.env("__GL_GSYNC_ALLOWED", "1")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("BROWSER", apps.browser)
hl.env("FILE_MANAGER", apps.fileManagerGUI)

hl.config({
    general = {
        border_size = 0,
        gaps_in     = 4,
        gaps_out    = 4,
    },

    input = {
        kb_layout    = "us,ua",
        kb_options   = "grp:alt_space_toggle",
        follow_mouse = 1,
        sensitivity  = -0.1,

        touchpad = {
            natural_scroll = true,
        },
    },

    animations = {
        enabled = false,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        force_default_wallpaper = 0,
        vrr                     = 2, -- fullscreen only
    },

    cursor = {
        no_hardware_cursors = true,
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

require("binds")
