# Input tape — record a real route once, replay it after every change

Status: **implemented** (`core/diagnostics/input_tape*.gd`, `tools/runtime/replay_input_tape.*`).
Origin: idea #1 in issue #213 (godot-stagehand). The idea was taken; the code was not.

## Record

Press **F9** in any scene that has Henry (`dev_input_tape`), play, and press **F9** again. The
`TapeRecorder` autoload writes `tape_<time>.json`:
- exported builds: `tapes/` beside the executable, like `logs/`;
- editor: `user://tapes`.

A red badge shows while recording.

The tape stores:
- the scene and Henry's start transform;
- the camera's start yaw and pitch;
- every gameplay **action** event (press, release, strength) at its physics frame, so keyboard and
  gamepad give the same tape and the key layout does not matter;
- the camera's yaw and pitch per physics frame. Look is stored as state, not mouse deltas, so the
  mouse sensitivity setting cannot bend a replay.

Menu (`ui_*`), `pause` and developer keys are not recorded.

## Replay

```
godot --path . --fixed-fps 60 res://tools/runtime/replay_input_tape.tscn -- \
  --tape=<tape.json> --out=<dir> [--shots=120,600] [--expect=<report.json>] [--tolerance=0.25]
```

The replay:
1. opens the tape's scene with the real autoloads;
2. lets it settle;
3. puts Henry and the camera at the start;
4. feeds the actions back as `InputEventAction`s and the look through `TpsCamera.set_look`.

`report.json` holds the path (every 30 frames), the end point and the frame-time stats. Any `--shots`
are saved as PNG; for real pixels, run under `xvfb-run` with Vulkan. With `--expect` the run fails
(exit 1) when the route ends further than the tolerance from the expected end.

## Evidence

- A synthetic TestScene tape, re-recorded by `TapeRecorder` during its own replay, gave the same 10
  events on the same frames and the same 61 look samples.
- Two replays ended 7 mm apart, and a third 14 mm away, so physics is not bit-exact. The CI tolerance is
  0.25 m.
- `checks` replays `tests/fixtures/input_tapes/testscene_demo.json` against its expected end.
  `test_input_tape` covers the JSON round trip and the recorder's filtering.

## Known limits

- Nothing outside the input is restored: weather, time of day, the save state and streaming timing.
  Record from a fresh start or a known save, and compare like with like.
- Henry's start is set directly. A tape that starts mid-air or inside a door frame replays from there.
