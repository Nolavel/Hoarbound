# Embodied Interaction — foundation contract

This document is the small shared contract under issue #198. It is intentionally narrower than a gameplay framework: current locomotion, inventory, doors and ice keep their existing ownership until a feature explicitly migrates to this contract.

## Design rule

Hoarbound targets convincing authored physicality, not exhaustive simulation.

`intent -> affordance/target -> align -> authored action -> selective physics/world-state change -> release`

Animation and physics present the action. Deterministic gameplay state remains authoritative for inventory ownership, door state, traversal result, ice integrity and save/load.

## Coordinate convention

- Godot world `+Y` is up.
- Henry's authored visual forward is `+Z` (the current UAL/Henry contract).
- `EmbodiedTarget3D.global_transform.origin` is the desired contact/alignment point.
- For a BODY target, the marker basis represents the desired final body facing.
- Hand/foot targets are contact hints relative to world geometry; they do not move gameplay state by themselves.

Do not introduce per-feature axis conventions. A door, ledge, backpack and tool all expose targets using the same transform meaning.

## Target roles

The initial authoring primitive supports:

- `BODY` — final body alignment transform.
- `LEFT_HAND`, `RIGHT_HAND` — contact/IK hints.
- `LEFT_FOOT`, `RIGHT_FOOT` — optional grounding/traversal hints.
- `EXIT` — authored action exit transform.
- `ITEM_PLACEMENT` — deterministic item-placement anchor/volume seed.

A target is metadata. It must not run an action or move Henry on its own.

## Character ownership

Normal movement stays owned by the existing `CharacterBody3D` / `MovementController` path.

Future embodied actions must explicitly acquire and release movement ownership. Only one owner may write Henry's body transform in a given action phase.

Initial phases:

`IDLE -> APPROACH -> ALIGN -> ACTION -> RELEASE -> IDLE`

The current prep lab demonstrates the seam only; it is not production traversal and does not replace `MovementController` or `HenryUALAnimation`.

## Skeleton contract

The existing UAL/Henry skeleton remains canonical. The prep validator checks semantic roles without renaming or reimporting bones:

- root
- pelvis
- head
- left/right hand
- left/right foot

Bone aliases exist only to make the validator tolerant of capitalization. Feature code should bind semantic roles once rather than rediscover bone names independently.

## Item authoring convention

When existing item scenes are migrated, prefer these marker names rather than hard-coded offsets:

- `GripRight`
- `GripLeft`
- `InspectPivot`
- `PlacementPivot`

The markers define presentation transforms only. Inventory/container state remains deterministic.

## Explicit non-goals of the foundation

- no Motion Matching dependency;
- no Smart Object registry/global manager;
- no new autoload;
- no replacement locomotion controller;
- no procedural climbing framework;
- no runtime mesh fracture;
- no physical backpack solver;
- no production IK/warping implementation yet.

## Prep proof acceptance

The isolated lab should visibly demonstrate:

1. Henry begins outside the BODY target.
2. BODY and RIGHT_HAND targets are visible independently of Henry.
3. Henry aligns to the BODY target using a bounded authored transition.
4. The existing `interact` animation starts only after alignment.
5. The action ends and control returns to the normal/idle owner.
6. Skeleton validation reports missing semantic bones instead of silently failing.

This proof exists to validate the seam before mantle, backpack, pry-door or thin-ice gameplay is built.
