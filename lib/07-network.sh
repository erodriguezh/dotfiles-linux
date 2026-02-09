#!/usr/bin/env bash
# lib/07-network.sh — Configure NetworkManager to use iwd backend
# Sourced by install.sh. Defines run_network() only.

# ---------------------------------------------------------------------------
# run_network — Write iwd backend config for NetworkManager
# ---------------------------------------------------------------------------
# Does NOT restart NetworkManager (would drop WiFi during install).
# Config takes effect after reboot.

_network_find_cmd() {
    # Check common sbin paths explicitly — command -v may miss /usr/sbin tools
    local cmd="$1"
    command -v "$cmd" &>/dev/null && return 0
    [[ -x "/usr/sbin/${cmd}" ]] && return 0
    [[ -x "/sbin/${cmd}" ]] && return 0
    return 1
}

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
    if _network_find_cmd restorecon; then
        sudo restorecon -R /etc/NetworkManager || warn "restorecon failed — continuing"
    else
        warn "restorecon not found — skipping SELinux relabel"
    fi

    info "iwd backend configured. Takes effect after reboot."
}
