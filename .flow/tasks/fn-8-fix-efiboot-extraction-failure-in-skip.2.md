# fn-8-fix-efiboot-extraction-failure-in-skip.2 Improve osirrox diagnostics across the script

## Description

Replace `2>/dev/null` on osirrox calls with captured stderr that is displayed on failure.

**File:** `iso/build-iso.sh`

<!-- Updated by plan-sync: fn-8-fix-efiboot-extraction-failure-in-skip.1 shifted lines +17 below line 957; established osirrox stderr capture pattern -->

Locations to update:
- `_extract_inst_ks_from_iso()` line ~849 — osirrox extraction of grub.cfg
- `_verify_inst_ks_efiboot()` line ~1636 — osirrox extraction of efiboot.img for verification
- `_verify_inst_ks_iso_configs()` line ~1600 — osirrox extraction of ISO-level EFI grub.cfg (required)
- `patch_efiboot()` post-rewrite spot-check line ~1323 — osirrox re-injection verification

Pattern: `2>/dev/null` → capture stderr into a variable, show on failure only.
Follow the pattern established in `patch_efiboot()` Step A by fn-8.1:
```bash
local extract_err=""
if ! extract_err="$(osirrox ... 2>&1)"; then
    error "Descriptive message"
    [[ -n "$extract_err" ]] && error "  osirrox: $extract_err"
    return 1
fi
```

**Note:** For non-critical extractions where failure is expected and handled, keep `2>/dev/null`:
- Apple EFI BOOT.conf at line ~1612 (warn-only diagnostic)
- BIOS candidate loop at line ~1582 (iterates multiple candidates, failure expected for most)

## Acceptance
- [ ] `_extract_inst_ks_from_iso` shows osirrox errors on failure
- [ ] `_verify_inst_ks_efiboot` shows osirrox errors on failure
- [ ] `_verify_inst_ks_iso_configs` shows osirrox errors on failure (except Apple EFI)
- [ ] `patch_efiboot` post-rewrite check shows errors on failure
- [ ] Non-critical extractions (Apple EFI) still suppress stderr

## Done summary
Replaced `2>/dev/null` with stderr capture (`2>&1` into variable) on four critical osirrox extraction calls across `_extract_inst_ks_from_iso`, `patch_efiboot` post-rewrite spot-check, `_verify_inst_ks_iso_configs` (EFI grub.cfg), and `_verify_inst_ks_efiboot`. Non-critical probe paths (BIOS candidate loop and Apple EFI BOOT.conf) correctly retain `2>/dev/null`.
## Evidence
- Commits: 8310748258206db72f37006f441264861e48605c
- Tests: bash -n iso/build-iso.sh (pre-existing syntax error confirmed not introduced by this change)
- PRs: