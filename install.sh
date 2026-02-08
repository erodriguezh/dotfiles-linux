#!/usr/bin/env bash
# install.sh — Surface Go 3 Fedora 43 post-install configuration
#
# Run as the target user (NOT root). System operations use sudo explicitly.
# Usage:
#   ./install.sh              # Run all stages
#   ./install.sh --list       # List available stages
#   ./install.sh --only <s>   # Run only stage <s> (with prerequisites)
#   ./install.sh --skip <s>   # Skip stage <s> (repeatable)

set -Eeuo pipefail
shopt -s inherit_errexit

# ---------------------------------------------------------------------------
# Resolve script directory and source library files
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lib in "${SCRIPT_DIR}"/lib/*.sh; do
    # shellcheck source=/dev/null
    source "$lib"
done

# ---------------------------------------------------------------------------
# Traps
# ---------------------------------------------------------------------------

trap '_err_handler "${LINENO}" "${BASH_COMMAND}" "$?"' ERR
trap '_exit_handler' EXIT

# ---------------------------------------------------------------------------
# Logging — tee stdout+stderr to log file
# ---------------------------------------------------------------------------

exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ "${EUID}" -eq 0 ]]; then
    error "Do not run this script as root. Run as your normal user; sudo is used internally."
    exit 1
fi

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------

ACTION="run"          # run | list
ONLY_STAGE=""         # empty = all
declare -a SKIP_STAGES=()

_usage() {
    cat <<'USAGE'
Usage: ./install.sh [OPTIONS]

Options:
  --list          List all stages in order and exit
  --only <stage>  Run only the specified stage (prerequisites run automatically)
  --skip <stage>  Skip the specified stage (can be repeated)
  -h, --help      Show this help message

Examples:
  ./install.sh                  # Full install
  ./install.sh --list           # Show stages
  ./install.sh --only packages  # Run repos + packages
  ./install.sh --skip kernel    # Run all except kernel
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            ACTION="list"
            shift
            ;;
        --only)
            if [[ -z "${2:-}" ]]; then
                error "--only requires a stage name"
                exit 1
            fi
            ONLY_STAGE="$2"
            shift 2
            ;;
        --skip)
            if [[ -z "${2:-}" ]]; then
                error "--skip requires a stage name"
                exit 1
            fi
            SKIP_STAGES+=("$2")
            shift 2
            ;;
        -h|--help)
            _usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            _usage
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# --list: print stages and exit
# ---------------------------------------------------------------------------

if [[ "$ACTION" == "list" ]]; then
    info "Available stages (${#STAGES[@]} total):"
    for i in "${!STAGES[@]}"; do
        printf '  %2d. %s\n' "$(( i + 1 ))" "${STAGES[$i]}"
    done
    exit 0
fi

# ---------------------------------------------------------------------------
# Validate --only / --skip targets
# ---------------------------------------------------------------------------

if [[ -n "$ONLY_STAGE" ]] && ! stage_exists "$ONLY_STAGE"; then
    error "Unknown stage: $ONLY_STAGE"
    info "Run --list to see available stages."
    exit 1
fi

for s in "${SKIP_STAGES[@]+"${SKIP_STAGES[@]}"}"; do
    if ! stage_exists "$s"; then
        error "Unknown stage to skip: $s"
        info "Run --list to see available stages."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Build the set of stages to run
# ---------------------------------------------------------------------------

_is_skipped() {
    local target="$1"
    local s
    for s in "${SKIP_STAGES[@]+"${SKIP_STAGES[@]}"}"; do
        [[ "$s" == "$target" ]] && return 0
    done
    return 1
}

# Collect prerequisite stages recursively for --only mode
_collect_prereqs() {
    local stage="$1"
    local dep
    local deps_str="${STAGE_DEPS[$stage]:-}"
    for dep in $deps_str; do
        if ! printf '%s\n' "${RUN_STAGES[@]+"${RUN_STAGES[@]}"}" | grep -qxF "$dep"; then
            _collect_prereqs "$dep"
            RUN_STAGES+=("$dep")
        fi
    done
}

declare -a RUN_STAGES=()

if [[ -n "$ONLY_STAGE" ]]; then
    # Collect prerequisites first, then the target
    _collect_prereqs "$ONLY_STAGE"
    RUN_STAGES+=("$ONLY_STAGE")

    # Warn about prerequisites being auto-included
    if [[ ${#RUN_STAGES[@]} -gt 1 ]]; then
        local_prereqs=()
        for s in "${RUN_STAGES[@]}"; do
            [[ "$s" != "$ONLY_STAGE" ]] && local_prereqs+=("$s")
        done
        warn "Stage '$ONLY_STAGE' has prerequisites: ${local_prereqs[*]}"
        warn "These will run automatically."
    fi
else
    # All stages, minus skipped ones
    for s in "${STAGES[@]}"; do
        if ! _is_skipped "$s"; then
            RUN_STAGES+=("$s")
        else
            warn "Skipping stage: $s"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Cache sudo credentials
# ---------------------------------------------------------------------------

info "Caching sudo credentials..."
sudo -v

# Keep sudo alive in the background for long-running stages
(
    while true; do
        sudo -n true 2>/dev/null
        sleep 50
    done
) &
SUDO_KEEPALIVE_PID=$!

_cleanup_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

# Extend exit trap to also clean up the keepalive
trap '_cleanup_sudo_keepalive; _exit_handler' EXIT

# ---------------------------------------------------------------------------
# Run stages
# ---------------------------------------------------------------------------

TOTAL=${#RUN_STAGES[@]}

if [[ $TOTAL -eq 0 ]]; then
    warn "No stages to run."
    exit 0
fi

info "Starting installation (${TOTAL} stage(s))..."
info "Log file: $LOG_FILE"
printf '\n'

COMPLETED=0

for stage in "${RUN_STAGES[@]}"; do
    COMPLETED=$(( COMPLETED + 1 ))
    stage_header "$stage" "$COMPLETED" "$TOTAL"

    fn="run_${stage}"
    if ! declare -F "$fn" &>/dev/null; then
        warn "Stage function '$fn' not found (lib file not yet created). Skipping."
        continue
    fi

    "$fn"
    success "Stage '$stage' complete."
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n'
success "========================================="
success "  Installation complete ($TOTAL stages)"
success "========================================="
info "Log written to: $LOG_FILE"
info "Next step: sudo reboot"
