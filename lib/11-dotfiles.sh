#!/usr/bin/env bash
# lib/11-dotfiles.sh — Config deployment: symlinks, aliases, wallpapers, UWSM
# Sourced by install.sh. Defines run_dotfiles() only.
#
# Prerequisites: theme stage must have generated color config files first.

# ---------------------------------------------------------------------------
# Config directories to symlink from config/ -> ~/.config/
# ---------------------------------------------------------------------------

# Each entry maps a directory under REPO_DIR/config/ to ~/.config/<name>.
# Directories listed here will be symlinked with ln -snfT.
_DOTFILES_SYMLINK_DIRS=(
    hypr
    waybar
    mako
    ghostty
    tofi
    nvim
    bashrc.d
    gtk-3.0
    gtk-4.0
    starship
)

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_dotfiles_symlink_dir() {
    # Symlink a directory from config/ to ~/.config/ using ln -snfT.
    # If the destination is an existing real directory (not a symlink),
    # back it up first (removing any prior .bak to prevent nesting).
    local src="$1"
    local dst="$2"
    local name
    name="$(basename "$dst")"

    if [[ -d "$dst" ]] && [[ ! -L "$dst" ]]; then
        # Destination is a real directory — back it up
        local backup="${dst}.bak"
        if [[ -e "$backup" ]]; then
            info "Removing existing backup: ${backup}"
            rm -rf "$backup"
        fi
        info "Backing up existing directory: ${dst} -> ${backup}"
        mv "$dst" "$backup"
    fi

    ln -snfT "$src" "$dst"
    info "Symlinked: ${name}/ -> ${src}"
}

_dotfiles_deploy_local_bin() {
    # Symlink helper scripts from config/local-bin/ to ~/.local/bin/.
    local src_dir="${REPO_DIR}/config/local-bin"
    local dst_dir="${HOME}/.local/bin"

    if [[ ! -d "$src_dir" ]]; then
        info "No config/local-bin/ directory — skipping helper scripts"
        return 0
    fi

    mkdir -p "$dst_dir"

    local count=0
    local f name
    for f in "$src_dir"/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        ln -snf "$f" "${dst_dir}/${name}"
        [[ -x "$f" ]] || chmod +x "$f"
        count=$(( count + 1 ))
    done

    if [[ $count -gt 0 ]]; then
        success "Deployed ${count} helper script(s) to ~/.local/bin/"
    else
        info "No helper scripts found in config/local-bin/"
    fi
}

_dotfiles_copy_wallpapers() {
    # Copy wallpapers from assets/wallpapers/ to a stable location under
    # ~/.local/share/wallpapers/surface-linux/. Hyprpaper needs stable
    # absolute paths that work even if the repo moves.
    local src_dir="${REPO_DIR}/assets/wallpapers"
    local dst_dir="${HOME}/.local/share/wallpapers/surface-linux"

    if [[ ! -d "$src_dir" ]]; then
        warn "assets/wallpapers/ not found — skipping wallpaper deployment"
        return 0
    fi

    mkdir -p "$dst_dir"

    # Copy the first wallpaper as the canonical wallpaper.png
    # (hyprpaper.conf references wallpaper.png)
    local first_wallpaper=""
    for f in "$src_dir"/*; do
        [[ -f "$f" ]] || continue
        first_wallpaper="$f"
        break
    done

    if [[ -z "$first_wallpaper" ]]; then
        warn "No wallpaper files found in assets/wallpapers/"
        return 0
    fi

    # Copy the primary wallpaper as wallpaper.png (what hyprpaper.conf expects)
    cp -f "$first_wallpaper" "${dst_dir}/wallpaper.png"
    info "Primary wallpaper: $(basename "$first_wallpaper") -> wallpaper.png"

    # Also copy all wallpapers by their original names for user switching
    local count=0
    for f in "$src_dir"/*; do
        [[ -f "$f" ]] || continue
        cp -f "$f" "${dst_dir}/$(basename "$f")"
        count=$(( count + 1 ))
    done

    success "Copied ${count} wallpaper(s) to ${dst_dir}/"
}

_dotfiles_deploy_xresources() {
    # Write ~/.Xresources for XWayland DPI scaling.
    # Loaded at session start by: exec-once = xrdb -merge ~/.Xresources
    local xresources="${HOME}/.Xresources"

    local desired_content="Xft.dpi: 144"

    if [[ -f "$xresources" ]] && grep -qxF "$desired_content" "$xresources"; then
        info ".Xresources already configured — skipping"
        return 0
    fi

    # Upsert: update existing Xft.dpi line if present, otherwise append
    if [[ -f "$xresources" ]] && grep -qE '^[[:space:]]*Xft\.dpi:' "$xresources"; then
        sed -i -E 's/^[[:space:]]*Xft\.dpi:.*/Xft.dpi: 144/' "$xresources"
        success "Updated ~/.Xresources (Xft.dpi: 144 for 1.5x scaling)"
        return 0
    fi

    printf '%s\n' "$desired_content" >> "$xresources"
    success "Appended to ~/.Xresources (Xft.dpi: 144 for 1.5x scaling)"
}

_dotfiles_bashrc_sourcing() {
    # Append a sourcing loop to ~/.bashrc that sources all files from
    # ~/.config/bashrc.d/*.sh. Guarded with grep -qF to prevent duplicates.
    local bashrc="${HOME}/.bashrc"
    local guard_string='# Source modular config from bashrc.d'

    if [[ -f "$bashrc" ]] && grep -qF "$guard_string" "$bashrc"; then
        info ".bashrc already sources bashrc.d/ — skipping"
        return 0
    fi

    cat >> "$bashrc" <<'BASHRC_BLOCK'

# Source modular config from bashrc.d
if [[ -d "${HOME}/.config/bashrc.d" ]]; then
    for _bashrc_f in "${HOME}"/.config/bashrc.d/*.sh; do
        [[ -f "$_bashrc_f" ]] && source "$_bashrc_f"
    done
    unset _bashrc_f
fi
BASHRC_BLOCK

    success "Appended bashrc.d sourcing loop to ~/.bashrc"
}

_dotfiles_bash_profile_uwsm() {
    # Add UWSM auto-start snippet to ~/.bash_profile (login shell only).
    # This starts Hyprland automatically on TTY login via UWSM.
    # MUST be in .bash_profile, NOT .bashrc — otherwise every subshell
    # would try to start Hyprland.
    local bash_profile="${HOME}/.bash_profile"
    local guard_string='# Auto-start Hyprland via UWSM on TTY login'

    if [[ -f "$bash_profile" ]] && grep -qF "$guard_string" "$bash_profile"; then
        info ".bash_profile already has UWSM snippet — skipping"
        return 0
    fi

    cat >> "$bash_profile" <<'UWSM_BLOCK'

# Auto-start Hyprland via UWSM on TTY login
if command -v uwsm &>/dev/null && uwsm check may-start; then
    exec uwsm start hyprland.desktop
fi
UWSM_BLOCK

    success "Appended UWSM auto-start snippet to ~/.bash_profile"
}

# ---------------------------------------------------------------------------
# run_dotfiles — Deploy all config files and shell integration
# ---------------------------------------------------------------------------

run_dotfiles() {
    info "Deploying dotfiles and configuration..."

    # -- Symlink config directories to ~/.config/ ------------------------------
    info "Creating config directory symlinks..."
    mkdir -p "${HOME}/.config"

    local dir src dst
    for dir in "${_DOTFILES_SYMLINK_DIRS[@]}"; do
        src="${CONFIG_DIR}/${dir}"
        dst="${HOME}/.config/${dir}"

        if [[ ! -d "$src" ]]; then
            warn "Config directory not found: config/${dir}/ — skipping"
            continue
        fi

        _dotfiles_symlink_dir "$src" "$dst"
    done

    success "Config directory symlinks created"

    # -- Deploy helper scripts to ~/.local/bin/ --------------------------------
    _dotfiles_deploy_local_bin

    # -- Copy wallpapers -------------------------------------------------------
    _dotfiles_copy_wallpapers

    # -- Deploy .Xresources ----------------------------------------------------
    _dotfiles_deploy_xresources

    # -- Configure .bashrc sourcing loop ---------------------------------------
    _dotfiles_bashrc_sourcing

    # -- Configure .bash_profile UWSM auto-start ------------------------------
    _dotfiles_bash_profile_uwsm

    success "Dotfiles deployment complete"
}
