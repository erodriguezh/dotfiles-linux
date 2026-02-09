#!/usr/bin/env bash
# lib/01-repos.sh — Repository setup: dnf5 plugins, COPRs, linux-surface repo
# Sourced by install.sh. Defines run_repos() only.

# ---------------------------------------------------------------------------
# run_repos — Install dnf5 plugins, enable COPRs, add linux-surface repo
# ---------------------------------------------------------------------------

run_repos() {
    # -- Step 1: Install dnf5 plugins (copr + config-manager subcommands) ----
    info "Installing dnf5 plugins..."
    sudo "$DNF" install -y dnf5-plugins

    # Verify plugins are functional
    if ! "$DNF" copr --help &>/dev/null; then
        error "dnf5 copr plugin is not functional after installing dnf5-plugins"
        exit 1
    fi
    if ! "$DNF" config-manager --help &>/dev/null; then
        error "dnf5 config-manager plugin is not functional after installing dnf5-plugins"
        exit 1
    fi
    success "dnf5 plugins verified (copr, config-manager)"

    # -- Step 2: Enable COPR repositories ------------------------------------
    local -a coprs=(
        "sdegler/hyprland"
        "scottames/ghostty"
        "alternateved/tofi"
    )

    for copr in "${coprs[@]}"; do
        info "Enabling COPR: ${copr}..."
        sudo "$DNF" copr enable -y "$copr"
    done
    success "All COPR repositories enabled"

    # -- Step 3: Add linux-surface external repo -----------------------------
    info "Adding linux-surface repository..."
    sudo "$DNF" config-manager addrepo \
        --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo \
        --overwrite
    success "linux-surface repository added"

    # Log active repos for debugging
    info "Active repositories:"
    sudo "$DNF" repolist --enabled 2>/dev/null || true

    # -- Step 4: Remove stale solopasha COPR if present ----------------------
    sudo "$DNF" copr remove -y solopasha/hyprland &>/dev/null || true
}
