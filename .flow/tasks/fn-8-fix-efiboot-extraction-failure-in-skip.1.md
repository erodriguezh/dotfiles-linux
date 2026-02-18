# fn-8-fix-efiboot-extraction-failure-in-skip.1 Add boot ISO fallback to patch_efiboot

## Description

Add optional 4th parameter `boot_iso` to `patch_efiboot()` and implement extraction fallback logic.

**File:** `iso/build-iso.sh`

1. Add optional 4th parameter `boot_iso` to `patch_efiboot()` signature
2. In Step A extraction: try output ISO first, then fall back to `$boot_iso`
3. Log which source was used
4. Stop suppressing osirrox stderr — capture stderr, display on final failure
5. Update call site to pass `$BOOT_ISO` as 4th argument

**Function signature:** `patch_efiboot ISO_PATH NEW_LABEL INST_KS_VALUE [BOOT_ISO]`

**Key context:**
- When `--skip-mkefiboot` is active, efiboot.img in the output ISO is identical to the input boot ISO
- The `$BOOT_ISO` variable is available in `stage_assemble_iso()` scope where `patch_efiboot` is called
- After `patch_efiboot` re-injects via xorriso, the file WILL exist in the ISO

## Acceptance
- [ ] `patch_efiboot` accepts optional 4th `boot_iso` parameter
- [ ] Extraction falls back to boot ISO when output ISO extraction fails
- [ ] Info log indicates which source was used for efiboot.img
- [ ] osirrox errors are captured and displayed on failure (not swallowed)
- [ ] Call site passes `$BOOT_ISO` as 4th argument

## Done summary
Added optional 4th parameter `boot_iso` to `patch_efiboot()` with fallback extraction logic: tries output ISO first, falls back to original boot ISO when efiboot.img is not a visible ISO 9660 entry (as happens with --skip-mkefiboot). osirrox stderr is now captured and displayed on failure instead of being swallowed. Call site updated to pass $BOOT_ISO.
## Evidence
- Commits: 89fd3781c7b85d68ea3d00de9af09f01acedb495
- Tests: manual: reviewed diff for correctness, RP code review SHIP
- PRs: