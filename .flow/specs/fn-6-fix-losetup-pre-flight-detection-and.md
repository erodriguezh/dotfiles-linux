# Fix losetup pre-flight detection and EFI boot label in ISO builder

## Overview

The ISO builder's losetup pre-flight check (PR #4, commit `2788642`) is too weak. It runs `losetup --find` (query-only: prints next available `/dev/loopN`) but mkefiboot internally runs `losetup --find --show <file>` (actual attachment). These test fundamentally different capabilities — the query can succeed in environments where attachment fails (loop device nodes exist but are non-functional).

Additionally, when `--skip-mkefiboot` activates and `-V "SurfaceLinux-43"` changes the ISO volume label, the efiboot.img's internal grub.cfg still references the original Fedora label. On UEFI USB boot, GRUB searches for a volume with the old label, fails to find it, and boot breaks. The current README incorrectly claims this path is safe.

## Scope

- Strengthen the losetup pre-flight to test actual loop device attachment, with defense-in-depth retry on mkefiboot failure (tight substring match, max 1 retry, partial ISO cleanup before retry, both attempts' stderr on failure)
- Add `mtools` to the Containerfile for loop-free FAT image manipulation
- When `--skip-mkefiboot` is active, detect appended EFI partition via `xorriso -report_system_area plain` with explicit decision table (4 cases); use `python3 -c` with `re.sub` + `re.escape()` for label replacement (python3 guaranteed via lorax)
- Fix duplicate `inst.ks` entries; verify EFI config via efiboot.img mtools extraction (the actual config UEFI firmware reads)
- Re-implant ISO media checksum (`implantisomd5`) and regenerate sha256 after any post-mkksiso ISO rewrite
- Correct iso/README.md troubleshooting section

## Quick commands

```bash
# Build ISO in container (the fix target)
sudo podman build -t surface-iso-builder -f iso/Containerfile iso/
sudo podman run --rm -v "$PWD:/build:Z" surface-iso-builder /build/iso/build-iso.sh --validate-only

# ShellCheck the script
shellcheck iso/build-iso.sh

# Verify final ISO EFI boot config (probe both known paths)
osirrox -indev output.iso -extract /images/efiboot.img /tmp/efiboot-check.img
mcopy -n -i /tmp/efiboot-check.img ::/EFI/BOOT/grub.cfg /tmp/efi-grub-check.cfg 2>/dev/null \
  || mcopy -n -i /tmp/efiboot-check.img ::/EFI/fedora/grub.cfg /tmp/efi-grub-check.cfg
cat /tmp/efi-grub-check.cfg

# Verify ISO boot structure and appended partitions
xorriso -indev output.iso -report_el_torito as_mkisofs
xorriso -indev output.iso -report_system_area plain
```

## Acceptance

- [ ] `losetup --find --show <tempfile>` used as the pre-flight probe (actual attachment test)
- [ ] Probe cleans up temp file and detaches loop device via trap on all exit paths
- [ ] Defense-in-depth: mkksiso mkefiboot/losetup failure (tight substring match) triggers max-once retry; partial ISO removed before retry; both stderr logs preserved; non-matching errors fail immediately
- [ ] `mtools` added to `iso/Containerfile`
- [ ] grub.cfg inside efiboot.img discovered by direct `mcopy` existence probes; build hard-fails if not found
- [ ] Label extracted via regex supporting `--label`/`-l`, quoted/unquoted; hard-fails if no label or multiple distinct labels
- [ ] Label replacement uses `python3 -c` with `re.sub` + `re.escape()`; post-replacement verification confirms old label gone, new present
- [ ] Appended EFI partition: xorriso non-zero → hard-fail; exactly one `Partition N ... type 0xEF` → replace at N; no match → `-update` only; >1 indices → hard-fail
- [ ] No duplicate `inst.ks` — BIOS via ISO filesystem; EFI via efiboot.img mtools extraction
- [ ] `implantisomd5` re-run after ISO rewrite; sha256 regenerated
- [ ] `iso/README.md` corrects "safe" claim; CI unaffected
- [ ] `shellcheck iso/build-iso.sh` passes

## References

- PR #4 (commit `2788642`): original losetup skip fix
- lorax issue #1046: volume label mismatch breaks UEFI USB boot
- Arch Linux archiso MR !72: migration from loop-mount to mtools
- linuxkit/linuxkit `make-efi`: production mtools-based EFI image building
- `iso/build-iso.sh:860-878`: current losetup check + mkksiso invocation
- `iso/Containerfile:12-21`: build tool installation
- `iso/README.md:210-225`: troubleshooting section
