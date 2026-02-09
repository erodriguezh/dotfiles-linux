## Description

Create lib scripts for the `zram`, `network`, `desktop`, and `services` install stages. These handle system-level configuration that runs after packages are installed and downloads are complete.

**Size:** M
<!-- Updated by plan-sync: fn-1...1 added fonts stage at position 5, shifting subsequent lib file numbers by +1 -->
**Files:** `lib/06-zram.sh`, `lib/07-network.sh`, `lib/08-desktop.sh`, `lib/12-services.sh`

## Approach

### lib/06-zram.sh (`run_zram`)
- Write `/etc/systemd/zram-generator.conf` with `zram-size = ram` (4GB → 4GB zram) and `compression-algorithm = zstd` via `sudo tee`
- Write `/etc/sysctl.d/99-zram.conf` with tuned values via `sudo tee`
- Idempotent: overwrite files (same content on re-run)
- Takes effect after reboot only

### lib/07-network.sh (`run_network`)
- Create `/etc/NetworkManager/conf.d/wifi-backend.conf` with iwd backend via `sudo tee`
- Do NOT enable `iwd.service` manually — NetworkManager manages it
- Run `sudo restorecon -R /etc/NetworkManager` after writing conf.d files (SELinux)
- Do NOT restart NetworkManager during install (would drop WiFi). Config takes effect after reboot.
- Print info message: "iwd backend configured. Takes effect after reboot."

### lib/08-desktop.sh (`run_desktop`)
- Getty auto-login override: write systemd drop-in for `getty@tty1.service` via `sudo tee`
  - Blank `ExecStart=` line REQUIRED before new one (systemd requires clearing inherited ExecStart first)
  - Use single-quoted heredoc (`<<'EOF'`) so shell does NOT expand `$TERM` — the literal `$TERM` must appear in the file for systemd to resolve at runtime. Substitute the autologin username via a separate `printf` or `sed` replacement (e.g., `sed "s/@@USER@@/$TARGET_USER/"` on the heredoc output), since single-quoted heredocs don't expand variables.
  - Run `sudo systemctl daemon-reload` after writing
- Plymouth theme: check current theme, only rebuild initrd if changed (saves ~30s)
- XDG portal config: write `~/.config/xdg-desktop-portal/portals.conf` with `default=hyprland`
  - Portal config takes effect on next login (xdg-desktop-portal reads it at startup)
- UWSM env files: create `~/.config/uwsm/env` for theming vars
- Create `~/.config/uwsm/env-hyprland` for Hyprland-specific vars
- Create `~/.config/environment.d/surface-linux.conf` for systemd user env
- Note: all env/portal files are written for first boot — they take effect after reboot when UWSM starts the Hyprland session

### lib/12-services.sh (`run_services`)
<!-- Updated by plan-sync: fn-1...2 excluded iptsd package (touchscreen disabled per epic), so iptsd.service must not be enabled -->
- Enable services via `sudo systemctl enable`: NetworkManager, bluetooth, tuned
- Enable tuned-ppd for powerprofilesctl CLI compatibility
- Verify required packages are installed before enabling (check `systemctl list-unit-files | grep <unit>` and warn if missing, pointing to packages stage)
- `systemctl enable` is already idempotent

## Key context

- All `sudo` used explicitly — script runs as user
- Getty override uses drop-in at `/etc/systemd/system/getty@tty1.service.d/override.conf`
- `restorecon` critical for SELinux on NM conf.d files
- UWSM env vars go in `~/.config/uwsm/env` and `~/.config/uwsm/env-hyprland`, NOT in `hyprland.conf`
- Network config does NOT restart NetworkManager — takes effect after reboot to avoid WiFi drop during install
- Fedora 43 uses `tuned + tuned-ppd` (packages installed by Task 2). Both `tuned.service` and `tuned-ppd.service` must be enabled for `powerprofilesctl` CLI to work.
- `bluez` package (installed by Task 2) provides `bluetooth.service`

## Acceptance

- [ ] zram configured to `ram` size with zstd compression
- [ ] sysctl tuned for zram workload (swappiness=180)
- [ ] NetworkManager iwd config written, SELinux contexts fixed
- [ ] NetworkManager NOT restarted during install (config takes effect after reboot)
- [ ] iwd.service NOT manually enabled
- [ ] Getty auto-login override correct (blank ExecStart, single-quoted heredoc preserving literal `$TERM`, daemon-reload)
- [ ] Plymouth theme set only if changed
- [ ] XDG portal config points to hyprland
- [ ] UWSM env files created with theming variables
<!-- Updated by plan-sync: fn-1...2 excluded iptsd package (touchscreen disabled), removed iptsd from service list -->
- [ ] All services enabled: NetworkManager, bluetooth, tuned, tuned-ppd
- [ ] Service enablement verifies units exist (graceful warning if missing)
- [ ] All system writes use `sudo`
- [ ] Idempotent: re-running produces no errors

## Done summary

_To be filled after implementation._

## Evidence

_To be filled after implementation._
