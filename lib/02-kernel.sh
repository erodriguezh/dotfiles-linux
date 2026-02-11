#!/usr/bin/env bash
# lib/02-kernel.sh — Surface kernel installation from linux-surface repo
# Sourced by install.sh. Defines run_kernel() only.

# ---------------------------------------------------------------------------
# run_kernel — Install kernel-surface and libwacom-surface
# ---------------------------------------------------------------------------
# Note: iptsd (touchscreen) is intentionally NOT installed — touchscreen is
# disabled per project design decision. Can be installed manually later.

run_kernel() {
    # Skip on non-Surface hardware (allows VM/other-hardware testing)
    if ! is_surface_hardware; then
        warn "Non-Surface hardware detected — skipping kernel stage"
        return 0
    fi

    info "Installing Surface kernel and hardware support packages..."
    sudo "$DNF" install -y --allowerasing \
        kernel-surface \
        libwacom-surface

    # -- Ensure iwlwifi firmware for Surface kernel ----------------------------
    # The surface kernel may request a newer iwlwifi firmware API version than
    # the linux-firmware package provides. Fetch it from upstream if missing.
    _kernel_ensure_iwlwifi_firmware

    success "Surface kernel and hardware packages installed"
}

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_kernel_ensure_iwlwifi_firmware() {
    local fw_dir="/lib/firmware"
    local fw_name="iwlwifi-cc-a0-77.ucode"

    if [[ -f "${fw_dir}/${fw_name}" ]]; then
        info "iwlwifi firmware ${fw_name} already present — skipping"
        return 0
    fi

    local fw_url="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/${fw_name}"
    info "Downloading missing iwlwifi firmware ${fw_name}..."
    if sudo curl -fSLo "${fw_dir}/${fw_name}" "$fw_url"; then
        success "iwlwifi firmware ${fw_name} installed"
    else
        warn "Failed to download ${fw_name} — WiFi may not work until firmware is available"
    fi
}
