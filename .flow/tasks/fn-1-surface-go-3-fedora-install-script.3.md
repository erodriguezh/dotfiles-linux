## Description

Create the Kickstart file for automated Fedora 43 Minimal Install on Surface Go 3 eMMC, plus README.md with full USB preparation guide.

**Size:** M
**Files:** `kickstart/surface-go3.ks`, `README.md`

## Approach

### kickstart/surface-go3.ks
- Target eMMC: `ignoredisk --only-use=mmcblk0`
- Use `zerombr` to suppress MBR wipe prompt
- Partitioning: `clearpart --all --initlabel --disklabel=gpt --drives=mmcblk0`
- `reqpart --add-boot` for auto EFI System Partition + /boot (Fedora 43 default /boot is 2 GiB). This creates separate /boot/efi and /boot partitions automatically.
- Root partition: `part / --fstype=ext4 --grow --ondisk=mmcblk0` (remaining space after EFI + /boot)
- No swap partition (zram handles it), no LUKS encryption
- `rootpw --lock` (no root login)
- `%pre` script: Interactive username prompt via `read`, password via `read -s` (hidden input)
- Hash password with SHA-512 in `%pre`: `openssl passwd -6 "$PASSWORD"` (openssl available in Anaconda environment)
- Write to `/tmp/user-include`: `user --name=$USERNAME --groups=wheel --password=$HASH --iscrypted`
- Also persist username to `/tmp/ks-username` for `%post` to read
- `%include /tmp/user-include` in main kickstart body
- User MUST be in `wheel` group for sudo (critical: rootpw is locked, install.sh needs sudo)
- `@^minimal-environment` package group + `sudo` package explicitly
- `%post --nochroot`: Read `/tmp/ks-username`, install git in chroot, clone repo to `/mnt/sysroot/home/$USERNAME/surface-linux`, `chroot /mnt/sysroot chown -R $USERNAME:$USERNAME /home/$USERNAME/surface-linux`, print instructions. Using `--nochroot` ensures access to both `/tmp` (installer env) and `/mnt/sysroot` (installed system).
- Boot parameter: `inst.ks=hd:LABEL=YOURFS:/ks/surface-go3.ks` or `inst.ks=http://...`
- Avoid deprecated kickstart commands: no `authconfig`, no `autostep`, no `device`

### README.md
- Project overview and hardware target
- USB preparation: download Everything ISO, copy kickstart, boot parameters
- Two methods: kickstart on USB partition, or HTTP serve
- Post-install: login as user (has sudo), run `./install.sh`, reboot
- Quick command reference (`--list`, `--only`, `--skip`)
- Mention that install.sh must be run as user (NOT root)
- Link to Fedora Kickstart docs and linux-surface wiki

## Key context

- Fedora 43 Anaconda uses DNF5 backend and requires GPT for UEFI
- Default `/boot` raised to 2 GiB in Fedora 43 — `reqpart --add-boot` handles this
- eMMC partitions use `mmcblk0p1` naming (with `p` separator)
- `%pre` runs in installer environment (limited tools). Use bash `read` for prompts
- **CRITICAL**: User must be in `wheel` group with sudo. Without this, install.sh cannot elevate privileges (rootpw is locked).
- `REPO_URL` is a placeholder the user must edit before writing USB
- Do NOT use `autopart` with manual `part` commands — mutually exclusive

## Acceptance

- [ ] Kickstart targets `mmcblk0` eMMC with GPT partitioning
- [ ] EFI + /boot + root partitions created via `reqpart --add-boot` + `part /` (no swap), plain ext4
- [ ] `rootpw --lock` used (no root login)
- [ ] User created with `--groups wheel` for sudo access
- [ ] `sudo` package explicitly included in %packages
- [ ] `%pre` prompts for username and password (hidden input via `read -s`)
- [ ] Password hashed with SHA-512 via `openssl passwd -6` (not plaintext)
- [ ] User created with `--iscrypted` flag for hashed password
- [ ] Username persisted from `%pre` to `%post` via `/tmp/ks-username`
- [ ] `%post --nochroot` reads username, clones repo to correct user home, sets ownership via chroot
- [ ] `REPO_URL` placeholder clearly documented
- [ ] Minimal Install package group selected
- [ ] README covers USB preparation with both methods
- [ ] README includes boot parameter examples
- [ ] README mentions install.sh runs as user (not root)
- [ ] README includes Secure Boot guidance (disable SB or enroll linux-surface keys via `surface-secureboot`)
- [ ] No deprecated kickstart commands used

## Done summary

_To be filled after implementation._

## Evidence

_To be filled after implementation._
