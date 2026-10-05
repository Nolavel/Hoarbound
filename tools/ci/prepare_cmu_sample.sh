#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$PROJECT_DIR/tests/motion_matching/_runtime_cmu"
TARGET_FILE="$TARGET_DIR/41_02.bvh"
SOURCE_URL="https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data/041/41_02.bvh"
OFFICIAL_SUBJECT_URL="https://mocap.cs.cmu.edu/search.php?subjectnumber=41"
MIRROR_README_URL="https://github.com/una-dinosauria/cmu-mocap/blob/master/READMEFIRST.txt"

mkdir -p "$TARGET_DIR"

echo "[cmu] downloading CMU Subject 41 trial 02"
curl --fail --location --retry 3 --retry-delay 2 \
	--output "$TARGET_FILE" "$SOURCE_URL"

if [[ ! -s "$TARGET_FILE" ]]; then
	echo "[cmu] staged BVH is empty" >&2
	exit 2
fi
if ! head -n 1 "$TARGET_FILE" | grep -q '^HIERARCHY'; then
	echo "[cmu] staged file is not a BVH hierarchy" >&2
	exit 3
fi
if ! grep -q '^MOTION' "$TARGET_FILE"; then
	echo "[cmu] staged BVH has no MOTION section" >&2
	exit 4
fi

SHA256="$(sha256sum "$TARGET_FILE" | awk '{print $1}')"
cat > "$TARGET_DIR/source_manifest.txt" <<EOF
source=CMU Graphics Lab Motion Capture Database, Subject 41 trial 02
official_subject_url=$OFFICIAL_SUBJECT_URL
bvh_conversion_url=$SOURCE_URL
conversion_rights_url=$MIRROR_README_URL
sha256=$SHA256
staging=CI-only; BVH is ignored by git and is not shipped from this repository
EOF

echo "[cmu] staged $(basename "$TARGET_FILE") sha256=$SHA256"
