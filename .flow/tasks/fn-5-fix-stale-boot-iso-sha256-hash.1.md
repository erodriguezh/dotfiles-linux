# fn-5-fix-stale-boot-iso-sha256-hash.1 Update boot.iso hash and URL

## Description

Update the two hardcoded constants in `iso/build-iso.sh` (lines 35-36):

1. Change `BOOT_ISO_URL` from:
   ```
   https://download.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/os/images/boot.iso
   ```
   to:
   ```
   https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-43-1.6.iso
   ```

2. Change `BOOT_ISO_SHA256` from:
   ```
   2bdf3826f0b5cf8f3e65e1ee3716c07e3e980f9e08ab30beb08d6a4e28745089
   ```
   to:
   ```
   f4d06a40ce4fb4a84705e1a1f01ca1328f95a2120d422ba5f719af5df62d0099
   ```

## Files to modify

- `iso/build-iso.sh` — lines 35-36 only

## Acceptance Criteria

- [ ] Both constants updated
- [ ] `shellcheck iso/build-iso.sh` passes
- [ ] No other changes to the file
