#!/bin/bash
# Local graphical Godot capture only. No Actions, no production project imports.
set -euo pipefail
source /workspace/work/env.sh
study_dir="$(cd "$(dirname "$0")" && pwd)"
capture_dir=/workspace/work/log-cycle
mkdir -p "$capture_dir"
Xvfb :99 -screen 0 960x540x24 -nolisten tcp > "$capture_dir/xvfb.log" 2>&1 &
xp=$!
trap 'kill "$xp" 2>/dev/null || true' EXIT
for i in $(seq 1 50); do test -S /tmp/.X11-unix/X99 && break; sleep 0.1; done
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path "$study_dir/source" \
 --display-driver x11 --rendering-driver opengl3 --rendering-method gl_compatibility \
 --audio-driver Dummy --write-movie "$capture_dir/frame.png" --fixed-fps 30 \
 --quit-after 300 > "$capture_dir/godot.log" 2>&1
if rg -n 'SCRIPT ERROR|SHADER ERROR|ERROR:' "$capture_dir/godot.log"; then
 cat "$capture_dir/godot.log"
 exit 1
fi
ffmpeg -y -hide_banner -loglevel error -framerate 30 -i "$capture_dir/frame%08d.png" \
 -frames:v 300 -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart "$study_dir/full-cycle.mp4"
cp "$capture_dir/frame00000045.png" "$study_dir/01-ignition.png"
cp "$capture_dir/frame00000150.png" "$study_dir/02-burning.png"
cp "$capture_dir/frame00000270.png" "$study_dir/03-embers.png"
cp "$capture_dir/godot.log" "$study_dir/godot-capture.txt"
