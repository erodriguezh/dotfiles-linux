#!/usr/bin/env bash
# lib/07-network.sh — Configure NetworkManager to use iwd backend
# Sourced by install.sh. Defines run_network() only.

# ---------------------------------------------------------------------------
# run_network — Write iwd backend config for NetworkManager
# ---------------------------------------------------------------------------
# Does NOT restart NetworkManager (would drop WiFi during install).
# Config takes effect after reboot.

run_network() {
    info "Configuring NetworkManager iwd backend..."

    # -- Write iwd backend config ---------------------------------------------
    sudo mkdir -p /etc/NetworkManager/conf.d
    info "Writing /etc/NetworkManager/conf.d/wifi-backend.conf..."
    sudo tee /etc/NetworkManager/conf.d/wifi-backend.conf >/dev/null <<'EOF'
[device]
wifi.backend=iwd
EOF
    success "NetworkManager iwd backend config written"

    # -- Restore SELinux contexts on conf.d files -----------------------------
    info "Restoring SELinux contexts on /etc/NetworkManager..."
    sudo restorecon -R /etc/NetworkManager

    info "iwd backend configured. Takes effect after reboot."
}
