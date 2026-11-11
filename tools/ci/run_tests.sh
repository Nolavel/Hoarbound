#!/usr/bin/env bash
## Runs every headless test suite under tests/systems and fails on the first
## suite that reports a failure. A suite that hangs is killed and counts as failed.
## The exit code is only one signal: a suite also fails on a script error, a
## reported failed check, or an error with no pass line.
## tools/ci/known_failing_suites.txt lists suites that are known to fail, one per
## line with its reason after a '#'. They are reported, not counted; one that
## passes fails the run, so the list never goes stale.
## A suite may ask for engine arguments on a line "## ci-args: <args>" (e.g. --fixed-fps 30 for one
## whose springs and scripted moves assume game-speed frames).
## With suite names as arguments (test_x or test_x.gd) only those run, by the same verdict: the `checks`
## gate runs tools/ci/required_suites.txt that way. Each named suite must exist.
set -uo pipefail

GODOT_BIN="${GODOT_BIN:-$HOME/.local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export VK_DRIVER_FILES="${VK_DRIVER_FILES:-/usr/share/vulkan/icd.d/lvp_icd.json}"

status=0
known_file="$PROJECT_DIR/tools/ci/known_failing_suites.txt"
known=""
[ -f "$known_file" ] && known="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$known_file" | grep -v '^$' || true)"
shopt -s nullglob
suites=("$PROJECT_DIR"/tests/systems/test_*.gd)
if [ "$#" -gt 0 ]; then
	suites=()
	for wanted in "$@"; do
		path="$PROJECT_DIR/tests/systems/${wanted%.gd}.gd"
		if [ ! -f "$path" ]; then
			echo "FAILED: $wanted (no such suite)"
			status=1
			continue
		fi
		suites+=("$path")
	done
fi
for suite in "${suites[@]}"; do
	name="$(basename "$suite")"
	echo "== $name"
	log="$(mktemp)"
	read -r -a extra <<< "$(sed -n 's/^## ci-args:[[:space:]]*//p' "$suite" | head -n 1)"
	timeout "${SUITE_TIMEOUT:-180}" "$GODOT_BIN" --headless --path "$PROJECT_DIR" --audio-driver Dummy "${extra[@]}" \
		--script "res://tests/systems/$name" 2>&1 | tee "$log"
	code=${PIPESTATUS[0]}
	failed=0
	if [ "$code" -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error|check\(s\) failed|[0-9]+ FAILED|FAIL:" "$log" \
		|| { grep -q "at: push_error" "$log" && ! grep -qE "passed|PASS" "$log"; }; then
		failed=1
	fi
	if printf '%s\n' "$known" | grep -qx "$name"; then
		if [ "$failed" -eq 1 ]; then
			echo "KNOWN FAILING: $name (see tools/ci/known_failing_suites.txt)"
		else
			echo "FAILED: $name now passes; remove it from tools/ci/known_failing_suites.txt"
			status=1
		fi
	elif [ "$failed" -eq 1 ]; then
		echo "FAILED: $name (exit $code)"
		status=1
	fi
	rm -f "$log"
done

if [ "$status" -eq 0 ]; then
	echo "all suites passed"
fi
exit "$status"
