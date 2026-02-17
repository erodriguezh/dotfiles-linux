## Description

Create the ISO-specific kickstart file that works with the embedded local repo and runs all configuration stages in %post. This kickstart is a SEPARATE file from the existing `kickstart/surface-go3.ks` — it's purpose-built for the custom ISO install path.

**Size:** M
**Files:** `iso/surface-go3-iso.ks`

## Approach

### Kickstart structure

The kickstart has 5 sections: header, %packages, %post --nochroot, %post (chroot), and the `services` directive.

**Header:**
- Text mode (`text`)
- Same locale/keyboard/timezone as existing kickstart (`kickstart/surface-go3.ks:23-31`)
- Same disk config: `ignoredisk --only-use=mmcblk0`, `clearpart --all --initlabel --disklabel=gpt`, `reqpart --add-boot`, `part / --fstype=ext4 --grow`
- `rootpw --lock`
- `firewall --enabled --service=mdns`
- `selinux --enforcing`
- `user --name=@@USERNAME@@ --groups=wheel --password=@@PASSWORD_HASH@@ --iscrypted`
- `network --bootproto=dhcp --device=link --activate` (kept for optional post-install connectivity; Anaconda won't stall — offline install still works)
- `repo --name=surface-local --baseurl=file:///run/install/isodir/local-repo --cost=10` — points to the embedded local repo added by mkksiso. The ISO mounts at `/run/install/isodir/`.
- `services --enabled=NetworkManager,iwd,bluetooth,tuned` — canonical systemd unit names only. Note: `tuned-ppd` is a PACKAGE (extends tuned), NOT a service unit — it is included in `%packages` only.
- `shutdown` (for first testing; change to `reboot` once validated)

**%packages:**
- `--excludeWeakdeps --excludedocs` for size optimization
- `@^minimal-environment`
- ALL packages from `lib/03-packages.sh` (the full list — hyprland, ghostty, tofi, etc.)
- ALL packages from `lib/02-kernel.sh` (kernel-surface, libwacom-surface)
- `dnf5-plugins` (needed for post-install COPR management)
- `tuned-ppd` (the package, for powerprofilesctl support)
- Explicit excludes: `-kernel` (replaced by kernel-surface)

**%post --nochroot** (installer environment, installed system at `/mnt/sysroot/`):
- Set `USERNAME=@@USERNAME@@` (static, baked in at build time — no runtime discovery)
- Copy surface-linux repo from ISO: `cp -a /run/install/isodir/surface-linux /mnt/sysroot/home/$USERNAME/`
- Copy pre-downloaded binaries to `/mnt/sysroot/home/$USERNAME/.local/bin/` — these MUST match the exact versions from `lib/04-binaries.sh` so that re-running `./install.sh --only binaries` is idempotent
- Copy pre-downloaded fonts to `/mnt/sysroot/home/$USERNAME/.local/share/fonts/JetBrainsMono/` — reproduce `lib/05-fonts.sh` directory structure including `.nf-version` file
- Copy pre-cloned lazy.nvim to `/mnt/sysroot/home/$USERNAME/.local/share/nvim/lazy/lazy.nvim/`
- Set ownership: `chown -R` all copied files to target user
- Run `chroot /mnt/sysroot fc-cache -f` to rebuild font cache

**%post** (chroot, runs as root inside installed system):
- Set `HOME=/home/@@USERNAME@@`, `REPO_DIR=$HOME/surface-linux` — all `%post` logic uses the baked-in `@@USERNAME@@` placeholder. There is NO runtime discovery of the username.
- **zram** (from `lib/06-zram.sh:15-35` pattern): write `/etc/systemd/zram-generator.conf` + `/etc/sysctl.d/99-zram.conf`
- **network** (from `lib/07-network.sh:26-28` pattern): write `/etc/NetworkManager/conf.d/wifi-backend.conf`
- **desktop** (from `lib/08-desktop.sh` pattern):
  - Getty auto-login override at `/etc/systemd/system/getty@tty1.service.d/override.conf` — use single-quoted heredoc, `@@USERNAME@@` already substituted by build script
  - XDG portal config at `$HOME/.config/xdg-desktop-portal/portals.conf`
  - UWSM env files at `$HOME/.config/uwsm/env` and `$HOME/.config/uwsm/env-hyprland`
  - Systemd user env at `$HOME/.config/environment.d/surface-linux.conf`
- **dotfiles** (from `lib/11-dotfiles.sh` pattern):
  - Symlink config dirs: `ln -snfT $REPO_DIR/config/<dir> $HOME/.config/<dir>` for each of: hypr, waybar, mako, ghostty, tofi, nvim, bashrc.d, gtk-3.0, gtk-4.0, starship
  - Symlink local-bin scripts
  - Copy wallpapers to `$HOME/.local/share/wallpapers/surface-linux/`
  - Write `$HOME/.Xresources` with `Xft.dpi: 144`
  - Append bashrc.d sourcing loop to `$HOME/.bashrc` (from `lib/11-dotfiles.sh:160-174`)
  - Append UWSM auto-start to `$HOME/.bash_profile` (from `lib/11-dotfiles.sh:187-196`)
- **services**: `systemctl set-default graphical.target` (matches `lib/12-services.sh` behavior)
- **plymouth**: set spinner theme via `plymouth-set-default-theme spinner` (without `-R` — Anaconda handles initrd)
- **repos for post-install updates**: Configure COPR repos and linux-surface repo on the installed system so `dnf update` works once WiFi is connected. Follow patterns from `lib/01-repos.sh:29-45`.
- Fix ownership: `chown -R @@USERNAME@@:@@USERNAME@@ $HOME/`

**Parity requirement:** The `%post` configuration and `services` directive MUST fully mirror the behavior of `lib/12-services.sh` — enabling the same units and setting the same defaults. Any differences must be deliberate and documented. If `lib/12-services.sh` enables a unit, the ISO kickstart must enable it too (either via `services --enabled=` or `systemctl enable` in `%post`).

## Key context

- `%post --nochroot` sees installed system at `/mnt/sysroot/` (Fedora 43 Anaconda). NOT `/mnt/sysimage/` (older docs).
- `%post` (default, chroot) runs as root inside installed system. `$HOME` is `/root` unless explicitly set — MUST set `HOME=/home/@@USERNAME@@`.
- `systemctl enable` works in chroot (creates symlinks). But prefer kickstart `services --enabled=` directive.
- `systemctl daemon-reload` does NOT work in chroot. Not needed — next boot picks up config.
- Theme files are already generated by the build script (task .1) and included in the surface-linux repo copy. No template processing needed in %post.
- `plymouth-set-default-theme spinner -R` rebuilds initramfs. Use without `-R` in %post — Anaconda generates the initrd.
- `@@USERNAME@@` and `@@PASSWORD_HASH@@` are build-time substitution placeholders (distinct from existing kickstart's `CHANGEME_*` pattern).
- Kickstart `services` directive: comma-separated, NO spaces between service names. Use canonical systemd unit names only.
- `tuned-ppd` is a package, not a service unit. Include in `%packages`, not in `services --enabled=`.

## Acceptance

- [x] ISO kickstart uses embedded local repo via `repo --baseurl=file:///run/install/isodir/local-repo`
- [x] %post --nochroot copies repo, binaries, fonts, lazy.nvim to installed system
- [x] %post chroot mirrors all lib/ stage configurations
- [x] `@@USERNAME@@` and `@@PASSWORD_HASH@@` placeholders used for build-time substitution
- [x] RepoPrompt review: SHIP

## Done summary
Created ISO-specific kickstart file (iso/surface-go3-iso.ks) with embedded local repo directive, full package set from lib/*.sh, %post --nochroot asset copy (repo, binaries, fonts, lazy.nvim), and %post chroot configuration mirroring all lib/ stages (zram, network, getty, XDG portals, UWSM, dotfiles, services, plymouth, COPR repos). Repo configuration is best-effort for offline install safety.
## Evidence
- Commits: e598705119c89f41da7843e2385402e78b3a51af, 609455430e1f55e3f3829f66b8d1411d37e0e82f
- Tests: manual review via RepoPrompt (SHIP verdict)
- PRs: