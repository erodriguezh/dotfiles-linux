## Description

Create the Omarchy-inspired template engine that reads `colors.toml` and processes `.tpl` template files to generate themed configuration files. Also create `colors.toml` (Tokyo Night) and all `.tpl` template files.

**Size:** M
**Files:** `lib/08-theme.sh`, `colors.toml`, `templates/*.tpl`

## Approach

### lib/08-theme.sh (`run_theme`)
- Parse `colors.toml` (flat `key = "value"` format) with awk
- For each key-value pair, generate 3 sed substitution variants:
  - `{{ key }}` → raw value (e.g., `#7aa2f7`)
  - `{{ key_strip }}` → without `#` prefix (e.g., `7aa2f7`)
  - `{{ key_rgb }}` → decimal R,G,B (e.g., `122,162,247`)
- `hex_to_rgb()` function: extract hex pairs, convert via printf
- Escape replacement values for sed: handle `\`, `&`, `/` chars
- Process all `.tpl` files from `templates/` directory
- Output to **exact paths per the Generated File Contract** (see below)
- Idempotent: overwrites output files with same content on re-run

### colors.toml (Tokyo Night)
- Full 16-color palette + accent, cursor, foreground, background, selection colors

### Generated File Contract (STRICT)

Each `.tpl` maps to exactly one output file in `config/`:

| Template | Output | Purpose |
|----------|--------|---------|
| `templates/hyprland-colors.conf.tpl` | `config/hypr/colors.conf` | Hyprland border/group colors |
| `templates/waybar-colors.css.tpl` | `config/waybar/colors.css` | Waybar CSS color variables |
| `templates/ghostty-theme.tpl` | `config/ghostty/theme` | Ghostty palette |
| `templates/mako-colors.tpl` | `config/mako/colors` | Mako notification colors |
| `templates/tofi-colors.tpl` | `config/tofi/colors` | Tofi launcher colors |
| `templates/hyprlock-colors.conf.tpl` | `config/hypr/hyprlock-colors.conf` | Hyprlock lock screen colors |
| `templates/gtk3-settings.ini.tpl` | `config/gtk-3.0/settings.ini` | GTK3 dark theme |
| `templates/gtk4-settings.ini.tpl` | `config/gtk-4.0/settings.ini` | GTK4 dark theme |

These filenames are referenced by static configs in Task 6 via `source`/`@import`/`include`. Do NOT change filenames without updating Task 6.

## Key context

- Generated files go to `config/` directory, then get symlinked by dotfiles.sh
- Use `|` as sed delimiter when values contain slashes
- Do NOT use `envsubst` (replaces ALL $VAR patterns) or `eval` (injection risk)
- All generated files listed in `.gitignore` (configured in Task 1)
- Static configs (Task 6) reference generated files by name — this contract is binding

## Acceptance

- [ ] `colors.toml` contains full Tokyo Night palette (16 colors + accent/cursor/fg/bg/selection)
- [ ] Template processor generates all 3 variants per key
- [ ] `hex_to_rgb()` correctly converts hex to decimal R,G,B
- [ ] sed replacement values properly escaped
- [ ] Theme stage creates parent directories (`mkdir -p`) before writing outputs (e.g., `config/hypr/`, `config/waybar/`, `config/gtk-3.0/`)
- [ ] All 8 generated files produced at exact paths per contract table
- [ ] Generated files contain correct Tokyo Night colors
- [ ] No generated files conflict with static config files (disjoint filenames)
- [ ] Idempotent: re-running overwrites to same content

## Done summary

_To be filled after implementation._

## Evidence

_To be filled after implementation._
