#!/usr/bin/env bash
# clipboard-history.sh — Show clipboard history via tofi and paste selection
# Called by Hyprland keybind (SUPER+C)

set -euo pipefail

selected="$(cliphist list | tofi)"

if [[ -n "$selected" ]]; then
    echo "$selected" | cliphist decode | wl-copy
fi
