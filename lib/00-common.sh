#!/usr/bin/env bash
# lib/00-common.sh — Shared constants, functions, and stage registry
# Sourced by install.sh; defines functions only, no top-level execution.

set -Eeuo pipefail
shopt -s inherit_errexit

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly DNF=dnf5
readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CONFIG_DIR="${REPO_DIR}/config"
readonly LOG_FILE="/tmp/surface-install.log"

# ---------------------------------------------------------------------------
# Stage ordering
# ---------------------------------------------------------------------------

STAGES=(
    repos
    kernel
    packages
    binaries
    fonts
    zram
    network
    desktop
    theme
    dotfiles
    neovim
    services
)

# Stage prerequisites — each key lists stages that MUST run before it.
declare -A STAGE_DEPS=(
    [repos]=""
    [kernel]="repos"
    [packages]="repos"
    [binaries]="packages"
    [fonts]="packages"
    [zram]=""
    [network]="fonts"
    [desktop]=""
    [theme]=""
    [dotfiles]="theme"
    [neovim]="dotfiles"
    [services]=""
)

# ---------------------------------------------------------------------------
# Color helpers (respects NO_COLOR / TERM=dumb)
# ---------------------------------------------------------------------------

_use_color() {
    [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]
}

_color() {
    local code="$1"; shift
    if _use_color; then
        printf '\033[%sm%s\033[0m\n' "$code" "$*"
    else
        printf '%s\n' "$*"
    fi
}

info()    { _color "0;34" "[INFO]  $*"; }
warn()    { _color "0;33" "[WARN]  $*"; }
error()   { _color "0;31" "[ERROR] $*"; }
success() { _color "0;32" "[OK]    $*"; }

stage_header() {
    local name="$1"
    local idx="$2"
    local total="$3"
    printf '\n'
    if _use_color; then
        printf '\033[1;35m=== [%d/%d] Stage: %s ===\033[0m\n' "$idx" "$total" "$name"
    else
        printf '=== [%d/%d] Stage: %s ===\n' "$idx" "$total" "$name"
    fi
}

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

ensure_sudo() {
    if ! sudo -n true 2>/dev/null; then
        info "Refreshing sudo credentials..."
        sudo -v
    fi
}

is_installed() {
    # Check whether an RPM package is installed
    rpm -q "$1" &>/dev/null
}

is_surface_hardware() {
    # Detect Surface Go 3 via DMI product name
    local product
    product="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "")"
    [[ "$product" == *"Surface Go 3"* ]]
}

stage_index() {
    # Return the 1-based index of a stage name, or 0 if not found
    local target="$1"
    local i
    for i in "${!STAGES[@]}"; do
        if [[ "${STAGES[$i]}" == "$target" ]]; then
            echo $(( i + 1 ))
            return 0
        fi
    done
    echo 0
    return 1
}

stage_exists() {
    local target="$1"
    local s
    for s in "${STAGES[@]}"; do
        [[ "$s" == "$target" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Trap helpers (set up by install.sh, not here — just define the functions)
# ---------------------------------------------------------------------------

_err_handler() {
    local line="$1"
    local cmd="$2"
    local code="$3"
    error "Command failed (exit $code) at line $line: $cmd"
}

_exit_handler() {
    local code=$?
    if [[ $code -ne 0 ]]; then
        error "Script exited with code $code"
        error "Check log: $LOG_FILE"
    fi
}
