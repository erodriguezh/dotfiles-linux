# kickstart/surface-go3.ks — Fedora 43 Minimal Install for Surface Go 3
#
# Automated Anaconda installation targeting the eMMC (/dev/mmcblk0).
# Creates a user account (prompted interactively during install), installs
# a minimal system, and bootstraps the surface-linux repo for post-install.
#
# BEFORE USE: Edit REPO_URL below to point to your clone of this repository.
#   - HTTPS URL for public repos (no auth needed)
#   - Example: https://github.com/youruser/surface-linux.git
#
# Boot with: inst.ks=hd:LABEL=YOURUSB:/kickstart/surface-go3.ks
#        or: inst.ks=http://YOUR_IP:PORT/surface-go3.ks

# ============================================================================
# Installation settings
# ============================================================================

# Text-mode install (works without GPU driver)
text

# Locale / keyboard / timezone
lang en_US.UTF-8
keyboard --xlayouts='de'
timezone Europe/Vienna --utc

# Network — user connects WiFi via Anaconda GUI (Everything ISO needs network)
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
part / --fstype=ext4 --grow --ondisk=mmcblk0

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

bootloader --location=mbr --driveorder=mmcblk0

# ============================================================================
# Package selection — Minimal Install + sudo
# ============================================================================

%packages
@^minimal-environment
sudo
%end

# ============================================================================
# %pre — Interactive user creation (runs in installer environment)
# ============================================================================
# Prompts for username and password during install. The password is hashed
# with SHA-512 via openssl (available in the Anaconda environment).
# Outputs a kickstart snippet to /tmp/user-include for %include.

%pre
#!/bin/bash

echo ""
echo "============================================"
echo "  Surface Linux — User Account Setup"
echo "============================================"
echo ""

# --- Username ----------------------------------------------------------------
while true; do
    printf "Enter username: "
    read -r USERNAME
    if [[ -z "$USERNAME" ]]; then
        echo "Username cannot be empty. Try again."
        continue
    fi
    if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Invalid username. Use lowercase letters, digits, underscores, hyphens."
        continue
    fi
    break
done

# --- Password ----------------------------------------------------------------
while true; do
    printf "Enter password: "
    read -rs PASSWORD
    echo ""

    if [[ -z "$PASSWORD" ]]; then
        echo "Password cannot be empty. Try again."
        continue
    fi

    printf "Confirm password: "
    read -rs PASSWORD_CONFIRM
    echo ""

    if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
        echo "Passwords do not match. Try again."
        continue
    fi
    break
done

# Hash password with SHA-512
HASH=$(openssl passwd -6 "$PASSWORD")

# Write kickstart user directive for %include
echo "user --name=${USERNAME} --groups=wheel --password=${HASH} --iscrypted" \
    > /tmp/user-include

# Persist username for %post to read
echo "$USERNAME" > /tmp/ks-username

echo ""
echo "User '${USERNAME}' will be created in the wheel group (sudo access)."
echo ""
%end

# Include the dynamically generated user directive
%include /tmp/user-include

# ============================================================================
# %post --nochroot — Clone repo and set up bootstrap
# ============================================================================
# Runs after package installation. Uses --nochroot to access both /tmp
# (installer environment) and /mnt/sysroot (installed system).
# Installs git inside the chroot, clones the repo, and sets ownership.

%post --nochroot --log=/mnt/sysroot/var/log/kickstart-post.log
#!/bin/bash

# ---- EDIT THIS URL BEFORE USE ----------------------------------------------
# Set this to your clone of the surface-linux repository (HTTPS, public).
REPO_URL="https://github.com/CHANGEME/surface-linux.git"
# -----------------------------------------------------------------------------

# Read the username created in %pre
USERNAME=$(cat /tmp/ks-username)

if [[ -z "$USERNAME" ]]; then
    echo "ERROR: Could not read username from /tmp/ks-username"
    exit 1
fi

echo "Bootstrapping surface-linux for user: ${USERNAME}"

# Install git inside the target system
chroot /mnt/sysroot /usr/bin/dnf5 install -y git

# Clone the repository into the user's home directory
chroot /mnt/sysroot /usr/bin/git clone "$REPO_URL" \
    "/home/${USERNAME}/surface-linux"

# Set correct ownership (user:user, not root)
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
