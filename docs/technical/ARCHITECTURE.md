# Hoarbound — Technical Architecture

> **AUTHOR DECISION / CANONICAL TECHNICAL CONTRACT**
>
> Hoarbound does **not** adopt a full-project ECS architecture. ECS / data-oriented design may be introduced only as a local subsystem where scale, profiling, or simulation shape gives it a concrete advantage. This decision is intentional and follows the genre: Hoarbound is a third-person systemic survival game built around a small number of high-complexity player-facing objects and interactions, with potentially large amounts of simpler world state.
>
> Russian companion: [`ARCHITECTURE_RU.md`](ARCHITECTURE_RU.md). The two files must remain semantically aligned. If wording diverges, the author's latest explicit decision is authoritative.

This document defines the technical direction of the production codebase. It is not a snapshot of every current implementation detail; `docs/GDD.md` describes current code-grounded state. This document describes the shape the codebase should move toward.

## 1. Architecture direction

The target model is:

`Godot Scene / Component Shell -> Domain Core -> Authoritative State -> Presentation`

With optional local data-oriented / ECS-style islands only where justified.

The project should not be rewritten around a speculative framework. Existing production systems should be consolidated toward this model incrementally when real work touches them.

## 2. Why Hoarbound is not pure ECS

Hoarbound's central engineering problem is not updating tens of thousands of homogeneous gameplay entities. It is maintaining clear ownership across a relatively small number of complicated, embodied systems:

- Henry, locomotion and animation;
- hands, carried objects and physical inventory;
- contextual interaction and attention;
- camera;
- shelter, windows, stove and domestic actions;
- survival state;
- weather and world exposure;
- persistence and streaming.

A full ECS would not remove these ownership problems. It could instead replace Node coupling with entity/component/system coupling plus an additional bridge back to Godot scenes, animation, physics and presentation.

Therefore ECS is a tool, not the foundation of the whole product.

## 3. Godot-native shell

Godot remains the runtime shell for the parts it already models well:

- scenes and authored world objects;
- physics bodies, collision and queries;
- animation and skeleton presentation;
- rendering and materials;
- camera nodes;
- audio emitters;
- physical props and interactable scene instances;
- editor-time composition and authoring.

Do not fight the engine by recreating these systems inside a project-specific framework without a measured reason.

A Node should exist because it participates in the scene/runtime lifecycle, not merely because some data needs a container. Plain data, `Resource`, `RefCounted`, or small domain objects are preferred for state and rules that do not require SceneTree ownership.

## 4. Domain core

Gameplay decisions should progressively become independent of incidental SceneTree structure.

Good candidates for domain logic include:

- interaction selection and permission rules;
- inventory ownership rules;
- hands / carry transaction rules;
- thermal and wetness calculations;
- fuel and burn state;
- weather state and exposure evaluation;
- save / restore state transforms;
- persistent world-object state;
- route or shelter-condition calculations.

The Godot shell gathers physical/runtime facts and executes results. The domain layer decides what those facts mean for gameplay.

The goal is not functional-programming purity. The goal is that core rules can be understood without following chains of scene lookups.

## 5. One owner per authoritative state

Every important question must have one clear owner.

| Question / state | Intended owner |
|---|---|
| What is Henry holding? | Hands / carry ownership |
| What belongs to inventory? | Inventory |
| Henry's thermal / survival state | Survival / thermal domain |
| Current weather state | Weather |
| What `F` means now | Interaction intent |
| Final camera transform | Camera pipeline |
| Persistent state of unloaded world objects | World persistence |
| Presentation of a state | UI / animation / VFX, never the authoritative owner |

Avoid mirrored state such as UI, Player, inventory and world object each storing their own version of the same fact.

When two systems need the same information, one owns it and the other observes or requests it.

## 6. Commands and contracts over reach-through

Cross-system communication should use narrow contracts rather than knowledge of another subsystem's internal scene tree.

Prefer conceptual relationships such as:

`Interaction -> Hands.request_take(item)`

`Interaction -> Locomotion.request_approach(target)`

`World object -> Inventory.try_store(item)`

over chains of:

`get_node(...) -> has_method(...) -> call(...)`

Signals are appropriate for facts that happened. Commands / explicit methods are appropriate when one owner asks another owner to perform an action.

Do not introduce a global event bus merely to hide dependencies. Dependencies should remain visible and directional.

## 7. Simulation is authoritative; presentation derives from it

Gameplay state must not depend on whether an animation, UI widget, shader or particle effect currently shows that state.

The direction is:

`authoritative state -> presentation`

not:

`presentation -> gameplay truth`

Examples:

- an animation may show Henry holding an object, but Hands owns whether he actually holds it;
- a frost shader may show window frost, but room/window state owns the frost amount;
- HUD shows survival state but does not own it;
- VFX visualizes wind and snow conditions but does not become the weather model.

## 8. Persistent entity identity

Streaming scenes must not define whether a persistent world object exists.

A persistent object should conceptually have:

`persistent ID -> authoritative state -> loaded scene representation`

The scene may unload while the state remains available for save/load and later reconstruction.

This model is particularly important for:

- doors and windows;
- shelter repairs;
- loot and consumed items;
- fires and fuel;
- placed objects;
- world damage;
- streaming chunks;
- future long-running world simulation.

Do not make scene-instance lifetime the only place where durable gameplay history exists.

## 9. Interaction direction

Interaction should move toward a pipeline with explicit responsibilities:

`Sensors -> Candidates -> Attention Resolver -> Interaction Intent -> Executor -> subsystem owner`

Typical subsystem owners include Hands, Locomotion, Inventory and the world object itself.

The current interaction implementation must not grow indefinitely into a single component that owns targeting, attention, storage, approach, animation, hands, UI semantics and every future interaction mode.

Split by ownership when responsibilities become independently meaningful, not merely because a file is long.

## 10. Camera direction

Camera behaviour should have one final owner and one ordered pipeline:

`Player intent -> Base camera target -> Context modifiers -> Collision / occlusion -> Presentation smoothing -> Final camera`

Shoulder state, passage framing, interaction framing, auto-look and similar behaviours should become modifiers or inputs to that pipeline rather than independent systems competing to move the camera.

Multiple subsystems must not independently own the final camera transform.

## 11. Selective ECS / data-oriented islands

ECS / data-oriented structures may be appropriate when the problem is genuinely large and homogeneous, for example:

- large persistent world-state tables;
- large-scale wildlife or ambient simulation;
- streaming / LOD bookkeeping;
- spatial environmental sampling;
- large amounts of footprint / decal metadata;
- batch processing of simple environmental entities;
- future simulations where profiling demonstrates Node/object overhead is material.

They are **not** the default architecture for:

- Henry;
- hands and embodied inventory;
- contextual interaction;
- camera;
- backpack handling;
- shelter rituals;
- unique physical props with complex authored behaviour.

Before introducing an ECS-style subsystem, state the concrete scale/performance/complexity problem it solves and how it bridges to the production Godot path.

## 12. No speculative framework

Do not build a universal "Hoarbound framework" in anticipation of hypothetical future systems.

The preferred sequence is:

`concrete production problem -> clear owner -> small stable contract -> second real use case -> generalize if useful`

A reusable abstraction should normally be justified by at least two real production consumers, not by imagined future flexibility.

Avoid:

- generic managers without a specific state responsibility;
- compatibility layers that preserve obsolete implementations;
- wrappers around engine-native mechanisms without a demonstrated need;
- parallel architecture paths for the same gameplay responsibility.

## 13. Refactoring policy

This architecture is a direction, not permission for a global rewrite.

When touching an existing production system:

1. identify its authoritative state owner;
2. identify cross-system reach-through and duplicated state;
3. preserve player-facing behaviour unless the task changes it;
4. move one responsibility at a time toward an explicit contract;
5. remove obsolete paths when the replacement is proven;
6. validate in the real runtime path.

Do not pause product development for theoretical architectural purity. Consolidation should reduce risk and make future work easier.

## 14. What "commercially healthy" means here

The target is not a fashionable architecture label. A subsystem is healthy when a collaborator can quickly answer:

- who owns the state?
- who is allowed to change it?
- how does another subsystem request a change?
- what is simulation and what is presentation?
- what persists after scene unload?
- which path is production and which is experimental?

If those answers are clear, the system is moving toward production shape.
