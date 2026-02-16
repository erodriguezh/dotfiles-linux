# Fix dnf5 repo validation in ISO builder

## Problem

`iso/build-iso.sh` Stage 5 (`stage_validate_repo()`, lines 496-504) uses `dnf5 --setopt=local-only.baseurl=...` to create an ad-hoc repo for offline validation. **dnf5 does not support creating new repos via `--setopt`** — this was a dnf4-only feature. dnf5's `--setopt=REPO_ID.key=value` can only modify existing repos, not create new ones.

Error: `No matching repositories for local-only, local-only, local-only, *, local-only`

This blocks:
- CI validation (`--validate-only`) on every PR
- Full ISO builds (manual and workflow_dispatch)

## Fix

Replace `--setopt`-based ad-hoc repo with `--repofrompath` (canonical dnf5 approach) and add proper `repoclosure` check.

**`--repofrompath=REPO_ID,PATH`** creates a transient repo for a single command — no temp files, no cleanup needed. Combined with `--repo=REPO_ID` (restricts to only that repo) and `--setopt=reposdir=/dev/null` (prevents loading system repos).

Two complementary checks:
1. `dnf5 repoclosure` — verifies every RPM's `Requires:` is satisfiable within the repo (internal consistency)
2. `dnf5 install --assumeno` — verifies the specific package list can be resolved (completeness)

### Critical: `--assumeno` exit code

Under `set -Eeuo pipefail` + ERR trap, non-zero exit kills the script. The `--assumeno` flag may exit 1 (user declined transaction) even when resolution succeeds. The fix must capture the exit code explicitly or use an alternative approach.

## Scope

- **In scope**: `stage_validate_repo()` in `iso/build-iso.sh`, iso/README.md stage 5 description
- **Out of scope**: Other stages, temp file consolidation, DRY refactors (dedup loop)

## Quick commands

```bash
# Build container and run validate-only (tests the fix)
podman build -t surface-iso-builder -f iso/Containerfile iso/
podman run --privileged --rm -v "$(pwd):/build" surface-iso-builder /build/iso/build-iso.sh --validate-only
```

## Acceptance

- [ ] `stage_validate_repo()` uses `--repofrompath` instead of `--setopt` for repo creation
- [ ] `dnf5 repoclosure` runs as structural integrity check
- [ ] `dnf5 install --assumeno` runs with explicit exit-code handling (no false failures under `set -e`)
- [ ] `--validate-only` passes in the build container
- [ ] iso/README.md updated to reflect the new validation approach
- [ ] No temp files created/leaked by the validation stage

## References

- [dnf5(8) --repofrompath](https://dnf5.readthedocs.io/en/latest/dnf5.8.html)
- [dnf5 repoclosure plugin](https://dnf5.readthedocs.io/en/latest/dnf5_plugins/repoclosure.8.html)
- [GitHub Issue #1082](https://github.com/rpm-software-management/dnf5/issues/1082) — Invalid REPO_ID now errors in dnf5
- [Fedora QA Mediakit Repoclosure Test](https://fedoraproject.org/wiki/QA:Testcase_Mediakit_Repoclosure)
