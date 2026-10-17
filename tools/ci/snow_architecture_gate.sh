#!/usr/bin/env bash
## Cheap non-render snow regression gate for architecture changes.
set -euo pipefail

GODOT="${GODOT:-$HOME/.local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR"

for suite in \
	test_snow_architecture_contract \
	test_snow_contact_pipeline \
	test_snow_shell \
	test_snow_tracks; do
	log="$(mktemp)"
	if ! timeout 180 "$GODOT" --headless --path "$PROJECT_DIR" --audio-driver Dummy \
			--script "res://tests/systems/${suite}.gd" >"$log" 2>&1; then
		cat "$log" >&2
		echo "snow architecture gate: ${suite} exited non-zero" >&2
		exit 1
	fi
	if grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR" "$log"; then
		cat "$log" >&2
		echo "snow architecture gate: ${suite} logged an engine/script error" >&2
		exit 1
	fi
	if ! grep -q "all checks passed" "$log"; then
		cat "$log" >&2
		echo "snow architecture gate: ${suite} did not report success" >&2
		exit 1
	fi
	grep "all checks passed" "$log"
done

echo "snow architecture gate: all suites passed"
