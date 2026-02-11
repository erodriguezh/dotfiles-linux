#!/usr/bin/env bash
# lib/04-binaries.sh — Download and install pre-built binaries from GitHub
# Sourced by install.sh. Defines run_binaries() only.

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_binaries_ensure_local_bin() {
    local local_bin="$1"
    if [[ ! -d "$local_bin" ]]; then
        info "Creating ${local_bin}..."
        mkdir -p "$local_bin"
    fi
}

_binaries_map_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  echo "x86_64" ;;
        aarch64) echo "aarch64" ;;
        *)
            error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

_binaries_install() {
    local name="$1"
    local version="$2"
    local url="$3"
    local local_bin="$4"
    local dest="${local_bin}/${name}"

    # Check if binary already exists with the expected version
    if [[ -x "$dest" ]]; then
        local current_version
        current_version="$("$dest" --version 2>&1 || true)"
        if [[ "$current_version" == *"$version"* ]]; then
            info "${name} v${version} already installed — skipping"
            return 0
        fi
    fi

    info "Downloading ${name} v${version}..."

    # Download to temp file and atomically move on success
    local tmp
    tmp="$(mktemp "${dest}.tmp.XXXXXX")"
    if curl -fSL "$url" -o "$tmp"; then
        chmod +x "$tmp"
        mv -f "$tmp" "$dest"
        success "${name} v${version} installed to ${dest}"
    else
        rm -f "$tmp"
        error "Failed to download ${name} v${version}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# run_binaries — Download Impala and bluetui from GitHub Releases
# ---------------------------------------------------------------------------

run_binaries() {
    local impala_version="0.7.3"
    local bluetui_version="0.8.1"
    local local_bin="${HOME}/.local/bin"

    _binaries_ensure_local_bin "$local_bin"

    local arch
    arch="$(_binaries_map_arch)"

    # -- Impala (WiFi TUI) ---------------------------------------------------
    local impala_url="https://github.com/pythops/impala/releases/download/v${impala_version}/impala-${arch}-unknown-linux-musl"
    _binaries_install "impala" "$impala_version" "$impala_url" "$local_bin"

    # -- bluetui (Bluetooth TUI) ---------------------------------------------
    local bluetui_url="https://github.com/pythops/bluetui/releases/download/v${bluetui_version}/bluetui-${arch}-linux-musl"
    _binaries_install "bluetui" "$bluetui_version" "$bluetui_url" "$local_bin"

    # -- Starship (prompt) — not in Fedora repos ----------------------------
    local starship_version="1.23.0"
    local starship_url="https://github.com/starship/starship/releases/download/v${starship_version}/starship-${arch}-unknown-linux-musl.tar.gz"
    if [[ -x "${local_bin}/starship" ]]; then
        local current_version
        current_version="$(${local_bin}/starship --version 2>&1 || true)"
        if [[ "$current_version" == *"$starship_version"* ]]; then
            info "starship v${starship_version} already installed — skipping"
        fi
    else
        info "Downloading starship v${starship_version}..."
        local tmp_dir
        tmp_dir="$(mktemp -d)"
        if curl -fSL "$starship_url" | tar xz -C "$tmp_dir"; then
            chmod +x "${tmp_dir}/starship"
            mv -f "${tmp_dir}/starship" "${local_bin}/starship"
            success "starship v${starship_version} installed to ${local_bin}/starship"
        else
            error "Failed to download starship v${starship_version}"
            rm -rf "$tmp_dir"
            return 1
        fi
        rm -rf "$tmp_dir"
    fi

    success "All pre-built binaries installed"
}
