#!/usr/bin/env bash
# lib/05-fonts.sh — Download and install JetBrains Mono Nerd Font
# Sourced by install.sh. Defines run_fonts() only.

# ---------------------------------------------------------------------------
# run_fonts — Install JetBrains Mono Nerd Font from GitHub
# ---------------------------------------------------------------------------

run_fonts() {
    local nf_version="3.3.0"
    local font_name="JetBrainsMono"
    local font_dir="${HOME}/.local/share/fonts/${font_name}"

    # Check if already installed at expected version
    if [[ -d "$font_dir" && -f "${font_dir}/.nf-version" ]]; then
        local installed_version
        installed_version="$(cat "${font_dir}/.nf-version")"
        if [[ "$installed_version" == "$nf_version" ]]; then
            info "JetBrains Mono Nerd Font v${nf_version} already installed — skipping"
            return 0
        fi
    fi

    info "Downloading JetBrains Mono Nerd Font v${nf_version}..."

    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v${nf_version}/${font_name}.tar.xz"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    if ! curl -fSL "$url" -o "${tmp_dir}/${font_name}.tar.xz"; then
        error "Failed to download JetBrains Mono Nerd Font"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Extract and install
    mkdir -p "$font_dir"
    tar xf "${tmp_dir}/${font_name}.tar.xz" -C "$font_dir"
    rm -rf "$tmp_dir"

    # Record version for idempotency
    echo "$nf_version" > "${font_dir}/.nf-version"

    # Rebuild font cache
    info "Rebuilding font cache..."
    fc-cache -f

    success "JetBrains Mono Nerd Font v${nf_version} installed"
}
