#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$PROJECT_DIR/tests/motion_matching/_runtime_cmu"
BASE_URL="https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data"
OFFICIAL_URL="https://mocap.cs.cmu.edu/"
MIRROR_README_URL="https://github.com/una-dinosauria/cmu-mocap/blob/master/READMEFIRST.txt"
STYLE_OFFICIAL_URL="https://www.ianxmason.com/100style/"
STYLE_LICENSE_URL="https://creativecommons.org/licenses/by/4.0/"
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

# Dedicated lateral captures are deliberately staged in addition to the long
# navigate/turn pools. The latter contain useful transitions, but their steady
# side-walk ranges are short and easy to fragment at turn boundaries. These
# trials are authored as navigation or sideways walking and therefore give the
# kinematic segmenter real sustained lateral material to validate.
SOURCES+=("009|09_12|lateral_dedicated|Navigate - walk forward, backward, sideways")
for clip in 113_17 113_18; do
	SOURCES+=("113|$clip|lateral_dedicated|Walk sideways")
done
SOURCES+=("143|143_40|lateral_dedicated|Walk sideways")
for clip in 69_16 69_17 69_18 69_19; do
	SOURCES+=("069|$clip|pivot_pool|Turn in place candidate")
done
for clip in 69_20 69_21 69_22 69_23 69_24 69_25 69_26 69_27 69_28 69_29 69_30 69_31 69_32 69_33; do
	SOURCES+=("069|$clip|turn_90_pool|Forward 90-degree turn candidate")
done

# Henry walks at 1.5 m/s in the game; the pools above stop near 1.0 m/s. These
# trials are natural walks at 1.4-1.75 m/s source speed (CMU index titles).
for clip in 02_02 07_09 07_10 07_11 08_01 08_02 08_03 08_06 08_08 08_09 08_10 16_21 16_22; do
	SOURCES+=("${clip%%_*}|$clip|brisk_walk_pool|walk")
done
for clip in 39_01 39_02 39_03 39_04 39_05 39_06 39_07 39_08 39_09 39_10; do
	SOURCES+=("039|$clip|brisk_walk_pool|walk")
done
SOURCES+=("016|16_23|brisk_turn_pool|walk, veer left")
SOURCES+=("016|16_24|brisk_turn_pool|walk, veer left")
SOURCES+=("016|16_25|brisk_turn_pool|walk, veer right")
SOURCES+=("016|16_26|brisk_turn_pool|walk, veer right")
SOURCES+=("016|16_27|brisk_turn_pool|walk, 90-degree left turn")
SOURCES+=("016|16_28|brisk_turn_pool|walk, 90-degree left turn")
SOURCES+=("016|16_29|brisk_turn_pool|walk, 90-degree right turn")
SOURCES+=("016|16_30|brisk_turn_pool|walk, 90-degree right turn")

mkdir -p "$TARGET_DIR"
# Import conventions (units, reference pose, axes) live in per-family
# SourceRetargetProfile code, not in this manifest.
printf 'clip\tsubject\tdataset\tpool\tdescription\tsha256\turl\tlicense\n' > "$MANIFEST"

for entry in "${SOURCES[@]}"; do
	IFS='|' read -r subject clip role description <<< "$entry"
	# Subject directories in the mirror are zero-padded to three digits.
	if [[ "$subject" =~ ^[0-9]+$ ]]; then
		subject="$(printf '%03d' "$((10#$subject))")"
	fi
	filename="$clip.bvh"
	target="$TARGET_DIR/$filename"
	source_url="$BASE_URL/$subject/$filename"

	if [[ -s "$target" ]] && head -n 1 "$target" | grep -q '^HIERARCHY' && grep -q '^MOTION' "$target"; then
		echo "[cmu] reusing $clip ($role)"
	else
		echo "[cmu] downloading $clip ($role)"
		curl --fail --location --retry 3 --retry-delay 2 --output "$target" "$source_url"
	fi
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
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$clip" "$subject" "CMU" "$role" "$description" "$sha256" "$source_url" \
		"CMU: free for all uses" >> "$MANIFEST"
	echo "[cmu] staged $filename sha256=$sha256"
done

# 100STYLE's neutral sidestep and transition captures fill the steady diagonal
# gaps that CMU does not contain. They are staged only for the lab and retargeted
# after import; the source BVHs are not committed or shipped.
STYLE_SOURCES=(
	"Neutral_SW|1HzUccloKCjQgpObQ0ZXTEDW7-RllNwHX|07225ded6df11c4eb97a7b42e6121a9e985ae7e8d0f56f9ca971429f9c507ad9|neutral_directional|Neutral sidestep walking"
	"Neutral_TR1|1AnK7HGtuQR4aSVkyWKnZObgapd41KE1N|11e5f654daae97e3cc80432a7a89965749337b32571cad6ad71a1d1e6e8ff746|neutral_transitions|Neutral locomotion transitions"
)
STYLE_STAGED=0
for entry in "${STYLE_SOURCES[@]}"; do
	IFS='|' read -r clip file_id expected_sha256 role description <<< "$entry"
	filename="$clip.bvh"
	target="$TARGET_DIR/$filename"
	source_url="https://drive.google.com/uc?id=$file_id&export=download"
	if [[ -s "$target" ]] && head -n 1 "$target" | grep -q '^HIERARCHY' && grep -q '^MOTION' "$target"; then
		echo "[100style] reusing $clip ($role)"
	else
		echo "[100style] downloading $clip ($role)"
		# 100STYLE has no verified retarget profile yet, so an unreachable host
		# only skips it; a reachable file must still match its pinned hash.
		if ! curl --fail --location --retry 3 --retry-delay 2 --output "$target" "$source_url"; then
			rm -f "$target"
			echo "[100style] WARNING: $clip unreachable; skipped" >&2
			continue
		fi
	fi
	if [[ ! -s "$target" ]] || ! head -n 1 "$target" | grep -q '^HIERARCHY' || ! grep -q '^MOTION' "$target"; then
		echo "[100style] staged file is not a valid BVH: $filename" >&2
		exit 5
	fi
	sha256="$(sha256sum "$target" | awk '{print $1}')"
	if [[ "$sha256" != "$expected_sha256" ]]; then
		echo "[100style] checksum mismatch for $filename: $sha256" >&2
		exit 6
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$clip" "Neutral" "100STYLE" "$role" "$description" "$sha256" "$source_url" \
		"CC BY 4.0 (Ian Mason)" >> "$MANIFEST"
	echo "[100style] staged $filename sha256=$sha256"
	STYLE_STAGED=$((STYLE_STAGED + 1))
done

cat > "$TARGET_DIR/source_policy.txt" <<EOF
source=CMU Graphics Lab Motion Capture Database
official_url=$OFFICIAL_URL
rights=CMU states that the motion dataset is free for all uses
bvh_conversion_mirror=https://github.com/una-dinosauria/cmu-mocap
conversion_rights_url=$MIRROR_README_URL
staging=CI/lab only; third-party BVH files are ignored by git and are not shipped from this repository
selection=kinematic semantic segmentation; no synthetic direction rotation, mirroring, reversal, or generated locomotion clips
secondary_source=100STYLE Neutral locomotion by Ian Mason
secondary_official_url=$STYLE_OFFICIAL_URL
secondary_license=Creative Commons Attribution 4.0 International
secondary_license_url=$STYLE_LICENSE_URL
secondary_credit=The 100STYLE Dataset - Ian Mason
EOF

echo "[motion-data] canonical candidate set staged: ${#SOURCES[@]} CMU + $STYLE_STAGED/${#STYLE_SOURCES[@]} 100STYLE real captures"
