#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$PROJECT_DIR/tests/motion_matching/_runtime_cmu"
BASE_URL="https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data"
OFFICIAL_URL="https://mocap.cs.cmu.edu/"
MIRROR_README_URL="https://github.com/una-dinosauria/cmu-mocap/blob/master/READMEFIRST.txt"
MANIFEST="$TARGET_DIR/source_manifest.tsv"

# Real CMU source pool for #202 semantic segmentation. Long captures are NOT
# baked wholesale: cmu_motion_segmenter.gd extracts only stable authored ranges.
# No clip is mirrored, reversed or synthetically rotated.
SOURCES=(
	"111|111_28|idle_neutral|Standing still"
	"069|69_01|walk_f_reference|Walk forward"
	"016|16_33|stop_pool|Slow walk, stop"
	"016|16_34|stop_pool|Slow walk, stop"
)

for clip in 69_34 69_35 69_36 69_37 69_38 69_39; do
	SOURCES+=("069|$clip|backward_pool|Walk backwards / backward turn candidate")
done
for clip in 69_42 69_43 69_44 69_45 69_46 69_47 69_48 69_49 69_50 69_56; do
	SOURCES+=("069|$clip|lateral_pool|Sideways/backwards/turn locomotion candidate")
done
for clip in 40_02 40_03 40_04 40_05 41_02 41_03 41_04 41_05 41_06; do
	SOURCES+=("${clip%%_*}|$clip|multidirectional_pool|Forward/backward/sideways/diagonal navigation candidate")
done
for clip in 69_16 69_17 69_18 69_19; do
	SOURCES+=("069|$clip|pivot_pool|Turn in place candidate")
done
for clip in 69_20 69_21 69_22 69_23 69_24 69_25 69_26 69_27 69_28 69_29 69_30 69_31 69_32 69_33; do
	SOURCES+=("069|$clip|turn_90_pool|Forward 90-degree turn candidate")
done

mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -maxdepth 1 -type f -name '*.bvh' -delete
printf 'clip\tsubject\trole\tdescription\tsha256\tsource_url\n' > "$MANIFEST"

for entry in "${SOURCES[@]}"; do
	IFS='|' read -r subject clip role description <<< "$entry"
	# Subject directories in the mirror are zero-padded to three digits.
	if [[ "$subject" =~ ^[0-9]+$ ]]; then
		subject="$(printf '%03d' "$((10#$subject))")"
	fi
	filename="$clip.bvh"
	target="$TARGET_DIR/$filename"
	source_url="$BASE_URL/$subject/$filename"

	echo "[cmu] downloading $clip ($role)"
	curl --fail --location --retry 3 --retry-delay 2 --output "$target" "$source_url"
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
selection=kinematic semantic segmentation; no synthetic direction rotation, mirroring, reversal, or generated locomotion clips
EOF

echo "[cmu] canonical candidate set staged: ${#SOURCES[@]} real captures"
