#!/usr/bin/env bash
# lib/12-services.sh — Enable system services and set tuned profile
# Sourced by install.sh. Defines run_services() only.

# ---------------------------------------------------------------------------
# run_services — Enable required system services
# ---------------------------------------------------------------------------
# Note: iptsd.service is intentionally NOT enabled (touchscreen disabled).
# Note: iwd.service is NOT manually enabled (NetworkManager manages it).

run_services() {
    info "Enabling system services..."

    local -a services=(
        NetworkManager.service
        bluetooth.service
        tuned.service
        tuned-ppd.service
    )

    local svc
    for svc in "${services[@]}"; do
        _services_enable "$svc"
    done

    # -- Set tuned profile to powersave ---------------------------------------
    info "Setting tuned profile to 'powersave'..."
    if command -v tuned-adm &>/dev/null; then
        sudo tuned-adm profile powersave || warn "Failed to set tuned profile (may work after reboot)"
        success "Tuned profile set to 'powersave'"
    else
        warn "tuned-adm not found — tuned profile will need to be set manually after reboot"
    fi

    success "All services enabled"
}

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_services_enable() {
    local svc="$1"

    # Verify the unit file is actually present before enabling.
    # systemctl list-unit-files always returns 0, so check output for a match.
    local unit_match
    unit_match="$(systemctl list-unit-files --no-legend "$svc" 2>/dev/null | grep -F "$svc" || true)"
    if [[ -z "$unit_match" ]]; then
        warn "Unit '${svc}' not found — check that the required package is installed (see packages stage)"
        return 0
    fi

    info "Enabling ${svc}..."
    sudo systemctl enable "$svc"
    success "${svc} enabled"
}
