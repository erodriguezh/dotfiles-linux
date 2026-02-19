# fn-10-fix-mcopy-probe-failure-on-el-torito.1 Add partition-aware El Torito probe with dd extraction and README update

## Description

Add a two-stage fallback to the El Torito mcopy probe in `patch_efiboot()` Step A. When direct mcopy fails on ALL extracted files: (1) detect partition table wrappers via `sfdisk --json` + `jq` and extract the raw FAT partition with `dd`, or (2) scan for FAT boot sector signatures at bounded offsets. The result is always a clean raw FAT image assigned to `$efi_img`.

**Size:** M
**Files:** `iso/build-iso.sh`, `iso/Containerfile`, `iso/README.md`

### Approach

Extend the El Torito probe loop at `iso/build-iso.sh:1003-1045`. After the existing direct mcopy probe finds zero candidates:

1. **Log `file -b` diagnostic** for each extracted image (only when fallback triggers, not every build)

2. **Stage 1 — Partition table detection** — for each extracted file >1 MB:
   a. Run `sfdisk --json "$file" 2>/dev/null` and parse with `jq`
   b. Find EFI System Partition — match type case-insensitively: GPT GUID `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`, MBR type `ef`/`0xef`, gdisk-style `EF00`, label `EFI System`
   c. Read `sectorsize` from sfdisk JSON (do NOT hardcode 512)
   d. Compute byte offset = `start * sectorsize`, byte count = `size * sectorsize`
   e. Validate: `(start + size) * sectorsize <= file_size`
   f. Extract: `dd if="$file" of="${work_dir}/stripped-$(basename "$file").fat.img" bs=$sectorsize skip=$start count=$size`
   g. Probe stripped image with mcopy for both grub.cfg paths
   h. If match found, add to candidates array (same pattern as existing code)

3. **Stage 2 — FAT signature scan** — if Stage 1 found no partition table in any file:
   a. For each extracted file >1 MB: scan for FAT boot sector signature at bounded offsets (first 4 MiB, 512-byte steps)
   b. FAT signature: byte 0 is `0xEB` or `0xE9`, bytes 510-511 are `0x55 0xAA`
   c. Extract from found offset to end of file, probe with mcopy
   d. If match found, add to candidates

4. **Selection and `$efi_img` assignment** — if exactly one candidate found (from either stage):
   a. Copy to `$efi_img` (or overwrite if already exists)
   b. **Sanity check**: `file -b "$efi_img"` must contain `FAT` AND `mcopy -i "$efi_img" ::/EFI/.../grub.cfg /dev/null` must succeed without offset tricks
   c. Log extraction method, grub.cfg path, and source file

5. **mcopy stderr capture** — during probes, capture stderr of first failure per file; on final hard-fail, display the most informative stderr (from largest file that failed)

6. **Containerfile** — explicitly add `util-linux` (sfdisk), `file`, and `jq` to `iso/Containerfile` `dnf5 install`

7. **Missing sfdisk behavior** — if `sfdisk` not available (script run outside container), warn and skip Stage 1; fall through to Stage 2 FAT scan, then to hard-fail with diagnostic recommending `util-linux`

8. **Update iso/README.md** — in the El Torito bullet (line ~224), add note about partition-wrapper detection and automatic stripping

**Commit ordering:** (1) Containerfile tooling, (2) build-iso.sh fallback, (3) README update

### Key context

- `sfdisk --json` output: `{"partitiontable": {"sectorsize": N, "partitions": [{"start": S, "size": SZ, "type": "..."}]}}`
- Use `jq` for reliable JSON parsing — avoid regex on text output (brittle across util-linux versions)
- EFI partition type: match case-insensitively for GUID, hex code, and label variations
- `dd bs=$sectorsize skip=$start count=$size` — sector-size-aware extraction (NOT hardcoded 512)
- Per-input unique output: `${work_dir}/stripped-$(basename "$file").fat.img` — avoids overwriting results from prior files
- The resulting `$efi_img` must be a clean raw FAT image — ALL downstream mcopy calls (Steps B-G at lines 1058-1240) and `_verify_inst_ks_efiboot()` (line 1726) work unchanged
- Do NOT use mtools `@@offset` syntax — `dd` extraction is cleaner (avoids modifying 5+ call sites)
- The `$work_dir` RETURN trap at line 958 handles cleanup of temp files automatically
- Follow existing stderr capture pattern from fn-8: `extract_err="$(command 2>&1)"`
- `sfdisk` exits non-zero on files without partition tables — expected, not an error

## Acceptance

- [ ] Direct mcopy probe still tried first (backward compatible)
- [ ] `file -b` diagnostic logged for each extracted image (only during fallback)
- [ ] Partition table parsed via `sfdisk --json` + `jq` with correct sector size handling
- [ ] EFI partition type matched case-insensitively (GUID, `ef`/`0xef`, `EF00`, `EFI System`)
- [ ] Byte offset validated: `(start + size) * sectorsize <= file_size`
- [ ] Raw FAT partition extracted with `dd` using per-input unique filenames
- [ ] FAT signature scan fallback for alignment-padded images without partition tables
- [ ] `$efi_img` replaced with clean raw FAT — downstream Steps B-G unchanged
- [ ] Post-selection sanity: `file -b "$efi_img"` contains `FAT` and mcopy probe succeeds without offset
- [ ] `_verify_inst_ks_efiboot()` works without modification (receives clean FAT)
- [ ] mcopy stderr captured per-file during probes; displayed on final hard-fail
- [ ] `util-linux`, `file`, and `jq` explicitly installed in `iso/Containerfile`
- [ ] Missing `sfdisk`: warn, skip Stage 1, fall through to Stage 2/hard-fail
- [ ] iso/README.md updated to mention partition-wrapper and signature-scan handling
- [ ] Full ISO build succeeds end-to-end in Podman with loop device probe failure

## Done summary
Added two-stage partition-aware fallback to the El Torito mcopy probe in patch_efiboot(). When direct mcopy fails on extracted images, Stage 1 uses sfdisk+jq to detect GPT/MBR partition wrappers and dd-extracts the raw FAT ESP, while Stage 2 scans for FAT boot sector signatures at bounded offsets. Includes Containerfile dependency additions (util-linux, file) and README documentation update.
## Evidence
- Commits: dd79041, c67bc70, d3c1fb0, b95943a, e985812
- Tests: shellcheck -s bash iso/build-iso.sh
- PRs: