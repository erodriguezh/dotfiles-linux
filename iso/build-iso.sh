#!/usr/bin/env bash
# iso/build-iso.sh — Orchestrator for building a self-contained, offline
# Fedora 43 ISO for the Surface Go 3.
#
# Usage:
#   ./iso/build-iso.sh --username=edu --password-hash-file=/tmp/hash.txt
#   ./iso/build-iso.sh --test            # dummy credentials for dev builds
#   ./iso/build-iso.sh --validate-only   # dry run: RPM download + repo + repoclosure only
#
# Credential priority (first match wins):
#   1. --password-hash-file=PATH   (recommended — avoids shell history)
#   2. ISO_PASSWORD_HASH env var   (useful for CI)
#   3. --password-hash=HASH        (convenience — leaks to shell history)
#
# Requirements:
#   - Must run inside the Fedora 43 build container (see iso/Containerfile)
#   - mkksiso requires root (lorax 38.4+); container runs as root by default

set -Eeuo pipefail
shopt -s inherit_errexit

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly CACHE_DIR="/build/.cache"
readonly RPM_CACHE="${CACHE_DIR}/rpms"
readonly ISO_CACHE="${CACHE_DIR}/isos"
readonly ASSET_CACHE="${CACHE_DIR}/assets"
readonly DEFAULT_OUTPUT_DIR="/build/output"

# Fedora boot.iso details
readonly BOOT_ISO_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-43-1.6.iso"
readonly BOOT_ISO_SHA256="f4d06a40ce4fb4a84705e1a1f01ca1328f95a2120d422ba5f719af5df62d0099"

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

# ---------------------------------------------------------------------------
# Error handler
# ---------------------------------------------------------------------------

_err_handler() {
    local line="$1"
    local cmd="$2"
    local code="$3"
    error "Command failed (exit $code) at line $line: $cmd"
}
trap '_err_handler ${LINENO} "${BASH_COMMAND}" $?' ERR

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    local exit_code="${1:-0}"
    cat <<'USAGE'
Usage: build-iso.sh [OPTIONS]

Build a self-contained, offline Fedora 43 ISO for the Surface Go 3.

Options:
  --username=NAME            Target username (required unless --test or --validate-only)
  --password-hash-file=PATH  Read password hash from file (recommended)
  --password-hash=HASH       Password hash directly (WARNING: leaks to shell history)
  --test                     Use dummy credentials for dev builds
  --validate-only            Dry run: RPM download + repo creation + repoclosure only
  --boot-iso=PATH            Path to Fedora boot.iso (auto-downloads if not provided)
  --output-dir=PATH          Output directory (default: /build/output/)
  -h, --help                 Show this help

Environment:
  ISO_PASSWORD_HASH          Password hash via environment (useful for CI)

Credential priority: --password-hash-file > ISO_PASSWORD_HASH > --password-hash
USAGE
    exit "$exit_code"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

USERNAME=""
PASSWORD_HASH=""
PASSWORD_HASH_FILE=""
TEST_MODE=false
VALIDATE_ONLY=false
BOOT_ISO=""
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --username=*)     USERNAME="${1#*=}" ;;
            --password-hash-file=*)
                              PASSWORD_HASH_FILE="${1#*=}" ;;
            --password-hash=*)
                warn "--password-hash leaks the hash to shell history; prefer --password-hash-file"
                              PASSWORD_HASH="${1#*=}" ;;
            --test)           TEST_MODE=true ;;
            --validate-only)  VALIDATE_ONLY=true ;;
            --boot-iso=*)     BOOT_ISO="${1#*=}" ;;
            --output-dir=*)   OUTPUT_DIR="${1#*=}" ;;
            -h|--help)        usage ;;
            *)
                error "Unknown option: $1"
                usage 1
                ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Credential resolution
# ---------------------------------------------------------------------------

resolve_credentials() {
    if [[ "$TEST_MODE" == true ]]; then
        USERNAME="testuser"
        # Pre-computed hash for "test" via openssl passwd -6 -salt testsalt
        # shellcheck disable=SC2016
        PASSWORD_HASH='$6$testsalt$MKzbPFVB1VLv1NVFTjMGNOVOHN.3IsRpONqOdX4bXP4mXEDjKMaOFfAfZ3KabxqDpRjJbBMD7X00j0Y.YbkFV/'
        info "Test mode: using dummy credentials (username=testuser)"
        return
    fi

    if [[ "$VALIDATE_ONLY" == true ]]; then
        # Credentials not needed for validation
        USERNAME="${USERNAME:-validate}"
        PASSWORD_HASH="${PASSWORD_HASH:-validate}"
        return
    fi

    # Username is required for real builds
    if [[ -z "$USERNAME" ]]; then
        error "--username is required (or use --test for dummy credentials)"
        exit 1
    fi

    # Password hash resolution (priority order)
    if [[ -n "$PASSWORD_HASH_FILE" ]]; then
        if [[ ! -f "$PASSWORD_HASH_FILE" ]]; then
            error "Password hash file not found: $PASSWORD_HASH_FILE"
            exit 1
        fi
        PASSWORD_HASH="$(cat "$PASSWORD_HASH_FILE")"
        PASSWORD_HASH="$(echo "$PASSWORD_HASH" | tr -d '[:space:]')"
        info "Password hash read from file: $PASSWORD_HASH_FILE"
    elif [[ -n "${ISO_PASSWORD_HASH:-}" ]]; then
        PASSWORD_HASH="$ISO_PASSWORD_HASH"
        info "Password hash read from ISO_PASSWORD_HASH environment variable"
    fi

    if [[ -z "$PASSWORD_HASH" ]]; then
        error "No password hash provided. Use --password-hash-file, ISO_PASSWORD_HASH env, or --password-hash"
        exit 1
    fi

    # Basic validation: SHA-512 hashes start with $6$
    # shellcheck disable=SC2016
    if [[ "$PASSWORD_HASH" != '$6$'* ]]; then
        warn "Password hash does not start with \$6\$ — expected SHA-512 crypt format"
    fi
}

# ---------------------------------------------------------------------------
# Stage 1: Download Fedora boot.iso
# ---------------------------------------------------------------------------

stage_download_boot_iso() {
    info "=== Stage 1: Download Fedora boot.iso ==="

    if [[ -n "$BOOT_ISO" ]]; then
        if [[ ! -f "$BOOT_ISO" ]]; then
            error "Specified boot ISO not found: $BOOT_ISO"
            exit 1
        fi
        info "Using provided boot ISO: $BOOT_ISO"
        return
    fi

    mkdir -p "$ISO_CACHE"
    BOOT_ISO="${ISO_CACHE}/fedora-boot-43.iso"

    if [[ -f "$BOOT_ISO" ]]; then
        info "Boot ISO already cached, verifying checksum..."
        local actual_sha256
        actual_sha256="$(sha256sum "$BOOT_ISO" | awk '{print $1}')"
        if [[ "$actual_sha256" == "$BOOT_ISO_SHA256" ]]; then
            success "Boot ISO cached and verified: $BOOT_ISO"
            return
        else
            warn "Cached boot ISO checksum mismatch, re-downloading..."
            rm -f "$BOOT_ISO"
        fi
    fi

    info "Downloading Fedora 43 boot.iso..."
    curl -fSL "$BOOT_ISO_URL" -o "${BOOT_ISO}.tmp"

    local actual_sha256
    actual_sha256="$(sha256sum "${BOOT_ISO}.tmp" | awk '{print $1}')"
    if [[ "$actual_sha256" != "$BOOT_ISO_SHA256" ]]; then
        error "SHA256 mismatch for boot.iso"
        error "  expected: $BOOT_ISO_SHA256"
        error "  actual:   $actual_sha256"
        rm -f "${BOOT_ISO}.tmp"
        exit 1
    fi

    mv "${BOOT_ISO}.tmp" "$BOOT_ISO"
    success "Boot ISO downloaded and verified: $BOOT_ISO"
}

# ---------------------------------------------------------------------------
# Stage 2: Expand @^minimal-environment
# ---------------------------------------------------------------------------

# Global array populated by stage 2, used by stages 3-5
declare -a MINIMAL_ENV_PKGS=()

stage_expand_minimal_env() {
    info "=== Stage 2: Expand @^minimal-environment ==="

    # Extract mandatory and default package names from the environment group
    local raw_output
    raw_output="$(dnf5 group info '@^minimal-environment' --quiet 2>/dev/null || true)"

    if [[ -z "$raw_output" ]]; then
        # Fallback: try without --quiet
        raw_output="$(dnf5 group info '@^minimal-environment' 2>/dev/null || true)"
    fi

    # dnf5 group info outputs package names as lines under Mandatory/Default/Optional sections.
    # We parse mandatory and default packages (skip optional).
    local in_section=""
    while IFS= read -r line; do
        # Detect section headers
        if [[ "$line" =~ ^[[:space:]]*Mandatory\ [Pp]ackages ]]; then
            in_section="mandatory"
            continue
        elif [[ "$line" =~ ^[[:space:]]*Default\ [Pp]ackages ]]; then
            in_section="default"
            continue
        elif [[ "$line" =~ ^[[:space:]]*Optional\ [Pp]ackages ]]; then
            in_section=""
            continue
        elif [[ "$line" =~ ^[[:space:]]*Conditional\ [Pp]ackages ]]; then
            in_section=""
            continue
        elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        # Inside mandatory or default section, extract package names
        if [[ "$in_section" == "mandatory" || "$in_section" == "default" ]]; then
            # Lines typically look like "   package-name" or "   package-name: description"
            local pkg_name
            pkg_name="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]*:.*//' | tr -d '[:space:]')"
            if [[ -n "$pkg_name" && "$pkg_name" != *"Packages"* ]]; then
                MINIMAL_ENV_PKGS+=("$pkg_name")
            fi
        fi
    done <<< "$raw_output"

    # Also expand the nested groups within minimal-environment
    # The environment typically includes groups like "core" and "guest-agents"
    local groups_output
    groups_output="$(dnf5 group info '@^minimal-environment' 2>/dev/null || true)"

    # Extract mandatory group names (e.g., "core") and expand them
    local group_in_section=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Mandatory\ [Gg]roups ]]; then
            group_in_section="mandatory"
            continue
        elif [[ "$line" =~ ^[[:space:]]*Optional\ [Gg]roups ]]; then
            group_in_section=""
            continue
        elif [[ "$line" =~ ^[[:space:]]*Default\ [Gg]roups ]]; then
            group_in_section="default"
            continue
        elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        if [[ "$group_in_section" == "mandatory" || "$group_in_section" == "default" ]]; then
            local grp_name
            grp_name="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]*:.*//' | tr -d '[:space:]')"
            if [[ -n "$grp_name" && "$grp_name" != *"Groups"* ]]; then
                info "Expanding nested group: $grp_name"
                local grp_output
                grp_output="$(dnf5 group info "$grp_name" --quiet 2>/dev/null || true)"
                if [[ -z "$grp_output" ]]; then
                    grp_output="$(dnf5 group info "$grp_name" 2>/dev/null || true)"
                fi

                local grp_section=""
                while IFS= read -r gline; do
                    if [[ "$gline" =~ ^[[:space:]]*Mandatory\ [Pp]ackages ]]; then
                        grp_section="mandatory"
                        continue
                    elif [[ "$gline" =~ ^[[:space:]]*Default\ [Pp]ackages ]]; then
                        grp_section="default"
                        continue
                    elif [[ "$gline" =~ ^[[:space:]]*Optional\ [Pp]ackages ]]; then
                        grp_section=""
                        continue
                    elif [[ "$gline" =~ ^[[:space:]]*Conditional\ [Pp]ackages ]]; then
                        grp_section=""
                        continue
                    elif [[ "$gline" =~ ^[[:space:]]*$ ]]; then
                        continue
                    fi

                    if [[ "$grp_section" == "mandatory" || "$grp_section" == "default" ]]; then
                        local gpkg
                        gpkg="$(echo "$gline" | sed -E 's/^[[:space:]]+//; s/[[:space:]]*:.*//' | tr -d '[:space:]')"
                        if [[ -n "$gpkg" && "$gpkg" != *"Packages"* ]]; then
                            MINIMAL_ENV_PKGS+=("$gpkg")
                        fi
                    fi
                done <<< "$grp_output"
            fi
        fi
    done <<< "$groups_output"

    # Deduplicate
    local -A seen=()
    local -a unique=()
    for pkg in "${MINIMAL_ENV_PKGS[@]}"; do
        if [[ -z "${seen[$pkg]:-}" ]]; then
            seen[$pkg]=1
            unique+=("$pkg")
        fi
    done
    MINIMAL_ENV_PKGS=("${unique[@]}")

    info "Expanded @^minimal-environment to ${#MINIMAL_ENV_PKGS[@]} packages"
    success "Minimal environment expansion complete"
}

# ---------------------------------------------------------------------------
# Package extraction from lib/*.sh (single source of truth)
# ---------------------------------------------------------------------------

# Global array populated by extract_target_packages
declare -a TARGET_PKGS=()

extract_target_packages() {
    info "Extracting target packages from lib/03-packages.sh and lib/02-kernel.sh..."

    local packages_file="${REPO_ROOT}/lib/03-packages.sh"
    local kernel_file="${REPO_ROOT}/lib/02-kernel.sh"

    if [[ ! -f "$packages_file" ]]; then
        error "lib/03-packages.sh not found at $packages_file"
        exit 1
    fi

    # Extract the pkgs=() array contents from lib/03-packages.sh
    # Lines between "local -a pkgs=(" and ")" that contain package names
    local in_array=false
    while IFS= read -r line; do
        if [[ "$line" =~ pkgs=\( ]]; then
            in_array=true
            continue
        fi
        if [[ "$in_array" == true ]]; then
            # End of array
            if [[ "$line" =~ ^[[:space:]]*\) ]]; then
                in_array=false
                continue
            fi
            # Skip comments and blank lines
            local trimmed
            trimmed="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
            [[ "$trimmed" =~ ^# ]] && continue
            [[ -z "$trimmed" ]] && continue
            # Extract package name (strip inline comments)
            local pkg_name
            pkg_name="$(echo "$trimmed" | sed -E 's/[[:space:]]*#.*$//')"
            if [[ -n "$pkg_name" ]]; then
                TARGET_PKGS+=("$pkg_name")
            fi
        fi
    done < "$packages_file"

    # Extract kernel packages from lib/02-kernel.sh
    # Look for dnf install lines with package names
    if [[ -f "$kernel_file" ]]; then
        # kernel-surface and libwacom-surface are the two packages
        TARGET_PKGS+=("kernel-surface")
        TARGET_PKGS+=("libwacom-surface")
    fi

    # Also add sudo (present in existing kickstart)
    TARGET_PKGS+=("sudo")

    info "Extracted ${#TARGET_PKGS[@]} target packages from lib/*.sh"
}

# ---------------------------------------------------------------------------
# Stage 3: Download all RPMs
# ---------------------------------------------------------------------------

stage_download_rpms() {
    info "=== Stage 3: Download all RPMs ==="

    mkdir -p "$RPM_CACHE"

    # Combine minimal-environment packages with target packages
    local -a all_pkgs=("${MINIMAL_ENV_PKGS[@]}" "${TARGET_PKGS[@]}")

    # Deduplicate the combined list
    local -A seen=()
    local -a unique=()
    for pkg in "${all_pkgs[@]}"; do
        if [[ -z "${seen[$pkg]:-}" ]]; then
            seen[$pkg]=1
            unique+=("$pkg")
        fi
    done
    all_pkgs=("${unique[@]}")

    info "Downloading ${#all_pkgs[@]} packages (+ transitive deps) to $RPM_CACHE"

    dnf5 download \
        --resolve \
        --alldeps \
        --setopt=install_weak_deps=False \
        --destdir="$RPM_CACHE" \
        --arch=x86_64 \
        --arch=noarch \
        "${all_pkgs[@]}"

    local rpm_count
    rpm_count="$(find "$RPM_CACHE" -name '*.rpm' | wc -l)"
    success "Downloaded $rpm_count RPMs to $RPM_CACHE"
}

# ---------------------------------------------------------------------------
# Stage 4: Create local repo
# ---------------------------------------------------------------------------

stage_create_repo() {
    info "=== Stage 4: Create local repo ==="

    createrepo_c "$RPM_CACHE"

    success "Local repo created at $RPM_CACHE"
}

# ---------------------------------------------------------------------------
# Stage 5: Validate repo (repoclosure)
# ---------------------------------------------------------------------------

stage_validate_repo() {
    info "=== Stage 5: Validate repo (repoclosure) ==="

    # Combine all package names for validation
    local -a all_pkgs=("${MINIMAL_ENV_PKGS[@]}" "${TARGET_PKGS[@]}")

    # Deduplicate
    local -A seen=()
    local -a unique=()
    for pkg in "${all_pkgs[@]}"; do
        if [[ -z "${seen[$pkg]:-}" ]]; then
            seen[$pkg]=1
            unique+=("$pkg")
        fi
    done
    all_pkgs=("${unique[@]}")

    info "Validating that local repo can satisfy ${#all_pkgs[@]} packages..."

    # dnf5 does not support creating ad-hoc repos via --setopt=REPO_ID.key=value
    # (that was a dnf4-only feature). Instead, use --repofrompath to create a
    # transient repo for a single command — no temp .repo files needed.
    #
    # Flags used by both checks:
    #   --setopt=reposdir=/dev/null   prevents loading system/container repos
    #   --repofrompath=local-only,... creates a transient repo over RPM_CACHE
    #   --repo=local-only             restricts resolution to only that repo

    # Check A — structural integrity (repoclosure)
    # Verifies every RPM's Requires: is satisfiable within the local repo.
    # Exits 0 on success, non-zero on unresolved deps (safe under set -e).
    info "Running repoclosure on local repo..."
    dnf5 repoclosure \
        --setopt=reposdir=/dev/null \
        --repofrompath=local-only,"file://${RPM_CACHE}" \
        --repo=local-only

    success "Repoclosure passed: no unresolved dependencies"

    # Check B — completeness (install simulation)
    # Verifies the specific combined package list is resolvable from the
    # local repo alone. --assumeno causes dnf5 to resolve the transaction
    # without committing it. On successful resolution it exits 0; on
    # resolution failure (unresolvable deps) it exits 1. We capture the
    # exit code to inspect output for real errors under set -Eeuo pipefail.
    info "Running install simulation for ${#all_pkgs[@]} packages..."
    local install_output
    local install_rc=0
    if ! install_output="$(dnf5 install --assumeno \
        --setopt=reposdir=/dev/null \
        --repofrompath=local-only,"file://${RPM_CACHE}" \
        --repo=local-only \
        "${all_pkgs[@]}" 2>&1)"; then
        install_rc=$?
    fi

    # Fail on real resolution errors (Problem: or No match for argument:).
    # A non-zero exit without these patterns is unexpected but tolerable —
    # the resolution itself succeeded.
    if [[ $install_rc -ne 0 ]]; then
        if grep -qE 'Problem:|No match for argument:' <<<"$install_output"; then
            error "Local repo install simulation failed:"
            printf '%s\n' "$install_output"
            exit 1
        fi
        # Non-zero exit but no resolution error patterns found — likely
        # benign, but could mask a non-resolution error. Treat as success
        # for now; tighten to hard-fail if this path ever triggers unexpectedly.
    fi

    success "Install simulation passed: all ${#all_pkgs[@]} packages satisfiable from local repo"
}

# ---------------------------------------------------------------------------
# Stage 6: Download binaries
# ---------------------------------------------------------------------------

stage_download_binaries() {
    info "=== Stage 6: Download binaries ==="

    local bin_dir="${ASSET_CACHE}/binaries"
    mkdir -p "$bin_dir"

    # Version constants matching lib/04-binaries.sh exactly
    local impala_version="0.7.3"
    local bluetui_version="0.8.1"
    local starship_version="1.23.0"
    local arch="x86_64"

    # Impala — download to temp file, atomically move on success
    local impala_url="https://github.com/pythops/impala/releases/download/v${impala_version}/impala-${arch}-unknown-linux-musl"
    if [[ ! -x "${bin_dir}/impala" ]]; then
        info "Downloading impala v${impala_version}..."
        local tmp_impala
        tmp_impala="$(mktemp "${bin_dir}/impala.tmp.XXXXXX")"
        curl -fSL "$impala_url" -o "$tmp_impala"
        chmod +x "$tmp_impala"
        mv -f "$tmp_impala" "${bin_dir}/impala"
    else
        info "impala already cached"
    fi

    # bluetui — download to temp file, atomically move on success
    local bluetui_url="https://github.com/pythops/bluetui/releases/download/v${bluetui_version}/bluetui-${arch}-linux-musl"
    if [[ ! -x "${bin_dir}/bluetui" ]]; then
        info "Downloading bluetui v${bluetui_version}..."
        local tmp_bluetui
        tmp_bluetui="$(mktemp "${bin_dir}/bluetui.tmp.XXXXXX")"
        curl -fSL "$bluetui_url" -o "$tmp_bluetui"
        chmod +x "$tmp_bluetui"
        mv -f "$tmp_bluetui" "${bin_dir}/bluetui"
    else
        info "bluetui already cached"
    fi

    # Starship (tar.gz archive — extract the binary)
    local starship_url="https://github.com/starship/starship/releases/download/v${starship_version}/starship-${arch}-unknown-linux-musl.tar.gz"
    if [[ ! -f "${bin_dir}/starship" ]]; then
        info "Downloading starship v${starship_version}..."
        local tmp_dir
        tmp_dir="$(mktemp -d)"
        curl -fSL "$starship_url" | tar xz -C "$tmp_dir"
        mv -f "${tmp_dir}/starship" "${bin_dir}/starship"
        chmod +x "${bin_dir}/starship"
        rm -rf "$tmp_dir"
    else
        info "starship already cached"
    fi

    success "All binaries downloaded to $bin_dir"
}

# ---------------------------------------------------------------------------
# Stage 7: Download fonts
# ---------------------------------------------------------------------------

stage_download_fonts() {
    info "=== Stage 7: Download fonts ==="

    # Version constant matching lib/05-fonts.sh exactly
    local nf_version="3.3.0"
    local font_name="JetBrainsMono"
    local font_dir="${ASSET_CACHE}/fonts/${font_name}"

    # Check if already cached at expected version
    if [[ -d "$font_dir" && -f "${font_dir}/.nf-version" ]]; then
        local cached_version
        cached_version="$(cat "${font_dir}/.nf-version")"
        if [[ "$cached_version" == "$nf_version" ]]; then
            info "JetBrains Mono Nerd Font v${nf_version} already cached"
            success "Fonts already cached"
            return
        fi
    fi

    info "Downloading JetBrains Mono Nerd Font v${nf_version}..."

    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v${nf_version}/${font_name}.tar.xz"
    local tmp_file
    tmp_file="$(mktemp)"

    curl -fSL "$url" -o "$tmp_file"

    mkdir -p "$font_dir"
    tar xf "$tmp_file" -C "$font_dir"
    rm -f "$tmp_file"

    # Record version for idempotency (matching lib/05-fonts.sh layout)
    echo "$nf_version" > "${font_dir}/.nf-version"

    success "JetBrains Mono Nerd Font v${nf_version} downloaded to $font_dir"
}

# ---------------------------------------------------------------------------
# Stage 8: Pre-clone lazy.nvim
# ---------------------------------------------------------------------------

stage_clone_lazy_nvim() {
    info "=== Stage 8: Pre-clone lazy.nvim ==="

    local lazy_dir="${ASSET_CACHE}/lazy-nvim"

    if [[ -d "$lazy_dir/.git" ]]; then
        info "lazy.nvim already cached, updating..."
        git -C "$lazy_dir" fetch --tags --force origin --depth=1
        git -C "$lazy_dir" checkout stable
        git -C "$lazy_dir" reset --hard stable
    else
        info "Cloning lazy.nvim (stable branch)..."
        rm -rf "$lazy_dir"
        git clone --filter=blob:none --branch=stable \
            https://github.com/folke/lazy.nvim.git "$lazy_dir"
    fi

    success "lazy.nvim cached at $lazy_dir"
}

# ---------------------------------------------------------------------------
# Stage 9: Copy surface-linux repo + generate theme files
# ---------------------------------------------------------------------------

stage_prepare_repo() {
    info "=== Stage 9: Copy surface-linux repo + generate theme ==="

    local staging_dir="/tmp/surface-linux"
    rm -rf "$staging_dir"

    info "Copying surface-linux repo to staging directory..."
    cp -a "$REPO_ROOT" "$staging_dir"

    # Remove .git directory from staging (not needed on target)
    rm -rf "${staging_dir}/.git"

    # Generate theme files using the template engine
    info "Generating theme files from templates..."

    local colors_file="${staging_dir}/colors.toml"
    local templates_dir="${staging_dir}/templates"

    if [[ ! -f "$colors_file" ]]; then
        error "colors.toml not found at $colors_file"
        exit 1
    fi

    # Build sed script from colors.toml (replicating lib/09-theme.sh logic)
    local sed_script
    sed_script="$(mktemp /tmp/theme-sed.XXXXXX)"

    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Parse key = "value" (TOML string format)
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"

            # Escape sed-special characters (using | as delimiter)
            local escaped_val="${val//\\/\\\\}"
            escaped_val="${escaped_val//&/\\&}"
            escaped_val="${escaped_val//|/\\|}"

            # Variant 1: {{ key }} -> raw value
            printf 's|{{ %s }}|%s|g\n' "$key" "$escaped_val" >> "$sed_script"

            # Variant 2: {{ key_strip }} -> without # prefix
            local stripped="${val#\#}"
            local escaped_stripped="${stripped//\\/\\\\}"
            escaped_stripped="${escaped_stripped//&/\\&}"
            escaped_stripped="${escaped_stripped//|/\\|}"
            printf 's|{{ %s_strip }}|%s|g\n' "$key" "$escaped_stripped" >> "$sed_script"

            # Variant 3: {{ key_rgb }} -> decimal R,G,B (only for valid 6-digit hex)
            if [[ "$val" =~ ^#?[0-9a-fA-F]{6}$ ]]; then
                local hex="${val#\#}"
                local r g b
                r=$(printf '%d' "0x${hex:0:2}")
                g=$(printf '%d' "0x${hex:2:2}")
                b=$(printf '%d' "0x${hex:4:2}")
                local rgb
                rgb="$(printf '%d,%d,%d' "$r" "$g" "$b")"
                printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$rgb" >> "$sed_script"
            fi
        fi
    done < "$colors_file"

    # Template-to-output mapping (matching lib/09-theme.sh exactly)
    local -a tpl_names=(
        hyprland-colors.conf.tpl
        waybar-colors.css.tpl
        ghostty-theme.tpl
        mako-colors.tpl
        tofi-colors.tpl
        hyprlock-colors.conf.tpl
        gtk3-settings.ini.tpl
        gtk4-settings.ini.tpl
    )
    local -a tpl_outputs=(
        config/hypr/colors.conf
        config/waybar/colors.css
        config/ghostty/themes/theme
        config/mako/colors
        config/tofi/colors
        config/hypr/hyprlock-colors.conf
        config/gtk-3.0/settings.ini
        config/gtk-4.0/settings.ini
    )

    local i
    for i in "${!tpl_names[@]}"; do
        local tpl_path="${templates_dir}/${tpl_names[$i]}"
        local out_path="${staging_dir}/${tpl_outputs[$i]}"

        if [[ ! -f "$tpl_path" ]]; then
            error "Template not found: $tpl_path"
            exit 1
        fi

        mkdir -p "$(dirname "$out_path")"
        sed -f "$sed_script" "$tpl_path" > "$out_path"
        info "  Generated ${tpl_outputs[$i]}"
    done

    rm -f "$sed_script"

    success "Surface-linux repo staged with generated theme files"
}

# ---------------------------------------------------------------------------
# Stage 10: Substitute credentials in kickstart
# ---------------------------------------------------------------------------

stage_substitute_credentials() {
    info "=== Stage 10: Substitute credentials in kickstart ==="

    local ks_template="${REPO_ROOT}/iso/surface-go3-iso.ks"
    local ks_output="/tmp/kickstart.ks"

    if [[ ! -f "$ks_template" ]]; then
        error "ISO kickstart template not found: $ks_template"
        error "This file will be created by task fn-2.2"
        exit 1
    fi

    # Copy template to temp
    cp "$ks_template" "$ks_output"

    # Substitute placeholders — credential values are NOT logged
    # Use sed with a different delimiter to handle $6$ hashes safely
    sed -i "s|@@USERNAME@@|${USERNAME}|g" "$ks_output"

    # For password hash, write to a temp file and use sed -f to avoid
    # shell escaping issues with the $ characters in SHA-512 hashes
    local hash_sed
    hash_sed="$(mktemp /tmp/hash-sed.XXXXXX)"
    printf 's|@@PASSWORD_HASH@@|%s|g\n' "$PASSWORD_HASH" > "$hash_sed"
    sed -i -f "$hash_sed" "$ks_output"
    rm -f "$hash_sed"

    # Verify no placeholders remain
    if grep -q '@@USERNAME@@\|@@PASSWORD_HASH@@' "$ks_output"; then
        error "Kickstart still contains unsubstituted placeholders"
        exit 1
    fi

    info "Kickstart prepared at $ks_output"
    success "Credentials substituted (values not logged)"
}

# ---------------------------------------------------------------------------
# Helper: Extract inst.ks= value from ISO-level EFI grub.cfg
# ---------------------------------------------------------------------------
# Extracts /EFI/BOOT/grub.cfg from the ISO (already modified by mkksiso),
# scans installer stanzas (those containing inst.stage2=), parses the
# inst.ks= argument from linux/linuxefi cmdlines (joining \ continuations),
# and returns exactly one distinct inst.ks= value. Hard-fails if missing
# or if multiple distinct values found.

_extract_inst_ks_from_iso() {
    local iso_path="$1"
    local work_dir
    work_dir="$(mktemp -d /tmp/extract-inst-ks.XXXXXX)"
    trap 'rm -rf "$work_dir"; trap - RETURN' RETURN

    local grub_file="${work_dir}/grub.cfg"
    if ! osirrox -indev "$iso_path" -extract "/EFI/BOOT/grub.cfg" "$grub_file" 2>/dev/null; then
        error "Cannot extract /EFI/BOOT/grub.cfg from ISO — cannot derive inst.ks= value"
        return 1
    fi

    # Use python3 to parse GRUB config: join \ continuations, find installer
    # stanzas (containing inst.stage2=), extract inst.ks= tokens.
    local result
    result="$(python3 -c "$(cat << 'PYEOF'
import re, sys

content = open(sys.argv[1]).read()

# Join backslash-continuation lines into logical lines
lines = content.splitlines()
logical_lines = []
buf = ""
for line in lines:
    stripped = line.rstrip()
    if stripped.endswith("\\"):
        buf += stripped[:-1] + " "
    else:
        buf += stripped
        logical_lines.append(buf)
        buf = ""
if buf:
    logical_lines.append(buf)

# Find linux/linuxefi cmdlines in installer stanzas (those with inst.stage2=)
inst_ks_values = set()
installer_count = 0
missing_ks_count = 0
for ll in logical_lines:
    # Match linux or linuxefi commands
    if not re.match(r'\s*(linux|linuxefi)\s', ll):
        continue
    # Must be an installer stanza (contains inst.stage2=)
    if 'inst.stage2=' not in ll:
        continue
    installer_count += 1
    # Extract inst.ks= token(s)
    found_ks = False
    tokens = ll.split()
    for token in tokens:
        if token.startswith('inst.ks='):
            inst_ks_values.add(token)
            found_ks = True
    if not found_ks:
        missing_ks_count += 1

if not inst_ks_values:
    print('__NO_INST_KS__', end='')
    sys.exit(0)

if missing_ks_count > 0:
    print('__PARTIAL_INST_KS__:' + str(missing_ks_count) + '/' + str(installer_count), end='')
    sys.exit(0)

if len(inst_ks_values) > 1:
    print('__MULTIPLE_INST_KS__:' + '|'.join(sorted(inst_ks_values)), end='')
    sys.exit(0)

print(inst_ks_values.pop(), end='')
PYEOF
    )" "$grub_file")"

    if [[ "$result" == "__NO_INST_KS__" ]]; then
        error "No inst.ks= found in ISO /EFI/BOOT/grub.cfg installer stanzas"
        return 1
    fi

    if [[ "$result" == __PARTIAL_INST_KS__:* ]]; then
        local partial_info="${result#__PARTIAL_INST_KS__:}"
        error "Not all installer stanzas have inst.ks= in ISO /EFI/BOOT/grub.cfg: $partial_info missing"
        return 1
    fi

    if [[ "$result" == __MULTIPLE_INST_KS__:* ]]; then
        local found_values="${result#__MULTIPLE_INST_KS__:}"
        error "Multiple distinct inst.ks= values in ISO /EFI/BOOT/grub.cfg: $found_values"
        return 1
    fi

    # Output the inst.ks= value (e.g., "inst.ks=hd:LABEL=SurfaceLinux-43:/ks.cfg")
    printf '%s' "$result"
}

# ---------------------------------------------------------------------------
# Helper: Patch efiboot.img inside an ISO (label + inst.ks injection)
# ---------------------------------------------------------------------------
# When --skip-mkefiboot is active, the efiboot.img's internal grub.cfg
# still references the original Fedora label and lacks inst.ks= injection.
# This function:
#   1. Replaces volume labels in known patterns (search --label/-l, hd:LABEL=)
#   2. Injects inst.ks= into installer stanzas (those with inst.stage2=)
# Uses mtools (no loop devices needed).

patch_efiboot() {
    local iso_path="$1"
    local new_label="$2"
    local inst_ks_value="$3"
    local work_dir
    work_dir="$(mktemp -d /tmp/efi-patch.XXXXXX)"

    # Clean up work_dir on any function return (normal or error).
    # Self-disarms after firing to avoid leaking into the caller's scope.
    trap 'rm -rf "$work_dir"; trap - RETURN' RETURN

    info "Patching efiboot.img: label='$new_label', inst.ks='$inst_ks_value'..."

    # Step A: Extract efiboot.img from the output ISO
    local efi_img="${work_dir}/efiboot.img"
    if ! osirrox -indev "$iso_path" -extract /images/efiboot.img "$efi_img" 2>/dev/null; then
        error "Failed to extract efiboot.img from ISO"
        return 1
    fi

    # Step B: Discover grub.cfg inside the FAT image
    local grub_path=""
    local candidate
    for candidate in "::/EFI/BOOT/grub.cfg" "::/EFI/fedora/grub.cfg"; do
        if mcopy -o -i "$efi_img" "$candidate" /dev/null 2>/dev/null; then
            grub_path="$candidate"
            break
        fi
    done

    if [[ -z "$grub_path" ]]; then
        error "Cannot locate grub.cfg inside efiboot.img (tried EFI/BOOT and EFI/fedora)"
        return 1
    fi
    info "  Found grub.cfg at: $grub_path"

    # Step C: Extract, patch, and write back grub.cfg
    local grub_file="${work_dir}/grub.cfg"
    mcopy -i "$efi_img" "$grub_path" "$grub_file"

    # Extract original label(s) from grub.cfg using python3 -c (python3 guaranteed via lorax).
    local old_label
    old_label="$(python3 -c "$(cat << 'PYEOF'
import re, sys

content = open(sys.argv[1]).read()

# Per-line patterns in priority order: quoted first, unquoted last.
# This prevents the unquoted catch-all from capturing quote characters.
line_patterns = [
    r"search.*(?:--label|-l)\s+'([^']+)'",       # single-quoted
    r'search.*(?:--label|-l)\s+"([^"]+)"',        # double-quoted
    r"search.*(?:--label|-l)\s+([^\s'\"]+)",       # unquoted (no quotes/spaces)
]

labels = set()
for line in content.splitlines():
    for pat in line_patterns:
        m = re.search(pat, line)
        if m:
            labels.add(m.group(1))
            break  # first match wins per line

# Fallback: if no search --label/-l found, try hd:LABEL= in inst.stage2=/inst.ks=
if not labels:
    hd_label_pat = r'inst\.(?:stage2|ks)=hd:LABEL=([^\s:/]+)'
    for m in re.finditer(hd_label_pat, content):
        labels.add(m.group(1))

if not labels:
    print('__NO_LABEL_FOUND__', end='')
    sys.exit(0)

if len(labels) > 1:
    print('__MULTIPLE_LABELS__:' + ','.join(sorted(labels)), end='')
    sys.exit(0)

print(labels.pop(), end='')
PYEOF
    )" "$grub_file")"

    if [[ "$old_label" == "__NO_LABEL_FOUND__" ]]; then
        error "No volume label found in grub.cfg — cannot patch efiboot.img"
        return 1
    fi

    if [[ "$old_label" == __MULTIPLE_LABELS__:* ]]; then
        local found_labels="${old_label#__MULTIPLE_LABELS__:}"
        error "Multiple distinct labels found in grub.cfg: $found_labels"
        error "Ambiguous — cannot safely patch efiboot.img"
        return 1
    fi

    info "  Original label: '$old_label'"
    info "  New label:      '$new_label'"

    # Patch grub.cfg: replace labels in known patterns, normalize hd:LABEL=,
    # and inject inst.ks= into installer stanzas. All done in a single
    # python3 invocation to handle line continuations correctly.
    python3 -c "$(cat << 'PYEOF'
import re, sys

old_label = sys.argv[1]
new_label = sys.argv[2]
inst_ks = sys.argv[3]
filepath = sys.argv[4]

content = open(filepath).read()

# --- Phase 1: Replace labels in search --label/-l patterns ---
# Preserve quoting style.
if old_label != new_label:
    search_patterns = [
        (r"(search.*--label\s+)'" + re.escape(old_label) + r"'",
         r"\1'" + new_label + r"'"),
        (r'(search.*--label\s+)"' + re.escape(old_label) + r'"',
         r'\1"' + new_label + r'"'),
        (r"(search.*--label\s+)" + re.escape(old_label) + r"([\s]|$)",
         r"\1" + new_label + r"\2"),
        (r"(search.*-l\s+)'" + re.escape(old_label) + r"'",
         r"\1'" + new_label + r"'"),
        (r'(search.*-l\s+)"' + re.escape(old_label) + r'"',
         r'\1"' + new_label + r'"'),
        (r"(search.*-l\s+)" + re.escape(old_label) + r"([\s]|$)",
         r"\1" + new_label + r"\2"),
    ]
    for pat, repl in search_patterns:
        content = re.sub(pat, repl, content, flags=re.MULTILINE)

# --- Phase 2: Replace labels in hd:LABEL= patterns ---
# Scoped to inst.stage2= and inst.ks= arguments only.
if old_label != new_label:
    content = re.sub(
        r"(inst\.(?:stage2|ks)=hd:LABEL=)" + re.escape(old_label),
        r"\1" + new_label,
        content
    )

# --- Phase 3: Inject inst.ks= into installer stanzas ---
# Process line-by-line, joining \ continuations into logical lines,
# then inject inst.ks= only into stanzas with inst.stage2=.
# Use rstrip() (strip all trailing whitespace) consistently when checking
# for backslash continuations — matches the verify script's behavior.
lines = content.splitlines(True)  # keep line endings
output_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.rstrip()

    # Check if this is a linux/linuxefi command line
    if re.match(r'\s*(linux|linuxefi)\s', stripped):
        # Collect the full logical cmdline (join \ continuations)
        physical_lines = [lines[i]]
        while stripped.endswith('\\') and i + 1 < len(lines):
            i += 1
            physical_lines.append(lines[i])
            stripped = lines[i].rstrip()

        # Join into a single logical line for analysis
        logical = ""
        for pl in physical_lines:
            s = pl.rstrip()
            if s.endswith('\\'):
                logical += s[:-1] + " "
            else:
                logical += s

        # Only modify installer stanzas (those with inst.stage2=)
        if 'inst.stage2=' in logical:
            if 'inst.ks=' in logical:
                # Replace any existing inst.ks= with the correct value.
                # This handles stale/incorrect values from the original ISO.
                new_physical = []
                for pl in physical_lines:
                    # Replace inst.ks=<anything> tokens on this line
                    new_pl = re.sub(r'inst\.ks=\S+', inst_ks, pl)
                    new_physical.append(new_pl)
                physical_lines = new_physical
            else:
                # Inject inst.ks= at end of logical cmdline.
                last_pl = physical_lines[-1].rstrip()
                if last_pl.endswith('\\'):
                    physical_lines[-1] = last_pl[:-1].rstrip() + \
                        ' ' + inst_ks + ' \\\n'
                else:
                    physical_lines[-1] = last_pl + ' ' + inst_ks + '\n'
        output_lines.extend(physical_lines)
    else:
        output_lines.append(line)
    i += 1

content = ''.join(output_lines)
open(filepath, 'w').write(content)
PYEOF
    )" "$old_label" "$new_label" "$inst_ks_value" "$grub_file"

    # Write back
    mcopy -o -i "$efi_img" "$grub_file" "$grub_path"

    # Step D: Post-patch verification
    local verify_file="${work_dir}/grub-verify.cfg"
    mcopy -i "$efi_img" "$grub_path" "$verify_file"

    # Verify using python3 for accurate continuation-aware checking.
    local verify_result
    verify_result="$(python3 -c "$(cat << 'PYEOF'
import re, sys

old_label = sys.argv[1]
new_label = sys.argv[2]
inst_ks = sys.argv[3]
filepath = sys.argv[4]

content = open(filepath).read()
errors = []

# Check 1: Old label should not appear in known patterns
old_in_search = len(re.findall(
    r'search.*(?:--label|-l)\s+["\']?' + re.escape(old_label), content))
old_in_hd = len(re.findall(r'hd:LABEL=' + re.escape(old_label), content))
if old_label != new_label and (old_in_search + old_in_hd) > 0:
    errors.append(f"Old label '{old_label}' still present: "
                  f"{old_in_search} in search, {old_in_hd} in hd:LABEL=")

# Check 2: New label must appear at least once
new_in_search = len(re.findall(
    r'search.*(?:--label|-l)\s+["\']?' + re.escape(new_label), content))
new_in_hd = len(re.findall(r'hd:LABEL=' + re.escape(new_label), content))
if (new_in_search + new_in_hd) < 1:
    errors.append(f"New label '{new_label}' not found in any known pattern")

# Check 3: Every installer stanza must have exactly one inst.ks=
# Join continuation lines, find installer linux/linuxefi stanzas
lines = content.splitlines()
logical_lines = []
buf = ""
for line in lines:
    stripped = line.rstrip()
    if stripped.endswith('\\'):
        buf += stripped[:-1] + " "
    else:
        buf += stripped
        logical_lines.append(buf)
        buf = ""
if buf:
    logical_lines.append(buf)

installer_count = 0
missing_ks = 0
dup_ks = 0
wrong_ks = 0
for ll in logical_lines:
    if not re.match(r'\s*(linux|linuxefi)\s', ll):
        continue
    if 'inst.stage2=' not in ll:
        continue
    installer_count += 1
    # Extract all inst.ks= tokens from this stanza
    ks_tokens = [t for t in ll.split() if t.startswith('inst.ks=')]
    if len(ks_tokens) == 0:
        missing_ks += 1
    elif len(ks_tokens) > 1:
        dup_ks += 1
    elif ks_tokens[0] != inst_ks:
        wrong_ks += 1

if installer_count == 0:
    errors.append("No installer stanzas found (linux/linuxefi with inst.stage2=)")
if missing_ks > 0:
    errors.append(f"{missing_ks} installer stanza(s) missing inst.ks=")
if dup_ks > 0:
    errors.append(f"{dup_ks} installer stanza(s) have duplicate inst.ks=")
if wrong_ks > 0:
    errors.append(f"{wrong_ks} installer stanza(s) have wrong inst.ks= value (expected {inst_ks})")

if errors:
    print('FAIL:' + '|'.join(errors), end='')
else:
    print(f'OK:search={new_in_search},hd={new_in_hd},stanzas={installer_count}', end='')
PYEOF
    )" "$old_label" "$new_label" "$inst_ks_value" "$verify_file")"

    if [[ "$verify_result" == FAIL:* ]]; then
        local fail_detail="${verify_result#FAIL:}"
        error "Post-patch verification failed:"
        # Split on pipe and report each error
        while IFS='|' read -r -d '|' err_msg || [[ -n "$err_msg" ]]; do
            error "  - $err_msg"
        done <<< "$fail_detail"
        return 1
    fi
    success "  efiboot.img grub.cfg patched and verified ($verify_result)"

    # Step E: Detect appended EFI partition and re-inject via xorriso
    local xorriso_output
    local xorriso_rc=0
    xorriso_output="$(xorriso -indev "$iso_path" -report_system_area plain 2>&1)" || xorriso_rc=$?

    if [[ $xorriso_rc -ne 0 ]]; then
        error "xorriso -report_system_area failed (exit $xorriso_rc):"
        printf '%s\n' "$xorriso_output" >&2
        return 1
    fi

    # Parse for appended EFI partitions: lines with "Partition N ... 0xEF"
    # Tolerant of leading whitespace, case variations, and formatting changes.
    local -a efi_indices=()
    local partition_count=0
    local xline
    while IFS= read -r xline; do
        if [[ "$xline" =~ ^[[:space:]]*[Pp]artition[[:space:]]+([0-9]+) ]]; then
            local _part_idx="${BASH_REMATCH[1]}"
            partition_count=$((partition_count + 1))
            if [[ "$xline" =~ 0x[Ee][Ff] ]]; then
                efi_indices+=("$_part_idx")
            fi
        fi
    done <<< "$xorriso_output"

    # Deduplicate indices
    local -A seen_idx=()
    local -a unique_idx=()
    local idx
    for idx in "${efi_indices[@]}"; do
        if [[ -z "${seen_idx[$idx]:-}" ]]; then
            seen_idx[$idx]=1
            unique_idx+=("$idx")
        fi
    done

    local fixed_iso="${work_dir}/fixed.iso"

    if [[ ${#unique_idx[@]} -gt 1 ]]; then
        error "Multiple distinct EFI partition indices found: ${unique_idx[*]}"
        error "Ambiguous — cannot safely re-inject efiboot.img"
        return 1
    elif [[ ${#unique_idx[@]} -eq 0 && $partition_count -gt 0 ]]; then
        info "  Found $partition_count partition(s) but none matched EFI signature (0xEF)"
    fi

    if [[ ${#unique_idx[@]} -eq 1 ]]; then
        local efi_idx="${unique_idx[0]}"
        info "  Appended EFI partition found at index $efi_idx — re-injecting with -append_partition"
        xorriso -indev "$iso_path" -outdev "$fixed_iso" \
            -boot_image any replay \
            -update "$efi_img" /images/efiboot.img \
            -append_partition "$efi_idx" 0xEF "$efi_img"
    else
        info "  No appended EFI partition — updating efiboot.img in-place"
        xorriso -indev "$iso_path" -outdev "$fixed_iso" \
            -boot_image any replay \
            -update "$efi_img" /images/efiboot.img
    fi

    # Replace original ISO with patched version
    mv -f "$fixed_iso" "$iso_path"

    # Step F: Post-rewrite spot-check — verify ISO-level EFI grub.cfg survived xorriso
    local spot_check="${work_dir}/spot-check-grub.cfg"
    if ! osirrox -indev "$iso_path" -extract "/EFI/BOOT/grub.cfg" "$spot_check" 2>/dev/null; then
        error "Post-rewrite spot-check failed: /EFI/BOOT/grub.cfg missing from ISO after xorriso"
        return 1
    fi
    if ! grep -q 'inst\.ks=' "$spot_check" 2>/dev/null; then
        error "Post-rewrite spot-check failed: inst.ks= missing from ISO /EFI/BOOT/grub.cfg after xorriso"
        return 1
    fi
    success "  Post-rewrite spot-check passed: ISO /EFI/BOOT/grub.cfg intact"

    # Step G: Re-implant media checksum
    info "  Re-implanting media checksum (implantisomd5)..."
    implantisomd5 "$iso_path"

    success "efiboot.img patched successfully"
}

# ---------------------------------------------------------------------------
# Stage 11: Assemble ISO
# ---------------------------------------------------------------------------

stage_assemble_iso() {
    info "=== Stage 11: Assemble ISO ==="

    mkdir -p "$OUTPUT_DIR"

    local iso_date
    iso_date="$(date +%Y%m%d)"
    local output_iso="${OUTPUT_DIR}/surface-linux-F43-${iso_date}-x86_64.iso"

    # Remove any previous build output — mkksiso has no --force/--overwrite
    # flag and refuses to write to an existing path.
    if [[ -f "$output_iso" ]]; then
        info "Removing previous build: $(basename "$output_iso")"
    fi
    rm -f "$output_iso" "${output_iso}.sha256"

    # mkksiso -a SRC:DEST maps source directories to ISO root paths.
    # If mkksiso doesn't support :DEST syntax, use fallback with temp dirs.
    info "Preparing directories for ISO embedding..."

    # Fallback approach: create temp dirs with the exact names we want on the ISO
    local staging="/tmp/iso-staging"
    rm -rf "$staging"
    mkdir -p "$staging"

    # Copy/link directories with desired ISO names
    cp -a "$RPM_CACHE" "${staging}/local-repo"
    cp -a "$ASSET_CACHE" "${staging}/iso-assets"
    cp -a "/tmp/surface-linux" "${staging}/surface-linux"

    info "Running mkksiso to assemble ISO..."
    info "  Input: $BOOT_ISO"
    info "  Output: $output_iso"

    # -----------------------------------------------------------------------
    # Pre-flight: test actual loop device attachment (not just availability).
    # mkefiboot runs `losetup --find --show <file>` internally; the bare
    # `losetup --find` query that was here before tests a fundamentally
    # different capability (device nodes can exist but be non-functional).
    # -----------------------------------------------------------------------
    local -a mkksiso_flags=()
    local needs_efi_patch=false

    local _loop_probe_ok=false
    local _probe_file=""
    local _probe_loop=""

    # Install EXIT trap BEFORE mktemp/truncate so cleanup covers all paths,
    # including early failures (disk full, etc.) under set -e.
    _probe_cleanup() {
        [[ -n "${_probe_loop:-}" ]] && losetup -d "$_probe_loop" 2>/dev/null || true
        [[ -n "${_probe_file:-}" ]] && rm -f "$_probe_file"
    }
    trap _probe_cleanup EXIT

    _probe_file="$(mktemp /tmp/loop-probe.XXXXXX)"
    truncate -s 1M "$_probe_file"

    if _probe_loop="$(losetup --find --show "$_probe_file" 2>/dev/null)"; then
        # Detach immediately -- we only needed to test attachment
        losetup -d "$_probe_loop" 2>/dev/null || true
        _probe_loop=""
        _loop_probe_ok=true
        info "Loop device probe succeeded — mkefiboot will run normally"
    else
        _probe_loop=""
        warn "Loop device attachment failed — adding --skip-mkefiboot"
    fi
    # Explicit cleanup on normal path, then clear the EXIT trap
    _probe_cleanup
    trap - EXIT

    if [[ "$_loop_probe_ok" != true ]]; then
        mkksiso_flags+=(--skip-mkefiboot)
        needs_efi_patch=true
    fi

    # -----------------------------------------------------------------------
    # Run mkksiso (with defense-in-depth retry on mkefiboot/losetup failure)
    # -----------------------------------------------------------------------
    # NOTE: --ks already injects inst.ks=cdrom:/ks.cfg into boot configs.
    # Do NOT also pass -c "inst.ks=..." — that causes duplicate entries.
    local mkksiso_stderr
    mkksiso_stderr="$(mktemp /tmp/mkksiso-stderr.XXXXXX)"

    local mkksiso_rc=0
    mkksiso --ks /tmp/kickstart.ks \
        "${mkksiso_flags[@]}" \
        -a "${staging}/local-repo" \
        -a "${staging}/iso-assets" \
        -a "${staging}/surface-linux" \
        -V "SurfaceLinux-43" \
        "$BOOT_ISO" \
        "$output_iso" \
        2> "$mkksiso_stderr" || mkksiso_rc=$?

    if [[ $mkksiso_rc -ne 0 ]]; then
        # Check if the failure is mkefiboot/losetup-related (tight substring match)
        local retry_match=false
        local pattern
        for pattern in "mkefiboot" "losetup:" "loop_attach" "failed to set up loop device"; do
            if grep -qi "$pattern" "$mkksiso_stderr" 2>/dev/null; then
                retry_match=true
                break
            fi
        done

        if [[ "$retry_match" == true && "$needs_efi_patch" == false ]]; then
            # First attempt failed with mkefiboot/losetup error — retry once
            # with --skip-mkefiboot
            warn "mkksiso failed with mkefiboot/losetup error — retrying with --skip-mkefiboot"
            local first_stderr
            first_stderr="$(mktemp /tmp/mkksiso-stderr-first.XXXXXX)"
            cp "$mkksiso_stderr" "$first_stderr"

            # Remove partially written output ISO before retry
            rm -f "$output_iso"

            mkksiso_flags+=(--skip-mkefiboot)
            needs_efi_patch=true

            local retry_rc=0
            mkksiso --ks /tmp/kickstart.ks \
                "${mkksiso_flags[@]}" \
                -a "${staging}/local-repo" \
                -a "${staging}/iso-assets" \
                -a "${staging}/surface-linux" \
                -V "SurfaceLinux-43" \
                "$BOOT_ISO" \
                "$output_iso" \
                2> "$mkksiso_stderr" || retry_rc=$?

            if [[ $retry_rc -ne 0 ]]; then
                error "mkksiso retry also failed (exit $retry_rc)"
                error "--- First attempt stderr ---"
                cat "$first_stderr" >&2
                error "--- Retry attempt stderr ---"
                cat "$mkksiso_stderr" >&2
                rm -f "$first_stderr" "$mkksiso_stderr"
                exit 1
            fi
            rm -f "$first_stderr"
            success "mkksiso retry with --skip-mkefiboot succeeded"
        else
            # Non-mkefiboot error, or already retried — fail immediately
            error "mkksiso failed (exit $mkksiso_rc)"
            cat "$mkksiso_stderr" >&2
            rm -f "$mkksiso_stderr"
            exit 1
        fi
    fi
    rm -f "$mkksiso_stderr"

    # -----------------------------------------------------------------------
    # Verify no duplicate inst.ks entries in boot configs
    # -----------------------------------------------------------------------
    # Continuation-aware: joins GRUB \ continuation lines into logical
    # cmdlines before checking for duplicates. Multiple boot entries each
    # having their own inst.ks= is normal; the bug we guard against is
    # duplicate inst.ks= tokens on the SAME logical linux/linuxefi cmdline.
    _assert_no_dup_inst_ks_in_file() {
        local path="$1"
        local label="$2"
        local result
        result="$(python3 -c "$(cat << 'PYEOF'
import re, sys

filepath = sys.argv[1]
content = open(filepath).read()

# Join backslash-continuation lines into logical lines
lines = content.splitlines()
logical_lines = []
buf = ""
for line in lines:
    stripped = line.rstrip()
    if stripped.endswith("\\"):
        buf += stripped[:-1] + " "
    else:
        buf += stripped
        logical_lines.append(buf)
        buf = ""
if buf:
    logical_lines.append(buf)

# Only check linux/linuxefi cmdlines (kernel boot commands).
# This avoids false positives from comments or non-kernel GRUB directives.
any_found = False
for ll in logical_lines:
    if not re.match(r'\s*(linux|linuxefi)\s', ll):
        continue
    c = ll.count("inst.ks=")
    if c > 0:
        any_found = True
    if c > 1:
        print("DUP:" + ll.strip(), end="")
        sys.exit(0)

if not any_found:
    print("MISSING", end="")
else:
    print("OK", end="")
PYEOF
        )" "$path")"

        if [[ "$result" == DUP:* ]]; then
            local dup_line="${result#DUP:}"
            error "Duplicate inst.ks= on one logical cmdline in $label:"
            error "  $dup_line"
            return 1
        fi
        if [[ "$result" == "MISSING" ]]; then
            error "No inst.ks= found in $label"
            return 1
        fi
        return 0
    }

    # -------------------------------------------------------------------
    # _verify_inst_ks_iso_configs — Check ISO-level boot configs
    # -------------------------------------------------------------------
    # Checks BIOS GRUB2 configs (warn-only) and ISO-level /EFI/BOOT/grub.cfg
    # (required, hard-fail). Run BEFORE optional efiboot.img patching.
    _verify_inst_ks_iso_configs() {
        local iso_path="$1"
        local tmp_mount
        tmp_mount="$(mktemp -d /tmp/iso-verify-iso.XXXXXX)"
        trap 'rm -rf "$tmp_mount"; trap - RETURN' RETURN

        # BIOS: check GRUB2 configs from ISO filesystem (Fedora 37+ uses GRUB2,
        # not isolinux/syslinux). Keep legacy candidates as trailing fallbacks.
        local bios_cfg=""
        local bios_candidate
        for bios_candidate in \
            "/boot/grub2/grub.cfg" \
            "/boot/grub/grub.cfg" \
            "/isolinux/isolinux.cfg" \
            "/syslinux/syslinux.cfg"; do
            if osirrox -indev "$iso_path" -extract "$bios_candidate" "${tmp_mount}/bios.cfg" 2>/dev/null; then
                bios_cfg="${tmp_mount}/bios.cfg"
                break
            fi
        done

        # BIOS: warn if absent — Surface Go 3 is UEFI-only, BIOS boot is optional
        if [[ -z "$bios_cfg" ]]; then
            warn "No BIOS boot config found (grub2/grub.cfg, isolinux.cfg, syslinux.cfg) — skipping BIOS inst.ks= check"
        else
            if ! _assert_no_dup_inst_ks_in_file "$bios_cfg" "BIOS config ($bios_candidate)"; then
                return 1
            fi
            info "BIOS config ($bios_candidate): no duplicate inst.ks= on any cmdline"
        fi

        # ISO-level EFI: /EFI/BOOT/grub.cfg — required (mkksiso EditGrub2 always modifies this)
        local iso_efi_grub="${tmp_mount}/efi-boot-grub.cfg"
        if ! osirrox -indev "$iso_path" -extract "/EFI/BOOT/grub.cfg" "$iso_efi_grub" 2>/dev/null; then
            error "ISO-level /EFI/BOOT/grub.cfg not found — mkksiso may have failed"
            return 1
        fi

        if ! _assert_no_dup_inst_ks_in_file "$iso_efi_grub" "ISO /EFI/BOOT/grub.cfg"; then
            return 1
        fi
        info "ISO /EFI/BOOT/grub.cfg: no duplicate inst.ks= on any cmdline"

        # /EFI/BOOT/BOOT.conf (Apple EFI) — warn-only diagnostic
        local apple_conf="${tmp_mount}/boot.conf"
        if osirrox -indev "$iso_path" -extract "/EFI/BOOT/BOOT.conf" "$apple_conf" 2>/dev/null; then
            if ! _assert_no_dup_inst_ks_in_file "$apple_conf" "ISO /EFI/BOOT/BOOT.conf"; then
                warn "/EFI/BOOT/BOOT.conf has inst.ks= issue — non-fatal (Apple EFI path)"
            else
                info "ISO /EFI/BOOT/BOOT.conf: inst.ks= verified"
            fi
        fi

        success "ISO-level boot config verification passed"
    }

    # -------------------------------------------------------------------
    # _verify_inst_ks_efiboot — Check efiboot.img internal grub.cfg
    # -------------------------------------------------------------------
    # Checks the grub.cfg INSIDE efiboot.img (USB UEFI boot path).
    # Run AFTER optional efiboot.img patching.
    _verify_inst_ks_efiboot() {
        local iso_path="$1"
        local tmp_mount
        tmp_mount="$(mktemp -d /tmp/iso-verify-efi.XXXXXX)"
        trap 'rm -rf "$tmp_mount"; trap - RETURN' RETURN

        # Extract efiboot.img from ISO
        local efi_img="${tmp_mount}/efiboot.img"
        if ! osirrox -indev "$iso_path" -extract "/images/efiboot.img" "$efi_img" 2>/dev/null; then
            error "Cannot extract efiboot.img from ISO — cannot verify EFI internal boot config"
            return 1
        fi

        # Locate grub.cfg inside the FAT image
        local efi_grub=""
        local efi_candidate
        for efi_candidate in "::/EFI/BOOT/grub.cfg" "::/EFI/fedora/grub.cfg"; do
            if mcopy -o -i "$efi_img" "$efi_candidate" "${tmp_mount}/efi-grub.cfg" 2>/dev/null; then
                efi_grub="${tmp_mount}/efi-grub.cfg"
                break
            fi
        done

        if [[ -z "$efi_grub" ]]; then
            error "Cannot locate grub.cfg inside efiboot.img — cannot verify EFI internal boot config"
            return 1
        fi

        if ! _assert_no_dup_inst_ks_in_file "$efi_grub" "efiboot.img grub.cfg ($efi_candidate)"; then
            return 1
        fi
        info "efiboot.img grub.cfg ($efi_candidate): no duplicate inst.ks= on any cmdline"

        success "efiboot.img internal boot config verification passed"
    }

    # -----------------------------------------------------------------------
    # Pre-patch: verify ISO-level boot configs
    # -----------------------------------------------------------------------
    if ! _verify_inst_ks_iso_configs "$output_iso"; then
        error "ISO-level boot config verification failed — aborting"
        exit 1
    fi

    # -----------------------------------------------------------------------
    # Patch efiboot.img when --skip-mkefiboot was used and -V changed the label
    # -----------------------------------------------------------------------
    if [[ "$needs_efi_patch" == true ]]; then
        local inst_ks_value
        if ! inst_ks_value="$(_extract_inst_ks_from_iso "$output_iso")"; then
            error "Cannot derive inst.ks= value from ISO — aborting"
            exit 1
        fi
        info "Derived inst.ks= value from ISO: $inst_ks_value"

        if ! patch_efiboot "$output_iso" "SurfaceLinux-43" "$inst_ks_value"; then
            error "efiboot.img patching failed — aborting"
            exit 1
        fi
    fi

    # -----------------------------------------------------------------------
    # Post-patch: verify efiboot.img internal grub.cfg
    # -----------------------------------------------------------------------
    if ! _verify_inst_ks_efiboot "$output_iso"; then
        error "efiboot.img boot config verification failed — aborting"
        exit 1
    fi

    # Clean up staging
    rm -rf "$staging"

    # Generate checksum (after all patching is complete)
    local sha256
    sha256="$(sha256sum "$output_iso" | awk '{print $1}')"
    echo "$sha256  $(basename "$output_iso")" > "${output_iso}.sha256"

    local iso_size
    iso_size="$(du -h "$output_iso" | awk '{print $1}')"
    success "ISO assembled: $output_iso ($iso_size)"
    info "SHA256: $sha256"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"
    resolve_credentials

    info "Surface Linux ISO Builder"
    info "========================="
    info "Username:      $USERNAME"
    info "Validate only: $VALIDATE_ONLY"
    info "Test mode:     $TEST_MODE"
    info "Output dir:    $OUTPUT_DIR"
    info "Cache dir:     $CACHE_DIR"
    echo ""

    # Stage 2: Expand @^minimal-environment
    stage_expand_minimal_env

    # Extract target packages from lib/*.sh
    extract_target_packages

    # Stage 3: Download all RPMs
    stage_download_rpms

    # Stage 4: Create local repo
    stage_create_repo

    # Stage 5: Validate repo (repoclosure)
    stage_validate_repo

    # In validate-only mode, stop after repo validation (stages 2-5)
    if [[ "$VALIDATE_ONLY" == true ]]; then
        success "Validation complete. Repo download and dependency closure verified."
        return
    fi

    # Stage 1: Download boot.iso
    stage_download_boot_iso

    # Stage 6: Download binaries
    stage_download_binaries

    # Stage 7: Download fonts
    stage_download_fonts

    # Stage 8: Pre-clone lazy.nvim
    stage_clone_lazy_nvim

    # Stage 9: Copy surface-linux repo + generate theme
    stage_prepare_repo

    # Stage 10: Substitute credentials
    stage_substitute_credentials

    # Stage 11: Assemble ISO
    stage_assemble_iso

    echo ""
    success "ISO build complete!"
}

main "$@"
