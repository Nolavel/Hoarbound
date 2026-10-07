# Embodied Interaction — foundation contract

This document is the small shared contract under issue #198. It is intentionally narrower than a gameplay framework: current locomotion, inventory, doors and ice keep their existing ownership until a feature explicitly migrates to this contract.

## Design rule

Hoarbound targets convincing authored physicality, not exhaustive simulation.

`intent -> affordance/target -> align -> authored action -> selective physics/world-state change -> release`

Animation and physics present the action. Deterministic gameplay state remains authoritative for inventory ownership, door state, traversal result, ice integrity and save/load.

## Coordinate convention

- Godot world `+Y` is up.
- Henry's authored visual forward is `+Z` (the current UAL/Henry contract).
- The interaction object's world transform supplies the contact point.
- Body alignment is a collision-checked `CharacterBody3D` stance in front of that object.
- Hand targets are short-lived IK hints; they do not move gameplay state by themselves.

Do not introduce per-feature axis conventions. A door, ledge, backpack and tool all expose targets using the same transform meaning.

## Character ownership

Normal movement stays owned by the existing `CharacterBody3D` / `MovementController` path.

Future embodied actions must explicitly acquire and release movement ownership. Only one owner may write Henry's body transform in a given action phase.

Initial phases:

`IDLE -> APPROACH -> ALIGN -> ACTION -> RELEASE -> IDLE`

The current lab drives the production `HenryUALAnimation` action path. It does not replace `MovementController`, inventory ownership, or production item fitting.

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
- no custom arm or finger solver;
- no motion-matching or GASP clone;
- no semantic success rule based on rendered fingertip pixels.

## Pickup proof acceptance

The isolated lab must visibly and semantically demonstrate:

1. Five cylinders at head, chest, waist, knee, and floor context.
2. Henry chooses left or right from measured live arm reach and target side.
3. A complete existing UAL action plays through contact and back to idle.
4. Godot `TwoBoneIK3D` only corrects the selected wrist near contact.
5. Henry holds each cylinder in idle, then returns the first four to their origins.
6. The floor cylinder is lifted while Henry rises, then transferred right-to-left.
7. Skeleton validation and a machine-readable capture report fail loudly on an incomplete sequence.

This proof validates the narrow production path before the same pattern is applied to mantle, backpack, pry-door, or thin-ice gameplay.
