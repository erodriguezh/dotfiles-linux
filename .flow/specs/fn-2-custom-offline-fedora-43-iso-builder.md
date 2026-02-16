# Custom Offline Fedora 43 ISO Builder

## Overview

Build a custom, self-contained Fedora 43 ISO for the Surface Go 3 that produces a fully configured Hyprland desktop with a single boot + reboot — zero manual post-install steps, zero network required during install. Inspired by [Omarchy's ISO builder](https://github.com/omacom-io/omarchy-iso) but adapted for Fedora's kickstart ecosystem.

**Current flow:** Download stock Fedora Everything ISO → edit kickstart placeholders → boot with OEMDRV → Anaconda installs Minimal → reboot → manually run `./install.sh` → reboot → done (3 boots, manual steps, needs WiFi).

**New flow:** Run `./iso/build-iso.sh --username=X --password-hash-file=./hash.txt` → produces `surface-linux-F43-YYYYMMDD.iso` → flash to USB → boot Surface Go 3 → Anaconda installs everything from embedded local repo (offline) → reboot → fully configured Hyprland desktop (2 boots, zero manual steps, zero network).

## Scope

**In scope:**
- `iso/` directory: build script, Containerfile, ISO-specific kickstart
- GitHub Actions workflow for CI validation + ISO artifact production
- Offline package repo (official Fedora + 3 COPRs + linux-surface)
- Pre-downloaded assets (binaries, fonts, lazy.nvim)
- Theme generation during build
- README restructuring for two install paths

**Out of scope:**
- Modifying existing `install.sh` or `lib/*.sh` stages
- Custom package repository infrastructure (no pkgs.omarchy.org equivalent)
- Nightly automated builds (manual dispatch only)
- LUKS encryption (matches current design)
- Secure Boot key enrollment during ISO install

## Approach

### Architecture: mkksiso + offline repo

```
┌─────────────────────────────────────────────────────────┐
│ BUILD (Podman container, Fedora 43)                      │
│                                                          │
│ 1. Enable repos: official + 3 COPRs + linux-surface      │
│ 2. Expand @^minimal-environment → package list           │
│ 3. dnf5 download --resolve --destdir → local RPM cache   │
│ 4. createrepo_c → local repo with metadata               │
│ 5. repoclosure validation → verify self-contained repo   │
│ 6. Download: impala, bluetui, starship, JetBrains Mono   │
│    (impala/bluetui kept as TUIs; Waybar uses nmtui)      │
│ 7. git clone lazy.nvim (stable branch)                   │
│ 8. Copy surface-linux repo + generate theme files        │
│ 9. Substitute credentials in kickstart template          │
│ 10. mkksiso: embed ks + repo + assets → boot.iso         │
│                                                          │
│ Output: surface-linux-F43-YYYYMMDD-x86_64.iso (~1.5 GB)  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ INSTALL (Surface Go 3, fully offline)                    │
│                                                          │
│ 1. Boot from USB                                         │
│ 2. Anaconda auto-loads embedded kickstart (inst.ks=cdrom)│
│ 3. Partitions eMMC (EFI + /boot + ext4 root, no swap)   │
│ 4. Installs ALL packages from embedded local repo        │
│ 5. %post --nochroot: copies repo, binaries, fonts,       │
│    lazy.nvim to installed system                         │
│ 6. %post (chroot): zram, network, getty, XDG portals,    │
│    UWSM env, dotfile symlinks, services, tuned profile   │
│ 7. Reboot → Hyprland desktop, fully configured           │
│                                                          │
│ First nvim launch: lazy.nvim auto-syncs plugins (WiFi)   │
└─────────────────────────────────────────────────────────┘
```

### Key design decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base ISO | Fedora boot.iso (~800 MB) | Smallest Anaconda base; all packages from embedded repo |
| Build tool | mkksiso (from lorax) | Embeds kickstart + files into existing ISO; simpler than livemedia-creator |
| Credentials | Build-time injection via `--password-hash-file` or `ISO_PASSWORD_HASH` env var | Issue #14: %pre interactive prompts fail in Anaconda. File/env avoids shell history leaks |
| Package install | All in kickstart `%packages` | Anaconda handles dependency resolution from embedded repo |
| Config stages | kickstart `%post` (chroot) | Pure file ops + `systemctl enable` (creates symlinks, no running systemd needed) |
| Neovim plugins | Pre-clone lazy.nvim; defer plugin sync | First nvim launch auto-syncs (needs WiFi); matches Omarchy approach |
| install.sh | Unchanged, kept as manual path | ISO = alternative path, not replacement |
| ISO size target | <2 GiB | Fits GitHub Release asset limit; boot.iso + packages ≈ 1.3-1.8 GB |

### mkksiso contract (critical details)

mkksiso embeds files into the existing Fedora boot.iso. The exact in-ISO paths:

- `mkksiso --ks /tmp/kickstart.ks` → embeds as `/ks.cfg` at ISO root
- `-a <local-repo-dir>:/local-repo` → RPM repo appears as `/local-repo` at ISO root
- `-a <assets-dir>:/iso-assets` → assets appear as `/iso-assets` at ISO root
- `-a <repo-dir>:/surface-linux` → dotfiles repo appears as `/surface-linux` at ISO root
- `-c "inst.ks=cdrom:/ks.cfg"` → boot cmdline tells Anaconda to load ks from the ISO itself (NOT `file:///` which refers to initrd filesystem)
- `-V "SurfaceLinux-43"` → volume label

Note: If mkksiso on Fedora 43 does not support `-a SRC:DEST` mapping syntax, use a fallback: copy directories to temp paths with the desired names (`/tmp/local-repo`, `/tmp/iso-assets`, `/tmp/surface-linux`) and use plain `-a /tmp/local-repo` etc.

When Anaconda boots from this ISO, it mounts the ISO filesystem at `/run/install/isodir/`. Therefore:
- The local repo is at `file:///run/install/isodir/local-repo` (used in kickstart `repo` directive)
- Assets are at `/run/install/isodir/iso-assets/` (used in `%post --nochroot`)

### Credential handling

The build script accepts credentials via three methods (priority order):
1. `--password-hash-file=PATH` — reads hash from file (recommended, avoids shell history)
2. `ISO_PASSWORD_HASH` environment variable — useful for CI
3. `--password-hash=HASH` — direct CLI (convenience, but leaks to shell history)

Username is provided via `--username=NAME` (not sensitive).

The ISO kickstart template has `@@USERNAME@@` and `@@PASSWORD_HASH@@` placeholders (distinct from the existing kickstart's `CHANGEME_*` pattern). The build script substitutes these before passing to mkksiso. The resulting ISO has credentials baked in — acceptable for personal use (single device, single user).

For GitHub Actions: CI runs validation/dry-run with dummy credentials. The build script MUST NOT log password hashes in any output.

**Security note:** ISOs built with real credentials should never be uploaded to public GitHub Releases. CI builds always use `--test` mode with dummy credentials.

### Package list single source of truth

To avoid drift between `lib/03-packages.sh` and the ISO kickstart's `%packages`, the build script extracts the package list from the existing lib files at build time. Pattern:
- Parse `lib/03-packages.sh` for the `pkgs=()` array
- Parse `lib/02-kernel.sh` for kernel packages
- Parse `lib/01-repos.sh` for COPR list
- Generate the kickstart `%packages` section dynamically

### Offline repo construction

In the build container (Fedora 43):
1. Install `dnf5-plugins` (for copr + config-manager subcommands)
2. Enable 3 COPRs + linux-surface repo
3. Expand `@^minimal-environment` group to individual package names:
   ```
   dnf5 group info '@^minimal-environment' --quiet → parse mandatory/default package names
   ```
4. `dnf5 download --resolve --destdir=/build/.cache/rpms --arch=x86_64 --arch=noarch <all-packages>`
5. `createrepo_c /build/.cache/rpms`
6. **Validate with repoclosure**: verify the local repo alone can satisfy the *expanded package set* (individual packages from `@^minimal-environment` expansion + explicit packages) without external repos. Use expanded package names, not the group token, since the local repo has no comps.xml group metadata

**Critical constraints:**
- The Containerfile MUST NOT install any target runtime packages; only build tools (lorax, createrepo_c, dnf5-plugins, git, jq, xorriso, isomd5sum). Installing target packages would cause `dnf5 download --resolve` to miss their transitive dependencies.
- Cache paths use the workspace mount (`/build/.cache/`) not container `/tmp/`, so GitHub Actions can cache them between runs.

### %post structure (ISO kickstart)

All `%post` logic uses the baked-in `@@USERNAME@@` placeholder (substituted at ISO build time). There is no runtime discovery of the username — the model is purely static.

```
%post --nochroot --log=/mnt/sysroot/var/log/ks-nochroot.log
# Copy surface-linux repo from ISO to installed system
# Copy pre-downloaded binaries to ~/.local/bin/ (matching lib/04-binaries.sh versions)
# Copy pre-downloaded fonts to ~/.local/share/fonts/JetBrainsMono/ (matching lib/05-fonts.sh layout + .nf-version)
# Copy pre-cloned lazy.nvim to ~/.local/share/nvim/lazy/lazy.nvim/
# Set ownership to target user
# Run: chroot /mnt/sysroot fc-cache -f (rebuild font cache)
%end

%post --log=/var/log/ks-post.log
# Set HOME=/home/@@USERNAME@@, REPO_DIR=$HOME/surface-linux
# Write zram config (from lib/06-zram.sh pattern)
# Write iwd backend config (from lib/07-network.sh pattern)
# Write getty auto-login override (from lib/08-desktop.sh pattern)
# Write XDG portal config, UWSM env, systemd user env
# Create dotfile symlinks (from lib/11-dotfiles.sh pattern)
# Deploy helper scripts, wallpapers, .Xresources
# Append bashrc.d sourcing + UWSM auto-start to shell profiles
# Set graphical.target as default (matches lib/12-services.sh)
# Set plymouth spinner theme (without -R)
# Fix ownership of all $HOME content
%end
```

Service enabling uses kickstart's `services` directive with canonical unit names:
```
services --enabled=NetworkManager,iwd,bluetooth,tuned
```

Note: `tuned-ppd` is a package (extends tuned's powerprofilesctl interface), NOT a service unit. It is included in `%packages` but not in `services --enabled`.

The `%post` and `services` directive MUST fully mirror the behavior of `lib/12-services.sh` — enabling the same units and setting the same default target. Any differences should be deliberate and documented.

### Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| mkksiso can't handle 500 MB+ local repo addition | Low | mkksiso uses xorriso internally; handles large files. Fallback: manual xorriso ISO remaster |
| Package dependency incomplete (dnf5 download misses transitive deps) | Medium | Run download in minimal container (no target packages installed). Validate with repoclosure in CI |
| ISO exceeds 2 GiB (GitHub Release limit) | Low | boot.iso (800 MB) + packages (~700 MB) + assets (~50 MB) ≈ 1.5 GB. Use `%packages --excludedocs --excludeWeakdeps` |
| COPR package ABI mismatch at download time | Low | Download all COPR packages atomically. Accept that COPR maintainer could push partial update |
| Anaconda can't find embedded repo | Medium | Use `inst.ks=cdrom:/ks.cfg` + `repo --baseurl=file:///run/install/isodir/local-repo`. Test in QEMU first |
| mkksiso-modified ISO doesn't boot via Ventoy | Low | Test on actual Ventoy USB. Fallback: dd directly to USB, skip Ventoy |
| Build fails on GitHub Actions (disk space) | Medium | Use `jlumbroso/free-disk-space` action first. Monitor disk usage in workflow |
| Config drift between ISO and install.sh paths | Medium | %post mirrors exact behavior of lib/*.sh stages. Acceptance criteria require parity |

### Test notes

- **Local build test:** Run `./iso/build-iso.sh` in Podman on macOS (Apple Silicon with `--platform linux/amd64`). Verify ISO is produced.
- **Repoclosure test:** Validate the offline repo can satisfy all packages in an isolated container (no external repos). Run automatically in `--validate-only` mode.
- **QEMU smoke test:** Boot the ISO in QEMU with `-m 4096 -drive file=test.qcow2,format=qcow2` and verify Anaconda starts, finds embedded repo, begins installation.
- **Real hardware test:** Flash ISO to USB, boot Surface Go 3, verify full offline install produces working Hyprland desktop.
- **Idempotency test:** After ISO install, verify `./install.sh` can still run without errors (converges to same state). Specifically: `./install.sh --only fonts`, `--only binaries`, `--only dotfiles` must be idempotent with pre-seeded assets.
- **CI validation:** GitHub Actions builds ISO with dummy credentials, validates repo completeness, uploads as artifact.

## Quick commands

```bash
# Build the ISO locally (requires Podman)
# Generate password hash first:
openssl passwd -6 > /tmp/hash.txt
./iso/build-iso.sh --username=edu --password-hash-file=/tmp/hash.txt

# Build with default test credentials (for development)
./iso/build-iso.sh --test

# Validate ISO build + repo completeness in CI (no credentials, no mkksiso)
./iso/build-iso.sh --validate-only

# Flash ISO to USB
sudo dd if=output/surface-linux-F43-*.iso of=/dev/sdX bs=4M status=progress

# After ISO install, verify install.sh still works
./install.sh --list
./install.sh --only theme
```

## Acceptance

- [ ] `./iso/build-iso.sh --username=X --password-hash-file=Y` produces a bootable ISO from Fedora boot.iso
- [ ] ISO contains embedded local repo with all packages (official + COPR + linux-surface)
- [ ] Offline repo passes repoclosure: can satisfy all `%packages` + `@^minimal-environment` without external repos
- [ ] ISO contains pre-downloaded binaries (impala, bluetui, starship), fonts (JetBrains Mono NF), lazy.nvim
- [ ] Binary versions and font layout match `lib/04-binaries.sh` and `lib/05-fonts.sh` exactly
- [ ] Anaconda installs fully offline from embedded repo (no network activity during install)
- [ ] %post configures: zram, iwd backend, getty auto-login, XDG portals, UWSM env, dotfiles, services
- [ ] %post service configuration matches `lib/12-services.sh` behavior (same enabled units, same default target)
- [ ] After reboot: Hyprland starts via UWSM with Tokyo Night theme, all tools functional
- [ ] Existing `install.sh` works unchanged after ISO-based install (including `--only fonts`, `--only binaries`)
- [ ] GitHub Actions workflow validates ISO build + repo completeness on every push/PR
- [ ] ISO size < 2 GiB (fits GitHub Release asset limit)
- [ ] README documents both install paths (manual kickstart vs. custom ISO)
- [ ] Build script never logs password hashes; supports file/env input methods

## References

- [Omarchy ISO builder](https://github.com/omacom-io/omarchy-iso) — Arch Linux equivalent, architecture inspiration
- [mkksiso documentation](https://weldr.io/lorax/mkksiso.html) — Embed kickstart + files into existing Fedora ISO
- [livemedia-creator docs](https://weldr.io/lorax/livemedia-creator.html) — Fallback if mkksiso insufficient
- [voor/fedora-offline-kickstart-spin](https://github.com/voor/fedora-offline-kickstart-spin) — Example offline Fedora ISO project
- [Pykickstart reference](https://pykickstart.readthedocs.io/en/latest/kickstart-docs.html) — Kickstart syntax
- [Anaconda boot options](https://anaconda-installer.readthedocs.io/en/latest/user-guide/boot-options.html) — inst.repo, inst.ks paths
- [Project Issue #14](ISSUES.md) — Why %pre interactive prompts fail
- [jlumbroso/free-disk-space](https://github.com/jlumbroso/free-disk-space) — GitHub Actions disk space recovery
