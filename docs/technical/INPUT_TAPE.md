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

`report.json` holds the path every 30 frames, with speed and its snow, load and status factors, plus the end point and the frame-time stats. Any `--shots`
are saved as PNG; for real pixels, run under `xvfb-run` with Vulkan. With `--expect` the run fails
(exit 1) when the route ends further than the tolerance from the expected end.

## Evidence

- A synthetic TestScene tape, re-recorded by `TapeRecorder` during its own replay, gave the same 10
  events on the same frames and the same 61 look samples.
- **Without snow the replay is bit-exact.** In `ice_lab.tscn` (shore route), three idle runs and one run
  with all 4 cores busy ended on the same coordinates to the last digit.
  `checks` replays `tests/fixtures/input_tapes/ice_lab_shore_demo.json` with a 5 cm tolerance.
- `test_input_tape` covers the JSON round trip and the recorder's filtering.

## Finding: snow makes Henry's speed depend on the CPU

On TestScene the same tape ended in very different places.

| Run | End of route | Snow speed factor at frames 0 / 90 / 180 |
|---|---|---|
| idle CPU | 6.82 m from start | 0.90 / 0.90 / 0.78 |
| 4 cores busy | 4.01 m from start | 0.72 / 0.68 / 0.47 |

**Cause.** `SnowField.step_rebuild()` and `SnowChunkCover` advance by a **wall-clock** budget
(`Time.get_ticks_usec()`), not per frame. On a busy or slow CPU the field under Henry is less complete
at the same physics frame. `MovementController.snow_speed_multiplier` reads it, so gameplay speed
follows the hardware.

That is a determinism defect in the simulation. It may also matter for the HD 620 laptop: there,
Henry's speed and the snow around him would depend on how fast the CPU finishes the rebuild.

**Not fixed here:** snow work waits for the owner's HD 620 confirmation. Possible fix, for the owner to decide:
- keep the per-frame wall-clock budget for presentation only;
- make what the simulation reads (depth for speed and sinking) independent of how far the rebuild has
  got. For example, sample the last finished field until the new one is live, and never a half-built one.

## Known limits

- Nothing outside the input is restored: weather, time of day, the save state and streaming timing.
  Record from a fresh start or a known save, and compare like with like.
- Henry's start is set directly. A tape that starts mid-air or inside a door frame replays from there.

## Report bundle (F10)

`ReportBundle` (`core/diagnostics/report_bundle.gd`) writes one zip to `reports/` beside the exe, or to
`user://reports` in the editor. It contains:
- `report.json`: reason, version, OS, CPU, RAM, GPU, renderer, screen, locale, FPS;
- `BUILD_INFO.txt`;
- `settings.cfg`;
- the last 4000 lines of the session log;
- the newest tape;
- `world.json`: scene, Henry's position, camera, draw calls and primitives;
- a screenshot.

The `TesterReport` autoload saves one on **F10** (`report_bundle`) and shows where it went.

**Crashes:**
- `BuildLog` now starts each log with `session: v2` and ends it with `SESSION END` on a clean exit.
- On start-up it looks at the newest earlier log. A v2 log without the end line means the last run
  crashed or was killed, and `TesterReport` bundles that log automatically.
- Older logs without the header never trigger it.

**Verified on a Linux export:**
- after a `kill -9`, the next start saved a report with the killed session's log;
- a clean `--quit-after` run ended with `SESSION END`;
- the start after it saved nothing.

`test_report_bundle` covers the zip contents and the detection.
