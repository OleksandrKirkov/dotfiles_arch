-- Monitors and workspace placement.
--
-- Docked (laptop + external connected):
--   laptop   -> workspace LAPTOP_WORKSPACE only
--   external -> every other workspace (FIRST..LAST_WORKSPACE)
-- Laptop only:
--   laptop   -> all workspaces
--
-- Placement is re-applied on config load and on every monitor hotplug.

local LAPTOP           = "eDP-1"
local EXTERNAL         = "HDMI-A-1"
local LAPTOP_WORKSPACE = 1
local FIRST_WORKSPACE  = 1
local LAST_WORKSPACE   = 20 -- binds.lua: SUPER + [0-9] -> 1-10, SUPER + ALT + [0-9] -> 11-20

-- Outputs

-- Fallback for any other display (projector, second external, ...)
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.monitor({
    output   = EXTERNAL,
    mode     = "3440x1440@99.98",
    position = "0x0",
    scale    = 1,
    bitdepth = 10,
})

hl.monitor({
    output   = LAPTOP,
    mode     = "1920x1080@120",
    position = "3440x0",
    scale    = 1,
})

-- Workspace rules: active only while docked. Undocked, no rule applies, so
-- every workspace opens on the laptop.

local docked_rules = {
    hl.workspace_rule({ workspace = tostring(LAPTOP_WORKSPACE), monitor = LAPTOP, default = true }),
}

local external_default_set = false
for id = FIRST_WORKSPACE, LAST_WORKSPACE do
    if id ~= LAPTOP_WORKSPACE then
        docked_rules[#docked_rules + 1] = hl.workspace_rule({
            workspace = tostring(id),
            monitor   = EXTERNAL,
            default   = not external_default_set,
        })
        external_default_set = true
    end
end

local function connected(name, removed)
    if name == removed then return false end
    for _, m in ipairs(hl.get_monitors()) do
        if m.name == name then return true end
    end
    return false
end

-- removed: name of a monitor being unplugged (still listed during monitor.removed)
local function apply(removed)
    local docked = connected(LAPTOP, removed) and connected(EXTERNAL, removed)

    for _, rule in ipairs(docked_rules) do
        rule:set_enabled(docked)
    end

    -- Undocked: Hyprland itself moves the unplugged monitor's workspaces to
    -- the remaining one, and no rule pins anything elsewhere.
    if not docked then return end

    -- Laptop workspace first, so the laptop never ends up showing nothing.
    local laptop_ws = hl.get_workspace(LAPTOP_WORKSPACE)
    if laptop_ws and laptop_ws.monitor and laptop_ws.monitor.name ~= LAPTOP then
        hl.dispatch(hl.dsp.workspace.move({ workspace = LAPTOP_WORKSPACE, monitor = LAPTOP }))
    end

    for _, ws in ipairs(hl.get_workspaces()) do
        if not ws.special and ws.id ~= LAPTOP_WORKSPACE
            and ws.monitor and ws.monitor.name == LAPTOP then
            hl.dispatch(hl.dsp.workspace.move({ workspace = ws.id, monitor = EXTERNAL }))
        end
    end
end

hl.on("monitor.added", function() apply() end)
hl.on("monitor.removed", function(m) apply(m and m.name) end)
apply()
