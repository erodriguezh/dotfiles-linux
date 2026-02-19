# Fix mcopy probe failure on El Torito-extracted EFI images

## Problem

The fn-9 El Torito extraction fallback succeeds — `osirrox -extract_boot_images` correctly extracts 6 files from the Fedora 43 boot.iso, including `eltorito_img2_uefi.img` (13 MB, clearly the EFI boot image). However, the mcopy probe at `iso/build-iso.sh:1010` fails to find `grub.cfg` in ANY extracted file:

```
[INFO]    El Torito images extracted via osirrox
[ERROR] El Torito extraction produced no EFI boot image (no files contain grub.cfg)
[ERROR]   Extracted files:
[ERROR]     eltorito_img2_uefi.img (13225984 bytes)
[ERROR]     gpt_part2_efi.img (13225984 bytes)
```

The probe checks both `::/EFI/BOOT/grub.cfg` and `::/EFI/fedora/grub.cfg` but finds neither.

## Root Cause

The El Torito-extracted image is likely NOT a raw FAT filesystem that mtools can read directly. Two scenarios:

1. **Partition table wrapper** — The extracted image has a GPT or MBR partition table wrapping the FAT filesystem. mtools expects the first sector to be a FAT boot sector, but instead finds a partition table header.

2. **Alignment padding** — The extracted byte range includes leading padding/zeroes before the actual FAT boot sector (e.g., sector-aligned gap before the ESP payload).

Both produce the same symptom: `mcopy -i <file>` fails because LBA0 is not a FAT boot sector.

## Solution

Add a two-stage fallback to the El Torito mcopy probe. When direct mcopy fails on ALL extracted files:

**Stage 1: Partition table detection** — Use `sfdisk --json` + `jq` to find the EFI System Partition offset and size, accounting for the actual sector size reported by sfdisk. Extract the raw FAT partition with `dd` using the correct sector size, then re-probe.

**Stage 2: FAT signature scan** — If no partition table is found (alignment padding case), scan for a FAT boot sector signature (`0xEB` or `0xE9` at byte 0, `0x55AA` at bytes 510-511) at small offsets (e.g., first 4 MiB in 512-byte steps), extract from that offset, re-probe.

**Key design choice**: Strip the partition wrapper with `dd` to produce a clean raw FAT image that becomes `$efi_img`. This is safer than using mtools `@@offset` syntax because:
- ALL 5+ downstream mcopy calls in `patch_efiboot()` Steps B-G work unchanged
- `_verify_inst_ks_efiboot()` (outside the function, at `iso/build-iso.sh:1726`) works unchanged
- xorriso re-injection with `-update "$efi_img" /images/efiboot.img` gets a clean FAT image
- UEFI firmware compatibility is guaranteed (expects raw FAT for efiboot.img)

After the fallback selects a candidate, `$efi_img` is replaced/overwritten with the stripped FAT image. An explicit sanity check verifies the result: `file -b "$efi_img"` must contain `FAT` and `mcopy -i "$efi_img" ::/EFI/.../grub.cfg /dev/null` must succeed.

**Fallback chain for El Torito image identification** (extends existing code at `iso/build-iso.sh:1003-1045`):

1. **Direct mcopy probe** (existing) — try `mcopy -o -i "$file" ::/EFI/BOOT/grub.cfg /dev/null` and `::/EFI/fedora/grub.cfg`
2. **NEW Stage 1: Partition-stripped probe** — if direct probe finds zero candidates:
   a. For each extracted file >1 MB: log `file -b` output
   b. Run `sfdisk --json "$file"` and parse with `jq` for EFI System Partition (match type case-insensitively: GPT GUID `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`, MBR type `ef`/`0xef`, gdisk-style `EF00`, or label `EFI System`)
   c. Read `sectorsize` from sfdisk JSON; compute byte offset = `start * sectorsize`, byte count = `size * sectorsize`
   d. Validate: `(start + size) * sectorsize <= file_size`
   e. Extract: `dd if="$file" of="${work_dir}/stripped-$(basename "$file").fat.img" bs=$sectorsize skip=$start count=$size`
   f. Probe stripped image with mcopy for both grub.cfg paths
3. **NEW Stage 2: FAT signature scan** — if Stage 1 finds no partition table in any file:
   a. For each extracted file >1 MB: scan for FAT boot sector at bounded offsets (first 4 MiB, 512-byte steps)
   b. FAT signature: byte 0 is `0xEB` or `0xE9`, bytes 510-511 are `0x55 0xAA`
   c. Extract from found offset, probe with mcopy
4. Zero/multiple matches still cause hard-fail with diagnostics (unchanged)

**mcopy stderr capture strategy:**
- During direct probes: capture stderr of the first failure per file (for diagnostics), suppress subsequent probes
- On final hard-fail: display the most informative stderr block (from the best candidate — largest file that failed)
- During normal success: no extra noise

## Scope

Narrow — El Torito probe logic in `patch_efiboot()` Step A + Containerfile tool dependency + README update.

### Task 1: Add partition-aware El Torito probe with dd extraction and README update

**File:** `iso/build-iso.sh` — `patch_efiboot()` Step A El Torito probe (~lines 1003-1045)
**File:** `iso/Containerfile` — add `util-linux` (sfdisk), `file`, and `jq` explicitly
**File:** `iso/README.md` — update El Torito troubleshooting section

After the existing direct mcopy probe loop finds zero candidates, add:

1. Log `file -b` diagnostic for each extracted image (only when fallback is triggered, not on every build)
2. **Stage 1 (partition table):** For each file >1 MB with a partition table:
   a. `sfdisk --json "$file"` parsed with `jq` — find EFI partition (case-insensitive type match)
   b. Compute byte-accurate offset using reported sector size
   c. Validate offset+size fits within file
   d. `dd` extract to per-input unique file: `${work_dir}/stripped-$(basename "$file").fat.img`
   e. Probe stripped image with mcopy for both grub.cfg paths
3. **Stage 2 (FAT signature scan):** If Stage 1 found no partition table, scan for FAT boot sector signature at bounded offsets
4. If exactly one candidate found (from either stage), copy to `$efi_img` — verify with `file -b` containing `FAT`
5. If zero/multiple, hard-fail with diagnostics including mcopy stderr and `file` output
6. Explicitly add `util-linux`, `file`, and `jq` to `iso/Containerfile`
7. Update `iso/README.md` El Torito section

**Commit ordering:** (1) Containerfile tooling, (2) build-iso.sh fallback, (3) README update

**Missing sfdisk behavior:** If `sfdisk` is not available (script run outside container), warn and skip Stage 1 (fall through to Stage 2 FAT scan, then to hard-fail with diagnostic message recommending `util-linux`). Inside the supported container environment, sfdisk will always be present.

## Quick commands

```bash
# Build ISO — should complete Stage 11 including efiboot.img patching
podman run --privileged --rm -v "$PWD:/build" \
  surface-iso-builder /build/iso/build-iso.sh --test

# Diagnostic: inspect El Torito extracted images (run inside container)
mkdir -p /tmp/et && osirrox -indev /build/.cache/isos/fedora-boot-43.iso -extract_boot_images /tmp/et/
for f in /tmp/et/*; do echo "=== $(basename "$f") ==="; file "$f"; sfdisk --json "$f" 2>/dev/null | jq '.partitiontable.partitions[]? | select(.type | test("c12a7328|EFI|ef";"i"))' 2>/dev/null; done
```

## Acceptance

- [ ] mcopy probe succeeds on El Torito-extracted EFI images (both partition-wrapped and raw FAT)
- [ ] `file -b` diagnostic logged for each extracted image (only during fallback, not every build)
- [ ] Partition table parsed via `sfdisk --json` + `jq` with correct sector size handling
- [ ] EFI partition type matched case-insensitively (GUID, `ef`/`0xef`, `EF00`, `EFI System`)
- [ ] Byte offset validated: `(start + size) * sectorsize <= file_size`
- [ ] Raw FAT partition extracted with `dd` using per-input unique filenames
- [ ] FAT signature scan fallback for alignment-padded images without partition tables
- [ ] `$efi_img` always contains clean raw FAT — downstream Steps B-G unchanged
- [ ] Post-selection sanity: `file -b "$efi_img"` contains `FAT` and mcopy probe succeeds without offset
- [ ] `_verify_inst_ks_efiboot()` works without modification (receives clean FAT)
- [ ] Backward compatible — direct mcopy probe still tried first
- [ ] mcopy stderr captured per-file during probes; displayed on final hard-fail
- [ ] `util-linux`, `file`, and `jq` explicitly installed in `iso/Containerfile`
- [ ] Missing `sfdisk`: warn, skip Stage 1, fall through to Stage 2/hard-fail
- [ ] Full ISO build succeeds end-to-end in Podman with loop device probe failure
- [ ] iso/README.md updated to mention partition-wrapper and signature-scan handling

## Out of scope

- Changing Steps B-G or `_verify_inst_ks_efiboot()` (the dd extraction makes this unnecessary)
- Supporting images with multiple FAT partitions (hard-fail is correct)
- Using mtools `@@offset` syntax for downstream calls (dd extraction is simpler)
- Adding loop device support to the container

## References

- `iso/build-iso.sh:1003-1045` — El Torito mcopy probe loop (the failing code)
- `iso/build-iso.sh:1058-1066` — Step B grub.cfg discovery (depends on clean FAT)
- `iso/build-iso.sh:1076` — Step C mcopy extract (depends on clean FAT)
- `iso/build-iso.sh:1236` — Step C mcopy write-back (depends on clean FAT)
- `iso/build-iso.sh:1240` — Step D mcopy verify (depends on clean FAT)
- `iso/build-iso.sh:1726` — `_verify_inst_ks_efiboot()` mcopy probe (outside patch_efiboot)
- `iso/build-iso.sh:1332-1391` — Step E xorriso re-injection (needs clean FAT path)
- `iso/README.md:221-224` — El Torito troubleshooting documentation
- `iso/Containerfile` — Container build dependencies
- [GNU mtools manual](https://www.gnu.org/software/mtools/manual/mtools.html)
- [xorriso boot_sectors.txt](https://github.com/Distrotech/xorriso/blob/master/doc/boot_sectors.txt)
- [lorax mkefiboot source](https://github.com/weldr/lorax/blob/master/src/bin/mkefiboot) — confirms efiboot.img is raw FAT
