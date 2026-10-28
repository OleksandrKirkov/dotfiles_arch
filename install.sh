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

# Bootstrap this repo onto a fresh Arch install. Everything is per module:
# packages, services and install hooks (dotctl install), then links (dotctl apply).
# The modules for this machine are hosts/<hostname>.conf, or every module when
# that file does not exist.

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"

echo "Installing packages, services and tools..."
"$REPO/bin/dotctl" install

# Anything already in the way is moved to ~/.local/state/dotctl/backups/, never deleted.
echo "Linking modules..."
"$REPO/bin/dotctl" apply

echo "Selecting the default theme..."
"$HOME/.local/bin/theme-switch" --apply

# Migrations are no-ops on a fresh install; running them records them, so a
# later 'dotctl update' only runs the ones added after today.
echo "Running migrations..."
"$REPO/bin/dotctl" migrate

echo "Removing empty directories..."
find "$HOME/.config" -type d -empty -delete

echo "Installing and configuration complete! Check the result with: dotctl doctor"
