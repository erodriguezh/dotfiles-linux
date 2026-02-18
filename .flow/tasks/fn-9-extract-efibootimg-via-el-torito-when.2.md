# fn-9-extract-efibootimg-via-el-torito-when.2 Update iso/README.md for El Torito extraction fallback

## Description

Update `iso/README.md` section "mkksiso fails with losetup / mkefiboot error" (~lines 215-244) to describe the three-tier efiboot.img extraction fallback.

**Size:** S
**Files:** `iso/README.md`

### Approach

Update step 1 in the numbered list to explain:
- The three-tier extraction fallback chain (output ISO filesystem -> boot ISO filesystem -> El Torito boot catalog)
- Why El Torito extraction is needed: Fedora 43 stores the EFI boot image only in the El Torito boot catalog / appended partition, not as a visible ISO 9660 filesystem entry
- Brief explanation of El Torito concept (hidden boot partitions vs visible directory entries)

Follow the existing documentation style in `iso/README.md` — concise, factual, with code formatting for commands.

## Acceptance

- [ ] Step 1 updated to describe three-tier extraction fallback
- [ ] Explains WHY: Fedora 43 stores EFI image only in El Torito boot catalog
- [ ] El Torito concept explained briefly (hidden partition vs filesystem entry)
- [ ] Consistent with surrounding documentation style

## Done summary
Updated iso/README.md step 1 in the "mkksiso fails with losetup / mkefiboot error" section to describe the three-tier efiboot.img extraction fallback chain (output ISO filesystem, boot ISO filesystem, El Torito boot catalog) with a brief explanation of why Fedora 43 requires El Torito extraction and what El Torito is.
## Evidence
- Commits: 56d850229ed8e2f59e3a6f7a1b71511f5ae2f40d, f1926b6764e21fd397e24731132f3945666e443c
- Tests: documentation review via RepoPrompt
- PRs: