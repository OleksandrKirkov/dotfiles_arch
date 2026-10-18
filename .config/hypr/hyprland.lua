-- Hyprland Lua config: shared defaults.
-- App choices live in apps.lua, keybinds in binds.lua.
-- Machine-specific settings and overrides live in user.lua, loaded last.

local apps = require("apps")

-- Active theme (themes/<name>/hypr.lua via ~/.local/state/theme/current, set by theme-switch).
-- Falls back to Tsugumori colours if no theme has been selected yet.
local theme = { active_border = "rgba(cc1515ff)", inactive_border = "rgba(1a1814aa)" }
do
    local ok, t = pcall(dofile, os.getenv("HOME") .. "/.local/state/theme/current/hypr.lua")
    if ok and type(t) == "table" then theme = t end
end

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
    -- Look and motion adapted from Tsugumori (github.com/Aleph1-9012/Tsugumori, MIT)
    general = {
        border_size = 1,
        gaps_in     = 4,
        gaps_out    = 4,

        col = {
            active_border   = theme.active_border,
            inactive_border = theme.inactive_border,
        },
    },

    decoration = {
        rounding = 0,
        blur     = { enabled = false },
        shadow   = { enabled = false },
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
        enabled = true,
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

hl.curve("tsugumori", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })

hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "tsugumori", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "tsugumori", style = "slide" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4, bezier = "tsugumori" })
hl.animation({ leaf = "border",     enabled = true, speed = 8, bezier = "tsugumori" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "tsugumori", style = "slidevert" })

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

-- Loaded last so machine-specific settings win.
require("user")
