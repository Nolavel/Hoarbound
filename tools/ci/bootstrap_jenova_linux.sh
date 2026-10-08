#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/bin/godot}"
JENOVA_REF="${JENOVA_REF:-63ecdcb385fbcd8a59e1ed5896a6c03e0d0aacb2}"
WORK="${RUNNER_TEMP:-/tmp}/hoarbound-jenova-linux"
SRC="$WORK/Jenova-Runtime"
API="$WORK/godot-api"

rm -rf "$WORK"
mkdir -p "$WORK" "$API"

git clone --quiet https://github.com/Jenova-Framework/Jenova-Runtime.git "$SRC"
git -C "$SRC" checkout --quiet "$JENOVA_REF"

python3 -m pip install --disable-pip-version-check -q requests py7zr colored

# Fetch the official Jenova dependency bundle first. Builder skips this step once
# Dependencies/ exists, so our custom Godot 4.8-dev6 API survives the real build.
pushd "$SRC" >/dev/null
python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("jenova_builder", "Jenova.Builder.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.deps_version = "4.7"
mod.deploy_mode = True
mod.install_dependencies()
PY
popd >/dev/null

# Dump both high- and low-level GDExtension APIs from the exact engine Hoarbound uses.
# Use a clean temporary project: these APIs are properties of the engine build, and
# dumping from the Hoarbound root before import unnecessarily depends on .godot data.
cat > "$API/project.godot" <<'EOF'
[application]
config/name="Hoarbound Jenova API Dump"

[rendering]
renderer/rendering_method="gl_compatibility"
EOF
pushd "$API" >/dev/null
"$GODOT_BIN" --headless --path "$API" --dump-extension-api
"$GODOT_BIN" --headless --path "$API" --dump-gdextension-interface-json
popd >/dev/null

test -s "$API/extension_api.json"
test -s "$API/gdextension_interface.json"

test -d "$SRC/Dependencies/libgodot/gdextension"
cp "$API/extension_api.json" "$SRC/Dependencies/libgodot/gdextension/extension_api.json"
cp "$API/gdextension_interface.json" "$SRC/Dependencies/libgodot/gdextension/gdextension_interface.json"

# Hoarbound vendors its native toolchain/SDK. Keep Jenova's own compiler pipeline,
# but resolve these two package paths locally instead of requiring the online package DB.
python3 - "$SRC/Source/script_compiler.cpp" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8-sig")
marker = "// Linux Compilers"
pos = s.index(marker)
head, linux = s[:pos], s[pos:]
old = '''String selectedCompilerPath = jenova::GetInstalledCompilerPathFromPackages(compilerSettings["cpp_toolchain_path"], GetCompilerModel());\n            String selectedGodotKitPath = jenova::GetInstalledGodotKitPathFromPackages(compilerSettings["cpp_godotsdk_path"]);'''
new = '''String selectedCompilerPath = "/usr";\n            String selectedGodotKitPath = jenova::GetJenovaProjectDirectory() + "Jenova/GodotSDK";'''
count = linux.count(old)
if count != 2:
    raise SystemExit(f"expected two Linux compiler path blocks, found {count}")
linux = linux.replace(old, new)
p.write_text(head + linux, encoding="utf-8")
PY

# Jenova's static libcurl enables IDN2; resolve its symbols in the runtime binary.
python3 - "$SRC/Jenova.Builder.py" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8-sig")
old = ' -Wl,-Bdynamic -ldl -lrt -lzstd "'
new = ' -Wl,-Bdynamic -ldl -lrt -lzstd -lidn2 "'
count = s.count(old)
if count != 1:
  raise SystemExit(f"expected one Linux runtime link command, found {count}")
p.write_text(s.replace(old, new), encoding="utf-8")
PY

# A static libstdc++ copy inside the runtime crashed Godot's cold import: its
# std::regex locale code segfaulted in CPPScript::_get_global_name. Link the
# runtime against the shared libstdc++ the Godot process already uses.
python3 - "$SRC/Jenova.Builder.py" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8-sig")
old = 'f"-static-libstdc++ -static-libgcc -L/usr/lib64 '
new = 'f"-static-libgcc -L/usr/lib64 '
count = s.count(old)
if count != 1:
  raise SystemExit(f"expected one Linux runtime libstdc++ link flag, found {count}")
p.write_text(s.replace(old, new), encoding="utf-8")
PY

# Jenova's official Linux build uses Clang; build runtime + a generated GodotSDK
# from our patched 4.8-dev6 bindings.
pushd "$SRC" >/dev/null
python3 Jenova.Builder.py \
  --skip-packaging \
  --deploy-mode \
  --deps-version 4.7 \
  --compiler linux-clang \
  --generate-gdsdk
popd >/dev/null

mkdir -p "$ROOT/Jenova/GodotSDK" "$ROOT/Jenova/JenovaSDK"

cp "$SRC/Linux64/Jenova.Runtime.Linux64.so" "$ROOT/Jenova/Jenova.Runtime.Linux64.so"
cp "$SRC/Jenova.Runtime.gdextension" "$ROOT/Jenova/Jenova.Runtime.gdextension"
cp -a "$SRC/Linux64/GodotSDK/." "$ROOT/Jenova/GodotSDK/"
cp "$SRC/Source/JenovaSDK.h" "$ROOT/Jenova/JenovaSDK/JenovaSDK.h"
if [ -f "$SRC/Linux64/JenovaSDK/Jenova.SDK.x64.a" ]; then
  cp "$SRC/Linux64/JenovaSDK/Jenova.SDK.x64.a" "$ROOT/Jenova/JenovaSDK/Jenova.SDK.x64.a"
fi

BUILD_INFO="$ROOT/Jenova/HOARBOUND_JENOVA_BUILD.txt"
WINDOWS_INFO="$(grep '^Windows' "$BUILD_INFO" 2>/dev/null || true)"
cat > "$BUILD_INFO" <<EOF
Jenova Runtime source: $JENOVA_REF
Godot API: 4.8-dev6 generated from Hoarbound CI engine
Linux script compiler: Jenova ClangCompiler -> system clang++
Linux runtime libstdc++: shared (Hoarbound patch)
Package resolution: project-local Jenova/GodotSDK (Hoarbound patch)
EOF
if [ -n "$WINDOWS_INFO" ]; then
  printf '%s\n' "$WINDOWS_INFO" >> "$BUILD_INFO"
fi

printf '[jenova-bootstrap] Linux runtime + custom GodotSDK ready\n'
printf '[jenova-bootstrap] runtime bytes: '
wc -c < "$ROOT/Jenova/Jenova.Runtime.Linux64.so"
printf '[jenova-bootstrap] SDK bytes: '
du -sb "$ROOT/Jenova/GodotSDK" | cut -f1
