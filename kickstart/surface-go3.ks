# kickstart/surface-go3.ks — Fedora 43 Minimal Install for Surface Go 3
#
# Automated Anaconda installation targeting the eMMC (/dev/mmcblk0).
# Creates a user account with pre-hashed credentials, installs a minimal
# system, and bootstraps the surface-linux repo for post-install.
#
# See also: iso/surface-go3-iso.ks for the custom ISO kickstart (offline
# install path with all packages and configuration embedded).
#
# BEFORE USE:
#   1. Set USERNAME and PASSWORD_HASH below (see "User account" section)
#   2. Edit REPO_URL in %post to point to your clone of this repository
#
# Generate a password hash:
#   python3 -c "import crypt; print(crypt.crypt('mypass', crypt.mksalt(crypt.METHOD_SHA512)))"
#   # or: openssl passwd -6
#
# Boot methods (WiFi-only devices must use A or B):
#   A) OEMDRV partition on Ventoy USB (recommended — single USB, no boot params)
#      Anaconda auto-detects a partition labeled OEMDRV and loads ks.cfg from it.
#   B) inst.ks=hd:LABEL=KICKSTART:/surface-go3.ks  (second USB drive)
#   C) inst.ks=https://raw.githubusercontent.com/erodriguezh/dotfiles-linux/main/kickstart/surface-go3.ks  (wired only)

# ============================================================================
# Installation settings
# ============================================================================

# Text-mode install (works without GPU driver)
text

# Locale / keyboard / timezone
lang en_US.UTF-8
keyboard --xlayouts='de'
timezone Europe/Vienna --utc

# Network — user connects WiFi via Anaconda text UI (Everything ISO needs network)
network --bootproto=dhcp --activate

# ============================================================================
# Disk configuration — eMMC only, plain ext4, no encryption
# ============================================================================

# Ignore all disks except the eMMC
ignoredisk --only-use=mmcblk0

# Suppress MBR wipe prompt
zerombr

# Clear all existing partitions, use GPT (required for UEFI)
clearpart --all --initlabel --disklabel=gpt --drives=mmcblk0

# Auto-create EFI System Partition + /boot (Fedora 43 default: 2 GiB /boot)
reqpart --add-boot

# Root partition — ext4, uses remaining space after EFI + /boot
# No swap partition (zram handles swap in-memory)
part / --fstype=ext4 --size=10240 --grow --ondisk=mmcblk0

# ============================================================================
# Security
# ============================================================================

# Lock root password — no root login; user has sudo via wheel group
rootpw --lock

# SELinux enforcing (Fedora default)
selinux --enforcing

# Firewall with default services
firewall --enabled --service=mdns

# ============================================================================
# Bootloader
# ============================================================================

bootloader --boot-drive=mmcblk0

# ============================================================================
# Package selection — Minimal Install + sudo
# ============================================================================

%packages
@^minimal-environment
sudo
git
%end

# ============================================================================
# User account — EDIT BEFORE USE
# ============================================================================
# Pre-hashed credentials. No interactive %pre — works with every delivery
# method (OEMDRV, mkksiso, HTTP, Ventoy).
#
# Generate a hash: openssl passwd -6
#   or: python3 -c "import crypt; print(crypt.crypt('pw', crypt.mksalt(crypt.METHOD_SHA512)))"

user --name=CHANGEME_USERNAME --groups=wheel --password=CHANGEME_HASH --iscrypted

# ============================================================================
# %post --nochroot — Clone repo and set up bootstrap
# ============================================================================
# Runs after package installation. Uses --nochroot to access both /tmp
# (installer environment) and /mnt/sysroot (installed system).
# Clones the repo into the user's home and sets ownership.

%post --nochroot --log=/mnt/sysroot/var/log/kickstart-post.log
#!/bin/bash
set -Eeuo pipefail

# ---- EDIT THESE BEFORE USE --------------------------------------------------
REPO_URL="https://github.com/erodriguezh/dotfiles-linux.git"
USERNAME="CHANGEME_USERNAME"
# -----------------------------------------------------------------------------

# Guard against forgetting to edit placeholders
if [[ "$REPO_URL" == *"CHANGEME"* || "$USERNAME" == *"CHANGEME"* ]]; then
    echo "ERROR: You must edit REPO_URL and USERNAME in kickstart/surface-go3.ks before installing."
    exit 1
fi

echo "Bootstrapping surface-linux for user: ${USERNAME}"

# Ensure home directory exists with correct ownership
chroot /mnt/sysroot /usr/bin/mkdir -p "/home/${USERNAME}"
chroot /mnt/sysroot /usr/bin/chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

# Clone the repository into the user's home directory
# (git is installed via %packages, available in chroot)
chroot /mnt/sysroot /usr/bin/git clone "$REPO_URL" \
    "/home/${USERNAME}/surface-linux"

# Set correct ownership on the cloned repo (user:user, not root)
chroot /mnt/sysroot /usr/bin/chown -R "${USERNAME}:${USERNAME}" \
    "/home/${USERNAME}/surface-linux"

echo ""
echo "============================================"
echo "  Bootstrap complete!"
echo "============================================"
echo ""
echo "After reboot:"
echo "  1. Log in as '${USERNAME}'"
echo "  2. cd ~/surface-linux"
echo "  3. ./install.sh"
echo "  4. sudo reboot"
echo ""
%end

# Reboot after installation
reboot
