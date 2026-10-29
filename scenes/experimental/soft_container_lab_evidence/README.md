# Open soft container — experiment #254

Six rigid bodies (three 1.02 × 0.84 × 0.96 m cubes and three radius-0.54 m
spheres), native SoftBody3D, welded panel seams and pinned top/bottom rims.
The bottom interior is free. Default tilt is 60° around X; world gravity stays −Y.
The camera faces the opening. Mouse dragging uses a damped physical spring;
release removes the holding force and leaves gravity/contact response in charge.
This is a physics experiment, not production backpack/inventory integration.

Run the isolated capture from the repository root (Godot and ffmpeg on PATH;
Linux needs a working display, e.g. DISPLAY=:99 with Xvfb):

```sh
python tools/runtime/capture_soft_container.py --output /tmp/soft-container --tilt 60
```

The helper stages the scene without production autoloads, using Jolt at 240 Hz,
40 soft-body iterations and 0.09 m vertex contact radius. It leaves the main
project settings unchanged. Use `--tilt 0` for upright geometry. Directly opening
`scenes/experimental/soft_container_lab.tscn` starts manual LMB dragging, but
inherits the host project's physics settings. `--validate-only` checks parsing
without rendering.

`tilted-60.mp4` is the recorded six-body tilted run; `tilted-60.json` contains
all 648 source frames' body positions and six pick/release pairs. The 27-second
simulation is sped up 4.5× into a six-second, 1920×540, H.264 preview for reliable
mobile delivery. The preceding upright capture with 20% smaller bodies remains
local and is not included here. Rendered with Godot **4.6.3 stable**, Jolt and software
OpenGL Compatibility; the project baseline **4.8-dev6 .NET** is not validated.

The 4.6 Jolt implementation applies the configured point radius on a soft-body
space transition. The lab explicitly detaches/reattaches before simulation so
that this setting takes effect. No collision proxy or scripted fall replaces
the cloth/body interaction. Free-space targeting is a placement heuristic,
not an optimal packing solver. Captures do not establish continuous absence of
penetration or cloth self-collision, and pinned rims represent a supported bag.
Retain as an experiment; production acceptance and target-engine verification
remain outstanding.
