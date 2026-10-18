local apps = require("apps")

local mainMod = "SUPER"

local function bind(keys, dispatcher, opts)
    hl.bind(keys, dispatcher, opts)
end

local function exec(cmd)
    return hl.dsp.exec_cmd(cmd)
end

-- Window cycling
bind("ALT + TAB",         hl.dsp.window.cycle_next())
bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }))

-- Apps
bind(mainMod .. " + Q",         exec(apps.terminal))
bind(mainMod .. " + B",         exec(apps.browser))
bind(mainMod .. " + E",         exec(apps.fileManagerTerminal))
bind(mainMod .. " + SHIFT + E", exec(apps.fileManagerGUI))
bind(mainMod .. " + space",     exec(apps.menu))
bind(mainMod .. " + D",         exec(apps.menu))
bind(mainMod .. " + O",         exec("obsidian"))
bind(mainMod .. " + M",         exec("waybar"))
bind(mainMod .. " + N",         exec("killall waybar"))
local themeSwitch = os.getenv("HOME") .. "/.local/bin/theme-switch"
bind(mainMod .. " + T",         exec(themeSwitch .. " --apply"))
bind(mainMod .. " + SHIFT + T", exec(themeSwitch .. " --pick"))
bind(mainMod .. " + Escape",    exec("loginctl lock-session"))
bind("ALT + S",                 exec('grim -g "$(slurp)" - | wl-copy'))

-- Window state
bind(mainMod .. " + W", hl.dsp.window.close())
bind(mainMod .. " + V", hl.dsp.window.float())
bind("ALT + F",         hl.dsp.window.float())
bind(mainMod .. " + F", hl.dsp.window.fullscreen())

-- Focus and move (vim keys)
local directions = { H = "left", L = "right", K = "up", J = "down" }
for key, direction in pairs(directions) do
    bind(mainMod .. " + " .. key,             hl.dsp.focus({ direction = direction }))
    bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ direction = direction }))
end

-- Resize, repeats while held
local resizeSteps = {
    left  = { -1, 0 },
    right = { 1, 0 },
    up    = { 0, -1 },
    down  = { 0, 1 },
}
for key, step in pairs(resizeSteps) do
    bind(mainMod .. " + " .. key,
        hl.dsp.window.resize({ x = step[1] * 20, y = step[2] * 20, relative = true }),
        { repeating = true })
    bind(mainMod .. " + SHIFT + " .. key,
        hl.dsp.window.resize({ x = step[1] * 50, y = step[2] * 50, relative = true }),
        { repeating = true })
end

-- Workspaces 1-10: SUPER + [0-9], 11-20: SUPER + ALT + [0-9]
for i = 1, 10 do
    local key = tostring(i % 10)
    bind(mainMod .. " + " .. key,                 hl.dsp.focus({ workspace = i }))
    bind(mainMod .. " + SHIFT + " .. key,         hl.dsp.window.move({ workspace = i }))
    bind(mainMod .. " + ALT + " .. key,           hl.dsp.focus({ workspace = i + 10 }))
    bind(mainMod .. " + SHIFT + ALT + " .. key,   hl.dsp.window.move({ workspace = i + 10 }))
end

bind(mainMod .. " + TAB",        hl.dsp.focus({ workspace = "previous" }))
bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mouse move/resize
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media and brightness: work on the lock screen, volume/brightness repeat
local held   = { locked = true, repeating = true }
local locked = { locked = true }

bind("XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+"), held)
bind("XF86AudioLowerVolume",  exec("wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-"), held)
bind("XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       locked)
bind("XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     locked)
bind("XF86MonBrightnessUp",   exec("brightnessctl set +10%"),                           held)
bind("XF86MonBrightnessDown", exec("brightnessctl set 10%-"),                           held)
bind("XF86AudioNext",         exec("playerctl next"),                                   locked)
bind("XF86AudioPause",        exec("playerctl play-pause"),                             locked)
bind("XF86AudioPlay",         exec("playerctl play-pause"),                             locked)
bind("XF86AudioPrev",         exec("playerctl previous"),                               locked)
