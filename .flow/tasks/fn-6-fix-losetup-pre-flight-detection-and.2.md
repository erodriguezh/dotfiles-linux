## Description

Fix `_verify_no_duplicate_inst_ks()` (L1228-1287) and expand `patch_efiboot_label()` (L842-1046) to handle Fedora 43 UEFI-only ISOs correctly.

**Three bugs discovered:**

1. **BIOS config lookup uses wrong paths**: Checks `isolinux/isolinux.cfg` and `syslinux/syslinux.cfg`, which don't exist on Fedora 43 (dropped in F37). Must use `boot/grub2/grub.cfg` / `boot/grub/grub.cfg`.

2. **Missing ISO-level EFI check**: The function checks efiboot.img's *internal* grub.cfg but not the ISO filesystem's `EFI/BOOT/grub.cfg` (optical disc UEFI boot path). mkksiso's `EditGrub2()` modifies both.

3. **No `inst.ks=` in efiboot.img when `--skip-mkefiboot`**: mkksiso's `RebuildEFIBoot()` is skipped entirely, leaving efiboot.img untouched — no `inst.ks=` injected, old `hd:LABEL=` references remain. Current `patch_efiboot_label` only fixes `search --label` lines, not `hd:LABEL=` or `inst.ks=` injection.

**Size:** M
**Files:** `iso/build-iso.sh` (primary), `iso/README.md` (docs)

## Approach

### A. Fix BIOS config candidates (L1233-1248)

Replace the candidate list following mkksiso's `known_configs`:
- `/boot/grub2/grub.cfg` (Fedora 43 standard — GRUB2 BIOS)
- `/boot/grub/grub.cfg` (fallback for older lorax)
- Keep `/isolinux/isolinux.cfg` and `/syslinux/syslinux.cfg` as trailing fallbacks for older ISOs

When NO BIOS candidate is found: **warn** (not hard-fail). Surface Go 3 is UEFI-only; BIOS boot is optional.

### B. Add ISO-level EFI config check — **required**

Extract `/EFI/BOOT/grub.cfg` from the ISO filesystem using `osirrox`. This is the optical disc UEFI boot path. Run `_assert_no_dup_inst_ks_in_file` on it.

**Hard-fail** if missing — mkksiso's `EditGrub2()` always modifies this file. If absent, mkksiso failed.

Probe `/EFI/BOOT/BOOT.conf` (Apple EFI) as warn-only diagnostic.

### C. Restructure verification timing

Split `_verify_no_duplicate_inst_ks` into two functions:
- **`_verify_inst_ks_iso_configs(iso_path)`**: Check ISO-level configs (BIOS GRUB2 warn-only + `/EFI/BOOT/grub.cfg` required). Always runs pre-patch at L1289.
- **`_verify_inst_ks_efiboot(iso_path)`**: Check efiboot.img internal grub.cfg. Always runs once at the end — after optional `patch_efiboot` if `--skip-mkefiboot`, or directly if mkefiboot ran normally. Call order: pre-patch ISO-level checks → optional patch → efiboot verification.
- **Post-rewrite spot-check**: After xorriso rewrites the ISO in `patch_efiboot`, re-extract `/EFI/BOOT/grub.cfg` and confirm `inst.ks=` is still present. Guards against xorriso regressing ISO-level configs.

### D. Expand `patch_efiboot_label` → `patch_efiboot`

Rename function. New signature: `patch_efiboot <iso_path> <new_label> <inst_ks_value>`.

**D.1 — Derive `inst.ks=` value from ISO (don't hardcode)**:
Before calling `patch_efiboot`, extract the ISO-level `/EFI/BOOT/grub.cfg` (already modified by mkksiso). Parse the full `inst.ks=...` argument from a `linux`/`linuxefi` line (e.g., `inst.ks=hd:LABEL=SurfaceLinux-43:/ks.cfg`). Pass this exact value to `patch_efiboot`. This avoids hardcoding the on-ISO kickstart filename.

Helper: `_extract_inst_ks_from_iso(iso_path)` — uses osirrox to extract `/EFI/BOOT/grub.cfg`, scan installer stanzas (those containing `inst.stage2=`), parse tokens from the logical `linux`/`linuxefi` cmdline (joining `\` continuations), require exactly one distinct `inst.ks=...` value across all installer stanzas. Strip trailing `\`/whitespace. Hard-fail if missing or if multiple distinct values found.

**D.2 — Label replacement in known patterns (NOT blanket)**:
Extend the python3 replacement script to target these specific token forms:
- `search --label <old>` / `search -l <old>` (existing Phase 1 patterns, handles quoted/unquoted)
- `hd:LABEL=<old>` — normalize the label value to `<new_label>` in all `hd:LABEL=` tokens (scoped to `inst.stage2=` and `inst.ks=` arguments). This approach does not depend on finding the old label via `search` lines — it directly normalizes `hd:LABEL=` tokens.

Do NOT use blanket `re.sub(old_label, new_label, content)`.

**D.3 — `inst.ks=` injection into installer stanzas only**:
Inject `inst.ks=` only into GRUB stanzas that contain `inst.stage2=`. Do NOT inject into rescue/troubleshooting/memtest entries.

**Logical stanza parsing**: For each `menuentry` block, find the `linux`/`linuxefi` command. Join continuation lines ending with `\` into a single logical cmdline. The logical cmdline extends from the `linux`/`linuxefi` keyword until a line that does NOT end with `\` (or the next GRUB directive). Verify and inject on this joined logical cmdline, then split back into physical lines preserving original continuation style.

**D.4 — Post-patch verification**:
After mcopy write-back, re-extract and verify:
- Old label count == 0 in known patterns (`search --label`/`-l`, `hd:LABEL=`)
- New label count >= 1
- Exactly one `inst.ks=` per installer `linux`/`linuxefi` logical stanza
- No installer stanza (containing `inst.stage2=`) lacks `inst.ks=`

### E. Updated call site (L1289-1299)

```
# Pre-patch: verify ISO-level configs
_verify_inst_ks_iso_configs "$output_iso"

# Patching (if needed)
if [[ "$needs_efi_patch" == true ]]; then
    inst_ks_value="$(_extract_inst_ks_from_iso "$output_iso")"
    patch_efiboot "$output_iso" "SurfaceLinux-43" "$inst_ks_value"
fi

# Post-patch: verify efiboot.img internal grub.cfg
_verify_inst_ks_efiboot "$output_iso"
```

### F. Update `iso/README.md`

- Troubleshooting: remove obsolete isolinux reference
- Stage 11 description: three-layer verification model:
  1. ISO-level `/EFI/BOOT/grub.cfg` — required, verified pre-patch
  2. ISO-level BIOS GRUB2 (`boot/grub2/grub.cfg`) — best-effort, warn if missing
  3. efiboot.img internal grub.cfg — verified post-patch, USB UEFI boot path
- Document that `patch_efiboot` injects `inst.ks=` and updates `hd:LABEL=` when `--skip-mkefiboot` is active
- Keep diffs surgical

## Key context

- Fedora 37+ removed isolinux/syslinux — BIOS boot uses GRUB2 via `eltorito.img` + `boot/grub2/grub.cfg`
- mkksiso `EditGrub2()` modifies: `EFI/BOOT/grub.cfg`, `boot/grub2/grub.cfg`, `boot/grub/grub.cfg`, `EFI/BOOT/BOOT.conf`
- mkksiso `EditIsolinux()` gracefully skips when `isolinux.cfg` is absent
- `--skip-mkefiboot` skips `RebuildEFIBoot()` entirely — efiboot.img is untouched
- mkksiso injects: `inst.ks=hd:LABEL=<volid>:/<ks_basename>` — derive from ISO, don't hardcode
- GRUB configs may use `\` line continuations — process logical stanzas
- `osirrox` paths need leading `/`

## Acceptance

- [ ] BIOS config verification checks `/boot/grub2/grub.cfg`, `/boot/grub/grub.cfg`, then legacy isolinux/syslinux as fallbacks
- [ ] Missing BIOS config is a **warning**, not a hard-fail
- [ ] ISO-level `/EFI/BOOT/grub.cfg` is **required** — hard-fail if missing
- [ ] `/EFI/BOOT/BOOT.conf` probed as warn-only diagnostic
- [ ] Verification split: `_verify_inst_ks_iso_configs` pre-patch, `_verify_inst_ks_efiboot` post-patch
- [ ] `patch_efiboot_label` renamed to `patch_efiboot` — accepts `inst_ks_value` parameter
- [ ] `inst.ks=` value derived from ISO-level EFI grub.cfg (what mkksiso injected), not hardcoded
- [ ] Label replacement targets known patterns only (`search --label`/`-l`, `hd:LABEL=`), NOT blanket global replace
- [ ] `inst.ks=` injected only into installer stanzas (those containing `inst.stage2=`)
- [ ] GRUB `\` line continuations handled — logical stanza = `linux`/`linuxefi` command + continuation lines joined
- [ ] Post-patch verification: efiboot.img has correct label AND exactly one `inst.ks=` per installer stanza
- [ ] Post-rewrite spot-check: ISO-level `EFI/BOOT/grub.cfg` still intact after xorriso rewrite
- [ ] `implantisomd5` + sha256 regenerated after patching
- [ ] `iso/README.md` updated with three-layer verification model + `inst.ks=` injection docs
- [ ] `shellcheck iso/build-iso.sh` passes
- [ ] Diffs kept surgical — no unrelated refactors in Stage 11
