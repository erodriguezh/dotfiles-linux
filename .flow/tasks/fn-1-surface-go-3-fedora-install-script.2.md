## Description

Create 4 lib scripts covering the `repos`, `kernel`, `packages`, and `binaries` install stages for Fedora 43. Installs dnf5 plugins, enables 3 COPRs + linux-surface external repo, installs the Surface kernel, installs all desktop + system packages, and downloads pre-built binaries.

**Size:** M
**Files:** `lib/01-repos.sh`, `lib/02-kernel.sh`, `lib/03-packages.sh`, `lib/04-binaries.sh`

## Approach

### lib/01-repos.sh (`run_repos`)
- Install dnf5 plugins first: `sudo $DNF install -y dnf5-plugins` (provides copr + config-manager subcommands). If the specific virtual provides `dnf5-command(copr)` etc. work, use those; fall back to `dnf5-plugins` package name.
- Enable 3 COPRs idempotently: `sudo $DNF -y copr enable sdegler/hyprland`, `scottames/ghostty`, `alternateved/tofi`
- Add linux-surface repo: `sudo $DNF config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo --overwrite`
- Remove stale solopasha COPR if present: `sudo $DNF copr remove solopasha/hyprland 2>/dev/null || true`

### lib/02-kernel.sh (`run_kernel`)
- Install `kernel-surface libwacom-surface` with `--allowerasing` flag (iptsd excluded per epic touchscreen-disabled decision)
- Install only — do NOT enable services here (all `systemctl enable` centralized in Task 4)

### lib/03-packages.sh (`run_packages`)
- Single `sudo $DNF install -y` with complete package list (dnf is already idempotent)
- **COPR packages**: hyprland, hyprlock, hypridle, hyprpaper, hyprpolkitagent, hyprland-guiutils, waybar-git (NOT waybar), cliphist, ghostty, tofi, uwsm, xdg-desktop-portal-hyprland
- **XDG portal stack**: xdg-desktop-portal, xdg-desktop-portal-gtk (required for GTK file dialogs)
- **Bluetooth**: bluez (bluetooth daemon stack)
- **Power management**: tuned, tuned-ppd
- **Audio/video**: wireplumber, pipewire
- **Notifications**: mako
- **Screenshots**: grim, slurp
- **Networking**: NetworkManager, iwd
- **Keybind tools**: brightnessctl (screen brightness), playerctl (media control)
- **System**: plymouth, polkit, wl-clipboard, curl, jq, git, unzip
- **Neovim + deps**: neovim, tree-sitter-cli (for LazyVim v15.x)
- Verify: full package list must be audited against Fedora 43 repos during implementation

### lib/04-binaries.sh (`run_binaries`)
- Download Impala v0.7.3 and bluetui v0.8.1 from GitHub Releases
- Use `curl -fSL` (fail on HTTP errors)
- Install to `~/.local/bin/` with `chmod +x`
- Skip download if binary already exists and matches expected version (check via `<binary> --version`; if `--version` is unsupported, always re-download)
- Detect architecture: `ARCH=$(uname -m)` → map to download URL

## Key context

- All package operations use `sudo $DNF` (where `$DNF=dnf5` from common.sh)
- `waybar-git` (from sdegler COPR) NOT `waybar` (Fedora repos)
- `hyprland-guiutils` NOT `hyprland-qtutils` — renamed package
- `--allowerasing` REQUIRED for kernel-surface
- All downloads in this task complete BEFORE the network stage switches to iwd
- `bluez`, `tuned`, `tuned-ppd` MUST be in package list — Task 4 enables their services

## Acceptance

- [ ] dnf5 plugins installed before any COPR/repo operations
- [ ] Plugin verification: `$DNF copr --help` and `$DNF config-manager --help` succeed after install (fail with clear error if not)
- [ ] 3 COPRs enabled: sdegler/hyprland, scottames/ghostty, alternateved/tofi
- [ ] linux-surface external repo added via `config-manager addrepo`
- [ ] `kernel-surface`, `libwacom-surface` installed with `--allowerasing` (iptsd excluded per epic touchscreen-disabled decision)
- [ ] Full Hyprland ecosystem from COPR installed
- [ ] XDG portal stack installed: xdg-desktop-portal, xdg-desktop-portal-gtk, xdg-desktop-portal-hyprland
- [ ] Bluetooth + power packages installed: bluez, tuned, tuned-ppd
- [ ] Official repo packages installed: grim, slurp, mako, wireplumber, neovim, iwd, plymouth, tree-sitter-cli
- [ ] Impala v0.7.3 and bluetui v0.8.1 in `~/.local/bin/`
- [ ] Idempotent: re-running produces no errors
- [ ] All `sudo` used explicitly (not running as root)

## Done summary

_To be filled after implementation._

## Evidence

_To be filled after implementation._
