## Description

Add a GitHub Actions workflow that validates the ISO build pipeline on every push/PR and optionally produces a downloadable ISO artifact via manual dispatch.

**Size:** M
**Files:** `.github/workflows/build-iso.yml`

## Approach

### Workflow triggers
- `push` to main branch (paths: `iso/**`, `lib/**`, `kickstart/**`, `config/**`, `templates/**`, `colors.toml`)
- `pull_request` (same paths)
- `workflow_dispatch` with inputs:
  - `upload_artifact` (boolean, default: false) — upload ISO as workflow artifact
  - `create_release` (boolean, default: false) — create GitHub Release with ISO

### Job: `build-iso`

**Runner:** `ubuntu-latest`

**Steps:**

1. **Free disk space** — Use `jlumbroso/free-disk-space@v1.3.1` to reclaim ~30 GB. Settings: `android: true`, `dotnet: true`, `haskell: true`, `large-packages: true`, `docker-images: true`, `tool-cache: false`, `swap-storage: true`. This MUST run BEFORE checkout.

2. **Checkout** — `actions/checkout@v4`

3. **Cache RPM repo** — `actions/cache@v4` with:
   - `path: .cache/rpms`
   - `key: fedora43-rpms-${{ hashFiles('lib/03-packages.sh', 'lib/02-kernel.sh') }}`
   This avoids re-downloading 500+ MB of RPMs when package lists haven't changed.

4. **Cache boot ISO** — `actions/cache@v4` with:
   - `path: .cache/isos`
   - `key: fedora43-boot-iso`

5. **Install Podman** — Standard ubuntu-latest has Podman. Verify version, install latest if needed.

6. **Build container** — `sudo podman build -t surface-iso-builder iso/`

7. **Run build (validate mode)** — For push/PR: `sudo podman run --privileged --rm -v ${{ github.workspace }}:/build surface-iso-builder /build/iso/build-iso.sh --test --validate-only`. This validates minimal-environment expansion, RPM download, repo creation, and repoclosure check, but skips boot.iso download, asset downloads (binaries, fonts, lazy.nvim), theme generation, and mkksiso assembly. Note: NO `:Z` suffix on volume mount (not needed on ubuntu-latest, causes warnings).
<!-- Updated by plan-sync: fn-2-custom-offline-fedora-43-iso-builder.1 validate-only stops after stage 5 (repoclosure), not after asset downloads -->

8. **Run build (full, on dispatch)** — When `workflow_dispatch` with `upload_artifact=true`: run full build with `--test` credentials. Produces actual ISO.

9. **Report disk usage** — `df -h` after build to monitor space consumption.

10. **Upload artifact** — Conditional on dispatch input. Use `actions/upload-artifact@v4` with `compression-level: 0` (ISO is already compressed), `retention-days: 7`.

11. **Create release** — Conditional on dispatch input. Use `softprops/action-gh-release@v2` with tag from run number or date. Generate SHA256 checksum alongside ISO.

### Repoclosure validation in CI

The validate-only mode MUST include an automated correctness check (from task .1's `--validate-only` behavior):
- The build script's `stage_validate_repo()` runs `dnf5 --setopt=reposdir=/dev/null --setopt=local-only.baseurl=file://<rpm-cache> install --assumeno --repo=local-only <all-pkgs>` inline (no nested container needed)
- This verifies `dnf5 install --assumeno` can resolve ALL expanded packages without external repos
- This goes beyond "dnf5 download succeeded" — it proves the repo is self-contained
<!-- Updated by plan-sync: fn-2-custom-offline-fedora-43-iso-builder.1 uses inline dnf5 --setopt repoclosure, not a nested container -->

### Permissions
```yaml
permissions:
  contents: write  # needed for release creation
```

### Caching strategy

Cache paths match the build script's `.cache/` directory structure:
- `.cache/rpms/` — local RPM repo (500 MB+, key changes when package lists change)
- `.cache/isos/` — Fedora boot.iso (~800 MB, rarely changes)

These paths are in the workspace mount (not container `/tmp/`), so GitHub Actions can see and cache them.

## Key context

- Podman on ubuntu-latest: use `sudo podman` (rootful) for `--privileged` support.
- Do NOT use `:Z` SELinux volume suffix on ubuntu-latest (not an SELinux host, may cause warnings).
- `jlumbroso/free-disk-space` must run early to reclaim ~30 GB on the 14 GB default runner.
- GitHub Release assets max 2 GiB per file. ISO target is ~1.5 GB.
- `actions/upload-artifact@v4`: `compression-level: 0` is critical for ISOs (already compressed).
- Do NOT use GitHub Actions `container:` directive for Podman. Use explicit `podman run` in `run:` steps.
- Workflow should NOT embed real credentials. Always use `--test` for CI builds.
- CI builds with real credentials should only happen via workflow_dispatch with repository secrets.

## Acceptance

- [x] Workflow triggers on push/PR for relevant paths
- [x] `--validate-only` mode runs on push/PR (repoclosure check)
- [x] Full build with `--test` runs on manual dispatch
- [x] RPM and boot ISO caching configured
- [x] Optional artifact upload and GitHub Release creation
- [x] YAML validates successfully

## Done summary
Added GitHub Actions workflow (.github/workflows/build-iso.yml) that validates the ISO build pipeline on push/PR via --validate-only mode and optionally produces a full ISO artifact or GitHub Release via manual dispatch with test credentials.
## Evidence
- Commits: 93e81962e33a10d6e500e6f6a23f3b7bfefb5e10, 44aa38167f233f22df61b571c28c0e98d7076e60
- Tests: python3 -c 'import yaml; yaml.safe_load(...)' (YAML validation)
- PRs: