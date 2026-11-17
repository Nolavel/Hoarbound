---
paths:
  - "scripts/systems/time/**"
  - "scripts/systems/save/**"
  - "scripts/systems/actions/**"
  - "scripts/actors/player/henry/held/held_flare.gd"
  - "scripts/actors/player/henry/held/held_searchlight.gd"
  - "core/contracts/simulation_participant_capability.gd"
  - "core/contracts/save_participant_capability.gd"
---
# Simulation time, sleep and save

## Design constraint

World memory (Pillar 18): heated things cool, spent things stay spent, and every change survives sleep and save/load. Sleep is the autosave.

## Facts (VERIFIED 2026-11-17, code)

- `SimulationClock` owns time. Realtime advances in small slices (`REALTIME_REASON`). Sleep (`&"sleep"`) and waiting (`&"wait"`) advance in jumps through `advance_hours`.
- Anything that burns, drains or ages must be a `SimulationParticipantCapability` participant. A participant registers with the clock and is advanced for every reason.
  - Ignore `REALTIME_REASON` only if `_process` already counts frame time; otherwise a skip leaves it untouched.
  - Missing this let a flare burn on after hours of sleep (`test_flare_sleep_burn`, #336).
- The flare's burn is 75 real seconds, which is 30 game minutes (`rated_game_hours = 0.5`).
- A node created after `on_world_ready` is not registered by the clock: register it yourself (`HeldFlare._ready`).
- Save participants map their state through `SaveParticipantCapability` (`key / capture / restore`).

## Open (ASSUMPTION 2026-11-17)

- A flare left burning on the ground is not part of the save (grep of `scripts/systems/save` finds no flare state). Not verified by a test.
