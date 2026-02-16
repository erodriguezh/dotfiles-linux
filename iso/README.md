# Custom ISO Build System

Developer documentation for building a self-contained, offline Fedora 43 ISO for the Surface Go 3.

## Overview

The ISO build system produces a single bootable ISO (~1.5 GB) that contains all packages, binaries, fonts, and configuration needed for a complete Hyprland desktop install. No network is required during installation.

```
┌─────────────────────────────────────────────────────────┐
│ BUILD (Podman container, Fedora 43)                      │
│                                                          │
│ 1. Enable repos: official + 3 COPRs + linux-surface      │
│ 2. Expand @^minimal-environment to package list          │
│ 3. dnf5 download --resolve to local RPM cache            │
│ 4. createrepo_c to build repo metadata                   │
│ 5. repoclosure validation                                │
│ 6. Download: impala, bluetui, starship, JetBrains Mono   │
│ 7. git clone lazy.nvim (stable branch)                   │
│ 8. Copy surface-linux repo + generate theme files        │
│ 9. Substitute credentials in kickstart template          │
│ 10. mkksiso: embed ks + repo + assets into boot.iso      │
│                                                          │
│ Output: surface-linux-F43-YYYYMMDD-x86_64.iso (~1.5 GB)  │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Podman** (rootless is fine; the build runs as root inside the container)
- ~5 GB free disk space (RPM cache + ISO output)
- Network access (for downloading packages, boot.iso, and assets during build)

## Usage

### Credential input methods

The build script accepts credentials through multiple methods. Credentials are injected into the ISO kickstart at build time.

| Flags | Credentials used | mkksiso run? |
|-------|-----------------|--------------|
| `--username X --password-hash-file Y` | Real | Yes |
| `--test` | Dummy (testuser/test) | Yes |
| `--validate-only` | Dummy or none | No |
| `--test --validate-only` | Dummy | No |

Priority order when multiple are provided:
1. `--password-hash-file=PATH` (recommended -- avoids shell history)
2. `ISO_PASSWORD_HASH` environment variable (useful for CI)
3. `--password-hash=HASH` (convenience -- leaks to shell history)

### Generate a password hash

```bash
openssl passwd -6 > hash.txt
```

This writes a SHA-512 crypt hash (starts with `$6$`) to `hash.txt`. The file should contain only the hash string.

### Build with real credentials

```bash
./iso/build-iso.sh --username=edu --password-hash-file=hash.txt
```

### Build with test credentials

```bash
./iso/build-iso.sh --test
```

Uses dummy credentials (`testuser` / `test`). Suitable for development and CI.

### Validate repo completeness only

```bash
./iso/build-iso.sh --validate-only
```

Downloads packages, creates the local repo, and runs repoclosure to verify all dependencies are satisfied. Does not download boot.iso, assets, or produce an ISO. Useful for CI validation.

### Additional options

```
--boot-iso=PATH     Use a pre-downloaded boot.iso (skips download)
--output-dir=PATH   Output directory (default: /build/output/)
-h, --help          Show usage
```

## How It Works

### Build stages (in order)

1. **Expand @^minimal-environment** -- Queries dnf5 for the full list of packages in the Minimal Install environment group, including nested mandatory/default groups.

2. **Extract target packages** -- Parses `lib/03-packages.sh` and `lib/02-kernel.sh` to build the list of packages the install script would normally install. This keeps the ISO's package list in sync with the manual install path.

3. **Download RPMs** -- `dnf5 download --resolve` fetches all packages and their transitive dependencies to `/build/.cache/rpms/`. The build container has only build tools installed (no target packages), so `--resolve` correctly captures the full dependency tree.

4. **Create local repo** -- `createrepo_c` generates repo metadata over the downloaded RPMs.

5. **Repoclosure validation** -- Verifies the local repo alone can satisfy every package in the combined list. Uses `dnf5 install --assumeno` with only the local repo enabled.

6. **Download boot.iso** -- Fetches the Fedora 43 boot.iso (~800 MB) with SHA-256 verification. Cached between builds.

7. **Download binaries** -- Fetches impala, bluetui, and starship at the exact versions matching `lib/04-binaries.sh`.

8. **Download fonts** -- Fetches JetBrains Mono Nerd Font at the version matching `lib/05-fonts.sh`, preserving the `.nf-version` marker file.

9. **Pre-clone lazy.nvim** -- Clones the stable branch of lazy.nvim for offline Neovim bootstrap.

10. **Prepare repo + theme** -- Copies the surface-linux repo to a staging directory, generates theme files from `colors.toml` templates (replicating `lib/09-theme.sh` logic).

11. **Substitute credentials** -- Replaces `@@USERNAME@@` and `@@PASSWORD_HASH@@` placeholders in the ISO kickstart template.

12. **Assemble ISO** -- `mkksiso` embeds the kickstart, local repo, assets, and surface-linux repo into the Fedora boot.iso. Generates a SHA-256 checksum file alongside the output ISO.

### ISO layout

After mkksiso assembly, the ISO root contains:

```
/ks.cfg          -- Kickstart (from iso/surface-go3-iso.ks with credentials)
/local-repo/     -- All RPMs + repodata (offline package source)
/iso-assets/     -- Pre-downloaded binaries, fonts, lazy.nvim
/surface-linux/  -- This repository (with pre-generated theme files)
```

Anaconda mounts the ISO at `/run/install/isodir/` during installation.

### Kickstart details

The ISO uses `iso/surface-go3-iso.ks` (separate from `kickstart/surface-go3.ks` used by the manual path). Key differences:

- Packages come from the embedded local repo (`repo --baseurl=file:///run/install/isodir/local-repo`)
- All target packages are listed explicitly in `%packages` (not just Minimal Install + git)
- `%post --nochroot` copies binaries, fonts, lazy.nvim, and the repo from the ISO to the installed system
- `%post` (chroot) configures zram, networking, getty, XDG portals, UWSM, dotfiles, and services
- Credentials are baked in at build time (no `CHANGEME_*` placeholders)
- The stock kernel is excluded (`-kernel`) in favor of `kernel-surface`

## GitHub Actions

The CI workflow (`.github/workflows/build-iso.yml`) runs on every push and PR:

- **Validation job:** Builds the container, runs `--validate-only` to verify repo completeness
- **Manual dispatch:** Supports `workflow_dispatch` to trigger a full ISO build with test credentials, uploaded as a GitHub Actions artifact

CI builds always use `--test` mode with dummy credentials. The workflow uses `jlumbroso/free-disk-space` to reclaim runner disk space before building.

## Customization

### Keyboard layout

Edit the `keyboard` line in `iso/surface-go3-iso.ks`:
```
keyboard --xlayouts='us'
```

### Timezone

Edit the `timezone` line in `iso/surface-go3-iso.ks`:
```
timezone America/New_York --utc
```

### Adding packages

Add packages to `lib/03-packages.sh` in the `pkgs=()` array. The build script extracts packages from this file automatically, so changes apply to both install paths. You will also need to add the package to the `%packages` section in `iso/surface-go3-iso.ks` to ensure it is included in the offline repo.

## Troubleshooting

### Build fails with disk space error

The build needs ~5 GB: ~2 GB for RPMs, ~800 MB for boot.iso, ~1.5 GB for the output ISO. Free disk space or use `--output-dir` to write to a different mount.

### COPR repo unavailable

If a COPR repo is temporarily down, the RPM download stage will fail. Retry later, or manually download the affected packages and place them in `/build/.cache/rpms/`.

### repoclosure fails

This means the local repo is missing a dependency. Check the error output for which package requires what. Common causes:
- A new dependency was added upstream since the last build
- A COPR package has an unlisted dependency on an official Fedora package

Fix: Add the missing package to `lib/03-packages.sh` and rebuild.

### mkksiso fails with "ISO too large"

The ISO must stay under 2 GiB for GitHub Release compatibility. The `--excludeWeakdeps --excludedocs` flags in `%packages` help. If the ISO still exceeds the limit, review the package list for removable weak dependencies.

## Testing

### QEMU smoke test

```bash
# Create a test disk image
qemu-img create -f qcow2 test.qcow2 32G

# Boot the ISO in QEMU (UEFI mode)
qemu-system-x86_64 \
    -m 4096 \
    -enable-kvm \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -drive file=test.qcow2,format=qcow2 \
    -cdrom output/surface-linux-F43-*.iso \
    -boot d
```

Verify: Anaconda starts, finds the embedded repo, begins installation without network prompts.

### Idempotency test

After an ISO install, verify that `install.sh` still works:

```bash
./install.sh --only fonts      # should detect fonts already present
./install.sh --only binaries   # should detect binaries already present
./install.sh --only dotfiles   # should re-symlink without errors
```

## Security

- **Never upload ISOs with real credentials to public GitHub Releases.** CI builds always use `--test` mode with dummy credentials.
- Use `--password-hash-file` instead of `--password-hash` to avoid leaking the hash to shell history.
- The build script never logs password hashes in its output.
- The ISO kickstart contains the baked-in password hash. Treat ISOs built with real credentials as sensitive -- they should not be shared publicly.

## Files

| File | Purpose |
|------|---------|
| `iso/build-iso.sh` | Build orchestrator (runs inside Podman container) |
| `iso/Containerfile` | Build environment definition (Fedora 43 + build tools) |
| `iso/surface-go3-iso.ks` | Kickstart template for the custom ISO (separate from `kickstart/surface-go3.ks`) |
| `iso/README.md` | This file |
