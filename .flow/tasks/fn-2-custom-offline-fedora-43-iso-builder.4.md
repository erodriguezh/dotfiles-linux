## Description

Update README.md to document the new custom ISO install path alongside the existing manual kickstart path. Create `iso/README.md` with build/development documentation.

**Size:** M
**Files:** `README.md`, `iso/README.md`

## Approach

### README.md restructuring

Add a new section near the top (after "Hardware Target") that presents two installation paths:

**New section: "Installation"**
- Brief comparison table: Path A (Manual) vs Path B (Custom ISO)
- Path A: current flow (download Everything ISO, edit kickstart, OEMDRV, boot, then run install.sh)
- Path B: new flow (build or download custom ISO, flash to USB, boot, done)
- Link to detailed steps for each

**Restructure existing sections:**
- Move current "USB Preparation" through "Post-Install" under a "Path A: Manual Installation" subsection
- Add "Path B: Custom ISO Installation" subsection with:
  - Prerequisites (Podman for building, or download from GitHub Releases)
  - How to build the ISO locally (with credential input methods)
  - How to flash and boot
  - What happens automatically (all stages run in kickstart %post)
- Update "Quick Reference" to mention both paths

**Preserve:**
- All existing content (just reorganized, not deleted)
- Hardware Target, Hardware Detection, Idempotency, Secure Boot, Log File, References sections (unchanged)
- Stage table and dependency info (still applies to Path A and to `install.sh --only` reruns after ISO install)

**Add notes:**
- After ISO install, `install.sh` still works for re-running individual stages (`--only fonts`, `--only theme`, etc.)
- First `nvim` launch needs WiFi for plugin sync
- ISO credentials are baked in at build time (no runtime prompts) — recommend `--password-hash-file` for security

### iso/README.md (new file)

Developer documentation for the ISO build system:
- Overview and architecture (reference epic spec diagram)
- Prerequisites: Podman, ~5 GB disk space, network for package downloads
- Credential input methods with clear matrix:

  | Flags | Credentials used | mkksiso run? |
  |-------|-----------------|--------------|
  | `--username X --password-hash-file Y` | Real | Yes |
  | `--test` | Dummy | Yes |
  | `--validate-only` | Dummy or none | No |
  | `--test --validate-only` | Dummy | No |

- Password hash generation: `openssl passwd -6 > hash.txt`
- How it works (step by step: expand groups, download packages, create repo, repoclosure, download assets, generate theme, mkksiso)
- GitHub Actions: how CI validates builds (repoclosure check), how to trigger manual build + release
- Customization: changing keyboard layout, timezone, adding packages
- Troubleshooting: common build failures, disk space issues, COPR repo unavailability
- How to test: QEMU smoke test command
- Security: never upload ISOs with real credentials to public releases

### Style guidelines
- Follow existing README.md style: tables for hardware/stages, bash code blocks with comments, step numbers
- Follow commit message convention: `docs(iso): ...` or `docs: ...`
- Do NOT add emojis (not used in existing docs)

## Key context

- The existing README is 254 lines. Restructuring should keep it similar length (reorganize, don't bloat).
- Commit message style from recent history: `fix(waybar):`, `docs: switch to OEMDRV`, `docs(issues):`.
- The Stages table and dependencies section still applies — stages are what install.sh does, and after an ISO install the user can still run individual stages.
- `kickstart/surface-go3.ks` inline comments should get a brief "see also: `iso/surface-go3-iso.ks` for the custom ISO kickstart" note.

## Done summary
Restructured README.md with dual install paths (Path A: manual kickstart, Path B: custom ISO) including comparison table, and created iso/README.md with comprehensive build system developer documentation covering architecture, credential handling, build stages, CI workflow, customization, troubleshooting, and security. Added cross-reference from kickstart/surface-go3.ks to the ISO kickstart.
## Evidence
- Commits: a9f6e67, 38ba8b3139ef804d2fdf186caf95c7bfb9a207db
- Tests: manual review of documentation accuracy against build-iso.sh and kickstart files
- PRs: