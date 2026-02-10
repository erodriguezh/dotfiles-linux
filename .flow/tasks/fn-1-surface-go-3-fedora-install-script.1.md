## Description

Create the main entry point `install.sh` and shared library `lib/00-common.sh` that all stage scripts depend on. Also create the root `.gitignore`.

**Size:** M
**Files:** `install.sh`, `lib/00-common.sh`, `.gitignore`

## Approach

- `install.sh`: Source all `lib/*.sh` files in sorted order, parse `--only`/`--skip`/`--list` CLI flags, run stages sequentially from the STAGES array. Must be run as the target user (NOT root). Call `sudo -v` at startup to cache credentials.
- `lib/00-common.sh`: Define shared functions (logging with color, `info`/`warn`/`error`/`success`, `ensure_sudo`, `is_installed`, `stage_header`), constants (`REPO_DIR`, `CONFIG_DIR`, `LOG_FILE`, `DNF=dnf5`), and the `STAGES` array
- `.gitignore`: Ignore `.idea/`, generated config files (`config/hypr/colors.conf`, `config/waybar/colors.css`, `config/ghostty/theme`, `config/mako/colors`, `config/tofi/colors`, `config/hypr/hyprlock-colors.conf`, `config/gtk-3.0/settings.ini`, `config/gtk-4.0/settings.ini`), `*.log`
- Use `set -Eeuo pipefail` + `shopt -s inherit_errexit` as the strict-mode preamble
- Separate `local` declaration from assignment to avoid masking failures (`local var; var=$(cmd)`)
- Trap on EXIT for cleanup, trap on ERR for diagnostic line/command info
- Log to `/tmp/surface-install.log` with tee
- Stage ordering: `repos → kernel → packages → binaries → zram → network → desktop → theme → dotfiles → neovim → services`
- `--only <stage>` should warn if running without prerequisites
- Each lib file defines a `run_<stage>()` function; `install.sh` calls them in order

## Key context

- `install.sh` runs as the target user, NOT root. System operations use `sudo` explicitly via `$DNF` or direct `sudo` calls.
- `DNF=dnf5` variable in common.sh — all package operations use this consistently.
- `lib/` files define functions only — no top-level execution. `install.sh` sources them then invokes `run_<stage>()`.
- `set -e` inside conditionals silently disables `errexit` for nested calls — critical commands need explicit checks.

## Acceptance

- [ ] `./install.sh --list` prints all 11 stages in order
- [ ] `./install.sh` refuses to run as root (checks `$EUID != 0`)
- [ ] `sudo -v` called at startup to cache credentials
- [ ] `./install.sh --only <stage>` runs only that stage with prerequisite warning
- [ ] `./install.sh --skip <stage>` skips that stage
- [ ] Colored output: stage headers, info (blue), warn (yellow), error (red), success (green)
- [ ] Log file written to `/tmp/surface-install.log`
- [ ] `set -Eeuo pipefail` + `shopt -s inherit_errexit` in both files
- [ ] ERR trap shows failing command and line number
- [ ] `.gitignore` covers `.idea/`, all generated config files per contract, log files
- [ ] All lib files sourceable without side effects (functions only)
- [ ] `DNF=dnf5` defined in common.sh

## Done summary
Created install.sh entry point with CLI parsing (--list/--only/--skip/--help), root check, sudo credential caching with keepalive, deterministic lib sourcing, and stage execution with recursive prerequisite resolution. Created lib/00-common.sh with shared constants (DNF=dnf5, REPO_DIR, CONFIG_DIR, LOG_FILE), 12-stage STAGES array with STAGE_DEPS prerequisite map, colored logging respecting NO_COLOR, utility functions (ensure_sudo, is_installed, is_surface_hardware), and ERR/EXIT trap handlers. Created .gitignore covering IDE files, all generated theme config files per contract, and logs.
## Evidence
- Commits: 3461c07, d6de97d, f9e8627
- Tests: manual review: CLI parsing, stage deps, trap behavior, .gitignore coverage
- PRs: