## Description

Create the dotfiles deployment script that symlinks config files from the repo to `~/.config/`, deploys shell aliases, copies wallpapers, sets up the UWSM auto-start snippet, and creates helper scripts.

**Size:** M
<!-- Updated by plan-sync: fn-1...1 added fonts stage at position 5, shifting subsequent lib file numbers by +1 -->
<!-- Updated by plan-sync: fn-1...6 placed clipboard helper in config/local-bin/ not scripts/ -->
**Files:** `lib/11-dotfiles.sh`, `config/bashrc.d/aliases.sh`

## Approach

### lib/11-dotfiles.sh (`run_dotfiles`)
- Symlink all directories in `config/` to `~/.config/` using `ln -snf` (with `-n` to prevent nested symlinks)
- Handle Neovim specially: symlink `config/nvim/` → `~/.config/nvim/`
- Deploy helper scripts from `config/local-bin/` to `~/.local/bin/` (symlink each file, e.g. `config/local-bin/clipboard-history.sh` -> `~/.local/bin/clipboard-history.sh`)
- Copy wallpapers from `assets/wallpapers/` → `~/.local/share/wallpapers/surface-linux/` (stable absolute paths for hyprpaper)
- Deploy `.bashrc` additions:
  - Source all files from `~/.config/bashrc.d/*.sh` pattern (append sourcing loop to `.bashrc` if not present)
  - Guard with `grep -qF` before appending to prevent duplicates on re-run
- Deploy UWSM auto-start to `~/.bash_profile`:
  - Add `uwsm check may-start && exec uwsm start hyprland.desktop` snippet
  - Must go in `~/.bash_profile` NOT `.bashrc` (login shell only)
  - Guard with `grep -qF` before appending

### config/bashrc.d/aliases.sh
- `n` → `nvim`
- `ll` → `ls -la`
- `la` → `ls -A`
- `..` → `cd ..`
- Other quality-of-life aliases

### config/local-bin/clipboard-history.sh (already created by Task 6)
<!-- Updated by plan-sync: fn-1...6 created clipboard helper at config/local-bin/ not scripts/ -->
- Already exists at `config/local-bin/clipboard-history.sh` (executable)
- `lib/11-dotfiles.sh` must symlink it to `~/.local/bin/clipboard-history.sh`
- Keybind in `config/hypr/keybinds.conf` references `~/.local/bin/clipboard-history.sh`

### Symlink mapping
```
config/hypr/        → ~/.config/hypr/
config/waybar/      → ~/.config/waybar/
config/mako/        → ~/.config/mako/
config/ghostty/     → ~/.config/ghostty/
config/tofi/        → ~/.config/tofi/
config/nvim/        → ~/.config/nvim/
config/bashrc.d/    → ~/.config/bashrc.d/
config/gtk-3.0/     → ~/.config/gtk-3.0/
config/gtk-4.0/     → ~/.config/gtk-4.0/
```

## Key context

- Use `ln -snfT` for directory symlinks (`-T` treats destination as a file, not directory). If destination exists as a real directory (not a symlink), remove any existing `<name>.bak` first, then back up to `<name>.bak` before linking. This prevents `.bak` nesting on repeated partial runs.
- `.bashrc` sourcing loop: iterate `~/.config/bashrc.d/*.sh` files. This keeps `.bashrc` modifications minimal and modular
- `.bash_profile` UWSM snippet must NOT be in `.bashrc` — it would try to start Hyprland on every subshell
- Guard all `.bashrc`/`.bash_profile` appends with `grep -qF` to prevent duplicate entries on re-run
- Wallpapers MUST be copied (not symlinked) to `~/.local/share/wallpapers/surface-linux/` — hyprpaper needs stable absolute paths that work even if repo moves
- File ownership: all files under `~/.config/`, `~/.local/` should be owned by the user (not root)

## Acceptance

- [ ] All config directories symlinked: hypr, waybar, mako, ghostty, tofi, nvim, bashrc.d, gtk-3.0, gtk-4.0
- [ ] Symlinks use `ln -snfT` (handles existing dirs and symlinks correctly on re-run)
- [ ] Wallpapers copied to `~/.local/share/wallpapers/surface-linux/`
- [ ] Shell aliases working: `n`=nvim, `ll`, `la`, `..`
- [ ] `.bashrc` sources `~/.config/bashrc.d/*.sh` (no duplicates on re-run)
- [ ] `.bash_profile` contains UWSM auto-start snippet (no duplicates on re-run)
- [ ] Clipboard history helper script in `~/.local/bin/` and executable
- [ ] All `~/.config/` and `~/.local/` files owned by user (not root)
- [ ] Idempotent: re-running produces correct symlinks, no duplicate .bashrc entries

## Done summary
Implemented dotfiles deployment stage (lib/11-dotfiles.sh) that symlinks config dirs to ~/.config/ with ln -snfT, deploys helper scripts to ~/.local/bin/, copies wallpapers, writes/upserts .Xresources, appends bashrc.d sourcing loop to ~/.bashrc, and adds UWSM auto-start snippet to ~/.bash_profile. Created config/bashrc.d/ with aliases.sh, starship.sh, and path.sh, plus config/starship/starship.toml with Tokyo Night colors.
## Evidence
- Commits: 03d8506, f7a8473
- Tests: shellcheck review via RepoPrompt
- PRs: