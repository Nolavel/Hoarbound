#!/usr/bin/env bash
## Renders a scene to PNG on CPU (lavapipe + Xvfb). No GPU required.
## Usage: tools/ci/render.sh <res://scene.tscn> <out.png> [frames]
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-$HOME/.local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

scene="${1:?scene path required}"
out="${2:-user://shots/shot.png}"
frames="${3:-30}"

## The lavapipe ICD is named differently across distributions. A path that does not
## exist leaves the loader with no driver, and Godot then falls back to OpenGL and
## still writes a PNG - so take the first name that is actually there.
if [ -z "${VK_DRIVER_FILES:-}" ]; then
	for candidate in \
		/usr/share/vulkan/icd.d/lvp_icd.x86_64.json \
		/usr/share/vulkan/icd.d/lvp_icd.json; do
		if [ -f "$candidate" ]; then
			export VK_DRIVER_FILES="$candidate"
			break
		fi
	done
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
mkdir -p "$XDG_RUNTIME_DIR"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

if ! xvfb-run -a "$GODOT_BIN" \
	--path "$PROJECT_DIR" \
	--rendering-driver vulkan \
	--rendering-method forward_plus \
	--audio-driver Dummy \
	--script tools/ci/screenshot.gd -- "$scene" "$out" "$frames" 2>&1 | tee "$log"; then
	echo "render.sh: the render failed" >&2
	exit 1
fi

## A Vulkan run that fell back to OpenGL writes a PNG just the same, and that PNG
## does not show Forward+. Say so instead of handing out a picture of the wrong
## renderer. The word "Forward+" also turns up in the OpenGL warnings, so the
## renderer's own banner is what is looked for.
if ! grep -qE "Vulkan .*Forward\+.*Using Device" "$log"; then
	echo "render.sh: the render did not run Forward+ (Vulkan); see the log above" >&2
	exit 1
fi
