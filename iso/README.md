# Custom ISO Build System

Developer documentation for building a self-contained, offline Fedora 43 ISO for the Surface Go 3.

## Overview

The ISO build system produces a single bootable ISO (~1.5 GB) that contains all packages, binaries, fonts, and configuration needed for a complete Hyprland desktop install. No network is required during installation.

```
┌─────────────────────────────────────────────────────────┐
│ BUILD (Podman container, Fedora 43)                      │
│                                                          │
│ Containerfile: enables repos (3 COPRs + linux-surface)   │
│                                                          │
│ build-iso.sh (runs inside the container):                │
│  1. Expand @^minimal-environment to package list         │
│  2. dnf5 download --resolve --alldeps to local RPM cache  │
│  3. createrepo_c to build repo metadata                  │
│  4. Dual validation (repoclosure + install simulation)    │
│  5. Download: impala, bluetui, starship, JetBrains Mono  │
│  6. git clone lazy.nvim (stable branch)                  │
│  7. Copy surface-linux repo + generate theme files       │
│  8. Substitute credentials in kickstart template         │
│  9. mkksiso: embed ks + repo + assets into boot.iso      │
│                                                          │
│ Output: surface-linux-F43-YYYYMMDD-x86_64.iso (~1.5 GB)  │
└─────────────────────────────────────────────────────────┘
```

Repo enablement (COPRs + linux-surface) is done in `iso/Containerfile`; `build-iso.sh` assumes those repos are already available inside the container.

## Prerequisites

- **Podman** (rootless is fine; the build runs as root inside the container)
- ~5 GB free disk space (RPM cache + ISO output)
- Network access (for downloading packages, boot.iso, and assets during build)

## Usage

All `build-iso.sh` commands below must run **inside** the Fedora 43 build container. From the host, invoke them via Podman:

```bash
# Build the container image (once)
podman build -t surface-iso-builder iso/

# Run build-iso.sh inside the container (mount repo at /build)
podman run --privileged --rm \
  -v "$PWD:/build" \
  surface-iso-builder \
  /build/iso/build-iso.sh [OPTIONS]
```

If you are already inside the builder container (e.g., during development), run `./iso/build-iso.sh [OPTIONS]` directly.

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

3. **Download RPMs** -- `dnf5 download --resolve --alldeps` fetches all packages and their transitive dependencies to `/build/.cache/rpms/`. The `--alldeps` flag is critical: it disables the system RPM database during resolution, ensuring ALL transitive deps are downloaded regardless of what is installed in the build container. `--setopt=install_weak_deps=False` excludes weak dependencies to match the kickstart's `--excludeWeakdeps` and keep the ISO lean.

4. **Create local repo** -- `createrepo_c` generates repo metadata over the downloaded RPMs.

5. **Repo validation** -- Two complementary checks verify the local repo is self-consistent and complete, using `--repofrompath` to create a transient repo (dnf5 does not support ad-hoc repo creation via `--setopt`). First, `dnf5 repoclosure` verifies every RPM's `Requires:` is satisfiable within the repo (structural integrity). Then, `dnf5 install --assumeno` verifies the specific combined package list can be resolved from the local repo alone (completeness); `--assumeno` exits 0 on successful resolution and 1 on failure, so the script inspects output for `Problem:` or `No match for argument:` to distinguish real errors. Both checks use `--setopt=reposdir=/dev/null` to isolate the local repo.

6. **Download boot.iso** -- Fetches the Fedora 43 boot.iso (~800 MB) with SHA-256 verification. Cached between builds.

7. **Download binaries** -- Fetches impala, bluetui, and starship at the exact versions matching `lib/04-binaries.sh`.

8. **Download fonts** -- Fetches JetBrains Mono Nerd Font at the version matching `lib/05-fonts.sh`, preserving the `.nf-version` marker file.

9. **Pre-clone lazy.nvim** -- Clones the stable branch of lazy.nvim for offline Neovim bootstrap.

10. **Prepare repo + theme** -- Copies the surface-linux repo to a staging directory, generates theme files from `colors.toml` templates (replicating `lib/09-theme.sh` logic).

11. **Substitute credentials** -- Replaces `@@USERNAME@@` and `@@PASSWORD_HASH@@` placeholders in the ISO kickstart template.

12. **Assemble ISO** -- `mkksiso` embeds the kickstart, local repo, assets, and surface-linux repo into the Fedora boot.iso. After assembly, a three-layer verification model checks boot configs:
    1. **ISO-level `/EFI/BOOT/grub.cfg`** -- required, verified pre-patch. Hard-fails if missing (mkksiso `EditGrub2()` always creates this).
    2. **ISO-level BIOS GRUB2** (`boot/grub2/grub.cfg`) -- best-effort, warn if missing. Surface Go 3 is UEFI-only; Fedora 37+ dropped isolinux/syslinux in favor of GRUB2 for BIOS boot.
    3. **efiboot.img internal grub.cfg** -- verified post-patch (USB UEFI boot path). When `--skip-mkefiboot` is active, `patch_efiboot` updates volume labels in known patterns (`search --label`/`-l`, `hd:LABEL=`) and injects `inst.ks=` into installer stanzas.

    Generates a SHA-256 checksum file alongside the output ISO.

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
- **Manual dispatch (`workflow_dispatch`):**
  - `upload_artifact: true` -- builds a full ISO with test credentials and uploads it as a workflow artifact
  - `create_release: true` -- builds a full ISO with test credentials and publishes it as a GitHub Release (with checksum)

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

### Repo validation fails

Stage 5 runs two checks. If **repoclosure** fails, a downloaded RPM has a `Requires:` that no other RPM in the local repo satisfies. If the **install simulation** fails (look for `Problem:` or `No match for argument:` in the output), the specific package list cannot be resolved from the local repo alone. Common causes:
- A new dependency was added upstream since the last build
- A COPR package has an unlisted dependency on an official Fedora package

Fix: Add the missing package to `lib/03-packages.sh` and rebuild.

### mkksiso fails with losetup / mkefiboot error

`mkksiso` calls `mkefiboot` which needs loop devices (`/dev/loop*`) to build the EFI boot image. Loop devices are unavailable in rootless Podman, macOS Docker, and some CI environments.

The build script **automatically detects** this using an actual loop device attachment test (creates a 1 MiB temp file and attempts `losetup --find --show`). If attachment fails, it adds `--skip-mkefiboot` and then **patches the efiboot.img** inside the output ISO using mtools (no loop devices needed):

1. **Extracts `efiboot.img`** using a three-tier fallback chain:
    1. **Output ISO filesystem** -- `osirrox -extract /images/efiboot.img` from the assembled ISO (works when mkksiso preserves the entry).
    2. **Boot ISO filesystem** -- same extraction from the original Fedora `boot.iso` (works if the boot ISO has a visible `/images/efiboot.img` entry).
    3. **El Torito boot catalog** -- `osirrox -extract_boot_images` (falls back to `xorriso -osirrox on -extract_boot_images` if extraction fails) extracts hidden boot images from the boot ISO. Fedora 43 stores `efiboot.img` exclusively in the [El Torito](https://en.wikipedia.org/wiki/El_Torito_(CD-ROM_standard)) boot catalog and GPT appended partition, not as a visible ISO 9660 directory entry. El Torito is a standard for embedding hidden boot partitions in optical media -- these partitions are invisible to normal filesystem extraction (`osirrox -extract`) but contain the actual EFI FAT image that firmware reads at boot. The extracted files are probed with `mcopy` to identify the one containing `grub.cfg` (checking both `/EFI/BOOT/grub.cfg` and `/EFI/fedora/grub.cfg`); ambiguous or empty results cause a hard failure with diagnostics.
2. Locates `grub.cfg` inside the FAT image via `mcopy` existence probes
3. Derives the `inst.ks=` value from the ISO-level `/EFI/BOOT/grub.cfg` (what mkksiso already injected)
4. Replaces the original Fedora volume label in known patterns (`search --label`/`-l`, `hd:LABEL=`) using targeted `python3` regex substitution
5. Injects `inst.ks=` into installer stanzas (those containing `inst.stage2=`), handling GRUB `\` line continuations
6. Re-injects the patched `efiboot.img` via `xorriso`, preserving any appended EFI partition
7. Spot-checks that ISO-level `/EFI/BOOT/grub.cfg` is still intact after xorriso rewrite
8. Re-implants the media checksum via `implantisomd5`

You'll see warnings in the output:

```
[WARN] Loop device attachment failed — adding --skip-mkefiboot
[INFO] Patching efiboot.img: label='SurfaceLinux-43', inst.ks='inst.ks=hd:LABEL=...'
```

As a defense-in-depth measure, if the initial mkksiso run (without `--skip-mkefiboot`) fails with a mkefiboot/losetup error, the script automatically retries once with `--skip-mkefiboot` and patching enabled.

UEFI USB boot is preserved because the patched grub.cfg searches for the correct custom volume label and includes the `inst.ks=` boot argument. If you need custom EFI partition modifications beyond label patching, use rootful Podman:

```bash
sudo podman run --privileged --rm -v "$PWD:/build" \
  surface-iso-builder /build/iso/build-iso.sh [OPTIONS]
```

### Re-running build-iso.sh on the same day

Safe by design. `mkksiso` has no `--force` or `--overwrite` flag and will refuse to write to an output path that already exists. The build script handles this automatically by removing any previous `surface-linux-F43-YYYYMMDD-x86_64.iso` (and its `.sha256` sidecar) before invoking `mkksiso`. You will see an info log when a previous build is detected:

```
[INFO]  Removing previous build: surface-linux-F43-20260218-x86_64.iso
```

No manual cleanup is needed between re-runs.

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
