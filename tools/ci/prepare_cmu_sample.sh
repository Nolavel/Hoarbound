#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$PROJECT_DIR/tests/motion_matching/_runtime_cmu"
BASE_URL="https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data"
OFFICIAL_URL="https://mocap.cs.cmu.edu/"
MIRROR_README_URL="https://github.com/una-dinosauria/cmu-mocap/blob/master/READMEFIRST.txt"
MANIFEST="$TARGET_DIR/source_manifest.tsv"

# Curated real-mocap source pool for issue #202. Roles are candidates until the
# kinematic segmentation pass confirms exact direction / start-stop windows.
# No clip is mirrored, reversed, or generated from another direction.
SOURCES=(
	"111|111_28|idle_neutral|Standing still"
	"069|69_01|walk_f|Walk forward"
	"069|69_34|walk_b_pool|Walk backwards and turn; extract authored backward windows"
	"069|69_42|walk_lateral_a_pool|Walk sideways and turn; determine signed side from root trajectory"
	"069|69_48|walk_lateral_b_pool|Opposite sideways capture; determine signed side from root trajectory"
	"040|40_02|diagonal_pool|Navigate forward/backward/on a diagonal"
	"040|40_03|diagonal_pool|Navigate forward/backward/on a diagonal"
	"040|40_04|diagonal_pool|Navigate forward/backward/on a diagonal"
	"040|40_05|diagonal_pool|Navigate forward/backward/on a diagonal"
	"016|16_33|stop_f|Slow walk, stop"
	"069|69_16|pivot_pool_a|Turn in place; classify 90/180 windows from facing delta"
	"069|69_18|pivot_pool_b|Opposite turn in place; classify 90/180 windows from facing delta"
	"069|69_20|turn_90_pool_a|Walk forward, 90-degree turn"
	"069|69_24|turn_90_pool_b|Walk forward, opposite 90-degree turn"
	"041|41_02|multidirectional_reference|Existing forward/backward/sideways/diagonal baseline"
)

mkdir -p "$TARGET_DIR"
# Keep stale staged BVHs from silently participating in a canonical-set run.
find "$TARGET_DIR" -maxdepth 1 -type f -name '*.bvh' -delete

printf 'clip\tsubject\trole\tdescription\tsha256\tsource_url\n' > "$MANIFEST"

for entry in "${SOURCES[@]}"; do
	IFS='|' read -r subject clip role description <<< "$entry"
	filename="$clip.bvh"
	target="$TARGET_DIR/$filename"
	source_url="$BASE_URL/$subject/$filename"

	echo "[cmu] downloading $clip ($role)"
	curl --fail --location --retry 3 --retry-delay 2 \
		--output "$target" "$source_url"

	if [[ ! -s "$target" ]]; then
		echo "[cmu] staged BVH is empty: $filename" >&2
		exit 2
	fi
	if ! head -n 1 "$target" | grep -q '^HIERARCHY'; then
		echo "[cmu] staged file is not a BVH hierarchy: $filename" >&2
		exit 3
	fi
	if ! grep -q '^MOTION' "$target"; then
		echo "[cmu] staged BVH has no MOTION section: $filename" >&2
		exit 4
	fi

	sha256="$(sha256sum "$target" | awk '{print $1}')"
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$clip" "$subject" "$role" "$description" "$sha256" "$source_url" >> "$MANIFEST"
	echo "[cmu] staged $filename sha256=$sha256"
done

cat > "$TARGET_DIR/source_policy.txt" <<EOF
source=CMU Graphics Lab Motion Capture Database
official_url=$OFFICIAL_URL
rights=CMU states that the motion dataset is free for all uses
bvh_conversion_mirror=https://github.com/una-dinosauria/cmu-mocap
conversion_rights_url=$MIRROR_README_URL
staging=CI/lab only; third-party BVH files are ignored by git and are not shipped from this repository
selection=no synthetic direction rotation, mirroring, reversal, or generated locomotion clips
EOF

echo "[cmu] canonical candidate set staged: ${#SOURCES[@]} real captures"
