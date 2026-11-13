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
- the world's save payload and a fresh global RNG seed (see the finding below);
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

## Finding: the weather roll, not the CPU, moved the route

On TestScene the same tape first ended in three different places: 6.82, 4.83 and 4.01 m out.

**First reading, wrong and withdrawn.** I blamed the snow field's wall-clock rebuild budget, because
one fast run was idle and one slow run had a busy CPU.

**Measured cause.** `WeatherController` picks profiles with the global `randf()`, which Godot seeds
randomly on every launch. Different weather gives a different settled snow cover, a different depth
under Henry and so a different snow speed factor. Fixing the global seed proves it:

| `--seed` | End of route |
|---|---|
| 1 | 4.03 / 4.01 m |
| 2 | 4.84 / 4.82 m |
| 3 | 6.82 m |

Same seed, idle or loaded CPU: within 2 cm. The snow rebuild budget does not change gameplay: the
field image swaps only when it is complete.

**Fix.** At F9 the tape now stores:
- `world`: the full save payload (`SaveManager.capture_payload()`), covering weather, snow, tracks,
  thermal, inventory and containers;
- `rng_seed`: a fresh global seed the recorder sets.

The replay restores both (`SaveManager.apply_payload()`) before it moves Henry. A TestScene tape
re-recorded this way ended 4.79–4.80 m out on three runs with a random launch seed each. Without the
world snapshot the same runs spread 2.8 m.

The ice-lab shore route in `checks` has no weather and stays bit-exact.

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
