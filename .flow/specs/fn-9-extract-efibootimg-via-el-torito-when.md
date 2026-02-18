# Extract efiboot.img via El Torito when ISO 9660 entry missing

## Problem

The fn-8 fix added a boot ISO fallback to `patch_efiboot()`, assuming the original Fedora 43 boot.iso has `/images/efiboot.img` as an extractable ISO 9660 filesystem entry. **It does not.** Both the output ISO and the boot ISO store efiboot.img only as a hidden El Torito EFI boot partition + GPT appended partition, not as a Rock Ridge directory entry.

Build log evidence:
```
xorriso : FAILURE : Cannot determine attributes of (ISO) source file '/images/efiboot.img' : No such file or directory
```
This fails on **both** output and boot ISOs — the fn-8 two-level fallback exhausts without success.

## Root Cause

Fedora 43 Everything/netinstall boot.iso stores the EFI boot image exclusively in the El Torito boot catalog (platform ID 0xEF) and as a GPT appended partition (type `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`). It is NOT a visible ISO 9660 / Rock Ridge directory entry at `/images/efiboot.img`. The `osirrox -extract` command can only extract filesystem-level entries, not raw El Torito partitions.

xorriso confirms the image exists as El Torito only:
```
libisofs: NOTE : Found hidden El-Torito image for EFI.
libisofs: NOTE : EFI image start and size: 565743 * 2048 , 25832 * 512
```

## Solution

Add El Torito extraction as a third fallback tier in `patch_efiboot()` Step A, using `osirrox -extract_boot_images` (or `xorriso` if osirrox lacks the option). This command extracts boot images that are not visible in the filesystem tree, including El Torito catalog entries.

**Extraction fallback chain:**
1. Filesystem extraction from output ISO (existing — works when mkksiso preserves entry)
2. Filesystem extraction from boot ISO (fn-8 — works if boot ISO has entry)
3. **NEW**: El Torito extraction from boot ISO via `osirrox -extract_boot_images`

The third tier handles the Fedora 43 case where neither ISO has a filesystem entry.

## Scope

Narrow — Step A extraction logic in `patch_efiboot()` + README update:

### Task 1: Add El Torito extraction fallback to patch_efiboot

**File:** `iso/build-iso.sh` — `patch_efiboot()` Step A (~lines 957-983)

After both filesystem-level extractions fail, add:
1. Call `osirrox -extract_boot_images` on `$boot_iso` into `${work_dir}/eltorito/` subdirectory
2. If osirrox extraction fails, retry with `xorriso -indev "$boot_iso" -osirrox on -extract_boot_images "${work_dir}/eltorito/"` — if both fail, report both stderrs and fail
3. Identify the EFI boot image among ALL extracted files (not just `eltorito_img*`) — probe each file with `mcopy -i <file> ::/EFI/BOOT/grub.cfg /dev/null 2>/dev/null` OR `mcopy -i <file> ::/EFI/fedora/grub.cfg /dev/null 2>/dev/null` (same candidate paths as Step B)
4. If multiple files pass the probe, hard-fail with a clear error listing all matching files
5. If exactly one passes, copy it to `$efi_img`
6. Log which extraction method and grub.cfg path were used
7. Capture and display osirrox/xorriso stderr on failure (follow fn-8 pattern)

**Key decisions:**
- Use `mcopy` probing with BOTH grub.cfg paths (`/EFI/BOOT/grub.cfg` and `/EFI/fedora/grub.cfg`) — not filename matching — to identify the correct image
- Scan ALL regular files in the extraction directory, not just `eltorito_img*.img` — xorriso naming is not guaranteed stable
- Hard-fail on ambiguous matches (multiple candidates pass probe) — don't silently pick wrong image
- Extract from `$boot_iso` (not output ISO) because the output ISO's El Torito entry may reference modified/partial data from mkksiso
- Place extracted files in `$work_dir/eltorito/` subdirectory — cleaned up by existing RETURN trap

### Task 2: Update iso/README.md for El Torito extraction

**File:** `iso/README.md` — "mkksiso fails with losetup / mkefiboot error" section (~lines 215-244)

Update step 1 description to explain:
- The three-tier extraction fallback chain
- Why El Torito extraction is needed: Fedora 43 stores the EFI boot image only in the El Torito boot catalog / appended partition, not as a visible ISO 9660 filesystem entry
- Brief explanation of El Torito (hidden boot partitions vs visible directory entries)

## Out of scope

- Changing the Containerfile or adding loop device support
- Investigating why Fedora 43 boot.iso lacks the Rock Ridge entry (lorax design choice)
- Rewriting the entire efiboot patching approach (Steps B-G work fine)
- `dd` + sector offset extraction (over-engineering; `osirrox -extract_boot_images` is cleaner)

## Quick commands

```bash
# Build ISO in container — should complete Stage 11 including efiboot.img patching
podman run --privileged --rm -v "$PWD:/build" \
  surface-iso-builder /build/iso/build-iso.sh --username=edu --password-hash-file=/tmp/hash.txt

# Verify El Torito extraction works on boot ISO (run inside container)
mkdir -p /tmp/eltorito-test
osirrox -indev /build/.cache/isos/fedora-boot-43.iso -extract_boot_images /tmp/eltorito-test/
ls -la /tmp/eltorito-test/
# Check which file(s) are EFI FAT images with grub.cfg
for f in /tmp/eltorito-test/*; do
  mcopy -i "$f" ::/EFI/BOOT/grub.cfg /dev/null 2>/dev/null && echo "EFI (BOOT): $f"
  mcopy -i "$f" ::/EFI/fedora/grub.cfg /dev/null 2>/dev/null && echo "EFI (fedora): $f"
done
```

## Key context

- `osirrox -extract_boot_images DIR/` extracts El Torito boot images to `DIR/` — xorriso 1.5.6+ (Fedora 43)
- If osirrox lacks the option, use `xorriso -indev ISO -osirrox on -extract_boot_images DIR/` instead
- File naming: typically `eltorito_img1_*.img` (BIOS), `eltorito_img2_*.img` (EFI) — but NOT guaranteed; scan ALL files
- `patch_efiboot()` Step B checks BOTH `::/EFI/BOOT/grub.cfg` and `::/EFI/fedora/grub.cfg` — the El Torito probe must check both paths too
- The `$work_dir` RETURN trap at line ~951 handles cleanup automatically
- The extracted image is a FAT filesystem containing grub.cfg — exactly what Steps B-G expect
- After xorriso re-injection (Step E), `/images/efiboot.img` WILL be a visible filesystem entry — so `_verify_inst_ks_efiboot()` works unchanged

## Acceptance

- [ ] `patch_efiboot` tries El Torito extraction when both filesystem-level extractions fail
- [ ] El Torito image identification probes both grub.cfg paths (`/EFI/BOOT/` and `/EFI/fedora/`)
- [ ] Empty extraction dir or zero probe matches cause hard-fail with diagnostic message listing extracted files
- [ ] Multiple matching candidates cause hard-fail with clear error listing matches
- [ ] Info log indicates extraction method used (filesystem vs El Torito) and grub.cfg path found
- [ ] osirrox/xorriso stderr captured and displayed on failure
- [ ] osirrox → xorriso fallback for `-extract_boot_images` (always try xorriso if osirrox fails)
- [ ] Full ISO build succeeds in Podman with loop device probe failure
- [ ] `iso/README.md` updated to describe three-tier extraction fallback and explain El Torito context

## References

- `iso/build-iso.sh:957-983` — Step A extraction (current two-tier fallback)
- `iso/build-iso.sh:948-1342` — Full `patch_efiboot()` function
- `iso/build-iso.sh:997-1017` — Step B grub.cfg discovery (both paths)
- `iso/build-iso.sh:1691` — Call site in `stage_assemble_iso()`
- `iso/README.md:215-244` — "mkksiso fails with losetup / mkefiboot error" section
- [Arch Forums xorriso -extract_boot_images example](https://bbs.archlinux.org/viewtopic.php?id=298981)
- [Debian RepackBootableISO wiki](https://wiki.debian.org/RepackBootableISO)
- [xorriso man page](https://www.gnu.org/software/xorriso/man_1_xorriso.html)
