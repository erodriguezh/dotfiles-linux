#!/usr/bin/env bash
# lib/04-binaries.sh — Download and install pre-built binaries from GitHub
# Sourced by install.sh. Defines run_binaries() only.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly IMPALA_VERSION="0.7.3"
readonly BLUETUI_VERSION="0.8.1"
readonly LOCAL_BIN="${HOME}/.local/bin"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_ensure_local_bin() {
    if [[ ! -d "$LOCAL_BIN" ]]; then
        info "Creating ${LOCAL_BIN}..."
        mkdir -p "$LOCAL_BIN"
    fi
}

_map_arch() {
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

_install_binary() {
    local name="$1"
    local version="$2"
    local url="$3"
    local dest="${LOCAL_BIN}/${name}"

    # Check if binary already exists with the expected version
    if [[ -x "$dest" ]]; then
        local current_version
        current_version="$("$dest" --version 2>/dev/null || echo "")"
        if [[ "$current_version" == *"$version"* ]]; then
            info "${name} v${version} already installed — skipping"
            return 0
        fi
    fi

    info "Downloading ${name} v${version}..."
    curl -fSL "$url" -o "$dest"
    chmod +x "$dest"
    success "${name} v${version} installed to ${dest}"
}

# ---------------------------------------------------------------------------
# run_binaries — Download Impala and bluetui from GitHub Releases
# ---------------------------------------------------------------------------

run_binaries() {
    _ensure_local_bin

    local arch
    arch="$(_map_arch)"

    # -- Impala (WiFi TUI) ---------------------------------------------------
    local impala_url="https://github.com/pythops/impala/releases/download/v${IMPALA_VERSION}/impala-${arch}-unknown-linux-musl"
    _install_binary "impala" "$IMPALA_VERSION" "$impala_url"

    # -- bluetui (Bluetooth TUI) ---------------------------------------------
    local bluetui_url="https://github.com/pythops/bluetui/releases/download/v${BLUETUI_VERSION}/bluetui-${arch}-linux-musl"
    _install_binary "bluetui" "$BLUETUI_VERSION" "$bluetui_url"

    success "All pre-built binaries installed"
}
