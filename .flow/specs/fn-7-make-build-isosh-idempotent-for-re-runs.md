# Make build-iso.sh idempotent for re-runs

## Problem

`mkksiso` (lorax) refuses to write to an output path that already exists and has **no `--force` or `--overwrite` flag**. When `build-iso.sh` is run twice on the same day, Stage 11 fails:

```
[ERROR] mkksiso failed (exit 1)
ERROR:/build/output/surface-linux-F43-20260218-x86_64.iso already exists
```

The retry path at L1436 already does `rm -f "$output_iso"` before retrying, but the **first** mkksiso invocation (L1406) has no such pre-cleanup. The date-stamped filename guarantees same-day collisions.

## Scope

Minimal — one code change + doc updates:

1. Add `rm -f "$output_iso" "${output_iso}.sha256"` after the output path is defined (~L1334) and before any mkksiso invocation
2. Add conditional info log when removing a previous build
3. Update `iso/README.md` troubleshooting section
4. Update `README.md` Path B with re-run safety note

**Out of scope:**
- Cleaning old date-stamped ISOs (different-day accumulation)
- `createrepo_c --update` optimization (Stage 4 works, just slower)
- Concurrent build locking (unsupported use case)

## Quick commands

```bash
# Build ISO (should succeed on re-runs now)
podman run --privileged --rm -v "$PWD:/build" \
  surface-iso-builder /build/iso/build-iso.sh --username=edu --password-hash-file=/tmp/hash.txt

# Verify idempotency: run twice, second run should not fail
podman run --privileged --rm -v "$PWD:/build" \
  surface-iso-builder /build/iso/build-iso.sh --username=edu --password-hash-file=/tmp/hash.txt
```

## Key context

- mkksiso source (`weldr/lorax` `src/pylorax/cmdline/mkksiso.py` ~L488) explicitly checks `os.path.exists(args.output_iso)` and errors — no workaround flag exists
- `rm -f` before mkksiso is the universal pattern (confirmed in 8/8 GitHub repos using mkksiso in scripts)
- All other stages (1, 6, 7, 8, 9) are already idempotent — Stage 11 is the only blocker
- The retry path at L1436 already uses this exact pattern, confirming it is established in the codebase

## Acceptance

- [ ] Re-running `build-iso.sh` with the same output dir does not fail on "already exists"
- [ ] Info log emitted when removing a previous build
- [ ] `.sha256` sidecar is also cleaned before rebuild
- [ ] Retry path at L1436 remains unchanged (defense-in-depth)
- [ ] `iso/README.md` documents re-run behavior
- [ ] `README.md` Path B notes that re-runs are safe

## References

- `iso/build-iso.sh:1327-1340` — Stage 11 entry, output path construction
- `iso/build-iso.sh:1406-1414` — First mkksiso invocation (no pre-cleanup)
- `iso/build-iso.sh:1436` — Retry path (has `rm -f`, the pattern to replicate)
- `iso/build-iso.sh:1679` — `.sha256` sidecar generation
- [mkksiso docs](https://weldr.io/lorax/mkksiso.html)
- [mkksiso source — exists check](https://github.com/weldr/lorax/blob/master/src/pylorax/cmdline/mkksiso.py)
