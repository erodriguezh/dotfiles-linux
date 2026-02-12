# Dotfiles Linux

Idempotent Bash install script for **Fedora 43** on the **Surface Go 3** (Intel Pentium Gold 6500Y, 4 GB RAM, eMMC storage). Transforms a Minimal Install into a fully configured Hyprland 0.53+ desktop with Tokyo Night theming.

## Hardware Target

| Component | Detail |
|-----------|--------|
| Device | Microsoft Surface Go 3 |
| CPU | Intel Pentium Gold 6500Y |
| RAM | 4 GB LPDDR3 |
| Storage | eMMC (`/dev/mmcblk0`) |
| Display | 10.5" 1920x1280 (~220 PPI), 1.5x scaling |
| Kernel | linux-surface (from linux-surface repo) |

## Prerequisites

- **Secure Boot disabled** in UEFI firmware settings (hold Volume Up during boot to enter UEFI). Alternatively, you can enroll linux-surface keys after install using `surface-secureboot`, but disabling is simpler.
- A USB flash drive (4 GB minimum).
- A network connection (the Everything ISO downloads packages during install).

## USB Preparation

### Step 1: Download the Fedora Everything ISO

Download the **Fedora 43 Everything** (netinstall) ISO from the [Fedora download page](https://fedoraproject.org/everything/download). This is a minimal network installer that pulls packages during installation.

### Step 2: Prepare the USB drive with Ventoy

Use [Ventoy](https://www.ventoy.net/) to create a multiboot USB with a reserved OEMDRV partition for the kickstart file. Anaconda has hardcoded logic to scan for a volume labeled `OEMDRV` and auto-load `ks.cfg` from it — no boot parameter editing needed.

```bash
# Install Ventoy with 16 MB reserved space at end of disk
sudo sh Ventoy2Disk.sh -i -r 16 /dev/sdX

# Create the OEMDRV partition in the reserved space (use GNOME Disks or CLI)
sudo mkfs.ext4 -L 'OEMDRV' /dev/sdXN

# Copy the kickstart file (MUST be named ks.cfg)
sudo mkdir -p /mnt/oemdrv
sudo mount /dev/sdXN /mnt/oemdrv
sudo cp kickstart/surface-go3.ks /mnt/oemdrv/ks.cfg
sudo umount /mnt/oemdrv

# Copy the Fedora Everything ISO to the Ventoy data partition
sudo mount /dev/sdX1 /mnt/usb
sudo cp Fedora-Everything-netinst-x86_64-43-*.iso /mnt/usb/
sudo umount /mnt/usb
```

**Note:** Anaconda may overwrite the OEMDRV partition during install. Recreate it after install if you need to reuse it. The kickstart's `ignoredisk --only-use=mmcblk0` protects the USB drive from `clearpart --all`.

### Step 3: Edit the Kickstart file

Open `kickstart/surface-go3.ks` and customize these values:

1. **REPO_URL** (required) -- set to your clone of this repository:
   ```
   REPO_URL="https://github.com/erodriguezh/dotfiles-linux.git"
   ```

2. **Keyboard layout** (optional) -- defaults to German (`de`). Change if needed:
   ```
   keyboard --xlayouts='us'
   ```

3. **Timezone** (optional) -- defaults to `Europe/Vienna`. Change if needed:
   ```
   timezone America/New_York --utc
   ```

Note: The keyboard layout affects the `%pre` password prompt. Make sure you know which layout is active when typing your password to avoid lockout.

### Step 4: Alternative kickstart delivery methods

Step 2 covers the recommended OEMDRV approach. These alternatives exist if OEMDRV is not an option.

#### Method A: Second USB drive

Format a second USB stick (or SD card) as FAT32 with the label `KICKSTART`, then copy the kickstart file to it.

**macOS** (replace `disk9` with your device — use `diskutil list` to find it):
```bash
diskutil eraseDisk FAT32 KICKSTART MBRFormat /dev/disk9
cp kickstart/surface-go3.ks /Volumes/KICKSTART/
```

**Linux** (replace `/dev/sdY` with your device):
```bash
sudo mkfs.vfat -n KICKSTART /dev/sdY1
sudo mkdir -p /mnt/ks
sudo mount /dev/sdY1 /mnt/ks
sudo cp kickstart/surface-go3.ks /mnt/ks/surface-go3.ks
sudo umount /mnt/ks
```

Insert both USB drives and boot (use a USB-C hub if the device has only one port). Boot parameter:
```
inst.ks=hd:LABEL=KICKSTART:/surface-go3.ks
```

#### Method B: GitHub raw URL (wired connection only)

If the device has ethernet (or a USB-C ethernet adapter), point the installer directly at the raw file — no second USB needed.

Boot parameter:
```
inst.ks=https://raw.githubusercontent.com/erodriguezh/dotfiles-linux/main/kickstart/surface-go3.ks
```

### Step 5: Boot and install

1. Insert the USB into the Surface Go 3.
2. Power on while holding **Volume Down** to boot from USB.
3. Select the Fedora Everything ISO in the Ventoy menu.
4. Anaconda auto-detects the OEMDRV partition and loads `ks.cfg` — no boot parameter editing needed. (If using an alternative method from Step 4, press **`e`** at the GRUB menu to append `inst.ks=...` to the `linuxefi` line, then **Ctrl+X** to boot.)
5. Anaconda will start in text mode:
   - **Connect to WiFi** when prompted (the Everything ISO needs network access).
   - You will be prompted for a **username** and **password** for your user account.
   - Installation proceeds automatically: partitions the eMMC, installs Minimal Install, creates your user (with sudo via wheel group), clones this repo.
6. The system reboots automatically when done.

### What the Kickstart does

- Targets the eMMC (`/dev/mmcblk0`) with GPT partitioning
- Creates EFI System Partition + `/boot` (2 GiB) + ext4 root (remaining space)
- No swap partition (zram handles it), no LUKS encryption
- Locks the root password (no root login)
- Creates your user in the `wheel` group (full sudo access)
- Installs Fedora 43 Minimal Install + `sudo` + `git`
- Clones this repository to `~/surface-linux`

## Post-Install

After the system reboots from the Kickstart install:

1. Log in at the text console as your user.
2. Run the install script:

```bash
cd ~/surface-linux
./install.sh
```

3. Wait for the script to complete (requires network for package downloads).
4. Reboot:

```bash
sudo reboot
```

5. After reboot, Hyprland starts automatically via UWSM.

**Important:** Run `install.sh` as your normal user, NOT as root. The script uses `sudo` internally for operations that require elevated privileges.

## Quick Reference

```bash
# Full install (all stages)
./install.sh

# List all available stages
./install.sh --list

# Run only a specific stage (prerequisites run automatically)
./install.sh --only packages

# Skip a specific stage (repeatable)
./install.sh --skip kernel

# Skip multiple stages
./install.sh --skip kernel --skip theme
```

## Stages

The install script runs these stages in order:

| # | Stage | Description |
|---|-------|-------------|
| 1 | `repos` | Enable COPR repos (sdegler/hyprland, scottames/ghostty, alternateved/tofi) + linux-surface repo |
| 2 | `kernel` | Install kernel-surface + libwacom-surface (skipped on non-Surface hardware) |
| 3 | `packages` | Install all desktop and system packages via dnf5 |
| 4 | `binaries` | Download Impala (WiFi TUI) and bluetui (Bluetooth TUI) to ~/.local/bin |
| 5 | `fonts` | Install JetBrains Mono Nerd Font |
| 6 | `zram` | Configure zram swap (4 GB, takes effect after reboot) |
| 7 | `network` | Configure iwd backend for NetworkManager |
| 8 | `desktop` | Configure plymouth, getty auto-login, XDG portals |
| 9 | `theme` | Process Tokyo Night color templates |
| 10 | `dotfiles` | Symlink configs from repo to ~/.config/ |
| 11 | `neovim` | Bootstrap LazyVim with Tokyo Night theme |
| 12 | `services` | Enable and configure systemd services |

### Stage dependencies

Using `--only <stage>` automatically runs prerequisite stages:

- `kernel` requires `repos`
- `packages` requires `repos`
- `binaries` requires `packages`
- `fonts` requires `packages`
- `network` requires `fonts`
- `desktop` requires `packages`
- `theme` requires `packages`
- `dotfiles` requires `theme`
- `neovim` requires `dotfiles`
- `services` requires `packages`

## Hardware Detection

On non-Surface hardware (VMs, other laptops), the script automatically skips Surface-specific stages (kernel installation). Everything else -- Hyprland, packages, configs, theming -- works on any Fedora 43 machine.

## Idempotency

Running the script multiple times is safe. It converges to the same end-state without errors, duplicate entries, or accumulated side effects. Packages already installed are skipped by dnf, configs are overwritten to the canonical state, and symlinks are replaced atomically.

## Secure Boot

This setup assumes Secure Boot is **disabled** in the UEFI firmware. If you prefer to keep Secure Boot enabled, first run `./install.sh` (or at least `./install.sh --only repos`) to add the linux-surface repository, then enroll the signing keys:

```bash
sudo dnf5 install surface-secureboot
sudo surface-secureboot enroll
```

Then re-enable Secure Boot in the UEFI settings. See the [linux-surface wiki](https://github.com/linux-surface/linux-surface/wiki/Secure-Boot) for details.

## Log File

The install script logs all output to `/tmp/surface-install.log` (in addition to printing to the terminal). Check this file if something goes wrong.

## References

- [linux-surface Wiki](https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup)
- [Hyprland Wiki](https://wiki.hypr.land/Configuring/)
- [Fedora Kickstart Documentation](https://docs.fedoraproject.org/en-US/fedora/f43/install-guide/advanced/Kickstart_Installations/)
- [sdegler/hyprland COPR](https://copr.fedorainfracloud.org/coprs/sdegler/hyprland/)
- [scottames/ghostty COPR](https://copr.fedorainfracloud.org/coprs/scottames/ghostty/)
- [alternateved/tofi COPR](https://copr.fedorainfracloud.org/coprs/alternateved/tofi/)
- [LazyVim](https://www.lazyvim.org/)
- [UWSM](https://github.com/Vladimir-csp/uwsm)
