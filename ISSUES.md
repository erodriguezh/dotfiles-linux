# Install Issues Log

Issues encountered during the first real install on Surface Go 3 hardware. All have been fixed. This document serves as the anchor for hardening the install script and preventing regressions.

## Issue 1: `starship` not in Fedora repos

**Stage:** packages
**Error:** `No match for argument: starship` — dnf5 aborts the entire transaction
**Root cause:** starship is not packaged in Fedora repos or any configured COPRs. The plan assumed it was.
**Fix:** Moved starship install to the `binaries` stage as a GitHub release download (tarball extraction to `~/.local/bin/`).
**Commit:** `1e44c74`

## Issue 2: `tar` not in Minimal Install

**Stage:** binaries
**Error:** `tar: command not found` — starship tarball extraction fails, curl reports `Failure writing output to destination`
**Root cause:** Fedora Minimal Install (`@^minimal-environment`) does not include `tar`. The binaries stage pipes curl output to tar for starship extraction.
**Fix:** Added `tar` to the package list in `lib/03-packages.sh`.
**Commit:** `28b9304`

## Issue 3: Missing `lib/05-fonts.sh`

**Stage:** fonts
**Error:** `Stage function 'run_fonts' not found. Is lib file for 'fonts' missing?`
**Root cause:** The `fonts` stage was registered in the `STAGES` array in `lib/00-common.sh` but the corresponding `lib/05-fonts.sh` file was never created.
**Fix:** Created `lib/05-fonts.sh` — downloads JetBrains Mono Nerd Font from GitHub releases with version pinning and idempotency check.
**Commit:** `da50b10`

## Issue 4: Hyprland `gestures` config removed in 0.51+

**Stage:** N/A (runtime config error)
**Error:** `config option <gestures:workspace_swipe> does not exist`
**Root cause:** Hyprland 0.51 removed the `gestures {}` config block. Workspace swipe is now configured with the new `gesture = fingers, direction, action` syntax.
**Fix:** Replaced `gestures { workspace_swipe = true; workspace_swipe_fingers = 3 }` with `gesture = 3, l, workspace, m-1` and `gesture = 3, r, workspace, m+1`.
**Commit:** `ac36e65`

## Issue 5: Hyprland windowrule syntax changed in 0.53

**Stage:** N/A (runtime config error)
**Error:** `invalid field float: missing a value` (and 47+ similar errors)
**Root cause:** Hyprland 0.53 overhauled windowrule syntax. Old format `windowrule = float, class:^(...)$` is no longer valid.
**Fix:** Rewrote all window rules to new syntax: `windowrule = match:class ^(...)$, float on`. Also removed `idleinhibit fullscreen` rule (removed in 0.53, handled by hypridle).
**Commit:** `ac36e65`

## Issue 6: `stayfocused` and `dimaround` rules removed in 0.53

**Stage:** N/A (runtime config error)
**Error:** `invalid field type stayfocused` / `invalid field type dimaround`
**Root cause:** Both rule types were removed from Hyprland 0.53.
**Fix:** Removed the `stayfocused` and `dimaround` rules for the polkit agent (cosmetic, not functional).
**Commit:** `bc76d5c`

## Issue 7: Ghostty theme file in wrong directory

**Stage:** N/A (runtime config error)
**Error:** `theme" not found, tried path "/home/erodr/.config/ghostty/themes/theme"` and `/usr/share/ghostty/themes/theme`
**Root cause:** Theme engine generated the file to `config/ghostty/theme` but Ghostty resolves theme names by looking in `~/.config/ghostty/themes/<name>` (note the `themes/` subdirectory).
**Fix:** Changed theme output path from `config/ghostty/theme` to `config/ghostty/themes/theme` in both `lib/09-theme.sh` and `.gitignore`.
**Commit:** `ff78ed0`

## Issue 8: Invalid monitor scale 1.5x

**Stage:** N/A (runtime config warning)
**Error:** `Invalid scale passed to monitor eDP-1: 1.50, using suggested scale: 1.60`
**Root cause:** Hyprland 0.53 rejects 1.5x as an invalid fractional scale for 1920x1280. It requires 1.6x for pixel-perfect rendering on this resolution.
**Fix:** Changed `monitor = eDP-1, 1920x1280, auto, 1.5` to `1.6`.
**Commit:** `af60667`

## Issue 9: UWSM auto-start fails — wrong systemd target

**Stage:** services (missing configuration)
**Error:** `System has not reached graphical.target` — `uwsm check may-start` returns false, so the `.bash_profile` auto-start snippet never fires
**Root cause:** Fedora Minimal Install defaults to `multi-user.target`. UWSM requires `graphical.target` to be the default for `uwsm check may-start` to succeed.
**Fix:** Added `systemctl set-default graphical.target` to the `services` stage.
**Commit:** `09d1e36`

## Pre-install Issues (Kickstart / Boot)

### Ventoy + Kickstart incompatibility

**Error:** `Can't get kickstart from /dev/ventoy:/kickstart/surface-go3.ks`
**Root cause:** Ventoy creates a virtual `/dev/ventoy` block device for ISO passthrough. Anaconda's BusyBox-based initrd can't open it — `LABEL=Ventoy` resolves to this virtual device rather than the actual data partition.
**Workaround:** Used `mkksiso` to embed the kickstart into the ISO itself, then copied the custom ISO to Ventoy. Required `--platform linux/amd64` on Apple Silicon and `--skip-mkefiboot` inside Docker (no loop device access).
**Resolution:** Use OEMDRV partition on Ventoy USB. Anaconda has hardcoded logic to scan all attached block devices for a volume labeled `OEMDRV`. If found, it loads `ks.cfg` from the root — no `inst.ks=` boot parameter needed.

```bash
# Install Ventoy with reserved space (16 MB is more than enough)
sudo sh Ventoy2Disk.sh -i -r 16 /dev/sdX

# Create OEMDRV partition in the reserved space
sudo mkfs.ext4 -L 'OEMDRV' /dev/sdXN

# Copy kickstart file (MUST be named ks.cfg)
sudo mount /dev/sdXN /mnt
sudo cp surface-go3.ks /mnt/ks.cfg
sudo umount /mnt
```

**Why it works:** Bypasses Ventoy's `/dev/ventoy` device entirely. Anaconda natively scans for `OEMDRV` label. No boot parameter editing needed. Works with WiFi-only devices. Multiple independent repos confirm it works ([cuintle/fedora-minimal-installation](https://github.com/cuintle/fedora-minimal-installation), [foundata/kickstart-templates](https://github.com/foundata/kickstart-templates), [RHEL 7 Installation Guide 26.2.5](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/installation_guide/sect-kickstart-howto)).
**Caveat:** Anaconda may `dd` the OEMDRV partition during install, destroying it. Recreate after install if reuse is needed. The kickstart **must** protect the USB drive with `ignoredisk --only-use=mmcblk0` to prevent `clearpart --all` from wiping it.

### Kickstart %pre TTY failure with embedded ISO

**Error:** `Unable to open input kickstart file: [Errno 2] No such file or directory: '/tmp/user-include'`
**Root cause:** The interactive `%pre` script (username/password prompt) can't acquire a TTY when the kickstart is baked into the ISO via mkksiso. The `read` commands fail silently, `/tmp/user-include` is never created.
**Resolution:** Manual Anaconda install. The kickstart's interactive `%pre` approach needs rethinking for embedded ISO delivery — consider hardcoding a default username or using a non-interactive approach.

### Missing WiFi firmware after Minimal Install

**Error:** No wifi device in `nmcli device status`
**Root cause:** Fedora Minimal Install does not include `linux-firmware`, which provides the Marvell 88W8897 WiFi firmware for Surface Go 3.
**Resolution:** Connected via USB tethering, ran `sudo dnf install linux-firmware`, rebooted. Consider adding `linux-firmware` to the kickstart `%packages` section.

## Issue 10: Missing iwlwifi firmware — no WiFi adapter

**Stage:** packages
**Error:** `ip link` only shows `lo`. `dmesg | grep iwlwifi`: `Direct firmware load for iwlwifi-cc-a0-77.ucode failed with error -2` / `no suitable firmware found!`
**Root cause:** Fedora splits iwlwifi firmware into a separate subpackage (`iwlwifi-mvm-firmware`). The base `linux-firmware` package does not include it. Surface kernel 6.18.8 requires `iwlwifi-cc-a0-77.ucode` for the Intel Wi-Fi 6 AX200.
**Fix:** Replaced `linux-firmware` with `iwlwifi-mvm-firmware` in `lib/03-packages.sh`.
**Commit:** `d770f3a`

## Issue 11: iwd.service not enabled — impala reports "No adapter found"

**Stage:** services
**Error:** `impala` → `Can not access the iwd service: No adapter found`
**Root cause:** `lib/12-services.sh` did not enable `iwd.service`, assuming NetworkManager would auto-start it. NM does not — iwd must be explicitly enabled.
**Fix:** Added `iwd.service` to the enabled services list in `lib/12-services.sh`.
**Commit:** `7927cb4`

## Issue 12: Waybar on-click TUI apps fail silently

**Stage:** N/A (runtime)
**Error:** Clicking WiFi/Bluetooth icons in Waybar does nothing — no terminal appears.
**Root cause:** `on-click` in Waybar executes commands directly. TUI apps (impala, bluetui) need a terminal emulator to render. Running them without one fails silently.
**Fix:** Wrapped on-click commands in `ghostty -e` (e.g., `"on-click": "ghostty -e nmtui"`).
**Commit:** `7927cb4`

## Issue 13: impala incompatible with NetworkManager iwd backend

**Stage:** N/A (runtime)
**Error:** Selecting a WiFi network in impala and entering the password → `operation aborted`
**Root cause:** impala talks to iwd's D-Bus API directly. When iwd runs as a NetworkManager backend (`wifi.backend=iwd`), NM controls connections through iwd and iwd rejects direct connection attempts from other clients.
**Fix:** Replaced impala with `nmtui` (NetworkManager's built-in TUI) for the Waybar network on-click action.
**Commit:** `41f4c41`
