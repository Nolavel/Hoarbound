# Production C++ with GDExtension

Status: **approved production path** (2026-10-13).

Hoarbound uses the official Godot GDExtension API through `godot-cpp`. C++ is
compiled as a library, not as editor-managed script files. Jenova was evaluated
as an experiment and was not approved; see `JENOVA.md` for the decision record.

## Build contract

| Input | Pinned value |
|---|---|
| Godot | `4.8-dev6` Mono |
| godot-cpp | `b8530af7546a3fcae80cef2477526569fd42ffc2` |
| SCons | `4.4.0` |
| Windows | x86_64 DLL |
| Linux | x86_64 shared object |
| macOS | universal dylib (arm64 + x86_64), ad-hoc signed in CI |

The heavy build runs only on GitHub-hosted runners in
`.github/workflows/native-libraries.yml`. Windows, Linux and macOS execute in
parallel. Every runner:

1. downloads the checksum-pinned Godot build;
2. fetches the pinned `godot-cpp` commit;
3. dumps the API from the exact Godot binary;
4. builds `target=template_release`;
5. loads the library in a clean Godot smoke project;
6. proves the portable frost core, model adapter and controller adapter.

The final `hoarbound-native` artifact contains:

```text
addons/hoarbound_native/hoarbound_native.gdextension
bin/windows/hoarbound_native.dll
bin/linux/libhoarbound_native.so
bin/macos/libhoarbound_native.macos.dylib
manifest.json
SHA256SUMS.txt
```

The descriptor is intentionally activated only by the installer. A clean Git
checkout therefore imports without missing-library errors. The installer
verifies every checksum before copying the descriptor and all three platform
libraries into the project.

## Local workflow (no local C++ compilation)

Install once:

- Git;
- Python 3.10 or newer;
- GitHub CLI (`gh`) and run `gh auth login`;
- the exact Godot `4.8-dev6` Mono editor used by the project.

No Visual Studio, Xcode, Clang, GCC, SCons or local `godot-cpp` checkout is
required for the CI-first workflow.

After changing C++:

1. commit and push the source to `codex` (or later `main`);
2. wait for all three `native-libraries` matrix jobs and `Merged native package`;
3. from the repository root install the latest successful artifact:

   ```bash
   python tools/native/install_native_artifact.py --branch codex
   ```

   After the production merge use `--branch main` (the default).

4. open the project in Godot and test. The installed files are generated local
   state and stay out of Git.

To install an exact run:

```bash
python tools/native/install_native_artifact.py --run-id <run-id>
```

To install an artifact downloaded manually from the Actions page:

```bash
python tools/native/install_native_artifact.py --artifact-dir <unpacked-directory>
```

The frost integration scene is
`res://scenes/experimental/gdextension_frost_lab.tscn`. Its GDScript is only a
loader that instantiates the registered native class; progression, material
setup, slider handling and frame updates live in C++.

## Daily workflow after production integration

Normal feature work still starts on `codex`; `main` remains the reviewed
production branch.

1. Update `codex` from current `main`.
2. Edit the C++ sources under `native/hoarbound_core/` or
   `native/hoarbound_native/src/`. Godot does not compile these files in the
   editor.
3. Commit and push to `codex`. The native workflow performs the heavy build
   for Windows, Linux and macOS in parallel.
4. When the run is green, install its exact artifact locally:

   ```bash
   python tools/native/install_native_artifact.py --branch codex
   ```

5. Test the real game path in Godot. The installed descriptor and `bin/`
   libraries are ignored generated state and must not be committed.
6. After the reviewed source reaches `main`, wait for the new `main` native
   run and install the production artifact:

   ```bash
   git switch main
   git pull --ff-only
   python tools/native/install_native_artifact.py
   ```

The default installer branch is `main`. For a reproducible regression check,
pin the Actions run instead of taking the latest successful one:

```bash
python tools/native/install_native_artifact.py --run-id <run-id>
```

If a native run fails, do not reuse an older artifact as proof that the new
source works. Open the failed matrix job, use its
`hoarbound-native-log-<platform>` artifact, fix the source on `codex`, and
push again.

## Example: move one SnowField operation to C++

Use this sequence for a real subsystem migration. The example is the measured
`SnowField.rebuild` depth calculation; it is a candidate, not an instruction
to rewrite the whole snow system.

1. **Measure first.** Record the current input size, output digest and runtime
   cost in the production scene. Do not port a path that is not an observed CPU
   bottleneck.
2. **Freeze the boundary.** Keep `SnowField` as the state owner and keep its
   consumer-facing operation unchanged. Define one coarse request such as
   `rebuild_depth(width, height, samples)`; never cross the GDScript/C++
   boundary once per cell.
3. **Extract the portable core.** Put Godot-free math in
   `native/hoarbound_core/snow_depth_kernel.{hpp,cpp}` using plain values and
   containers. It must not include Godot headers, `Node`, `Resource` or
   `Variant`.
4. **Capture parity fixtures.** Save representative inputs and the expected
   output/digest from the current implementation, including empty, edge and
   normal cases.
5. **Add a thin adapter.** Create
   `HoarboundSnowDepthKernel : RefCounted` under
   `native/hoarbound_native/src/`. Convert
   `PackedFloat32Array`/Godot values once, call the portable core once, and
   convert the result once.
6. **Register and prove both layers.** Register the class in
   `register_types.cpp`. Extend `ci_project/smoke.gd` so the portable-core
   probe and the public GDExtension adapter produce the same fixture digest.
7. **Keep rollback cheap.** Select the old or native implementation behind the
   existing subsystem facade during validation. Do not fork the owning state or
   make consumers depend on the implementation language.
8. **Let CI compile.** Push to `codex`; all three runners must build and
   smoke-load the adapter. Install that run locally and compare output,
   save/load behavior and measured time in the real scene.
9. **Promote only after parity.** Integrate the source to `main`, wait for the
   green production run, install the `main` artifact, then remove the old hot
   implementation. Roll back by switching the facade to the old path; the
   portable core can remain without owning gameplay state.

A migrated subsystem is complete only when behavior parity, ownership, the
three platform smoke tests and the measured performance gain are all visible.

## When local compilation is useful

Local compilation is optional for engine programmers who want a shorter edit
loop. It requires a platform compiler, Python, SCons and a checkout of the
pinned `godot-cpp` revision. Local output is never accepted as release evidence:
the three GitHub runners and their merged manifest remain authoritative.
