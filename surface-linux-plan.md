# Surface Go 3 Fedora Install Script

## Overview

Build an idempotent Bash install script for **Fedora 43** on a Surface Go 3 (4GB RAM, Intel Pentium Gold 6500Y). A Kickstart file automates the base Fedora installation from the **Everything (netinstall) ISO** with Minimal Install (no desktop environment, no display manager). After first boot, `install.sh` sources modular function files from `lib/`, each defining functions only. The script runs all stages sequentially with `--only`/`--skip`/`--list` CLI support. After running once and rebooting, the machine boots into a fully configured Hyprland desktop with Tokyo Night theming.

## Target Platform

- **OS**: Fedora 43 (released Oct 2025, kernel 6.17)
- **Base Image**: Fedora Everything (netinstall) ISO → Minimal Install
- **Hardware**: Surface Go 3 — Intel Pentium Gold 6500Y (AES-NI capable), 4GB LPDDR3, eMMC storage (`/dev/mmcblk0`)
- **No encryption**: Plain ext4, no LUKS (eMMC is soldered, low theft-data risk)
- **Display**: 10.5" 1920x1280 (~220 PPI), 1.5x scaling
- **Secure Boot**: Already disabled in UEFI (prerequisite documented in README)
- **Locale**: en_US.UTF-8, German keyboard (de-latin1), Europe/Vienna timezone

## Privilege Model

`install.sh` MUST be run as the **target user** (not root). Individual operations that need root use `sudo` explicitly. The script calls `sudo -v` at startup to cache credentials. This ensures:
- `$HOME`, `~/.config/`, `~/.local/` paths resolve to the user's home
- All dotfiles and configs are owned by the user
- Only system-level operations (dnf, systemctl, writing to /etc/) use sudo

## Scope

- `kickstart/surface-go3.ks` — Automated Anaconda partitioning + minimal install + bootstrap
- `install.sh` entry point + modular lib files
- Omarchy-inspired template system (colors.toml → sed → .tpl files)
- Split-by-concern Hyprland config tree for 0.53+ (new windowrule syntax)
- App configs: waybar, mako, ghostty, tofi, hyprlock, hypridle, hyprpaper
- Config deployment via symlinks from repo to `~/.config/`
- Pre-built binary management (Impala, bluetui)
- JetBrains Mono Nerd Font download and installation
- Starship prompt with Tokyo Night colors
- LazyVim + Tokyo Night Neovim setup (replicate Omarchy's config, then trim)
- Full USB preparation guide in README + keybind cheat sheet (docs/keybinds.md)

## Kickstart File (`kickstart/surface-go3.ks`)

Automates the Fedora installation via Anaconda:
- **Disk target**: `ignoredisk --only-use=mmcblk0` (auto-detect eMMC, ignore USB)
- **Partitioning**: `reqpart --add-boot` (auto EFI + /boot) + ext4 root (rest of disk), no swap partition (zram handles it). Fedora 43 default `/boot` is 2 GiB.
- **No encryption**: Plain ext4
- **User account**: Prompted interactively via `%pre` script at boot time. Password hashed with SHA-512 (`openssl passwd -6`) in `%pre`. Created with `--groups wheel --iscrypted` for sudo access.
- **Root password**: `rootpw --lock` (no root login; user has sudo via wheel)
- **Package selection**: Minimal Install (no desktop, no display manager) + `sudo` package
- **Locale**: `lang en_US.UTF-8`, `keyboard de-latin1`, `timezone Europe/Vienna`
- **Network**: User connects WiFi via Anaconda GUI (Everything ISO needs network)
- **Post-install bootstrap**: Installs git, clones repo (default branch) to `/home/<user>/surface-linux` using a `REPO_URL` placeholder, sets ownership with `chown -R`, prints instructions. User runs `install.sh` manually after first boot.
- **Repo URL**: Placeholder `REPO_URL` that user edits before writing USB. Repo is public (HTTPS clone, no auth needed).

## Hardware Detection

The script detects Surface Go 3 hardware via DMI product name. On non-Surface hardware:
- **Auto-skip Surface-specific stages**: kernel (kernel-surface) and any Surface-specific config
- **Continue with everything else**: Hyprland, packages, configs, theme all work on any Fedora 43 machine
- This allows testing in VMs or on other hardware

## Display Scaling (1.5x)

Surface Go 3's 10.5" 1920x1280 display (~220 PPI) uses 1.5x scaling:
- **Hyprland**: `monitor = eDP-1, 1920x1280, auto, 1.5` + `xwayland { force_zero_scaling = true }`
- **External monitors**: Hyprland auto-detect (no hardcoded external config)
- **XCURSOR_SIZE=24, GDK_SCALE=1**: Set in UWSM env files (not hyprland.conf)
- **XWayland DPI**: `~/.Xresources` with `Xft.dpi: 144` (96 × 1.5), loaded via `exec-once = xrdb -merge ~/.Xresources`
- **Caveat**: Some GTK3/Electron apps may appear slightly blurry under XWayland (toolkit limitation)

## Package Sources (Fedora 43)

### COPR Repositories (3 COPRs + 1 external repo)
1. **sdegler/hyprland** (COPR) — Full Hyprland ecosystem (ABI-compatible set):
  - hyprland 0.53.3+, hyprlock, hypridle, hyprpaper, hyprpolkitagent, hyprland-guiutils, waybar-git, cliphist, uwsm, xdg-desktop-portal-hyprland
2. **scottames/ghostty** (COPR) — Ghostty terminal emulator
3. **alternateved/tofi** (COPR) — tofi app launcher (prebuilt RPM, no build-from-source needed)
4. **linux-surface** (external repo via `config-manager addrepo`, NOT `copr enable`) — kernel-surface, libwacom-surface

### Fedora Official Repos
- grim, slurp (screenshots), mako (notifications), wireplumber + pipewire (audio), NetworkManager, plymouth, neovim, iwd
- xdg-desktop-portal, xdg-desktop-portal-gtk (required for GTK file dialogs and portal stack)
- bluez (bluetooth stack), tuned, tuned-ppd (power profiles)
- polkit, wl-clipboard
- starship (prompt)
- All system/build dependencies (curl, jq, git, unzip, tree-sitter-cli)

### Pre-built Binaries (GitHub Releases)
- Impala v0.7.3 — WiFi TUI (`impala-${ARCH}-unknown-linux-musl`)
- bluetui v0.8.1 — Bluetooth TUI (`bluetui-${ARCH}-linux-musl`)

### Fonts (GitHub Releases)
- JetBrains Mono Nerd Font — pinned version (check current latest at release time). Downloaded to `~/.local/share/fonts/`, `fc-cache -fv` after install.

### DNF5 Standardization

All package operations use `dnf5` exclusively (Fedora 43 default). `lib/00-common.sh` defines a `DNF` variable pointing to `dnf5`. The `dnf5-plugins` package is installed first to ensure `copr` and `config-manager` subcommands are available.

### Key Fedora 43 Changes from Original Spec
- **Hyprland NOT in official repos** — dropped from Fedora 43, must use sdegler COPR
- **solopasha COPR abandoned** — replaced by sdegler/hyprland
- **hyprland-qt-support → hyprland-guiutils** — package renamed in COPR
- **Hyprland 0.53+ windowrule syntax** — new `windowrule = ..., match:class ...` format (old `windowrulev2` deprecated)
- **Ghostty NOT in official repos** — use scottames/ghostty COPR
- **tofi via COPR** — alternateved/tofi replaces build-from-source approach
- **dnf5 plugins** — explicitly install `dnf5-command(copr)` and `dnf5-command(config-manager)` first (may not be in Minimal Install)
- **linux-surface f43 repo** — available since Jan 2026 (was missing at Fedora 43 launch)
- **Full package audit needed** — verify all packages from original spec exist in Fedora 43 repos during implementation

## Generated vs Static Config File Contract

The template engine (Task 5) generates **color/theme files only**. Static configs (Task 6) reference them via `source` or `@import`. Clear namespace:

**Generated files** (by template engine, written to `config/`, added to `.gitignore`):
- `config/hypr/colors.conf` — Hyprland border/group colors
- `config/waybar/colors.css` — Waybar CSS color variables
- `config/ghostty/theme` — Ghostty palette
- `config/mako/colors` — Mako notification colors
- `config/tofi/colors` — Tofi launcher colors
- `config/hypr/hyprlock-colors.conf` — Hyprlock lock screen colors
- `config/gtk-3.0/settings.ini` — GTK3 dark theme settings (dark theme only, default Adwaita icons/cursor)
- `config/gtk-4.0/settings.ini` — GTK4 dark theme settings

**Static files** (Task 6, version-controlled):
- `config/hypr/hyprland.conf` — main config, `source = ~/.config/hypr/colors.conf`
- `config/hypr/input.conf` — input devices (German keyboard, no tap-to-click, no tap-drag, natural scroll)
- `config/hypr/keybinds.conf` — key bindings (Omarchy-style, research during impl)
- `config/hypr/windowrules.conf` — window rules (Omarchy-style, 0.53+ syntax)
- `config/hypr/autostart.conf` — exec-once daemons
- `config/waybar/config.jsonc` — module layout
- `config/waybar/style.css` — `@import "colors.css";` then static styles
- `config/mako/config` — references `include=~/.config/mako/colors`
- `config/ghostty/config` — references theme file
- `config/tofi/config` — references colors file
- `config/hypr/hypridle.conf` — idle timers
- `config/hypr/hyprlock.conf` — `source = ~/.config/hypr/hyprlock-colors.conf`
- `config/hypr/hyprpaper.conf` — wallpaper config
- `config/starship/starship.toml` — Starship prompt config (static, Tokyo Night colors)

## Hyprland Config Structure (Split-by-Concern)

Hyprland config is split into multiple files for maintainability:
```
config/hypr/
  hyprland.conf       # Main: monitor (1.5x scale), general, decoration (Omarchy defaults: 2px border, 8px rounding, 4px gaps), misc + source includes
  input.conf          # German keyboard (de), touchpad: no tap-to-click, no tap-drag, natural scroll, 2-finger right-click
  keybinds.conf       # All Omarchy keybinds: SUPER mod, SUPER+Enter=ghostty, SUPER+Q=close, SUPER+D=tofi, etc.
  windowrules.conf    # Omarchy-style window rules (0.53+ syntax)
  autostart.conf      # exec-once: waybar, mako, hypridle, hyprpaper, hyprpolkitagent, wl-paste --watch cliphist store, xrdb -merge ~/.Xresources
  colors.conf         # GENERATED by theme engine
  hypridle.conf       # 5min lock, 15min suspend (same on AC/battery)
  hyprlock.conf       # Minimal layout: clock + password on wallpaper blur
  hyprlock-colors.conf # GENERATED by theme engine
  hyprpaper.conf      # Single wallpaper
```

## Waybar Configuration

**Layout** (26px height, top position):
- **modules-left**: `hyprland/workspaces` — Workspaces 1–5 persistent, numbered icons, plus dynamic workspaces
- **modules-center**: `clock` — Date/time display
- **modules-right**: `group/tray-expander` (collapsible system tray with custom expand icon), `bluetooth`, `network`, `pulseaudio`, `cpu`, `battery`

Styling imports from `config/waybar/colors.css` (generated by theme engine). Tray is collapsed by default, click icon to expand.

## Autostart Daemons (exec-once)

- `waybar` — Status bar
- `mako` — Notification daemon
- `hypridle` — Idle lock/suspend manager
- `hyprpaper` — Wallpaper manager
- `hyprpolkitagent` — Polkit authentication agent
- `wl-paste --watch cliphist store` — Clipboard history tracking (required for cliphist to work)
- `xrdb -merge ~/.Xresources` — XWayland DPI settings

## Notification Config (mako)

- Position: top-right
- Auto-dismiss: 10 seconds
- Max visible: 5
- Colors: Tokyo Night via generated colors file

## Input Configuration

- **Keyboard**: German (de) standard QWERTZ layout. No variant. No layout toggle.
- **Touchpad**: No tap-to-click, no tap-and-drag, natural (reverse) scrolling, 2-finger right-click
- **Touchscreen**: Disabled — iptsd NOT installed, NOT enabled

## Touchscreen Decision

iptsd (touchscreen driver) is NOT installed and NOT enabled. The kernel-surface package and libwacom-surface are still installed (for other Surface hardware support), but iptsd is skipped entirely. Can be installed manually later if needed.

## Services (Enabled)

- `NetworkManager.service` — Network management
- `bluetooth.service` — Bluetooth (bluez defaults, managed via bluetui)
- `tuned.service` — Power management
- `tuned-ppd.service` — PowerProfilesCtl compatibility
- Default tuned profile: `powersave` (set via `tuned-adm profile powersave` in services stage)

**NOT enabled**: iptsd (touchscreen disabled), iwd (managed by NetworkManager), chronyd (Fedora default, already enabled)

## Research Findings (Resolved Open Questions)

| Question | Answer | Source |
|----------|--------|--------|
| Fedora version | Fedora 43 (current stable, Oct 2025) | Fedora Project |
| Base image | Everything (netinstall) → Minimal Install | Community recommendation |
| Hyprland source | sdegler/hyprland COPR (0.53.3+) | Fedora Discussion |
| Ghostty source | scottames/ghostty COPR | ghostty.org docs |
| tofi source | alternateved/tofi COPR (prebuilt RPM) | Fedora COPR |
| linux-surface f43 | Available since Jan 2026 | GitHub issue #1896 |
| LUKS encryption | No — AES-NI supported but unnecessary (soldered eMMC) | Intel specs |
| Kickstart approach | Omarchy-inspired: automate base install, manual script run after | Omarchy manual |
| Disk partitioning | Kickstart: ignoredisk mmcblk0, `reqpart --add-boot` (auto EFI + /boot) + ext4 root, zram for swap | Kickstart docs |
| User account | Prompted interactively in Kickstart %pre, added to wheel group | Design decision |
| dnf5 repo syntax | `dnf5 config-manager addrepo --from-repofile=URL` (NOT `--add-repo`) | Fedora Discussion |
| UWSM availability | In sdegler/hyprland COPR | COPR package list |
| Impala version | v0.7.3 (pinned) | GitHub releases |
| bluetui version | v0.8.1 (pinned) | GitHub releases |
| power-profiles-daemon | Fedora 43 uses tuned + tuned-ppd (same powerprofilesctl CLI) | Fedora Wiki |
| set -e variant | Use `set -Eeuo pipefail` | Best practices |
| Template placeholders | `{{ key }}`, `{{ key_strip }}` (no #), `{{ key_rgb }}` (decimal RGB) | Omarchy source |
| XDG portal config | `~/.config/xdg-desktop-portal/portals.conf` | XDG docs |
| Hyprland config syntax | 0.53+ anonymous windowrule syntax | Hyprland changelog |
| Neovim setup | LazyVim + Tokyo Night (replicate Omarchy, then trim) | Design decision |
| Shell aliases | Include n=nvim, ll, la etc. in bashrc.d | Design decision |
| XDG portals | Need xdg-desktop-portal + xdg-desktop-portal-gtk for GTK file dialogs | XDG docs |
| Display scaling | 1.5x with Xft.dpi=144, XCURSOR_SIZE=24 | Hyprland Wiki + community |
| Touchscreen | Disabled, iptsd NOT installed | Design decision |
| Keyboard layout | German (de) standard QWERTZ | Design decision |
| Timezone | Europe/Vienna | Design decision |
| Prompt | Starship with Tokyo Night custom config | Design decision |
| Font | JetBrains Mono Nerd Font (pinned version from GitHub) | Design decision |

## Idempotency Definition

"Idempotent" means: **no errors; converges to the same end-state; no duplicate snippets, backups, or repeated expensive work.** Observable changes like log file timestamps, dnf metadata refresh, and template regeneration (file overwrites to same content) are acceptable. The key guarantee is that running the script twice does not break anything or accumulate side effects.

**Re-run behavior**: Script runs identically whether from TTY (first install) or inside Hyprland terminal (re-run after reboot). No special session detection or different behavior in graphical mode.

## Error Handling

- **WiFi drop during install**: Fail fast & exit. Let dnf/curl fail naturally. User re-runs after reconnecting. Idempotency handles partial state.
- **Package install failure**: Fail entire stage. No partial installs. User fixes and re-runs.
- **Interruption (Ctrl+C, power loss)**: Trap SIGINT/SIGTERM, log which stage was interrupted, exit cleanly. User re-runs to continue.
- **Colored output**: Respect `NO_COLOR` env var and `TERM=dumb`. Disable colors if set.

## Key Gotchas

1. **kernel-surface needs `--allowerasing`** flag to replace stock kernel
2. **iwd**: Do NOT enable `iwd.service` manually — NetworkManager manages it. Must `restorecon -R /etc/NetworkManager` after creating conf.d files (SELinux)
3. **Getty auto-login**: Blank `ExecStart=` line REQUIRED before new one. Must use single-quoted heredoc to preserve `$TERM` literal. Must run `systemctl daemon-reload` after.
4. **Plymouth**: Check current theme before rebuilding initrd with `-R` (saves ~30s). Use dark/minimal theme (research available packages during implementation).
5. **zram config**: Write to `/etc/systemd/zram-generator.conf` (NOT `/usr/lib/`). Takes effect after reboot.
6. **Symlinks**: Use `ln -snfT` for directory symlinks (`-T` treats dest as file, not dir). If dest is a real directory (not symlink), back up to `<name>.bak` first (remove existing `.bak` if present to avoid nesting).
7. **curl downloads**: Always use `-fSL` (fail on HTTP errors)
8. **NetworkManager iwd switch**: Write config, defer restart to reboot (avoids WiFi drop during install). Document in services stage.
9. **UWSM**: Add `uwsm check may-start` to `~/.bash_profile`, NOT `.bashrc`
10. **Complex Hyprland keybinds**: Wrap pipes/subshells in `sh -c` or use helper scripts in `~/.local/bin/`
11. **GTK theme on TTY**: Use `settings.ini` files directly, NOT `gsettings`/`dconf` (no DBus session). Dark theme only (default Adwaita icons/cursor).
12. **Wallpaper paths**: Copy single wallpaper to `~/.local/share/wallpapers/surface-linux/` for stable absolute paths
13. **dnf5 plugins**: Ensure `dnf5-command(copr)` and `dnf5-command(config-manager)` are installed BEFORE any COPR/repo operations
14. **Missing critical packages**: waybar-git (from COPR, not waybar), mako, wireplumber, bluez, tuned, tuned-ppd, starship must be in package list
15. **Hyprland 0.53+ syntax**: Use `windowrule` not `windowrulev2`. New `match:class` format.
16. **hyprland-guiutils replaces hyprland-qtutils** — old package name will fail
17. **Neovim version**: LazyVim v15.x needs Neovim >= 0.11.2. Check version and pin LazyVim v14.x if needed.
18. **Privilege model**: Run as user, sudo per-operation. Never run install.sh as root.
19. **Hardware detection**: Skip Surface-specific stages (kernel) on non-Surface hardware. Allows VM testing.
20. **iptsd NOT installed**: Touchscreen disabled. Only kernel-surface + libwacom-surface from linux-surface repo.
21. **Nerd Font**: Download from GitHub (ryanoasis/nerd-fonts), not dnf. Run fc-cache after install.
22. **Starship init**: Goes in `config/bashrc.d/starship.sh` (our modular pattern), not directly in .bashrc.
23. **~/.local/bin PATH**: Verify it's in PATH, add via bashrc.d if missing.
24. **wl-paste watcher**: Must be in autostart for clipboard history to work: `wl-paste --watch cliphist store`
25. **Display scaling**: 1.5x with force_zero_scaling. Xresources Xft.dpi=144. Env vars in UWSM env files.

## Neovim Configuration

- Bootstrap LazyVim (lazy.nvim plugin manager + LazyVim distribution)
- Set Tokyo Night as colorscheme
- Replicate Omarchy's Neovim config, then trim unnecessary plugins during implementation
- Ship `config/nvim/` directory with init.lua and lua/ config
- Gets symlinked to `~/.config/nvim/` by dotfiles.sh
- Includes LSP, treesitter, telescope out of the box via LazyVim defaults
- `run_neovim` checks `nvim --version` and pins LazyVim branch accordingly

## Shell Configuration

### Starship Prompt
- Install `starship` via dnf (Fedora repos)
- Custom `config/starship/starship.toml` with Tokyo Night colors (static file, not template-generated)
- Symlink `config/starship/` → `~/.config/starship/`
- Init via `config/bashrc.d/starship.sh` containing `eval "$(starship init bash)"`

### Aliases (config/bashrc.d/aliases.sh)
- `n` → `nvim`
- `ll` → `ls -la`
- `la` → `ls -A`
- `..` → `cd ..`
- Other quality-of-life aliases as appropriate

### PATH
- Verify `~/.local/bin` is in PATH
- Add via bashrc.d file if missing (for Impala, bluetui, helper scripts)

## Template Output Strategy

Template-processed files are written INTO the repo's `config/` directory using fixed filenames (see "Generated vs Static Config File Contract" above). Generated files are added to `.gitignore`. Static configs reference generated files via `source`/`@import`.

## Bootstrap Flow

1. User disables Secure Boot in UEFI (already done on this device — documented as prerequisite in README)
2. User writes Fedora Everything ISO to USB
3. User edits `kickstart/surface-go3.ks` to set REPO_URL
4. User copies kickstart to USB or serves via HTTP
5. Boot USB with `inst.ks=...` parameter
6. Anaconda: user connects WiFi via GUI, install runs: partitions eMMC, installs minimal system, creates user in wheel group, clones repo
7. Reboot → login to CLI as user (sudo available via wheel)
8. Run `cd ~/surface-linux && ./install.sh`
9. Reboot → Hyprland desktop via UWSM

## Stage Ordering and Dependencies

```
repos → kernel → packages → binaries → fonts → zram → network → desktop → theme → dotfiles → neovim → services
```

Key constraints:
- `repos` must run first (adds COPR repos + linux-surface repo, installs dnf5 plugins)
- `kernel` after repos (needs linux-surface repo). **Skipped on non-Surface hardware.**
- `packages` after repos (needs COPR repos enabled). Includes starship.
- `binaries` after packages (needs curl; downloads Impala + bluetui)
- `fonts` after packages (needs curl; downloads JetBrains Mono NF, runs fc-cache)
- `network` after fonts (writes iwd config; takes effect after reboot)
- `theme` before dotfiles (generates config files that dotfiles symlinks)
- `dotfiles` before neovim (symlinks `~/.config/nvim/` which neovim headless sync needs)
- `neovim` after dotfiles (LazyVim headless sync requires config at `~/.config/nvim/`)
- `services` last (enables services after all config is in place; sets tuned profile to powersave)

**`--only` behavior**: Automatically runs prerequisite stages first. No `--no-deps` flag needed.

When using `--only`, the script automatically runs prerequisite stages to ensure the requested stage can succeed.

## Install Summary Output

At completion, the script prints a concise summary:
- Kernel installed (which version)
- Services enabled (list)
- Config deployed (symlinks created)
- Next step: `sudo reboot`

## Omarchy Research Items

The following should be researched from Omarchy's source during implementation:
- **Keybinds**: Full keybind set (SUPER mod, all Omarchy bindings)
- **Media key binds**: Volume, brightness, play/pause behavior (bindel vs bindl)
- **Clipboard history keybind**: Which key triggers cliphist
- **Border colors**: Active/inactive window border colors for Tokyo Night
- **Cursor theme**: Which cursor theme and size
- **Neovim plugins**: Exact plugin set (replicate, then trim)
- **Window rules**: Omarchy-style rules (float dialogs, dim inactive, etc.)

## Quick Commands

```bash
# Full install
./install.sh

# List stages
./install.sh --list

# Run specific stage (auto-runs prerequisites)
./install.sh --only packages

# Skip a stage
./install.sh --skip kernel
```

## Acceptance

- [ ] Kickstart file automates Fedora 43 Minimal Install on Surface Go 3 eMMC
- [ ] Kickstart creates user in wheel group with sudo access
- [ ] Kickstart sets locale en_US.UTF-8, keyboard de-latin1, timezone Europe/Vienna
- [ ] README includes USB preparation guide, Secure Boot prerequisite, keybind reference (docs/keybinds.md)
- [ ] `./install.sh` runs as user (not root), uses sudo per-operation
- [ ] `./install.sh` runs to completion on fresh Fedora 43 Minimal Install
- [ ] Hardware detection: skips Surface stages on non-Surface hardware
- [ ] Idempotent: running twice produces no errors and converges to same end-state
- [ ] `--only`, `--skip`, `--list` flags work correctly
- [ ] `--only` auto-runs prerequisite stages
- [ ] Colored output respects NO_COLOR env var
- [ ] System boots to Hyprland 0.53+ desktop via UWSM after reboot
- [ ] Display scaled at 1.5x with XWayland DPI fix (Xft.dpi=144)
- [ ] Tokyo Night theme applied consistently across hyprland, waybar, ghostty, mako, tofi, hyprlock
- [ ] All Omarchy keybinds work: terminal, close, launcher, workspaces, focus, move, fullscreen, float
- [ ] Media keys work: volume, brightness, play/pause
- [ ] Screenshots: PrintScreen triggers area select → save to ~/Pictures/screenshots/ + clipboard
- [ ] Clipboard history working (wl-paste watcher + cliphist + tofi)
- [ ] Waybar: workspaces, clock, collapsible tray, bluetooth, network, pulseaudio, cpu, battery
- [ ] linux-surface kernel running (on Surface hardware)
- [ ] WiFi via iwd/Impala, Bluetooth via bluetui
- [ ] zram tuned to 4GB (verified after reboot)
- [ ] Screen locks at 5min idle, suspends at 15min (same on AC/battery)
- [ ] Hyprlock: minimal layout (clock + password on wallpaper blur)
- [ ] Mako notifications: top-right, 10s timeout, 5 max visible
- [ ] Neovim launches with LazyVim + Tokyo Night theme (Omarchy-based config)
- [ ] Starship prompt with Tokyo Night colors
- [ ] JetBrains Mono Nerd Font installed and used by Ghostty
- [ ] Shell aliases (n=nvim, ll, la, ..) working
- [ ] ~/.local/bin in PATH
- [ ] All symlinks correct from ~/.config/ to repo (including starship/)
- [ ] Log file at /tmp/surface-install.log (tee: screen + file)
- [ ] Summary printed at end: kernel, services, config, reboot instruction
- [ ] Hyprland input: German keyboard, no tap-to-click, no tap-drag, natural scroll
- [ ] touchscreen disabled (iptsd NOT installed)
- [ ] tuned profile set to powersave
- [ ] All 3 COPRs + linux-surface external repo configured correctly
- [ ] Hyprland config uses 0.53+ windowrule syntax throughout
- [ ] hyprpolkitagent working for authentication prompts
- [ ] XDG portal stack working (file dialogs via xdg-desktop-portal-gtk)
- [ ] Generated and static config files clearly separated per contract
- [ ] Plymouth dark/minimal theme set
- [ ] Trap handlers for clean exit on interruption

## References

- [linux-surface Wiki](https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup)
- [Hyprland Wiki](https://wiki.hypr.land/Configuring/)
- [UWSM GitHub](https://github.com/Vladimir-csp/uwsm)
- [Omarchy Theme System](https://deepwiki.com/basecamp/omarchy/6.1-theme-management)
- [DNF5 Config-Manager](https://dnf5.readthedocs.io/en/latest/dnf5_plugins/config-manager.8.html)
- [sdegler/hyprland COPR](https://copr.fedorainfracloud.org/coprs/sdegler/hyprland/packages/)
- [scottames/ghostty COPR](https://copr.fedorainfracloud.org/coprs/scottames/ghostty/)
- [alternateved/tofi COPR](https://copr.fedorainfracloud.org/coprs/alternateved/tofi/)
- [Fedora 43 Hyprland Tutorial](https://discussion.fedoraproject.org/t/tutorial-fedora-43-install-hyprland-from-scratch/168386)
- [Fedora Kickstart Docs](https://docs.fedoraproject.org/en-US/fedora/f35/install-guide/advanced/Kickstart_Installations/)
- [JaKooLit/Fedora-Hyprland](https://github.com/JaKooLit/Fedora-Hyprland)
- [LazyVim](https://www.lazyvim.org/)
- [Starship](https://starship.rs/)
- [Nerd Fonts](https://www.nerdfonts.com/)
