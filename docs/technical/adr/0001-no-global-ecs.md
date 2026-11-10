# ADR 0001: No project-wide ECS

- **Status:** Accepted (author decision), recorded 2026-11-06.
- **Owner:** the author; engineering recorded by Claude (Technical Director).

## Context

Hoarbound is a third-person systemic survival game. Its hard engineering is a small number of complicated, embodied
systems near the player (Henry and his locomotion and animation, hands and carried objects, the pack and pockets,
contextual interaction, the camera, shelter rituals such as the stove and windows) plus a larger amount of simpler
world state (weather, streaming, persistent objects). The engine already models scenes, physics, animation, rendering
and audio as nodes.

## Decision

The project is not built on a global ECS. The shape is
`Godot Scene / Component Shell -> Domain Core -> Authoritative State -> Presentation` (ARCHITECTURE §1–4). A local
ECS-style or data-oriented island is allowed where a large, homogeneous problem justifies it (ARCHITECTURE §12).

## Alternatives weighed

- **Full ECS (a framework or a home-grown one).** It suits tens of thousands of homogeneous entities. It does not solve
  Hoarbound's real problem, which is ownership between a few complex systems. It would add an entity/component bridge
  back to Godot's scene tree, physics, animation and rendering, so every embodied system would cross that bridge.
- **Plain nodes with no rules.** It is what Godot gives by default. It drifts into reach-through (`get_node` chains,
  `has_method` probes) and duplicated state.

## Cost

- No uniform data layout for mass entities: large homogeneous simulations need their own island when they appear.
- Ownership and contracts must be kept by discipline and tests (ARCHITECTURE §5, §16), not by a framework.

## Revisit when

- A profile on a real route shows that node or object overhead of homogeneous entities (wildlife, ambient simulation,
  world-state tables, footprint metadata) is a material frame cost. Then the answer is a data-oriented island for that
  subsystem, bridged to the production path, not a global rewrite.
- Or a proposal shows a concrete Hoarbound ownership problem that an ECS removes, with the bridge cost measured.
