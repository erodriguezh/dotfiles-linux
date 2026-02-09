#!/usr/bin/env bash
# lib/08-desktop.sh — Getty auto-login, plymouth theme, XDG portal, UWSM env
# Sourced by install.sh. Defines run_desktop() only.

# ---------------------------------------------------------------------------
# run_desktop — Configure desktop session prerequisites
# ---------------------------------------------------------------------------

run_desktop() {
    local target_user
    target_user="$(whoami)"

    # -- Getty auto-login override --------------------------------------------
    _desktop_getty_autologin "$target_user"

    # -- Plymouth theme -------------------------------------------------------
    _desktop_plymouth_theme

    # -- XDG portal config ----------------------------------------------------
    _desktop_xdg_portal

    # -- UWSM env files ------------------------------------------------------
    _desktop_uwsm_env

    # -- systemd user environment ---------------------------------------------
    _desktop_systemd_user_env

    success "Desktop session configuration complete"
}

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_desktop_getty_autologin() {
    local user="$1"
    local dropin_dir="/etc/systemd/system/getty@tty1.service.d"
    local dropin_file="${dropin_dir}/override.conf"

    info "Configuring getty auto-login for '${user}' on tty1..."

    sudo mkdir -p "$dropin_dir"

    # Write the override with single-quoted heredoc to preserve literal $TERM,
    # then substitute the username via sed.
    sudo tee "$dropin_file" >/dev/null <<'GETTY_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin @@USER@@ --noclear %I $TERM
GETTY_EOF

    # Replace @@USER@@ placeholder with the actual username.
    # Use a delimiter unlikely to appear in usernames to avoid sed injection.
    local escaped_user
    escaped_user="$(printf '%s\n' "$user" | sed 's/[&/\]/\\&/g')"
    sudo sed -i "s/@@USER@@/${escaped_user}/" "$dropin_file"

    sudo systemctl daemon-reload
    success "Getty auto-login override written and daemon reloaded"
}

_desktop_plymouth_theme() {
    local desired_theme="spinner"

    info "Checking plymouth theme..."

    if ! command -v plymouth-set-default-theme &>/dev/null; then
        warn "plymouth-set-default-theme not found — skipping plymouth theme"
        return 0
    fi

    # Check current theme; only rebuild initrd if changed
    local current_theme
    current_theme="$(plymouth-set-default-theme 2>/dev/null || echo "")"

    if [[ "$current_theme" == "$desired_theme" ]]; then
        info "Plymouth theme already set to '${desired_theme}' — skipping initrd rebuild"
        return 0
    fi

    info "Setting plymouth theme to '${desired_theme}'..."
    if sudo plymouth-set-default-theme "$desired_theme" -R; then
        success "Plymouth theme set to '${desired_theme}' (initrd rebuilt)"
    else
        warn "Failed to set plymouth theme — continuing"
    fi
}

_desktop_xdg_portal() {
    local portal_dir="${HOME}/.config/xdg-desktop-portal"
    local portal_file="${portal_dir}/portals.conf"

    info "Writing XDG portal configuration..."

    mkdir -p "$portal_dir"
    cat > "$portal_file" <<'EOF'
[preferred]
default=hyprland;gtk
EOF

    success "XDG portal config written"
}

_desktop_uwsm_env() {
    local uwsm_dir="${HOME}/.config/uwsm"

    info "Writing UWSM environment files..."

    mkdir -p "$uwsm_dir"

    # -- env (shared theming variables) ---------------------------------------
    cat > "${uwsm_dir}/env" <<'EOF'
export XCURSOR_SIZE=24
export GDK_SCALE=1
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export MOZ_ENABLE_WAYLAND=1
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1
EOF

    # -- env-hyprland (Hyprland-specific variables) ---------------------------
    cat > "${uwsm_dir}/env-hyprland" <<'EOF'
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
EOF

    success "UWSM env files written"
}

_desktop_systemd_user_env() {
    local env_dir="${HOME}/.config/environment.d"
    local env_file="${env_dir}/surface-linux.conf"

    info "Writing systemd user environment file..."

    mkdir -p "$env_dir"
    cat > "$env_file" <<'EOF'
XCURSOR_SIZE=24
GDK_SCALE=1
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
MOZ_ENABLE_WAYLAND=1
SDL_VIDEODRIVER=wayland
_JAVA_AWT_WM_NONREPARENTING=1
EOF

    success "systemd user environment file written"
}
