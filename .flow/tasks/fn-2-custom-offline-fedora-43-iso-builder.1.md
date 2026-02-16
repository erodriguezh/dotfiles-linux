## Description

Create the ISO build pipeline: a Containerfile for the Fedora 43 build environment and a `build-iso.sh` orchestrator script that produces a self-contained, offline-installable ISO.

**Size:** M
**Files:** `iso/build-iso.sh`, `iso/Containerfile`

## Approach

### Containerfile (`iso/Containerfile`)
- Base: `registry.fedoraproject.org/fedora:43`
- Install **ONLY build tools**: `lorax` (provides mkksiso), `createrepo_c`, `dnf5-plugins`, `git`, `jq`, `xorriso`, `isomd5sum`
- Enable 3 COPRs: `sdegler/hyprland`, `scottames/ghostty`, `alternateved/tofi`
- Add linux-surface repo via `dnf5 config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo`
- **FORBIDDEN**: The Containerfile must NOT install any target runtime packages (hyprland, ghostty, kernel-surface, etc.). Only build tools are allowed. Installing target packages would cause `dnf5 download --resolve` to miss their transitive dependencies.
- Workdir: `/build`

### build-iso.sh (`iso/build-iso.sh`)
Follow the project's shell conventions from `lib/00-common.sh:1-11`: `set -Eeuo pipefail`, `shopt -s inherit_errexit`, color logging helpers.

**Credential input (priority order):**
1. `--password-hash-file=PATH` — reads hash from file (recommended, avoids shell history)
2. `ISO_PASSWORD_HASH` environment variable — useful for CI
3. `--password-hash=HASH` — direct CLI (convenience, leaks to shell history — warn in help text)

**Other arguments:**
- `--username=NAME` (required unless `--test` or `--validate-only`)
- `--test` — use dummy credentials for dev builds
- `--validate-only` — dry run: downloads + repo creation + repoclosure check, but skips mkksiso
- `--boot-iso=PATH` — path to Fedora boot.iso (auto-downloads if not provided)
- `--output-dir=PATH` — output directory (default: `./output/`)

**The script MUST NOT log password hashes in any output** (no `set -x` over credential handling, no echoing hash values).

**Cache paths:** All downloads use workspace-relative `.cache/` directory (not container `/tmp/`), so GitHub Actions can cache between runs:
- RPMs: `/build/.cache/rpms` (where `/build` is the workspace mount)
- Boot ISO: `/build/.cache/isos/fedora-boot-43.iso`
- Assets: `/build/.cache/assets/`

**Stages (in order):**

1. **Download Fedora boot.iso** — if not provided via `--boot-iso` and not cached in `.cache/isos/`, download from Fedora mirrors. Verify SHA256 checksum.

2. **Expand @^minimal-environment** — extract individual package names from the group:
   ```
   dnf5 group info '@^minimal-environment' --quiet → parse mandatory/default package names
   ```
   This avoids relying on `dnf5 download` group support (historically fragile).

3. **Download all RPMs** — Extract package list from `lib/03-packages.sh` (the `pkgs=()` array), `lib/02-kernel.sh` (kernel-surface, libwacom-surface), combine with expanded minimal-environment packages. Run `dnf5 download --resolve --destdir=/build/.cache/rpms --arch=x86_64 --arch=noarch <all-packages>`. This MUST run inside the container (minimal env with no target packages) to capture all transitive deps.

4. **Create local repo** — Run `createrepo_c /build/.cache/rpms`. This generates the repodata Anaconda needs.

5. **Validate repo (repoclosure)** — Verify the local repo can satisfy ALL packages + `@^minimal-environment` without external repos. Run in an isolated context with only the local repo enabled:
   ```
   dnf5 \
     --setopt=reposdir=/dev/null \
     --setopt=local-only.name=local-only \
     --setopt=local-only.baseurl=file:///build/.cache/rpms \
     --setopt=local-only.enabled=1 \
     install --assumeno --repo=local-only \
       "${minimal_env_pkgs[@]}" "${all_pkgs[@]}"
   ```
   Where `minimal_env_pkgs[@]` is the expanded package list from Stage 2 and `all_pkgs[@]` is from `lib/03-packages.sh` + `lib/02-kernel.sh`. Use expanded package names, NOT the `@^minimal-environment` group token — the local repo has no comps.xml group metadata. This explicit `--setopt` pattern configures a temporary repo pointing only at the local cache, with no external repos (`reposdir=/dev/null`). This MUST pass before proceeding to ISO assembly. Runs in both `--validate-only` and full build modes. CI and local runs use the identical pattern.

6. **Download binaries** — Following URL patterns from `lib/04-binaries.sh:68-87`: download impala, bluetui, starship for x86_64. **Must use the same version constants** as `lib/04-binaries.sh` (impala_version, bluetui_version, starship_version). Place in `/build/.cache/assets/binaries/`.

7. **Download fonts** — Following pattern from `lib/05-fonts.sh:10-11`: download JetBrains Mono Nerd Font tar.xz. **Must use the same version constant** as `lib/05-fonts.sh`. Extract to `/build/.cache/assets/fonts/JetBrainsMono/`. Write `.nf-version` file matching `lib/05-fonts.sh` layout.

8. **Pre-clone lazy.nvim** — `git clone --filter=blob:none --branch=stable https://github.com/folke/lazy.nvim.git /build/.cache/assets/lazy-nvim/`

9. **Copy surface-linux repo** — Copy the repo (from the build context mount) to staging directory. Generate theme files using existing template engine logic (process `colors.toml` + `templates/*.tpl` → `config/` output files). These are .gitignored so must be generated at build time.

10. **Substitute credentials** — Copy `iso/surface-go3-iso.ks` to temp, substitute `@@USERNAME@@` and `@@PASSWORD_HASH@@` placeholders with provided values.

11. **Assemble ISO** — Run mkksiso with explicit path mapping:
    ```
    mkksiso --ks /tmp/kickstart.ks \
      -a /build/.cache/rpms:/local-repo \
      -a /build/.cache/assets:/iso-assets \
      -a /tmp/surface-linux:/surface-linux \
      -c "inst.ks=cdrom:/ks.cfg" \
      -V "SurfaceLinux-43" \
      /build/.cache/isos/fedora-boot-43.iso \
      /build/output/surface-linux-F43-$(date +%Y%m%d)-x86_64.iso
    ```
    Note: `inst.ks=cdrom:/ks.cfg` is the correct Anaconda form (NOT `file:///`). Must run as root (mkksiso requirement since lorax 38.4).

    After mkksiso, the in-ISO layout is:
    - `/ks.cfg` — kickstart (auto-loaded via `inst.ks=cdrom:/ks.cfg`)
    - `/local-repo/` — offline RPM repo (referenced by kickstart `repo --baseurl=file:///run/install/isodir/local-repo`)
    - `/iso-assets/` — binaries, fonts, lazy.nvim
    - `/surface-linux/` — the dotfiles repo with generated theme files

**Package extraction from lib/*.sh:**
Parse `lib/03-packages.sh` to extract the `pkgs=()` array contents. Use grep/sed to extract package names. This avoids duplicating the package list — `lib/03-packages.sh` remains the single source of truth.

## Key context

- `mkksiso` must run as root (lorax 38.4+). The container runs as root by default.
- `mkksiso -a SRC:DEST` maps source directories to specific ISO root paths. If mkksiso on Fedora 43 does not support `:DEST` syntax, use a fallback: copy directories to temp paths with the desired names (`/tmp/local-repo`, `/tmp/iso-assets`, `/tmp/surface-linux`) and use plain `-a` flags.
- `dnf5 download --resolve` uses `--destdir` (NOT `--downloaddir`, removed in dnf5). Include `--arch=noarch` alongside `--arch=x86_64`.
- `createrepo_c` generates yum-compatible repo metadata that Anaconda expects.
- Theme engine outputs are `.gitignored` (`.gitignore:5-11`). They MUST be generated during build.
- Shell conventions: `set -Eeuo pipefail`, `shopt -s inherit_errexit`, `readonly` for constants, `info()`/`warn()`/`error()` color helpers.
- Cache directory pattern: `/build/.cache/` maps to `${REPO_ROOT}/.cache/` on host, enabling GitHub Actions caching.

## Done summary

## Evidence
