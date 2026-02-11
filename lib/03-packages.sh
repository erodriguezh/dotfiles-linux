#!/usr/bin/env bash
# lib/03-packages.sh — Install all desktop and system packages
# Sourced by install.sh. Defines run_packages() only.

# ---------------------------------------------------------------------------
# run_packages — Install full package set from COPR + Fedora repos
# ---------------------------------------------------------------------------

run_packages() {
    info "Installing desktop and system packages..."

    local -a pkgs=(
        # Hyprland ecosystem (sdegler/hyprland COPR)
        hyprland
        hyprlock
        hypridle
        hyprpaper
        hyprpolkitagent
        hyprland-guiutils
        waybar-git
        cliphist
        uwsm
        xdg-desktop-portal-hyprland

        # Terminal (scottames/ghostty COPR)
        ghostty

        # App launcher (alternateved/tofi COPR)
        tofi

        # XDG portal stack
        xdg-desktop-portal
        xdg-desktop-portal-gtk

        # Bluetooth
        bluez

        # Power management
        tuned
        tuned-ppd

        # Audio/video
        wireplumber
        pipewire
        pipewire-pulseaudio
        pipewire-alsa

        # Notifications
        mako

        # Screenshots
        grim
        slurp

        # Networking
        NetworkManager
        NetworkManager-wifi
        iwd

        # Firmware (surface kernel may need newer iwlwifi ucode than base install)
        linux-firmware

        # Keybind tools
        brightnessctl
        playerctl

        # System utilities
        plymouth
        polkit
        wl-clipboard
        curl
        jq
        git
        tar
        unzip

        # Neovim + deps
        neovim
        tree-sitter-cli

        # Prompt — starship installed in binaries stage (not in Fedora repos)
    )

    sudo "$DNF" install -y "${pkgs[@]}"

    success "All packages installed"
}
