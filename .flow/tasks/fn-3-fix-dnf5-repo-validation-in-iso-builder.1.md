# fn-3-fix-dnf5-repo-validation-in-iso-builder.1 Replace --setopt with --repofrompath in stage_validate_repo and update docs

## Description
Fix `stage_validate_repo()` in `iso/build-iso.sh` (lines 477-507) which fails because dnf5 does not support creating ad-hoc repos via `--setopt=REPO_ID.key=value`. Replace with `--repofrompath` — the canonical dnf5 approach for transient repos.

**Size:** S
**Files:** `iso/build-iso.sh`, `iso/README.md`

## Approach

### 1. Replace the dnf5 command block (lines 496-504)

The broken `--setopt` block must be replaced with two complementary checks using `--repofrompath`:

**Check A — `repoclosure` (structural integrity):**
```
dnf5 repoclosure --setopt=reposdir=/dev/null --repofrompath=local-only,"file://${RPM_CACHE}" --repo=local-only
```
- Verifies every RPM's `Requires:` is satisfiable within the local repo
- Exits 0 on success, 1 on unresolved deps — safe under `set -e`

**Check B — `install --assumeno` (completeness):**
```
dnf5 install --assumeno --setopt=reposdir=/dev/null --repofrompath=local-only,"file://${RPM_CACHE}" --repo=local-only "${all_pkgs[@]}"
```
- Verifies the specific combined package list is resolvable
- **Critical**: `--assumeno` may exit non-zero even on successful resolution (user declined). Must handle under `set -e` using the safe shell pattern:

```bash
local install_output
local install_rc=0
if ! install_output="$(dnf5 ... install --assumeno ... 2>&1)"; then
    install_rc=$?
fi
# Only fail on real resolution errors, not "Operation aborted"
if [[ $install_rc -ne 0 ]]; then
    if grep -qE 'Problem:|No match for argument:' <<<"$install_output"; then
        error "Local repo install simulation failed:"
        printf '%s\n' "$install_output"
        exit 1
    fi
fi
```

**Both checks MUST use `--setopt=reposdir=/dev/null`** so only the local repo is visible. All validation logic must operate purely in-memory (shell variables, pipes) — no temporary `.repo` files or log files.

### 2. Update iso/README.md

- Update the Stage 5 description under "How It Works / Build stages (in order)" to describe the dual checks (repoclosure + install simulation) via `--repofrompath`
- Update the overview diagram list item for validation to reflect both checks
- Update any troubleshooting bullet that references the old `--setopt`-based validation approach

## Key context

- `--repofrompath=REPO_ID,PATH` — dnf5 docs: creates transient repo for single command. [dnf5(8)](https://dnf5.readthedocs.io/en/latest/dnf5.8.html)
- `--repo=REPO_ID` — implicitly disables all other repos
- `dnf5-plugins` already installed in Containerfile — provides `repoclosure` command
- Script runs under `set -Eeuo pipefail` with ERR trap (lines 19-20, 70) — every non-zero exit is fatal
- `RPM_CACHE="/build/.cache/rpms"` (line 29) — hardcoded, no spaces
- `repoclosure` does NOT check weak/optional deps by default — no false positives from `--excludeWeakdeps` downloads
## Approach

### 1. Replace the dnf5 command block (lines 496-504)

The broken `--setopt` block must be replaced with two complementary checks using `--repofrompath`:

**Check A — `repoclosure` (structural integrity):**
- Uses `dnf5 repoclosure` with `--repofrompath=local-only,"file://${RPM_CACHE}"` and `--repo=local-only`
- Add `--setopt=reposdir=/dev/null` to prevent loading system repos
- Verifies every RPM's `Requires:` is satisfiable within the local repo
- Exits 0 on success, 1 on unresolved deps — safe under `set -e`

**Check B — `install --assumeno` (completeness):**
- Verifies the specific combined package list (`${all_pkgs[@]}`) is resolvable
- Uses same `--repofrompath` + `--repo` + `reposdir=/dev/null` flags
- **Critical**: `--assumeno` may exit non-zero even on successful resolution (user declined). Must handle this under `set -e` — capture exit code explicitly or use subshell with output parsing
- Pattern: capture output and rc, grep for "Problem:" or "No match for argument:" to distinguish real failures from the expected "Operation aborted" non-zero exit

### 2. Update iso/README.md

- Lines 119-121: update stage 5 description to mention `--repofrompath` and dual checks (repoclosure + install simulation)
- Lines 202-208 (troubleshooting): if this section references `--setopt`, update accordingly

## Key context

- `--repofrompath=REPO_ID,PATH` — dnf5 docs: creates transient repo for single command. [dnf5(8)](https://dnf5.readthedocs.io/en/latest/dnf5.8.html)
- `--repo=REPO_ID` — implicitly disables all other repos (equivalent to `--disablerepo='*' --enablerepo=REPO_ID`)
- `dnf5-plugins` already installed in Containerfile (line 14) — provides `repoclosure` command
- Script runs under `set -Eeuo pipefail` with ERR trap (lines 19-20, 70) — every non-zero exit is fatal
- `RPM_CACHE="/build/.cache/rpms"` (line 29) — hardcoded, no spaces
- `repoclosure` does NOT check weak/optional deps by default — no false positives from `--excludeWeakdeps` downloads
## Acceptance
- [ ] `stage_validate_repo()` uses `--repofrompath=local-only,"file://${RPM_CACHE}"` instead of `--setopt=local-only.*` flags
- [ ] `dnf5 repoclosure` runs with `--setopt=reposdir=/dev/null`, `--repofrompath`, and `--repo=local-only`
- [ ] `dnf5 install --assumeno` runs with same three flags AND explicit exit-code handling (capture rc, grep for "Problem:" / "No match for argument:" to distinguish real failures from --assumeno decline)
- [ ] Both checks use `--setopt=reposdir=/dev/null` so that only the local repo is visible
- [ ] All validation logic is in-memory (no temp .repo files, no temp log files)
- [ ] Comments in `stage_validate_repo()` explain why `--repofrompath` is used (dnf5 does not support ad-hoc repo creation via --setopt)
- [ ] iso/README.md Stage 5 description (under "How It Works / Build stages") updated to describe dual checks via `--repofrompath`
- [ ] iso/README.md overview list and troubleshooting updated if they reference old --setopt approach
- [ ] `--validate-only` mode completes successfully in build container
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
