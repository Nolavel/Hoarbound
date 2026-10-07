#!/usr/bin/env bash
## Fetch the official Rokoko sample archive only for the isolated retarget spike.
## Third-party FBX data stays out of git; CI places one Unreal-skeleton sample in
## the ignored runtime folder before Godot's import pass.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$PROJECT_DIR/tests/motion_matching/_runtime_rokoko"
TARGET_FBX="$TARGET_DIR/rokoko_unreal_sample.fbx"
SAMPLE_URL="${ROKOKO_SAMPLE_URL:-https://support.rokoko.com/hc/en-us/article_attachments/18888475406481}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$TARGET_DIR"
rm -f "$TARGET_FBX" "$TARGET_FBX.import" "$TARGET_DIR/source.txt"

ARCHIVE="$WORK_DIR/SampleStudioFiles.zip"
echo "rokoko sample: downloading official archive"
curl --fail --location --retry 3 --retry-all-errors --connect-timeout 20 \
  "$SAMPLE_URL" -o "$ARCHIVE"
unzip -q "$ARCHIVE" -d "$WORK_DIR/extracted"

candidate=""
while IFS= read -r -d '' file; do
  lower="${file,,}"
  if [[ "$lower" == *unreal* || "$lower" == *ue4* || "$lower" == *ue5* ]]; then
    candidate="$file"
    break
  fi
done < <(find "$WORK_DIR/extracted" -type f -iname '*.fbx' -print0)

## Some archive revisions use generic filenames. Fall back to inspecting the
## embedded UE mannequin bone names instead of guessing from directory names.
if [[ -z "$candidate" ]]; then
  while IFS= read -r -d '' file; do
    if strings "$file" | grep -q 'spine_01' && strings "$file" | grep -q 'thigh_l'; then
      candidate="$file"
      break
    fi
  done < <(find "$WORK_DIR/extracted" -type f -iname '*.fbx' -print0)
fi

if [[ -z "$candidate" ]]; then
  echo "rokoko sample: no Unreal-skeleton FBX found; archive contents:" >&2
  find "$WORK_DIR/extracted" -type f -maxdepth 6 -print >&2
  exit 2
fi

cp "$candidate" "$TARGET_FBX"
{
  echo "url=$SAMPLE_URL"
  echo "archive_path=${candidate#$WORK_DIR/extracted/}"
  sha256sum "$TARGET_FBX" | awk '{print "sha256=" $1}'
} > "$TARGET_DIR/source.txt"

echo "rokoko sample: selected ${candidate#$WORK_DIR/extracted/}"
echo "rokoko sample: staged at $TARGET_FBX"
