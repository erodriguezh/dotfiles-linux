# Fix efiboot.img extraction failure when --skip-mkefiboot is active

## Problem

When `build-iso.sh` runs in Podman (even with `--privileged`), the loop device probe fails, triggering the `--skip-mkefiboot` path. After mkksiso succeeds, the `patch_efiboot()` function attempts to extract `/images/efiboot.img` from the **output** ISO via `osirrox`, but this fails:

```
[WARN]  Loop device attachment failed — adding --skip-mkefiboot
[OK]    ISO-level boot config verification passed
[INFO]  Derived inst.ks= value from ISO: inst.ks=hd:LABEL=SurfaceLinux-43:/kickstart.ks
[INFO]  Patching efiboot.img: label='SurfaceLinux-43', inst.ks='inst.ks=hd:LABEL=SurfaceLinux-43:/kickstart.ks'...
[ERROR] Failed to extract efiboot.img from ISO
[ERROR] efiboot.img patching failed — aborting
```

Key observations:
1. `osirrox -extract "/EFI/BOOT/grub.cfg"` succeeds on the same output ISO (in `_extract_inst_ks_from_iso`)
2. `osirrox -extract "/images/efiboot.img"` fails (in `patch_efiboot` Step A)
3. stderr is suppressed (`2>/dev/null`), so the actual xorriso error is invisible

When mkksiso runs with `--skip-mkefiboot`, it may not include `/images/efiboot.img` as a visible Rock Ridge/ISO 9660 filesystem entry. The EFI boot image exists only as a raw partition in the ISO system area (El Torito / appended partition), making it unreachable via filesystem-level extraction.

## Root Cause

`patch_efiboot()` (line 961) only tries to extract from the **output** ISO. Since `--skip-mkefiboot` means efiboot.img was NOT rebuilt by mkksiso, the original boot ISO (`$BOOT_ISO`) contains the **byte-for-byte identical** file at `/images/efiboot.img` — and that file IS extractable (it's a standard Fedora ISO 9660 entry).

## Scope

Narrow — one function signature change + extraction fallback + diagnostic improvements:

### Task 1: Add boot ISO fallback to `patch_efiboot`

**File:** `iso/build-iso.sh`

1. Add optional 4th parameter `boot_iso` to `patch_efiboot()` signature
2. In Step A extraction: try output ISO first, then fall back to `$boot_iso`
3. Log which source was used
4. Stop suppressing osirrox stderr — capture to tempfile, display on final failure
5. Update call site (line 1666) to pass `$BOOT_ISO` as 4th argument

**Before (line 961):**
```bash
if ! osirrox -indev "$iso_path" -extract /images/efiboot.img "$efi_img" 2>/dev/null; then
    error "Failed to extract efiboot.img from ISO"
    return 1
fi
```

**After:**
```bash
local boot_iso="${4:-}"
local extract_err=""

if ! extract_err="$(osirrox -indev "$iso_path" -extract /images/efiboot.img "$efi_img" 2>&1)"; then
    if [[ -n "$boot_iso" && -f "$boot_iso" ]]; then
        info "  /images/efiboot.img not in output ISO — extracting from original boot ISO"
        if ! extract_err="$(osirrox -indev "$boot_iso" -extract /images/efiboot.img "$efi_img" 2>&1)"; then
            error "Failed to extract efiboot.img from both output and boot ISO"
            [[ -n "$extract_err" ]] && error "  osirrox: $extract_err"
            return 1
        fi
    else
        error "Failed to extract efiboot.img from ISO"
        [[ -n "$extract_err" ]] && error "  osirrox: $extract_err"
        return 1
    fi
fi
```

**Call site update (line 1666):**
```bash
# Before:
patch_efiboot "$output_iso" "SurfaceLinux-43" "$inst_ks_value"
# After:
patch_efiboot "$output_iso" "SurfaceLinux-43" "$inst_ks_value" "$BOOT_ISO"
```

### Task 2: Improve osirrox diagnostics across the script

**File:** `iso/build-iso.sh`

Replace `2>/dev/null` on ALL osirrox calls with captured stderr that is displayed on failure:

- `_extract_inst_ks_from_iso()` line 849
- `_verify_inst_ks_efiboot()` line 1619
- `_verify_inst_ks_iso_configs()` lines 1583, 1595
- `patch_efiboot()` post-rewrite spot-check line 1306

Pattern: `2>/dev/null` → capture stderr, show on failure only.

**Note:** For non-critical extractions (Apple EFI BOOT.conf at line 1595), keep `2>/dev/null` since failure is expected and handled.

## Out of scope

- Investigating WHY mkksiso with `--skip-mkefiboot` doesn't preserve `/images/efiboot.img` as a filesystem entry (that's a lorax bug/design choice)
- Changing the container to support loop devices (the `--skip-mkefiboot` path must work)
- Modifying the Containerfile

## Quick commands

```bash
# Build ISO — should complete Stage 11 including efiboot.img patching
podman run --privileged --rm -v "$PWD:/build" \
  surface-iso-builder /build/iso/build-iso.sh --username=edu --password-hash-file=/tmp/hash.txt
```

## Key context

- When `--skip-mkefiboot` is active, efiboot.img in the output ISO is identical to the input boot ISO
- After `patch_efiboot` re-injects via xorriso (`-update efi_img /images/efiboot.img`), the file WILL exist in the ISO — so `_verify_inst_ks_efiboot()` at line 1675 should work post-patch
- The `$BOOT_ISO` variable is available in `stage_assemble_iso()` scope where `patch_efiboot` is called
- `patch_efiboot` function signature: `patch_efiboot ISO_PATH NEW_LABEL INST_KS_VALUE [BOOT_ISO]`

## Acceptance

- [ ] `patch_efiboot` accepts optional 4th `boot_iso` parameter
- [ ] Extraction falls back to boot ISO when output ISO extraction fails
- [ ] Info log indicates which source was used for efiboot.img
- [ ] osirrox errors are captured and displayed on failure (not swallowed)
- [ ] `_extract_inst_ks_from_iso` and `_verify_inst_ks_efiboot` also show osirrox errors on failure
- [ ] Full build succeeds in Podman with loop device probe failure

## References

- `iso/build-iso.sh:946-964` — `patch_efiboot()` function, Step A extraction (the failing code)
- `iso/build-iso.sh:1658-1669` — Call site in `stage_assemble_iso()`
- `iso/build-iso.sh:842-934` — `_extract_inst_ks_from_iso()` (succeeds because it extracts grub.cfg, not efiboot.img)
- `iso/build-iso.sh:1611-1645` — `_verify_inst_ks_efiboot()` (also extracts efiboot.img, runs post-patch)
- `iso/build-iso.sh:1290-1298` — xorriso re-injection (creates /images/efiboot.img in output ISO)
