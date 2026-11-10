# ADR 0003: GodotPhysics3D, and native C++ only after profiling

- **Status:** Accepted (author's play test and Technical Director rule), recorded 2026-11-06.
- **Owner:** the author for the physics engine (play feel); Claude for the native-code rule.

## Context

Two engine-level choices keep being proposed: switching 3D physics to Jolt, and moving systems to C++ for speed. Both
are attractive in general and both have been tried here.

- **Jolt.** It was tried on 2026-10-15. On CI, Buildings-part instantiation dropped from 9–18 ms to 2–3 ms and the
  gate showed frame-time parity (`REALITY_HLOD.md`). On the author's machine the game ran slower, with more hitches, and
  Henry's snow contact pushed him out erratically. It was reverted the same day.
- **Native code.** Jenova was evaluated and rejected for production. The approved path is GDExtension and godot-cpp
  (`GDEXTENSION.md`): portable math in `native/hoarbound_core/`, Godot adapters in `native/hoarbound_native/`, libraries
  built in GitHub Actions.

## Decision

- 3D physics stays GodotPhysics3D (`project.godot` `3d/physics_engine`).
- A system moves to C++ only after a profile shows a real bottleneck. Its public capability contract and its consumers
  stay unchanged (ADR 0002), and parity is proven before the GDScript version is removed.

## Alternatives weighed

- **Jolt by default** (Godot's default for new projects since 4.6). It is faster at mesh-shape builds, but it failed the
  author's play test, which is the acceptance criterion for movement feel.
- **C++ first for anything heavy-looking.** It costs a compiled library per platform and a slower edit loop, for
  speed-ups nobody has measured.

## Cost

- GodotPhysics3D's slower concave-shape attach on streaming: the fort chunk needs a simplified collision mesh, an asset
  task.
- Some code stays slower than it could be until it is measured.

## Revisit when

- **Jolt.** A profile on the author's own route (the snow contact and the 727 loop) shows parity or better, and the
  author's play test accepts the movement feel.
- **Native.** A profiler trace names the function and its frame cost on a real route.
