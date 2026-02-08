## Description

Create all static application configuration files for Hyprland 0.53+ (split-by-concern) and companion apps, plus Neovim/LazyVim setup. These are version-controlled config files that reference template-generated color files.

**Size:** M
**Files:** `config/hypr/hyprland.conf`, `config/hypr/input.conf`, `config/hypr/keybinds.conf`, `config/hypr/windowrules.conf`, `config/hypr/autostart.conf`, `config/hypr/hypridle.conf`, `config/hypr/hyprlock.conf`, `config/hypr/hyprpaper.conf`, `config/waybar/config.jsonc`, `config/waybar/style.css`, `config/mako/config`, `config/ghostty/config`, `config/tofi/config`, `config/nvim/init.lua`, `config/nvim/lua/config/lazy.lua`, `config/nvim/lua/config/options.lua`, `config/nvim/lua/plugins/colorscheme.lua`, `lib/09-neovim.sh`

## Approach

### Hyprland Split-by-Concern Config

`config/hypr/hyprland.conf` — Main file with:
- `source` includes for all sub-configs: `source = ~/.config/hypr/input.conf`, `source = ~/.config/hypr/keybinds.conf`, `source = ~/.config/hypr/windowrules.conf`, `source = ~/.config/hypr/autostart.conf`, `source = ~/.config/hypr/colors.conf` (GENERATED)
- Monitor config for Surface Go 3 (10.5" 1920x1280)
- General, decoration, misc settings
- `misc:disable_hyprland_guiutils_check = false`

`config/hypr/input.conf` — Touchpad + keyboard config
`config/hypr/keybinds.conf` — All bind/bindm/bindel/bindl entries:
  - `bindel` for volume/brightness (repeatable)
  - `bindl` for media play/pause (works on lockscreen)
  - Screenshots: `sh -c` wrapper for grim+slurp pipe
  - Clipboard history: call `~/.local/bin/clipboard-history.sh` helper
  - Session exit: `uwsm stop` (NOT `exit` dispatcher)
`config/hypr/windowrules.conf` — 0.53+ syntax: `windowrule = ..., match:class ...`
`config/hypr/autostart.conf` — `exec-once` for waybar, mako, hyprpaper, hyprpolkitagent, cliphist watcher

### Other App Configs (static, referencing generated color files)

- `config/waybar/config.jsonc` — Module layout (workspaces, clock, battery, network, bluetooth, audio, tray)
- `config/waybar/style.css` — `@import "colors.css";` then static styling
- `config/mako/config` — Static config referencing `include=~/.config/mako/colors`
- `config/ghostty/config` — References generated theme file
- `config/tofi/config` — References generated colors file
- `config/hypr/hypridle.conf` — Lock at 5min, DPMS off at 10min, suspend at 15min
- `config/hypr/hyprlock.conf` — Layout with `source = ~/.config/hypr/hyprlock-colors.conf`
- `config/hypr/hyprpaper.conf` — References `~/.local/share/wallpapers/surface-linux/`

### Neovim (`config/nvim/` + `lib/09-neovim.sh`)

- LazyVim bootstrap: `init.lua` with lazy.nvim clone from `--branch=stable`
- `lua/config/lazy.lua`: LazyVim setup
- `lua/plugins/colorscheme.lua`: Tokyo Night with `priority = 1000`, `lazy = false`, style = "night"
- `lib/09-neovim.sh` (`run_neovim`):
  - Check `nvim --version` — if < 0.11.2, warn and pin LazyVim to v14.x compatible branch
  - Clone lazy.nvim to `~/.local/share/nvim/lazy/lazy.nvim` if not present
  - Run headless plugin install: `nvim --headless "+Lazy! sync" +qa`

## Key context

- **ZERO overlap with generated files**: This task creates ONLY static configs. Generated color files (`colors.conf`, `colors.css`, `theme`, etc.) are created by Task 5. Static configs reference them via `source`/`@import`/`include`.
- Hyprland 0.53+: `windowrule` not `windowrulev2`. Use `match:class` prefix.
- Complex keybinds MUST use `sh -c` wrapper or helper scripts
- `exec-once` for daemons (session start only). `exec` re-runs on config reload — avoid for daemons.
- LazyVim v15.x needs Neovim >= 0.11.2. Fedora 43 version must be checked.
- Do NOT set `lazy = true` for colorscheme. Use `lazy = false` + `priority = 1000`.

## Acceptance

- [ ] Hyprland config split into 5+ files (main, input, keybinds, windowrules, autostart)
- [ ] `hyprland.conf` sources all sub-configs including generated `colors.conf`
- [ ] 0.53+ `windowrule` syntax throughout (zero `windowrulev2`)
- [ ] All keybinds defined: workspaces, window mgmt, volume, brightness, screenshots, clipboard
- [ ] Screenshots use `sh -c` wrapper for grim+slurp
- [ ] Session exit uses `uwsm stop` (not `exit` dispatcher)
- [ ] `exec-once` starts: waybar, mako, hyprpaper, hyprpolkitagent, cliphist watcher
- [ ] hypridle: lock at 5min, DPMS off at 10min, suspend at 15min
- [ ] hyprlock: sources generated colors file, has clock + password input
- [ ] Waybar: single top bar with expected modules, CSS imports generated colors
- [ ] Mako, Ghostty, Tofi configs reference generated color files
- [ ] Neovim: LazyVim bootstrap with Tokyo Night, version check for compatibility
- [ ] No hardcoded color values in static configs
- [ ] No filename overlap with Task 5 generated files
- [ ] Config passes parse validation: `hyprctl reload` produces no config parse errors (test after full setup)
- [ ] Keybinds use `brightnessctl` for brightness and `playerctl` for media (packages in Task 2)

## Done summary

_To be filled after implementation._

## Evidence

_To be filled after implementation._
