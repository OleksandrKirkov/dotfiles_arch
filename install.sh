#!/bin/bash

set -e

sudo pacman -Syu --noconfirm

sudo pacman -S --noconfirm neovim python-pynvim git nodejs \
    npm curl zsh

if [ -d "$HOME/.config/nvim" ]; then
    echo "[Error]: nvim folder is exist. Deleting..."
    rm -rf "$HOME/.config/nvim"
fi

git clone https://github.com/OleksandrKirkov/nvim.git ~/.config/nvim

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
