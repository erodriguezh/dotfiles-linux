# Fix losetup pre-flight detection and EFI boot label in ISO builder

## Overview

The ISO builder's losetup pre-flight check (PR #4, commit `2788642`) is too weak. It runs `losetup --find` (query-only: prints next available `/dev/loopN`) but mkefiboot internally runs `losetup --find --show <file>` (actual attachment). These test fundamentally different capabilities — the query can succeed in environments where attachment fails (loop device nodes exist but are non-functional).

Additionally, when `--skip-mkefiboot` activates and `-V "SurfaceLinux-43"` changes the ISO volume label, the efiboot.img's internal grub.cfg still references the original Fedora label. On UEFI USB boot, GRUB searches for a volume with the old label, fails to find it, and boot breaks. The current README incorrectly claims this path is safe.

**Post-fn-6.1 discovery**: The `_verify_no_duplicate_inst_ks()` function hard-fails looking for `isolinux.cfg`/`syslinux.cfg`, which Fedora 43 does not ship (BIOS boot uses GRUB2 since Fedora 37). Additionally, when `--skip-mkefiboot` is active, the efiboot.img's internal grub.cfg lacks `inst.ks=` injection and has stale `hd:LABEL=` references.

## Scope

**Phase 1 (fn-6.1 — done):**
- Strengthen losetup pre-flight to test actual loop device attachment
- Defense-in-depth retry on mkefiboot failure
- Add `mtools` to Containerfile
- `patch_efiboot_label` for volume label fixup in efiboot.img (`search --label`/`-l` lines)
- Duplicate `inst.ks` detection framework

**Phase 2 (fn-6.2 — new):**
- Fix BIOS config verification to use GRUB2 paths (`boot/grub2/grub.cfg`) instead of isolinux/syslinux
- Add ISO-level `EFI/BOOT/grub.cfg` verification — **required** (hard-fail if missing)
- BIOS config is **best-effort** (warn if missing) — Surface Go 3 is UEFI-only
- Restructure verification timing: ISO-level configs pre-patch, efiboot.img post-patch
- Expand efiboot.img patching: replace label in known patterns (`search --label`/`-l`, `hd:LABEL=`) + inject `inst.ks=` into installer `linux`/`linuxefi` stanzas (only those with `inst.stage2=`)
- Derive `inst.ks=` value from the already-injected ISO-level `EFI/BOOT/grub.cfg` (don't hardcode filename — discover what mkksiso actually injected)
- Handle GRUB `\` line continuations for logical kernel cmdline stanzas
- Rename `patch_efiboot_label` → `patch_efiboot` to reflect expanded scope

## Quick commands

```bash
# Build ISO in container
sudo podman build -t surface-iso-builder -f iso/Containerfile iso/
sudo podman run --rm -v "$PWD:/build:Z" surface-iso-builder /build/iso/build-iso.sh --validate-only

# ShellCheck
shellcheck iso/build-iso.sh

# Verify ISO boot configs (all three layers)
osirrox -indev output.iso -extract /boot/grub2/grub.cfg /tmp/bios-grub.cfg
osirrox -indev output.iso -extract /EFI/BOOT/grub.cfg /tmp/efi-grub.cfg
osirrox -indev output.iso -extract /images/efiboot.img /tmp/efiboot.img
mcopy -n -i /tmp/efiboot.img ::/EFI/BOOT/grub.cfg /tmp/efi-internal-grub.cfg 2>/dev/null \
  || mcopy -n -i /tmp/efiboot.img ::/EFI/fedora/grub.cfg /tmp/efi-internal-grub.cfg
grep inst.ks= /tmp/bios-grub.cfg /tmp/efi-grub.cfg /tmp/efi-internal-grub.cfg
```

## Acceptance

- [ ] `losetup --find --show <tempfile>` used as the pre-flight probe (actual attachment test)
- [ ] Probe cleans up temp file and detaches loop device via trap on all exit paths
- [ ] Defense-in-depth: mkksiso mkefiboot/losetup failure triggers max-once retry
- [ ] `mtools` added to `iso/Containerfile`
- [ ] EFI label patching: grub.cfg discovered via `mcopy` probes, label replaced via `python3 -c` with `re.sub`
- [ ] Appended EFI partition: xorriso decision table (4 cases) for re-injection
- [ ] BIOS verification uses `boot/grub2/grub.cfg` (+ `boot/grub/grub.cfg` fallback); **warn** if absent
- [ ] ISO-level `EFI/BOOT/grub.cfg` **required** (hard-fail if missing); verified for `inst.ks=`
- [ ] efiboot.img patching: label replaced in known patterns (`search --label`/`-l`, `hd:LABEL=`), NOT blanket global replace
- [ ] efiboot.img patching: `inst.ks=` value derived from ISO-level EFI grub.cfg (what mkksiso injected), not hardcoded
- [ ] efiboot.img patching: `inst.ks=` injected only into installer entries (those containing `inst.stage2=`), handling `\` line continuations
- [ ] Post-patch verification: efiboot.img has correct label AND exactly one `inst.ks=` per installer stanza
- [ ] Post-patch spot-check: ISO-level `EFI/BOOT/grub.cfg` still intact after xorriso rewrite
- [ ] No duplicate `inst.ks=` in any boot config layer
- [ ] `implantisomd5` re-run after ISO rewrite; sha256 regenerated
- [ ] `iso/README.md` updated
- [ ] `shellcheck iso/build-iso.sh` passes
- [ ] Keep diffs surgical — avoid stacking unrelated refactors into Stage 11

## References

- PR #4 (commit `2788642`): original losetup skip fix
- lorax `mkksiso.py` source: `EditGrub2()` handles `EFI/BOOT/grub.cfg`, `boot/grub2/grub.cfg`, `boot/grub/grub.cfg`
- lorax `EditIsolinux()`: gracefully skips when isolinux.cfg absent
- lorax `known_configs`: `isolinux/isolinux.cfg`, `boot/grub2/grub.cfg`, `boot/grub/grub.cfg`, `EFI/BOOT/grub.cfg`, `EFI/BOOT/BOOT.conf`
- lorax `MakeKickstartISO()`: `inst.ks=hd:LABEL=<volid>:/<ks_basename>` injected via `add_args`
- Fedora Changes/BIOSBootISOWithGrub2: isolinux removed in Fedora 37
- `iso/build-iso.sh:1228-1287`: verification function
- `iso/build-iso.sh:842-1046`: `patch_efiboot_label` function
- `iso/build-iso.sh:1289-1299`: verify → patch execution order
