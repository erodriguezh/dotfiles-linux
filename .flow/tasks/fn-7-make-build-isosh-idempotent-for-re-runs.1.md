# fn-7-make-build-isosh-idempotent-for-re-runs.1 Remove stale output ISO before mkksiso and update docs

## Description
Add `rm -f` cleanup for the output ISO and its `.sha256` sidecar before the first `mkksiso` invocation in `stage_assemble_iso()`. Update docs to reflect that re-runs are safe.

**Size:** S
**Files:** `iso/build-iso.sh`, `iso/README.md`, `README.md`

## Approach

- Follow the existing pattern at `iso/build-iso.sh:1436` (retry path already does `rm -f "$output_iso"`)
- Add conditional `info` log when a previous build is detected (matches logging style used throughout the script)
- Also clean `${output_iso}.sha256` to prevent stale checksums surviving a rebuild
- Keep the retry path cleanup at L1436 as-is (harmless defense-in-depth)

## Key context

- `mkksiso` has NO `--force`/`--overwrite` flag — confirmed from lorax source code (`os.path.exists()` check at ~L488 of `mkksiso.py`)
- The `rm -f` + rebuild pattern is used by every open-source project that scripts mkksiso (Red Hat microshift-demos, etc.)
- The `.sha256` sidecar at L1679 uses `>` redirect (would overwrite), but it never runs if mkksiso fails first
## Acceptance
- [ ] `rm -f "$output_iso" "${output_iso}.sha256"` added after output_iso is defined (~L1334) and before staging/mkksiso work begins
- [ ] Conditional info log: `Removing previous build: $(basename "$output_iso")` when file exists
- [ ] Retry path `rm -f` at L1436 remains unchanged
- [ ] `iso/README.md` troubleshooting section has entry explaining re-run behavior (mkksiso has no --force, script auto-removes stale output)
- [ ] `README.md` Path B section notes that re-running build-iso.sh is safe
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
