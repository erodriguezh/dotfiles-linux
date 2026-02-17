# iso/surface-go3-iso.ks — Offline Fedora 43 kickstart for Surface Go 3
#
# Purpose-built for the custom ISO install path. All packages come from the
# embedded local repo; all configuration is done in %post. After a single
# reboot the Surface Go 3 has a fully-configured Hyprland desktop.
#
# Placeholders @@USERNAME@@ and @@PASSWORD_HASH@@ are substituted by
# iso/build-iso.sh at ISO build time. Do NOT edit them manually.
#
# This file is SEPARATE from kickstart/surface-go3.ks (the manual/network
# install path). They serve different workflows.

# ============================================================================
# Installation settings
# ============================================================================

# Text-mode install (works without GPU driver)
text

# Locale / keyboard / timezone (matches kickstart/surface-go3.ks)
lang en_US.UTF-8
keyboard --xlayouts='de'
timezone Europe/Vienna --utc

# Network — kept for optional post-install connectivity; Anaconda won't stall
# on an offline install even with this directive present.
network --bootproto=dhcp --device=link --activate

# ============================================================================
# Disk configuration — eMMC only, plain ext4, no encryption
# ============================================================================

# Ignore all disks except the eMMC
ignoredisk --only-use=mmcblk0

# Suppress MBR wipe prompt
zerombr

# Clear all existing partitions, use GPT (required for UEFI)
clearpart --all --initlabel --disklabel=gpt --drives=mmcblk0

# Auto-create EFI System Partition + /boot
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
# User account (build-time substitution)
# ============================================================================

user --name=@@USERNAME@@ --groups=wheel --password=@@PASSWORD_HASH@@ --iscrypted

# ============================================================================
# Embedded local repo (offline packages from ISO)
# ============================================================================
# mkksiso embeds the local-repo directory at the ISO root.
# Anaconda mounts the ISO at /run/install/isodir/.
# cost=10 ensures this repo is preferred over any network repos.

repo --name=surface-local --baseurl=file:///run/install/isodir/local-repo --cost=10

# ============================================================================
# Services — canonical systemd unit names, comma-separated, no spaces
# ============================================================================
# Mirrors lib/12-services.sh service list. tuned-ppd.service is enabled via
# systemctl in %post (kickstart services directive may not handle it correctly
# since tuned-ppd depends on tuned being fully configured first).
# Note: tuned-ppd is ALSO a package — included in %packages for
# powerprofilesctl support.

services --enabled=NetworkManager,iwd,bluetooth,tuned

# ============================================================================
# Package selection
# ============================================================================
# --excludeWeakdeps --excludedocs for size optimization.
# Packages sourced from lib/03-packages.sh + lib/02-kernel.sh.
# -kernel excludes stock kernel (replaced by kernel-surface).

%packages --excludeWeakdeps --excludedocs
@^minimal-environment

# --- Surface kernel (lib/02-kernel.sh) ---
kernel-surface
libwacom-surface
-kernel

# --- Hyprland ecosystem (lib/03-packages.sh — sdegler/hyprland COPR) ---
hyprland
hyprlock
hypridle
hyprpaper
hyprpolkitagent
hyprland-guiutils
waybar-git
cliphist
uwsm
xdg-desktop-portal-hyprland

# --- Terminal (scottames/ghostty COPR) ---
ghostty

# --- App launcher (alternateved/tofi COPR) ---
tofi

# --- XDG portal stack ---
xdg-desktop-portal
xdg-desktop-portal-gtk

# --- Bluetooth ---
bluez

# --- Power management ---
tuned
tuned-ppd

# --- Audio/video ---
wireplumber
pipewire
pipewire-pulseaudio
pipewire-alsa

# --- Notifications ---
mako

# --- Screenshots ---
grim
slurp

# --- Networking ---
NetworkManager
NetworkManager-wifi
iwd
iwlwifi-mvm-firmware

# --- Keybind tools ---
brightnessctl
playerctl

# --- System utilities ---
plymouth
polkit
wl-clipboard
curl
jq
git
tar
unzip
sudo

# --- Neovim + deps ---
neovim
tree-sitter-cli

# --- dnf5 plugins (for post-install COPR management) ---
dnf5-plugins

%end

# ============================================================================
# %post --nochroot — Copy assets from ISO to installed system
# ============================================================================
# Runs in the installer environment. Installed system is at /mnt/sysroot/.
# ISO filesystem is mounted at /run/install/isodir/.

%post --nochroot --log=/mnt/sysroot/var/log/ks-nochroot.log
#!/bin/bash
set -Eeuo pipefail

USERNAME="@@USERNAME@@"
HOME_DIR="/mnt/sysroot/home/${USERNAME}"

echo "=== %post --nochroot: Copying assets to installed system ==="

# -- Copy surface-linux repo from ISO to user home -------------------------
echo "Copying surface-linux repo..."
mkdir -p "${HOME_DIR}"
cp -a /run/install/isodir/surface-linux "${HOME_DIR}/surface-linux"

# -- Copy pre-downloaded binaries to ~/.local/bin/ -------------------------
# Must match lib/04-binaries.sh versions exactly for idempotency.
echo "Copying pre-downloaded binaries..."
mkdir -p "${HOME_DIR}/.local/bin"
cp -a /run/install/isodir/iso-assets/binaries/impala   "${HOME_DIR}/.local/bin/impala"
cp -a /run/install/isodir/iso-assets/binaries/bluetui   "${HOME_DIR}/.local/bin/bluetui"
cp -a /run/install/isodir/iso-assets/binaries/starship  "${HOME_DIR}/.local/bin/starship"
chmod +x "${HOME_DIR}/.local/bin/impala"
chmod +x "${HOME_DIR}/.local/bin/bluetui"
chmod +x "${HOME_DIR}/.local/bin/starship"

# -- Copy pre-downloaded fonts to ~/.local/share/fonts/JetBrainsMono/ ------
# Reproduces lib/05-fonts.sh directory structure including .nf-version file.
echo "Copying pre-downloaded fonts..."
mkdir -p "${HOME_DIR}/.local/share/fonts"
cp -a /run/install/isodir/iso-assets/fonts/JetBrainsMono \
    "${HOME_DIR}/.local/share/fonts/JetBrainsMono"

# -- Copy pre-cloned lazy.nvim --------------------------------------------
echo "Copying pre-cloned lazy.nvim..."
mkdir -p "${HOME_DIR}/.local/share/nvim/lazy"
cp -a /run/install/isodir/iso-assets/lazy-nvim \
    "${HOME_DIR}/.local/share/nvim/lazy/lazy.nvim"

# -- Set ownership of copied files before fc-cache -------------------------
# Ownership is fixed comprehensively in %post (chroot) after all home
# modifications. Here we only set ownership on the fonts directory so
# fc-cache runs as the right user context.
echo "Setting font directory ownership..."
chroot /mnt/sysroot chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.local/share/fonts" 2>/dev/null || true

# -- Rebuild font cache in chroot ------------------------------------------
echo "Rebuilding font cache..."
if chroot /mnt/sysroot command -v fc-cache &>/dev/null; then
    chroot /mnt/sysroot fc-cache -f || echo "WARN: fc-cache failed — continuing"
else
    echo "WARN: fc-cache not found in target system — skipping font cache rebuild"
fi

echo "=== %post --nochroot complete ==="
%end

# ============================================================================
# %post — Chroot configuration (runs as root inside installed system)
# ============================================================================
# All paths are relative to the installed system root.
# @@USERNAME@@ is baked in at build time — no runtime discovery.

%post --log=/var/log/ks-post.log
#!/bin/bash
set -Eeuo pipefail

USERNAME="@@USERNAME@@"
HOME="/home/${USERNAME}"
REPO_DIR="${HOME}/surface-linux"

echo "=== %post: Configuring installed system ==="

# --------------------------------------------------------------------------
# zram configuration (from lib/06-zram.sh:15-35)
# --------------------------------------------------------------------------
echo "Configuring zram swap..."

cat > /etc/systemd/zram-generator.conf <<'ZRAM_GEN'
# Surface Go 3 zram configuration
# zram size = total RAM (1:1 ratio with zstd compression)
[zram0]
zram-size = ram
compression-algorithm = zstd
ZRAM_GEN

cat > /etc/sysctl.d/99-zram.conf <<'ZRAM_SYSCTL'
# Tuned sysctl values for zram swap workload
# Higher swappiness is optimal with zram (compressed RAM is cheap)
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
ZRAM_SYSCTL

echo "zram configuration written"

# --------------------------------------------------------------------------
# Network — iwd backend for NetworkManager (from lib/07-network.sh:26-28)
# --------------------------------------------------------------------------
echo "Configuring NetworkManager iwd backend..."

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-backend.conf <<'NM_IWD'
[device]
wifi.backend=iwd
NM_IWD

echo "NetworkManager iwd backend config written"

# Restore SELinux contexts on NetworkManager config (parity with lib/07-network.sh)
if command -v selinuxenabled &>/dev/null && selinuxenabled 2>/dev/null; then
    echo "Restoring SELinux contexts on /etc/NetworkManager..."
    if command -v restorecon &>/dev/null; then
        restorecon -R /etc/NetworkManager || echo "WARN: restorecon failed — continuing"
    else
        echo "WARN: restorecon not found — skipping SELinux relabel"
    fi
else
    echo "SELinux disabled or not present — skipping restorecon"
fi

# --------------------------------------------------------------------------
# Getty auto-login override (from lib/08-desktop.sh:36-61)
# --------------------------------------------------------------------------
# @@USERNAME@@ is already substituted at build time, so the heredoc can
# use it directly. Single-quoted heredoc preserves literal $TERM.
echo "Configuring getty auto-login for ${USERNAME}..."

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<GETTY_EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USERNAME} --noclear %I \$TERM
GETTY_EOF

# Note: systemctl daemon-reload does NOT work in chroot. Not needed — next
# boot picks up the override automatically.
echo "Getty auto-login override written"

# --------------------------------------------------------------------------
# XDG portal config (from lib/08-desktop.sh:97-110)
# --------------------------------------------------------------------------
echo "Writing XDG portal configuration..."

mkdir -p "${HOME}/.config/xdg-desktop-portal"
cat > "${HOME}/.config/xdg-desktop-portal/portals.conf" <<'XDG_PORTAL'
[preferred]
default=hyprland
XDG_PORTAL

echo "XDG portal config written"

# --------------------------------------------------------------------------
# UWSM env files (from lib/08-desktop.sh:112-138)
# --------------------------------------------------------------------------
echo "Writing UWSM environment files..."

mkdir -p "${HOME}/.config/uwsm"

cat > "${HOME}/.config/uwsm/env" <<'UWSM_ENV'
export XCURSOR_SIZE=24
export GDK_SCALE=1
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export MOZ_ENABLE_WAYLAND=1
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1
UWSM_ENV

cat > "${HOME}/.config/uwsm/env-hyprland" <<'UWSM_HYPR'
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
UWSM_HYPR

echo "UWSM env files written"

# --------------------------------------------------------------------------
# Systemd user environment (from lib/08-desktop.sh:140-158)
# --------------------------------------------------------------------------
echo "Writing systemd user environment file..."

mkdir -p "${HOME}/.config/environment.d"
cat > "${HOME}/.config/environment.d/surface-linux.conf" <<'SYSTEMD_ENV'
XCURSOR_SIZE=24
GDK_SCALE=1
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
MOZ_ENABLE_WAYLAND=1
SDL_VIDEODRIVER=wayland
_JAVA_AWT_WM_NONREPARENTING=1
SYSTEMD_ENV

echo "systemd user environment file written"

# --------------------------------------------------------------------------
# Dotfiles — config directory symlinks (from lib/11-dotfiles.sh:13-24)
# --------------------------------------------------------------------------
echo "Creating config directory symlinks..."

mkdir -p "${HOME}/.config"

# Array of directories to symlink from repo config/ to ~/.config/
SYMLINK_DIRS="hypr waybar mako ghostty tofi nvim bashrc.d gtk-3.0 gtk-4.0 starship"

for dir in $SYMLINK_DIRS; do
    src="${REPO_DIR}/config/${dir}"
    dst="${HOME}/.config/${dir}"

    if [ ! -d "$src" ]; then
        echo "  WARN: config/${dir}/ not found in repo — skipping"
        continue
    fi

    # If destination is a real directory (not a symlink), back it up
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        backup="${dst}.bak"
        [ -e "$backup" ] && rm -rf "$backup"
        mv "$dst" "$backup"
    fi

    ln -snfT "$src" "$dst"
    echo "  Symlinked: ${dir}/ -> ${src}"
done

echo "Config directory symlinks created"

# --------------------------------------------------------------------------
# Dotfiles — helper scripts to ~/.local/bin/ (from lib/11-dotfiles.sh:54-81)
# --------------------------------------------------------------------------
echo "Deploying helper scripts..."

LOCAL_BIN="${HOME}/.local/bin"
SRC_BIN="${REPO_DIR}/config/local-bin"

mkdir -p "$LOCAL_BIN"

if [ -d "$SRC_BIN" ]; then
    for f in "$SRC_BIN"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        ln -snf "$f" "${LOCAL_BIN}/${name}"
        [ -x "$f" ] || chmod +x "$f"
    done
    echo "Helper scripts deployed"
else
    echo "No config/local-bin/ directory — skipping helper scripts"
fi

# --------------------------------------------------------------------------
# Dotfiles — wallpapers (from lib/11-dotfiles.sh:83-124)
# --------------------------------------------------------------------------
echo "Copying wallpapers..."

WALLPAPER_SRC="${REPO_DIR}/assets/wallpapers"
WALLPAPER_DST="${HOME}/.local/share/wallpapers/surface-linux"

if [ -d "$WALLPAPER_SRC" ]; then
    mkdir -p "$WALLPAPER_DST"

    # Copy first wallpaper as wallpaper.png (what hyprpaper.conf expects)
    first_wallpaper=""
    for f in "$WALLPAPER_SRC"/*; do
        [ -f "$f" ] || continue
        first_wallpaper="$f"
        break
    done

    if [ -n "$first_wallpaper" ]; then
        cp -f "$first_wallpaper" "${WALLPAPER_DST}/wallpaper.png"
    fi

    # Copy all wallpapers by original names
    for f in "$WALLPAPER_SRC"/*; do
        [ -f "$f" ] || continue
        cp -f "$f" "${WALLPAPER_DST}/$(basename "$f")"
    done
    echo "Wallpapers copied"
else
    echo "WARN: assets/wallpapers/ not found — skipping"
fi

# --------------------------------------------------------------------------
# Dotfiles — .Xresources (from lib/11-dotfiles.sh:126-147)
# --------------------------------------------------------------------------
echo "Writing .Xresources..."

printf '%s\n' "Xft.dpi: 144" > "${HOME}/.Xresources"
echo ".Xresources written (Xft.dpi: 144 for 1.5x scaling)"

# --------------------------------------------------------------------------
# Dotfiles — .bashrc sourcing loop (from lib/11-dotfiles.sh:149-172)
# --------------------------------------------------------------------------
echo "Configuring .bashrc..."

# Ensure .bashrc exists (Fedora Minimal creates it, but be safe)
touch "${HOME}/.bashrc"

# Guard against duplicate insertion (parity with lib/11-dotfiles.sh:149-172)
BASHRC_GUARD='# Source modular config from bashrc.d'
if ! grep -qF "$BASHRC_GUARD" "${HOME}/.bashrc" 2>/dev/null; then
    cat >> "${HOME}/.bashrc" <<'BASHRC_BLOCK'

# Source modular config from bashrc.d
if [[ -d "${HOME}/.config/bashrc.d" ]]; then
    for _bashrc_f in "${HOME}"/.config/bashrc.d/*.sh; do
        [[ -f "$_bashrc_f" ]] && source "$_bashrc_f"
    done
    unset _bashrc_f
fi
BASHRC_BLOCK
    echo ".bashrc sourcing loop appended"
else
    echo ".bashrc already sources bashrc.d/ — skipping"
fi

# --------------------------------------------------------------------------
# Dotfiles — .bash_profile UWSM auto-start (from lib/11-dotfiles.sh:174-196)
# --------------------------------------------------------------------------
echo "Configuring .bash_profile..."

# Ensure .bash_profile exists
touch "${HOME}/.bash_profile"

# Guard against duplicate insertion (parity with lib/11-dotfiles.sh:174-196)
PROFILE_GUARD='# Auto-start Hyprland via UWSM on TTY login'
if ! grep -qF "$PROFILE_GUARD" "${HOME}/.bash_profile" 2>/dev/null; then
    cat >> "${HOME}/.bash_profile" <<'UWSM_BLOCK'

# Auto-start Hyprland via UWSM on TTY login
if command -v uwsm &>/dev/null && uwsm check may-start; then
    exec uwsm start hyprland.desktop
fi
UWSM_BLOCK
    echo ".bash_profile UWSM auto-start appended"
else
    echo ".bash_profile already has UWSM snippet — skipping"
fi

# --------------------------------------------------------------------------
# Services — set default target (from lib/12-services.sh:29-38)
# --------------------------------------------------------------------------
echo "Setting default systemd target to graphical.target..."

systemctl set-default graphical.target
echo "Default target set to graphical.target"

# --------------------------------------------------------------------------
# Services — enable tuned-ppd.service (from lib/12-services.sh:13-18)
# --------------------------------------------------------------------------
# tuned-ppd.service extends tuned to expose the powerprofilesctl interface.
# Enabled here via systemctl (not in kickstart services directive) for
# reliable ordering — tuned must be set up first.
echo "Enabling tuned-ppd.service..."

systemctl enable tuned-ppd.service
echo "tuned-ppd.service enabled"

# --------------------------------------------------------------------------
# Services — set tuned profile to 'powersave' (from lib/12-services.sh:41-49)
# --------------------------------------------------------------------------
# Best-effort: tuned-adm may not function fully in chroot, but profile
# selection is stored as config and takes effect on first boot.
echo "Setting tuned profile to 'powersave'..."

if command -v tuned-adm &>/dev/null; then
    if tuned-adm profile powersave; then
        echo "Tuned profile set to 'powersave'"
    else
        echo "WARN: Failed to set tuned profile to 'powersave' (may work after reboot)"
    fi
elif [ -x /usr/sbin/tuned-adm ]; then
    if /usr/sbin/tuned-adm profile powersave; then
        echo "Tuned profile set to 'powersave'"
    else
        echo "WARN: Failed to set tuned profile to 'powersave' (may work after reboot)"
    fi
else
    echo "WARN: tuned-adm not found — tuned profile will need to be set manually after reboot"
fi

# --------------------------------------------------------------------------
# Plymouth — set spinner theme (from lib/08-desktop.sh:63-95)
# --------------------------------------------------------------------------
# Without -R: Anaconda handles initrd generation, so no rebuild needed here.
echo "Setting plymouth theme to spinner..."

if [ -x /usr/sbin/plymouth-set-default-theme ]; then
    /usr/sbin/plymouth-set-default-theme spinner || echo "WARN: Failed to set plymouth theme"
elif command -v plymouth-set-default-theme &>/dev/null; then
    plymouth-set-default-theme spinner || echo "WARN: Failed to set plymouth theme"
else
    echo "WARN: plymouth-set-default-theme not found — skipping"
fi
echo "Plymouth theme configured"

# --------------------------------------------------------------------------
# Repos — configure COPR repos + linux-surface for post-install updates
# (from lib/01-repos.sh:29-45)
# --------------------------------------------------------------------------
# These repos are needed so `dnf update` works once WiFi is connected.
# Best-effort: network may not be available during offline install.
# If these fail, user can re-run `./install.sh --only repos` post-install.
echo "Configuring repos for post-install updates (best-effort)..."

set +e
dnf5 copr enable -y sdegler/hyprland      || echo "WARN: failed to enable COPR sdegler/hyprland (no network?)"
dnf5 copr enable -y scottames/ghostty      || echo "WARN: failed to enable COPR scottames/ghostty (no network?)"
dnf5 copr enable -y alternateved/tofi      || echo "WARN: failed to enable COPR alternateved/tofi (no network?)"
dnf5 config-manager addrepo \
    --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo \
    --overwrite                             || echo "WARN: failed to add linux-surface repo (no network?)"
set -e

echo "Post-install repo configuration complete (check warnings above if offline)"

# --------------------------------------------------------------------------
# Fix ownership — ensure all $HOME content is owned by the target user
# --------------------------------------------------------------------------
echo "Fixing ownership of ${HOME}..."

chown -R "${USERNAME}:${USERNAME}" "${HOME}/"

echo "Ownership fixed"

echo "=== %post configuration complete ==="
%end

# Shutdown after install (change to 'reboot' once validated)
shutdown
