local terminal = "ghostty"

return {
    terminal            = terminal,
    editor              = "nvim",
    browser             = "flatpak run com.brave.Browser",
    fileManagerTerminal = terminal .. " -e yazi",
    fileManagerGUI      = "nautilus",
    menu                = "wofi --show drun",
}
