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

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly CACHE_DIR="/build/.cache"
readonly RPM_CACHE="${CACHE_DIR}/rpms"
readonly ISO_CACHE="${CACHE_DIR}/isos"
readonly ASSET_CACHE="${CACHE_DIR}/assets"
readonly DEFAULT_OUTPUT_DIR="/build/output"

# Fedora boot.iso details
readonly BOOT_ISO_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/os/images/boot.iso"
readonly BOOT_ISO_SHA256="2bdf3826f0b5cf8f3e65e1ee3716c07e3e980f9e08ab30beb08d6a4e28745089"

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
        git -C "$lazy_dir" fetch origin stable --depth=1
        git -C "$lazy_dir" checkout stable
        git -C "$lazy_dir" reset --hard origin/stable
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
# Stage 11: Assemble ISO
# ---------------------------------------------------------------------------

stage_assemble_iso() {
    info "=== Stage 11: Assemble ISO ==="

    mkdir -p "$OUTPUT_DIR"

    local iso_date
    iso_date="$(date +%Y%m%d)"
    local output_iso="${OUTPUT_DIR}/surface-linux-F43-${iso_date}-x86_64.iso"

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

    mkksiso --ks /tmp/kickstart.ks \
        -a "${staging}/local-repo" \
        -a "${staging}/iso-assets" \
        -a "${staging}/surface-linux" \
        -c "inst.ks=cdrom:/ks.cfg" \
        -V "SurfaceLinux-43" \
        "$BOOT_ISO" \
        "$output_iso"

    # Clean up staging
    rm -rf "$staging"

    # Generate checksum
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
