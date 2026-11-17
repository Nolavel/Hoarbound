---
paths:
  - "tests/**"
  - "tools/ci/**"
  - "tools/runtime/**"
---
# Running Godot suites and probes here

- **VERIFIED 2026-11-17:** a suite run is `godot --headless --script tests/systems/<suite>.gd`. Exit 0 is pass. `push_error` plus `quit(1)` is the failure path (#209, #288).
- **VERIFIED 2026-11-17:** after `main` changes texture import settings, suites fail with `Unable to open file: res://.godot/imported/…ctex`. That is a stale import cache, not a code bug: run `godot --headless --import` once.
- **VERIFIED 2026-11-17:** a new test must fail on the old code. Stash only the fix (`git stash push <file>`), run, then restore.
  - Pin design constants in the test (e.g. the flare's 30-minute rating). A missing property on old code makes the run hang instead of fail.
- **VERIFIED 2026-11-17:** throwaway probes live in `.probe_tmp/` (excluded through `.git/info/exclude`). Lavapipe frames go through `xvfb-run` (`tools/ci/render.sh`); the gauge capture is `tools/runtime/capture_backpack_load_banner.gd -- <out_dir>`.
- **VERIFIED 2026-11-17:** `Parameter "material" is null` errors in headless player suites are pre-existing noise; they appear on old and new code alike.
- New `.gd` files get a `.uid` on first import: commit it with the file.
- `tools/ci/check_runtime_construction.py` is a ratchet: no new visual `.new()` construction in `scripts/` or `world/`.
