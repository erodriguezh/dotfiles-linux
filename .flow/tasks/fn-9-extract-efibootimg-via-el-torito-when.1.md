# fn-9-extract-efibootimg-via-el-torito-when.1 Add El Torito extraction fallback to patch_efiboot Step A

## Description

Add a third-tier El Torito extraction fallback to `patch_efiboot()` Step A when both filesystem-level osirrox extractions fail (output ISO and boot ISO).

**Size:** M
**Files:** `iso/build-iso.sh`

### Approach

After the existing two-tier fallback (output ISO filesystem -> boot ISO filesystem), add:

1. Create temp subdirectory `${work_dir}/eltorito/` for extracted boot images
2. Run `osirrox -indev "$boot_iso" -extract_boot_images "${work_dir}/eltorito/"` — capture stderr per fn-8 pattern
3. If osirrox extraction fails, retry with `xorriso -indev "$boot_iso" -osirrox on -extract_boot_images "${work_dir}/eltorito/"` — if both fail, report both stderrs and fail
4. Identify the EFI image by probing ALL regular files in the extraction directory (not just `eltorito_img*`) with `mcopy` for BOTH grub.cfg paths:
   - `mcopy -i <file> ::/EFI/BOOT/grub.cfg /dev/null 2>/dev/null`
   - `mcopy -i <file> ::/EFI/fedora/grub.cfg /dev/null 2>/dev/null`
   (Same candidate paths as Step B in `patch_efiboot()` — see `iso/build-iso.sh:997-1017`)
5. If multiple files pass the probe, hard-fail with error listing all matching files
6. If exactly one passes, copy it to `$efi_img`
7. Log extraction method and which grub.cfg path was found

**Optional sanity check:** Before coding, run the Quick commands from the epic spec inside the Podman container to confirm exactly one extracted file passes the `mcopy` probe on the actual Fedora 43 boot.iso.

Follow the existing fn-8 stderr capture pattern at `iso/build-iso.sh:967-983`.

### Key context

- `osirrox -extract_boot_images DIR/` extracts El Torito boot images — xorriso 1.5.6+ (Fedora 43)
- If osirrox lacks the option: `xorriso -indev ISO -osirrox on -extract_boot_images DIR/`
- File naming NOT guaranteed stable — scan ALL files in extraction directory
- Step B checks BOTH `::/EFI/BOOT/grub.cfg` and `::/EFI/fedora/grub.cfg` — El Torito probe must do the same
- The `$work_dir` RETURN trap at line ~951 handles cleanup automatically
- The extracted image is a FAT filesystem containing grub.cfg — exactly what Steps B-G expect

## Acceptance

- [ ] El Torito extraction attempted when both filesystem extractions fail
- [ ] osirrox -> xorriso fallback (always try xorriso if osirrox fails)
- [ ] Empty extraction dir or zero probe matches cause hard-fail with diagnostic message
- [ ] EFI image identified by `mcopy` probe with BOTH grub.cfg paths (not filename matching)
- [ ] All regular files in extraction dir scanned (not just `eltorito_img*`)
- [ ] Multiple matching candidates cause hard-fail with error listing matches
- [ ] Extracted EFI image copied to `$efi_img` for Steps B-G
- [ ] Info log indicates extraction method and grub.cfg path found
- [ ] osirrox/xorriso stderr captured and displayed on failure
- [ ] Temp files in `$work_dir/eltorito/` — cleaned by existing RETURN trap
- [ ] Full ISO build succeeds end-to-end in Podman with loop device probe failure

## Done summary
Added three-tier El Torito extraction fallback to patch_efiboot() Step A: when both filesystem-level osirrox extractions fail, extracts El Torito boot images via osirrox -extract_boot_images (with xorriso fallback), identifies the EFI image by probing all extracted regular files with mcopy for both grub.cfg paths, and hard-fails on zero or multiple matches with diagnostic output.
## Evidence
- Commits: 9d6f1c2, 5e6897b, bd7a497
- Tests: bash -n iso/build-iso.sh (pre-existing heredoc parse limitation)
- PRs: