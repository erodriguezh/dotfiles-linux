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

    success "Surface kernel and hardware packages installed"
}
