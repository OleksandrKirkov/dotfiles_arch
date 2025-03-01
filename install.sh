#!/bin/bash

set -e

sudo pacman -Syu --noconfirm

sudo pacman -S --noconfirm neovim python-pynvim git nodejs \
    npm curl zsh nvidia nvidia-utils nvidia-settings nvidia-prime \
    hyprland xdg-desktop-portal-hyprland wlroots wayland xorg-xwayland \
    polkit-kde-agent dunst rofi kitty waybar wofi foot thunar hyprpaper

sudo pacman -S --noconfirm hyprland noto-fonts noto-fonts-cjk noto-fonts-emoji

sudo pacman -S --needed git base-devel

git clone https://aur.archlinux.org/yay.git

cd yay
makepkg -si
cd ..
rm -rf yay

if [ -d "$HOME/.config/nvim" ]; then
    echo "[Error]: nvim folder is exist. Deleting..."
    rm -rf "$HOME/.config/nvim"
fi

git clone https://github.com/OleksandrKirkov/nvim.git ~/.config/nvim

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
