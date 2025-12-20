#!/bin/bash

set -e

cat <<"EOF"

-------------------------------------------------

              ___           _     
             / _ \         | |    
            / /_\ \_ __ ___| |__  
            |  _  | '__/ __| '_ \ 
            | | | | | | (__| | | |
            \_| |_/_|  \___|_| |_|
                      
                      
-------------------------------------------------

EOF

echo "Update system..."
sudo pacman -Syu --noconfirm

echo "Installing packages..."

PACMAN_PACKAGES=(
    sudo
    git
    wget
    zip
    parallel
    jq
    fastfetch
    btop
    stow

    zsh
    ghostty
    neovim
    nano

    hyprland
    hypridle
    hyprlock
    hyprpaper
    hyprpicker
    hyprsunset
    waybar
    rofi
    wofi
    dunst
    wlogout
    grim
    slurp

    pavucontrol
    pipewire
    pipewire-alsa
    pipewire-pulse
    sof-firmware

    networkmanager
    network-manager-applet
    iwd
    bluez
    bluez-utils
    udiskie

    firefox
    chromium
    telegram-desktop
    obsidian

    go
    kotlin
    nodejs
    npm
    jdk-openjdk
    jdk21-openjdk
    maven
    cmake
    ccls
    python-pynvim
    lazygit

    yazi
    discord
    obs-studio
    tree
    ranger
    cmatrix
    imv

    nvidia
    nvidia-utils
    nvidia-settings
)

sudo pacman -S --noconfirm neovim python-pynvim git nodejs \
    npm curl zsh nvidia nvidia-utils nvidia-settings nvidia-prime \
    hyprland xdg-desktop-portal-hyprland wlroots wayland xorg-xwayland \
    polkit-kde-agent dunst rofi kitty waybar wofi foot thunar hyprpaper flatpack

sudo pacman -S --noconfirm hyprland noto-fonts noto-fonts-cjk noto-fonts-emoji

sudo pacman -S --needed git base-devel

echo "Installing yay..."
if ! command -v yay &>/dev/null; then
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
    cd ..
    rm -rf yay
fi

AUR_PACKAGES=(
    httptoolkit
    wlogout
    youtube-music-bin
    ttf-jetbrains-mono-nerd
)

yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"

FLATPACK_APPS=(
    app.zen_browser.zen
    com.spotify.Client
    org.blender.Blender
    rest.insomnia.Insomnia
    com.mojang.Minecraft
    us.zoom.Zoom
    com.google.AndroidStudio
    com.valvesoftware.Steam
    org.pgadmin.pgadmin4
)

sudo flatpak install -y "${FLATPACK_APPS[@]}"

echo "Install npm packages..."
npm install eslint_d vscode-langservers-extracted

echo "Installing Neovim config..."
NVIM_DIR="$HOME/.config/nvim"
if [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/OleksandrKirkov/nvim.git "$NVIM_DIR"
fi

echo "Installing oh-my-zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

echo "Installing zsh plugins..."

# zsh-autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# zsh-syntax-highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

echo "Delete existing dotfiles..."

CONFIG_DIR="$HOME/.config"

DIR=(
    "$CONFIG_DIR/create-next-app-nodejs"
    "$CONFIG_DIR/dunst"
    "$CONFIG_DIR/ghostty"
    "$CONFIG_DIR/hypr"
    "$CONFIG_DIR/rofi"
    "$CONFIG_DIR/waybar"
    "$CONFIG_DIR/wofi"
    "$HOME/.gitconfig"
    "$HOME/.zshrc"
    "$HOME/.npmrc"
)

for dir in "${DIR[@]}"; do
    if [ -f "$dir" ]; then
        rm -r "$dir"
        echo "Delete dir: $dir"
    else
        echo "Dir not found: $dir"
    fi
done

echo "Setting up dotfiles with Stow..."
sudo pacman -S --noconfirm stow
cd ~/dotfiles_arch
stow .

echo "Removing empty directories..."
find "$CONFIG_DIR" -type d -empty -delete

echo "Installing and configuration complete!"

echo "Do reboot? [Y,n]"
read input

case "$input" in
    [Nn]) echo "Do it later!" ;;
    *) echo reboot ;;
esac
