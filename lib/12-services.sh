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
    local skipped=0
    for svc in "${services[@]}"; do
        if ! _services_enable "$svc"; then
            skipped=$(( skipped + 1 ))
        fi
    done

    # -- Set tuned profile to powersave ---------------------------------------
    info "Setting tuned profile to 'powersave'..."
    if _services_find_cmd tuned-adm; then
        if sudo tuned-adm profile powersave; then
            success "Tuned profile set to 'powersave'"
        else
            warn "Failed to set tuned profile (may work after reboot)"
        fi
    else
        warn "tuned-adm not found — tuned profile will need to be set manually after reboot"
    fi

    if [[ "$skipped" -gt 0 ]]; then
        warn "Service enablement complete (${skipped} unit(s) skipped — see warnings above)"
    else
        success "All services enabled"
    fi
}

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_services_find_cmd() {
    # Check common sbin paths explicitly — command -v may miss /usr/sbin tools
    # when running as a non-root user with a limited PATH.
    local cmd="$1"
    command -v "$cmd" &>/dev/null && return 0
    [[ -x "/usr/sbin/${cmd}" ]] && return 0
    [[ -x "/sbin/${cmd}" ]] && return 0
    return 1
}

_services_enable() {
    local svc="$1"

    # Verify the unit file is actually present before enabling.
    # Match the first column exactly to avoid false positives.
    local unit_match
    unit_match="$(systemctl list-unit-files --no-legend "$svc" 2>/dev/null \
        | awk -v name="$svc" '$1 == name {print $1}' || true)"
    if [[ -z "$unit_match" ]]; then
        warn "Unit '${svc}' not found — check that the required package is installed (see packages stage)"
        return 1
    fi

    info "Enabling ${svc}..."
    sudo systemctl enable "$svc"
    success "${svc} enabled"
}
