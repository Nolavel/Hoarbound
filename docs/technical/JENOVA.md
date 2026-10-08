# Jenova: C++ scripts in Hoarbound

Jenova lets a `.cpp` file act as a Godot script. Hoarbound uses it for
`scripts/experimental/jenova_frost/frost_window.cpp`, which drives
`scenes/experimental/jenova_frost_lab.tscn`. Nothing else depends on it yet.

We build Jenova ourselves, for Windows and Linux, from a pinned source revision
and against our exact engine. No prebuilt Jenova release is used, because
official builds target stock Godot, not 4.8-dev6.

## Pinned inputs

| Input | Value |
|---|---|
| Jenova Runtime source | `Jenova-Framework/Jenova-Runtime` @ `63ecdcb385fbcd8a59e1ed5896a6c03e0d0aacb2` (v0.3.9.9 hotfix 7) |
| Jenova dependency bundle | `Jenova-Runtime-Dependencies-Universal-4.7.jnvpkg` |
| Godot API | `extension_api.json` + `gdextension_interface.json` dumped from Godot 4.8-dev6 |
| Windows toolchain | Jenova AiO Toolchain v1.0 (MSVC 14.38 `cl`/`link` + merged MSVC/Windows SDK headers), SHA-256 `6c0536fd901a694ffcb97783e69f738d5f64b62d336c91f1a2fe2a7ae49d80fd` |
| Linux toolchain | system `clang++` (CI: clang-19) |

`JENOVA_REF` in `tools/ci/bootstrap_jenova_linux.sh` and `$jenovaRef` in
`tools/ci/bootstrap_jenova_windows.ps1` must always match.

## What lives in `Jenova/`

| Path | Platform | Produced by | In git |
|---|---|---|---|
| `Jenova.Runtime.gdextension` | both | either bootstrap | yes |
| `Jenova.Runtime.Win64.dll` | Windows | Windows bootstrap | LFS |
| `Jenova.Runtime.Linux64.so` | Linux | Linux bootstrap | yes (plain, 20 MB) |
| `GodotSDK/` headers | both | either bootstrap (`--generate-gdsdk`) | yes |
| `GodotSDK/libGodot.x64.lib` | Windows | Windows bootstrap | LFS |
| `GodotSDK/libGodot.x64.a` | Linux | Linux bootstrap | yes (plain, 86 MB) |
| `JenovaSDK/JenovaSDK.h` | both | either bootstrap | yes |
| `JenovaSDK/Jenova.SDK.x64.lib` | Windows | Windows bootstrap | LFS |
| `JenovaSDK/Jenova.SDK.x64.a` | Linux | Linux bootstrap | yes (plain) |
| `Compilers/` | Windows | `tools/jenova/install_msvc_compiler.ps1` | **no** (git-ignored, `.gdignore`) |
| `HOARBOUND_JENOVA_BUILD.txt` | both | bootstraps | yes |

## Hoarbound patches to Jenova

Stock Jenova finds its compiler and GodotSDK through its online package
manager. Our SDK is generated for 4.8-dev6 and is not in that database, so both
bootstraps patch `Source/script_compiler.cpp` before building:

- **Linux:** compiler root `/usr`, GodotSDK `res://Jenova/GodotSDK`. Also adds
  `-lidn2` to the runtime link line (Jenova's static libcurl needs it).
- **Windows:** compiler root `res://Jenova/Compilers/JenovaMSVCCompiler`,
  GodotSDK `res://Jenova/GodotSDK`. Only `MicrosoftCompiler` is patched.

Jenova's MSVC compiler expects `<root>/Bin/cl.exe`, `<root>/Bin/link.exe`, one
`<root>/Include` and one `<root>/Lib`. The AiO toolchain already has this shape:
`bin/` plus `x86_64-msvc/{include,lib}`. `install_msvc_compiler.ps1` links them
with directory junctions. Visual Studio is not needed.

## Developer setup

Windows needs Git LFS (`git lfs install` once per machine) before cloning or
pulling, otherwise the Windows binaries arrive as 133-byte pointer files.

**Windows**, once per clone, to compile `.cpp` scripts in the editor:

```powershell
./tools/jenova/install_msvc_compiler.ps1
```

This downloads the AiO toolchain (157 MB), verifies its SHA-256 and extracts
`bin` + `x86_64-msvc` (~0.9 GB) into `Jenova/Compilers/`. It needs Python 3,
because Windows `tar` cannot read LZMA 7z. Close heavy apps on machines with
4 GB RAM.

**Linux:** install `clang` / `clang++` (CI uses 19). Nothing else is needed.

## Rebuilding the runtime

Rebuild only when the Jenova revision, the engine version, or a Hoarbound patch
changes.

**Windows (preferred: CI).** The `jenova-windows-build` job in
`.github/workflows/checks.yml` runs on a 16 GB GitHub Windows runner:

1. **Start it.** Push a commit whose message contains `[jenova-windows-build]`,
   or open *Actions → Checks → Run workflow* on `main`.
2. **Build.** The job builds the runtime with `bootstrap_jenova_windows.ps1`,
   uploads the vendor package, then proves the C++ script compiles and the frost
   scene runs.
3. **Artifacts.** Each run publishes two artifacts for 7 days:
   - `hoarbound-jenova-windows-vendor` — the complete `Jenova/` folder without
     `Compilers/`;
   - `hoarbound-jenova-windows-logs` — the BuildProject, scene and editor-scan
     logs.

Local Windows build is possible with ≥ 8 GB RAM:
`GODOT_BIN=<path to Godot 4.8-dev6 console exe> ./tools/ci/bootstrap_jenova_windows.ps1`.
The builder compiles with all cores; it was killed for lack of memory on a
4 GB machine.

**Linux.** Run `tools/ci/bootstrap_jenova_linux.sh` on Linux or WSL2 with
clang, cmake, ninja, `libssl-dev`, `libzstd-dev` and `libidn2-dev`. In CI, push
`[jenova-frost-preview]`.

## Getting the CI artifact into the repo

Without the GitHub CLI:

1. **Open the run.** On GitHub go to *Actions → Checks* and open the run of the
   `[jenova-windows-build]` commit. The `jenova-windows-build` job must show at
   least "Upload Windows Jenova vendor package" as green.
2. **Download.** At the bottom of the run page, under **Artifacts**, click
   `hoarbound-jenova-windows-vendor` (a zip). You must be signed in to GitHub.
3. **Unpack.** Extract the zip **into `Jenova/`**, overwriting files. The zip's
   root is the contents of `Jenova/`, not the folder itself.
4. **Check the files.** `git status` should show
   `Jenova/Jenova.Runtime.Win64.dll`, `Jenova/GodotSDK/libGodot.x64.lib` and
   `Jenova/JenovaSDK/Jenova.SDK.x64.lib`. `git lfs status` must list them as
   `LFS`.
5. **Commit and push.** The pre-push hook uploads the LFS objects.

With the GitHub CLI (`gh auth login` once):

```bash
gh run list --workflow checks.yml --limit 5
gh run download <run-id> -n hoarbound-jenova-windows-vendor -D Jenova
gh run download <run-id> -n hoarbound-jenova-windows-logs -D /tmp/jenova-logs
```

If a run fails, send the `hoarbound-jenova-windows-logs` artifact; job logs on
GitHub are not readable without signing in.

## Why only Windows binaries are in LFS

Godot loads `Jenova.Runtime.gdextension` at every start, so every Linux CI job
that runs Godot needs the real Linux runtime. Those jobs check out without LFS.
An LFS `.so` would arrive there as a pointer file and break every import.
Enabling LFS in all of them would spend GitHub Free's 1 GB monthly LFS bandwidth
in about ten runs. Linux binaries therefore stay plain git objects (each below
GitHub's 100 MB file limit).

Windows binaries are needed only by Windows machines and the
`jenova-windows-build` job, the only job with `lfs: true`. Keep it that way, and
do not re-trigger `[jenova-windows-build]` without a reason.

## Status (2026-10-09)

- **Linux runtime:** built and vendored.
- **Windows runtime:** built in CI, but not yet vendored. The C++ script proof
  failed before the Windows compiler patch: Jenova reported no installed MSVC
  package.
- **Import gate:** fails on `main` since Jenova was vendored; the cause is not
  yet confirmed from logs.
