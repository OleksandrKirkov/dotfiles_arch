local terminal = "ghostty"

return {
    terminal            = terminal,
    editor              = "nvim",
    browser             = "flatpak run com.brave.Browser",
    music               = "flatpak run com.spotify.Client",
    messenger           = "Telegram",
    fileManagerTerminal = terminal .. " -e yazi",
    fileManagerGUI      = "nautilus",
    menu                = "rofi -show drun",
    clipboard           = "cliphist list | rofi -dmenu -p clipboard | cliphist decode | wl-copy",
}
