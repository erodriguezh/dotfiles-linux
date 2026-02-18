# fn-8-fix-efiboot-extraction-failure-in-skip.2 Improve osirrox diagnostics across the script

## Description

Replace `2>/dev/null` on osirrox calls with captured stderr that is displayed on failure.

**File:** `iso/build-iso.sh`

Locations to update:
- `_extract_inst_ks_from_iso()` line ~849 — osirrox extraction of grub.cfg
- `_verify_inst_ks_efiboot()` line ~1619 — osirrox extraction of efiboot.img for verification
- `_verify_inst_ks_iso_configs()` line ~1583 — osirrox extraction of isolinux grub.cfg
- `patch_efiboot()` post-rewrite spot-check line ~1306 — osirrox re-injection verification

Pattern: `2>/dev/null` → capture stderr, show on failure only.

**Note:** For non-critical extractions (Apple EFI BOOT.conf at line ~1595), keep `2>/dev/null` since failure is expected and handled.

## Acceptance
- [ ] `_extract_inst_ks_from_iso` shows osirrox errors on failure
- [ ] `_verify_inst_ks_efiboot` shows osirrox errors on failure
- [ ] `_verify_inst_ks_iso_configs` shows osirrox errors on failure (except Apple EFI)
- [ ] `patch_efiboot` post-rewrite check shows errors on failure
- [ ] Non-critical extractions (Apple EFI) still suppress stderr

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
