# Claude's shared memory for Hoarbound: index

Loaded in every session. Topic files load on their own when their `paths:` code is touched.
Each entry carries a tag: **VERIFIED** (evidence named), **ASSUMPTION** or **TEMPORARY**, plus a date.
Change these files only through a PR to `main`; prune what is stale when you touch it.

## Topic files

- `hands-hub-storage.md`: what Henry holds, Quick Access, the Hub, pockets and the pack.
- `time-sleep-save.md`: the simulation clock, sleep and waiting, save and load.
- `godot-headless.md`: running suites and probes in this repository.
- `key-west-reconstruction.md`: sources, screenshots and documented buildings for the real Key West.

## Lessons that apply everywhere

- **VERIFIED 2026-11-17: a picture must not claim a state the simulation lacks** (ARCHITECTURE §8, Pillar 18).
  - The flare was "fixed" in the 01–03 QA pass by giving the Hub card a model. The real gap remained: nothing put the flare in the hand.
  - The owner found it again on 17.11 (fixed in #336). Fix the state, then let the picture follow.
- **VERIFIED 2026-11-17: fix the seam, not the item.**
  - "Held in the Hub, gone after closing" hit the hammer (0.312, #42) and later the flare.
  - Each fix was item-specific, so the class came back. Before closing such a bug, walk the item through every state of its seam (see the topic file).
- **VERIFIED 2026-11-17: Godot built-ins first.** The owner had to name `AreaLight3D` for the Hub light; the class reference had it. Search the 4.8 class reference before writing a system.
- **VERIFIED 2026-11-17: `look_at` fails near the target at Key West's coordinates.** Its equality tolerance is relative: about 3 cm at (−3533, 1592). Guard by distance, not by `is_equal_approx` alone (`Player.face_work_target`, `test_throw_aim_facing`).
- **VERIFIED 2026-11-17: facing a direction that moves as you turn feeds back.** The snowball aim spun Henry. Take the aim heading from the camera's control yaw, as TPS games do.
