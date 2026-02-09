# Surface Linux

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

### Step 2: Write the ISO to USB

Use `dd`, Fedora Media Writer, or Rufus (Windows):

```bash
# Linux / macOS — replace /dev/sdX with your USB device
sudo dd if=Fedora-Everything-netinst-x86_64-43-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### Step 3: Edit the Kickstart file

Open `kickstart/surface-go3.ks` and customize these values:

1. **REPO_URL** (required) -- set to your clone of this repository:
   ```
   REPO_URL="https://github.com/youruser/surface-linux.git"
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

### Step 4: Make the Kickstart available

Choose one of two methods:

#### Method A: Kickstart on USB via Ventoy

Use [Ventoy](https://www.ventoy.net/) to create a multiboot USB. Ventoy preserves a data partition where you can place the kickstart file alongside ISO images.

1. Install Ventoy on your USB drive (this creates a `Ventoy` data partition).
2. Copy the Fedora Everything ISO to the Ventoy partition.
3. Create a `kickstart/` folder on the Ventoy partition and copy the kickstart file:
   ```bash
   # Mount the Ventoy data partition (it is typically labeled "Ventoy")
   mkdir -p /mnt/usb
   mount /dev/disk/by-label/Ventoy /mnt/usb
   mkdir -p /mnt/usb/kickstart
   cp kickstart/surface-go3.ks /mnt/usb/kickstart/
   umount /mnt/usb
   ```
4. Boot from USB, select the Fedora ISO in Ventoy, then edit the boot entry to add:
   ```
   inst.ks=hd:LABEL=Ventoy:/kickstart/surface-go3.ks
   ```

#### Method B: Serve via HTTP (recommended)

Serve the kickstart file from another machine on the same network:

```bash
# On the serving machine, from the repo root
cd kickstart
python3 -m http.server 8080
```

Boot parameter:
```
inst.ks=http://192.168.1.100:8080/surface-go3.ks
```

Replace `192.168.1.100` with the IP of the serving machine.

### Step 5: Boot and install

1. Insert the USB into the Surface Go 3.
2. Power on while holding **Volume Down** to boot from USB.
3. At the GRUB boot menu, press **`e`** to edit the boot entry.
4. Append the `inst.ks=...` parameter to the `linuxefi` line (before any `quiet` option).
5. Press **Ctrl+X** to boot.
6. Anaconda will start in text mode:
   - **Connect to WiFi** when prompted (the Everything ISO needs network access).
   - You will be prompted for a **username** and **password** for your user account.
   - Installation proceeds automatically: partitions the eMMC, installs Minimal Install, creates your user (with sudo via wheel group), clones this repo.
7. The system reboots automatically when done.

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

This setup assumes Secure Boot is **disabled** in the UEFI firmware. If you prefer to keep Secure Boot enabled, you can enroll the linux-surface signing keys after installation:

```bash
sudo dnf install surface-secureboot
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
