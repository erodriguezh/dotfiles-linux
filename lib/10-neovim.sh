#!/usr/bin/env bash
# lib/10-neovim.sh — Neovim/LazyVim setup
# Sourced by install.sh. Defines run_neovim() only.
#
# Prerequisites: dotfiles stage must have symlinked ~/.config/nvim/ first.

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_neovim_check_version() {
    # Check Neovim version and warn if below required minimum for LazyVim v15.
    # Returns 0 if >= 0.11.2, 1 if below.
    local min_major=0 min_minor=11 min_patch=2

    local version_str
    version_str="$(nvim --version 2>/dev/null | head -1 || echo "")"

    if [[ -z "$version_str" ]]; then
        warn "Could not determine Neovim version"
        return 1
    fi

    # Extract version numbers from "NVIM v0.X.Y"
    if [[ "$version_str" =~ v([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"

        info "Detected Neovim v${major}.${minor}.${patch}"

        if (( major > min_major )) ||
           (( major == min_major && minor > min_minor )) ||
           (( major == min_major && minor == min_minor && patch >= min_patch )); then
            return 0
        else
            warn "Neovim ${major}.${minor}.${patch} is below ${min_major}.${min_minor}.${min_patch}"
            warn "LazyVim v15.x requires Neovim >= 0.11.2 — consider pinning LazyVim to v14.x"
            return 1
        fi
    else
        warn "Could not parse Neovim version from: ${version_str}"
        return 1
    fi
}

_neovim_bootstrap_lazy() {
    # Clone lazy.nvim to the standard data directory if not already present.
    local lazy_dir="${HOME}/.local/share/nvim/lazy/lazy.nvim"

    if [[ -d "$lazy_dir" ]]; then
        info "lazy.nvim already cloned — skipping"
        return 0
    fi

    info "Cloning lazy.nvim plugin manager..."
    git clone --filter=blob:none \
        https://github.com/folke/lazy.nvim.git \
        --branch=stable \
        "$lazy_dir"

    success "lazy.nvim cloned to ${lazy_dir}"
}

_neovim_sync_plugins() {
    # Run headless Neovim to install/sync all plugins.
    info "Running headless plugin sync (this may take a moment)..."

    local sync_output
    sync_output="$(nvim --headless "+Lazy! sync" +qa 2>&1)" || {
        warn "Neovim headless plugin sync returned non-zero exit"
        warn "Output: ${sync_output:-<empty>}"
        warn "Plugins may need manual sync — run :Lazy sync inside Neovim"
        return 0
    }

    success "Neovim plugin sync complete"
}

# ---------------------------------------------------------------------------
# run_neovim — Bootstrap LazyVim and sync plugins
# ---------------------------------------------------------------------------

run_neovim() {
    # Verify Neovim is installed
    if ! command -v nvim &>/dev/null; then
        error "Neovim is not installed — run packages stage first"
        return 1
    fi

    # Verify config is symlinked (dotfiles stage must have run)
    if [[ ! -f "${HOME}/.config/nvim/init.lua" ]]; then
        error "Neovim config not found at ~/.config/nvim/init.lua"
        error "Run the dotfiles stage first to symlink config"
        return 1
    fi

    # Check version compatibility — warn but don't block
    # Fedora 43 ships Neovim >= 0.11.2; older versions may break LazyVim v15+
    if ! _neovim_check_version; then
        warn "Neovim version is below 0.11.2 — LazyVim may not work correctly"
        warn "Consider: sudo dnf5 update neovim"
    fi

    # Clone lazy.nvim if needed
    _neovim_bootstrap_lazy

    # Sync plugins headlessly
    _neovim_sync_plugins

    success "Neovim/LazyVim setup complete"
}
