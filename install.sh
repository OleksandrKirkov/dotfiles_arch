#!/bin/bash

set -e

sudo pacman -Syu --noconfirm

sudo pacman -S --noconfirm neovim python-pynvim git nodejs \
    npm curl zsh nvidia nvidia-utils nvidia-settings nvidia-prime \
    hyprland xdg-desktop-portal-hyprland wlroots wayland xorg-xwayland \
    polkit-kde-agent dunst rofi kitty waybar wofi foot thunar hyprpaper

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
