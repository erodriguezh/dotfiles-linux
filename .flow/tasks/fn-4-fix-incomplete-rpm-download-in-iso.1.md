# fn-4-fix-incomplete-rpm-download-in-iso.1 Add --alldeps to dnf5 download and update docs

## Description
`dnf5 download --resolve` in `stage_download_rpms()` (`iso/build-iso.sh:449`) resolves against the container's installed RPM database, skipping packages already present in the `fedora:43` base image. Add `--alldeps` to force complete dependency resolution, add `--setopt=install_weak_deps=False` to match kickstart's `--excludeWeakdeps`, fix misleading comments, and update docs.

**Size:** M
**Files:** `iso/build-iso.sh`, `iso/Containerfile`, `iso/README.md`, `.github/workflows/build-iso.yml`

## Approach

- Add `--alldeps --setopt=install_weak_deps=False` to `dnf5 download` at `iso/build-iso.sh:449-454`
- Fix comments in `stage_validate_repo()` at `iso/build-iso.sh:516-541` — `--assumeno` returns exit 0 on successful resolution per dnf5 source, not non-zero as comments claim. The code logic is correct; only comments need fixing
- Update Containerfile comment at line 4-6: clarify that `--alldeps` is required, not just `--resolve`
- Update `iso/README.md:117` Stage 3 description: document `--alldeps` and weak-dep exclusion
- Update `iso/README.md:121` Stage 5 description: fix `--assumeno` exit-code explanation
- Add `-v2` suffix to CI cache key at `.github/workflows/build-iso.yml:79` to bust stale cache

## Key context

- dnf5 source (`download.cpp`): `--alldeps` sets `load_system_repo(false)`, `--resolve` alone sets it to `true`
- Kickstart uses `%packages --excludeWeakdeps --excludedocs` at `iso/surface-go3-iso.ks:101`
- `--assumeno` exit codes confirmed from dnf5 source: exit 0 on success, exit 1 on resolution failure
- [dnf5 #971](https://github.com/rpm-software-management/dnf5/issues/971): download resolves deps independently per-package (LOW risk, mitigated by Check B install simulation)
- RPM count will increase from ~400 to ~800-1200 with `--alldeps`; weak-dep exclusion keeps it closer to ~800
## Acceptance
- [ ] `stage_download_rpms` uses `dnf5 download --resolve --alldeps --setopt=install_weak_deps=False`
- [ ] `--validate-only` passes in the build container (both repoclosure and install simulation)
- [ ] Containerfile comment (lines 4-6) updated to mention `--alldeps` requirement
- [ ] `iso/README.md` Stage 3 (line 117) documents `--alldeps` and weak-dep exclusion
- [ ] `iso/README.md` Stage 5 (line 121) accurately describes `--assumeno` exit-code behavior
- [ ] Comments in `stage_validate_repo` (lines 516-541) fixed to reflect actual `--assumeno` semantics
- [ ] CI cache key (`.github/workflows/build-iso.yml:79`) has version suffix to bust stale cache
## Done summary
Added --alldeps and --setopt=install_weak_deps=False to dnf5 download in stage_download_rpms to fix incomplete RPM downloads. Updated comments, docs (Containerfile, README), and CI cache key (-v2 suffix) for consistency.
## Evidence
- Commits: 9afb0e0, f522923
- Tests: RepoPrompt impl review: SHIP verdict
- PRs: