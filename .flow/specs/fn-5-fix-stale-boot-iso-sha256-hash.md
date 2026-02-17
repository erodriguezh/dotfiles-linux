# fn-5: Fix stale boot.iso SHA256 hash

## Problem

The ISO builder fails at Stage 1 (boot.iso download) with a SHA256 mismatch:

```
[ERROR] SHA256 mismatch for boot.iso
[ERROR]   expected: 2bdf3826f0b5cf8f3e65e1ee3716c07e3e980f9e08ab30beb08d6a4e28745089
[ERROR]   actual:   f4d06a40ce4fb4a84705e1a1f01ca1328f95a2120d422ba5f719af5df62d0099
```

The hardcoded `BOOT_ISO_SHA256` in `iso/build-iso.sh:36` is stale. The official Fedora 43
CHECKSUM file (`Fedora-Everything-43-1.6-x86_64-CHECKSUM`) confirms the correct hash is
`f4d06a40ce4fb4a84705e1a1f01ca1328f95a2120d422ba5f719af5df62d0099`.

## Root Cause

The `BOOT_ISO_URL` uses `download.fedoraproject.org` (a mirror redirector). The boot.iso
served by mirrors matches the official Fedora 43 release compose (43-1.6), but the hardcoded
hash was either from a pre-release compose or was incorrect from the start.

## Fix

### Task 1: Update boot.iso hash and URL

**Changes to `iso/build-iso.sh`:**

1. **Update `BOOT_ISO_SHA256`** (line 36) to the correct hash:
   ```
   f4d06a40ce4fb4a84705e1a1f01ca1328f95a2120d422ba5f719af5df62d0099
   ```

2. **Update `BOOT_ISO_URL`** (line 35) to use:
   - `dl.fedoraproject.org` (direct Fedora server) instead of `download.fedoraproject.org` (mirror redirector) for consistent content
   - The versioned filename path for reproducibility:
   ```
   https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-43-1.6.iso
   ```

**Rationale for URL change:** The versioned path at `dl.fedoraproject.org` serves the exact
release compose (43-1.6) directly from Fedora infrastructure. This eliminates two sources of
inconsistency: (a) mirror redirector serving stale/different content, and (b) the unversioned
`boot.iso` filename that could silently change across composes.

### Acceptance Criteria

- [ ] `BOOT_ISO_SHA256` updated to `f4d06a40ce4fb4a84705e1a1f01ca1328f95a2120d422ba5f719af5df62d0099`
- [ ] `BOOT_ISO_URL` points to versioned path on `dl.fedoraproject.org`
- [ ] Cached ISO path stays as `fedora-boot-43.iso` (internal name, no user impact)
- [ ] No other code changes needed — verification logic in `stage_download_boot_iso()` is correct
- [ ] ShellCheck passes on modified file
