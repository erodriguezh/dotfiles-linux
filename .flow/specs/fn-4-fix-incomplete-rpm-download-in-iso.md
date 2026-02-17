# Fix incomplete RPM download in ISO builder

## Problem

`iso/build-iso.sh` Stage 3 (`stage_download_rpms`, line 449) uses `dnf5 download --resolve` without the `--alldeps` flag. By default, `--resolve` resolves dependencies against the container's installed RPM database — packages already present in the `fedora:43` base image (glibc, bash, systemd, coreutils, filesystem, etc.) are silently skipped. The resulting local repo is missing hundreds of base-system RPMs.

Stage 5 (`stage_validate_repo`, line 509) then correctly catches this: `dnf5 repoclosure` finds unresolved `Requires:` and exits 1.

Error: `Command failed (exit 1) at line 509: dnf5 repoclosure --setopt=reposdir=/dev/null --repofrompath=local-only,"file://${RPM_CACHE}" --repo=local-only`

This blocks both CI validation (`--validate-only`) and full ISO builds.

## Root cause

Confirmed from dnf5 source (`download.cpp`): when `--resolve` is used WITHOUT `--alldeps`, the system repo is loaded (`context.set_load_system_repo(true)`), skipping already-installed packages. With `--alldeps`, the system repo is NOT loaded, so ALL transitive deps are downloaded regardless of container state.

## Fix

1. **Add `--alldeps` to `dnf5 download`** (`build-iso.sh:449`) — forces complete dependency resolution
2. **Add `--setopt=install_weak_deps=False`** — aligns download with kickstart's `%packages --excludeWeakdeps` to avoid downloading hundreds of unnecessary weak-dep RPMs that would bloat the ISO
3. **Fix misleading comments** in `stage_validate_repo` — `--assumeno` returns exit 0 on successful resolution (not non-zero as comments suggest); the code logic is correct but comments are wrong
4. **Update Containerfile comment** (line 5) — current text says `--resolve` alone captures all transitive deps, which is the bug being fixed
5. **Update iso/README.md** Stage 3 description (line 117) — document `--alldeps` and `--setopt=install_weak_deps=False`
6. **Bust CI cache** — add `-v2` suffix to cache key in `.github/workflows/build-iso.yml:79` so the first `--alldeps` build gets a clean RPM cache

## Scope

**In scope**: `stage_download_rpms()`, comments in `stage_validate_repo()`, Containerfile comment, iso/README.md stage 3+5 descriptions, CI cache key

**Out of scope**: RPM cache pruning (stale version accumulation), replacing `--assumeno` with `--downloadonly` in Check B (current logic works correctly), `createrepo_c --update` optimization, issue #971 workarounds

## Known issues

- [dnf5 #971](https://github.com/rpm-software-management/dnf5/issues/971): `download --resolve` resolves deps independently per-package, not as a transaction. Conditional deps like `(foo if bar)` may be missed. LOW priority, unlikely to affect this package set. The install simulation (Check B) provides a safety net.

## Quick commands

```bash
# Build container and run validate-only (tests the fix)
podman build -t surface-iso-builder -f iso/Containerfile iso/
podman run --privileged --rm -v "$(pwd):/build" surface-iso-builder /build/iso/build-iso.sh --validate-only

# Check RPM count (expect ~800-1200 with --alldeps, was ~400 before)
podman run --privileged --rm -v "$(pwd):/build" surface-iso-builder \
    bash -c 'find /build/.cache/rpms -name "*.rpm" | wc -l'
```

## Acceptance

- [ ] `dnf5 download` in `stage_download_rpms` uses `--alldeps` and `--setopt=install_weak_deps=False`
- [ ] `--validate-only` passes: both repoclosure and install simulation succeed
- [ ] Containerfile comment updated to reflect `--alldeps` requirement
- [ ] iso/README.md Stage 3 and Stage 5 descriptions updated
- [ ] CI cache key busted (version suffix added) for clean first build
- [ ] Comments in `stage_validate_repo` accurately describe `--assumeno` exit-code behavior

## References

- [dnf5 download command](https://dnf5.readthedocs.io/en/latest/commands/download.8.html) — `--alldeps` flag
- [dnf5 #971](https://github.com/rpm-software-management/dnf5/issues/971) — independent per-package resolution
- [dnf5 repoclosure](https://dnf5.readthedocs.io/en/latest/dnf5_plugins/repoclosure.8.html) — exit codes
- [Fedora QA Repoclosure Test](https://fedoraproject.org/wiki/QA:Testcase_Mediakit_Repoclosure) — validation methodology
