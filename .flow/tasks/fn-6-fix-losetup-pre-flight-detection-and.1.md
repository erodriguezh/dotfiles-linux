## Description

Fix three related issues in `stage_assemble_iso()` that cause ISO builds to fail or produce non-bootable UEFI USB media when loop devices are unavailable.

**Size:** M
**Files:** `iso/build-iso.sh`, `iso/Containerfile`, `iso/README.md`

## Approach

### 1. Strengthen losetup pre-flight probe (`build-iso.sh:860-868`)

Replace the weak `losetup --find` query with an actual attachment test:

- Create a 1 MiB temp file via `truncate -s 1M`
- Attempt `losetup --find --show <tempfile>` — tests the exact operation mkefiboot uses
- On success: detach with `losetup -d`, remove temp file, proceed without `--skip-mkefiboot`
- On failure: remove temp file, add `--skip-mkefiboot` + trigger efiboot.img patching
- Use a trap to ensure cleanup on any exit path (temp file + loop device)

**Defense-in-depth retry:** Even when the probe succeeds, capture mkksiso's stderr to a temp file. If mkksiso exits non-zero, check stderr against a tight set of substrings: `mkefiboot`, `losetup:`, `loop_attach`, `failed to set up loop device`. On match: remove/rename any partially written output ISO, retry at most ONCE with `--skip-mkefiboot` + patching (keep both stderr logs). On retry failure: print BOTH attempts' stderr before exiting non-zero. On non-matching error: fail immediately (don't mask unrelated errors).

### 2. mtools efiboot.img patching (`build-iso.sh`, new helper function)

When `--skip-mkefiboot` is active and `-V` changes the volume label, patch EFI boot artifacts in the output ISO. This is a single new function (e.g., `patch_efiboot_label`).

**Step A — Extract efiboot.img from the output ISO:**
```
osirrox -indev <output> -extract /images/efiboot.img /tmp/efiboot.img
```

**Step B — Discover grub.cfg inside the FAT image:**
Probe an ordered list of known candidate paths using direct existence checks (FAT is case-insensitive; mtools handles this):
1. Try `mcopy -n -i /tmp/efiboot.img ::/EFI/BOOT/grub.cfg /dev/null 2>/dev/null` — if exit 0, path exists
2. Try `mcopy -n -i /tmp/efiboot.img ::/EFI/fedora/grub.cfg /dev/null 2>/dev/null`

Use the first path that succeeds. If none found, **hard-fail** the build with a clear error.

**Step C — Extract, patch, and write back grub.cfg:**
- Extract: `mcopy -i /tmp/efiboot.img ::<path>/grub.cfg /tmp/efi-grub.cfg`
- Extract original label(s) from grub.cfg. Support ALL common GRUB search variants:
  - `search.*--label\s+'([^']+)'` (single-quoted, long flag)
  - `search.*--label\s+"([^"]+)"` (double-quoted, long flag)
  - `search.*--label\s+(\S+)` (unquoted, long flag)
  - `search.*-l\s+'([^']+)'` (single-quoted, short flag)
  - `search.*-l\s+"([^"]+)"` (double-quoted, short flag)
  - `search.*-l\s+(\S+)` (unquoted, short flag)
  Hard-fail if no label token found. If multiple DISTINCT labels are found, hard-fail (ambiguous — can't safely patch).
- Replace using **targeted** `python3 -c` substitution (python3 is guaranteed present — lorax dependency). Use `re.sub` with `re.escape()` for the old label, only rewriting the `--label`/`-l` operand. Preserve the original quoting style. Patch ALL occurrences of the discovered label.
- Write back: `mcopy -o -i /tmp/efiboot.img /tmp/efi-grub.cfg ::<path>/grub.cfg`
- **Verify:** Re-extract grub.cfg after write-back. Assert: old label count == 0 AND new label count >= 1. Hard-fail on mismatch.

**Step D — Detect appended EFI partition and re-inject:**
Parse `xorriso -indev <output> -report_system_area plain 2>&1`.

Decision table:
1. If `xorriso` exits non-zero → **hard-fail** (print output)
2. If exit 0 and regex `^Partition\s+(\d+).*type\s+0xEF` finds exactly one indexed match → use detected index N for `-append_partition N 0xEF`
3. If exit 0 and regex finds no matches → treat as El Torito-only; do `-update` only
4. If exit 0 and regex finds >1 distinct indices → **hard-fail** (ambiguous)

Only lines containing BOTH a partition index AND `type 0xEF` are matched. Other EFI hints without an index are informational only (not used for parsing).

**When appended EFI partition exists (case 2):**
```
xorriso -indev <output> -outdev <fixed> \
    -boot_image any replay \
    -update /tmp/efiboot.img /images/efiboot.img \
    -append_partition <N> 0xEF /tmp/efiboot.img
```

**When NO appended EFI partition (case 3):**
```
xorriso -indev <output> -outdev <fixed> \
    -boot_image any replay \
    -update /tmp/efiboot.img /images/efiboot.img
```

**Step E — Re-implant media checksum + regenerate sha256:**
- Run `implantisomd5 <fixed>` to restore media check metadata
- Ensure the existing sha256 generation at the end of `stage_assemble_iso` runs on the patched ISO

### 3. Add mtools to Containerfile (`Containerfile:12-21`)

Add `mtools` to the `dnf5 install` line. Required unconditionally since loop device availability is only known at runtime. `python3` is already guaranteed present (lorax dependency) — no additional install needed for the label replacement.

### 4. Fix duplicate `inst.ks` entries (`build-iso.sh:870-875`)

Drop `-c "inst.ks=cdrom:/ks.cfg"` — let mkksiso's `--ks` flag handle it.

**Verification (mandatory):** After mkksiso produces the output ISO, verify BOTH boot paths:

- **BIOS:** Extract from ISO filesystem — probe `/isolinux/isolinux.cfg`, `/syslinux/syslinux.cfg`. Assert exactly one `inst.ks=` in the found config.
- **EFI:** Extract `efiboot.img` from the output ISO, then extract `grub.cfg` from inside it via mtools (same discovery flow as Step 2B). Assert exactly one `inst.ks=` in the found grub.cfg. This verifies the ACTUAL config that UEFI firmware reads at boot.

Hard-fail with a clear message if configs can't be located. Log the actual cmdline.

### 5. Update docs (`iso/README.md:210-225`)

The current README claims `--skip-mkefiboot` is "safe — UEFI boot works correctly with the original EFI image." Update to reflect:
- The stronger probe mechanism (actual attachment test + retry fallback)
- The mtools-based efiboot.img patching that preserves UEFI USB boot with custom labels
- The `implantisomd5` re-implantation after ISO rewrite
- When rootful build is still needed (custom EFI partition beyond label patching)

### Commit strategy

Two commits within a single PR to reduce blast radius:
1. **Commit 1:** Losetup probe strengthening + duplicate `inst.ks` fix + mtools in Containerfile
2. **Commit 2:** efiboot.img patching function + implantisomd5 + README update

## Key context

- `--skip-mkefiboot` is a valid mkksiso flag (`lorax/src/bin/mkksiso:L574`). It skips `RebuildEFIBoot()`.
- mtools `mcopy -i <img>` operates directly on FAT images without loop devices (Arch archiso, linuxkit).
- FAT is case-insensitive; mtools handles this natively. Use direct `mcopy` existence probes.
- Use `python3 -c` with `re.sub` + `re.escape()` for label replacement — python3 is guaranteed present via lorax dependency, avoids the `perl` availability question and `sed` escaping issues.
- `implantisomd5` (from isomd5sum package, already in Containerfile) must be re-run after any ISO rewrite.
- The UEFI boot config that firmware reads is INSIDE `efiboot.img`, not the ISO filesystem's `/EFI/BOOT/grub.cfg`.
- On retry, remove/rename partially written output ISO before rerunning mkksiso.

## Acceptance

- [ ] Pre-flight probe uses `losetup --find --show <tempfile>` (actual attachment test, not bare `--find`)
- [ ] Probe temp file and loop device cleaned up via trap on all exit paths
- [ ] Defense-in-depth: mkksiso mkefiboot/losetup failure (tight substring match) triggers max-once retry; partial output ISO removed before retry; both attempts' stderr preserved; non-matching errors fail immediately
- [ ] `mtools` added to `iso/Containerfile`
- [ ] grub.cfg location inside efiboot.img discovered by direct `mcopy` existence probes on ordered candidate paths; build hard-fails if not found
- [ ] Label extracted from grub.cfg via regex supporting `--label`/`-l` with single-quoted/double-quoted/unquoted variants; hard-fails if no label or multiple distinct labels found
- [ ] Label replacement uses `python3 -c` with `re.sub` + `re.escape()` (python3 guaranteed via lorax); post-replacement re-extraction verifies old label gone (0 hits) and new label present (>= 1 hit)
- [ ] Appended EFI partition: xorriso non-zero → hard-fail; exactly one `Partition N ... type 0xEF` → replace at index N; no match → `-update` only; >1 distinct indices → hard-fail
- [ ] `implantisomd5` re-run after any post-mkksiso ISO rewrite; sha256 regenerated
- [ ] No duplicate `inst.ks` — BIOS verified via ISO filesystem config; EFI verified via efiboot.img mtools extraction
- [ ] `iso/README.md` corrects misleading "safe" claim
- [ ] `shellcheck iso/build-iso.sh` passes; CI unaffected

## Done summary

## Evidence
