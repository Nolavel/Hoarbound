#!/usr/bin/env bash
## Runs every headless test suite under tests/systems and fails on the first
## suite that reports a failure. A suite that hangs is killed and counts as failed.
## The Jenova runtime quick_exit(0)s on unload, so the exit code alone lies: a suite
## also fails on a script error, a reported failed check, or an error with no pass line
## (docs/technical/JENOVA.md).
set -uo pipefail

GODOT_BIN="${GODOT_BIN:-$HOME/.local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export VK_DRIVER_FILES="${VK_DRIVER_FILES:-/usr/share/vulkan/icd.d/lvp_icd.json}"

status=0
shopt -s nullglob
for suite in "$PROJECT_DIR"/tests/systems/test_*.gd; do
	name="$(basename "$suite")"
	echo "== $name"
	log="$(mktemp)"
	timeout "${SUITE_TIMEOUT:-180}" "$GODOT_BIN" --headless --path "$PROJECT_DIR" --audio-driver Dummy \
		--script "res://tests/systems/$name" 2>&1 | tee "$log"
	code=${PIPESTATUS[0]}
	if [ "$code" -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error|check\(s\) failed|[0-9]+ FAILED|FAIL:" "$log" \
		|| { grep -q "at: push_error" "$log" && ! grep -qE "passed|PASS" "$log"; }; then
		echo "FAILED: $name (exit $code)"
		status=1
	fi
	rm -f "$log"
done

if [ "$status" -eq 0 ]; then
	echo "all suites passed"
fi
exit "$status"
