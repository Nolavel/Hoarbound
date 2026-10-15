<p align="center">
  <img src="icon.svg" width="160" alt="Hoarbound">
</p>

# Hoarbound

**Third-person systemic survival · Godot 4.8-dev6 .NET · PC**

Hoarbound is a survival game set in a frozen **Key West**. Henry leaves a bunker with limited supplies and must turn an abandoned house into a shelter capable of surviving the night.

Cold, wind, wet clothing, carried weight, fatigue, fuel and time are connected systems. The design goal is not to maintain meters for their own sake, but to make those systems change the player's route, priorities and willingness to take risks.

## Current production target — First Exit A

One continuous 10–15 minute loop:

`bunker -> route choice -> supplies -> worsening weather -> shelter -> repair -> stove -> recover/dry -> sleep/save -> reload`

The current closing work is human validation: a new player should be able to complete that loop without debug workarounds and understand at least one survival-driven change of plan.

The ordered build sequence and one-year plan live in [`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md).

## Project direction

- **Systemic survival:** weather, body state, carried load and time interact rather than living as isolated meters.
- **Shelter as an action:** a building is not automatically safe; the player repairs openings, manages fuel and creates usable warmth.
- **Physical interaction:** equipment, Quick Access and the backpack are moving toward readable diegetic handling rather than abstract menu-first interaction.
- **Real geography:** NOAA / OSM data underpins the Key West terrain and city; authored gameplay is layered on top.
- **Painterly 2.5D NPR:** full 3D geometry is presented with 2D painting logic — strong silhouettes, large colour/value masses, restrained PBR and surface-bound brushwork. The production contract is [`docs/art/ART_DIRECTION.md`](docs/art/ART_DIRECTION.md).
- **Winter presentation:** streamed snow, local deformation, footprints, weather and stylized rendering share one production world.

## Runtime

- Engine: **Godot 4.8-dev6 .NET**
- Renderer: **Forward+ / Vulkan**
- Main scene: `res://scenes/world/key_west/key_west_reality.tscn` (Key West Reality)
- Physics: **GodotPhysics3D** (Jolt tried and reverted, 2026-10-15)
- Current world: **Key West**

## Project documents

- [`PRD.md`](PRD.md) — product direction and current milestone
- [`docs/game_design/VERTICAL_SLICE.md`](docs/game_design/VERTICAL_SLICE.md) — First Exit A scope contract
- [`docs/GDD.md`](docs/GDD.md) — code-grounded gameplay / systems snapshot
- [`docs/technical/ARCHITECTURE.md`](docs/technical/ARCHITECTURE.md) — canonical technical architecture contract ([RU](docs/technical/ARCHITECTURE_RU.md))
- [`docs/technical/GDEXTENSION.md`](docs/technical/GDEXTENSION.md) — production C++ build, CI artifact and local install workflow
- [`docs/art/ART_DIRECTION.md`](docs/art/ART_DIRECTION.md) — production visual source of truth
- [`AGENTS.md`](AGENTS.md) — repository and agent workflow rules
- [`CONTRIBUTING_DECOMPOSITION.md`](CONTRIBUTING_DECOMPOSITION.md) — issue / milestone decomposition rules

## Status

**Active development — vertical slice.**

## Repository orientation

```text
┌─ PRODUCT ───────────────────────────────────────────────────────────────┐
│ GAME       Hoarbound — third-person systemic survival in frozen Key West.
│ TARGET     First Exit A — one 10–15 min bunker -> shelter -> sleep/save loop.
│ RUN        Godot 4.8-dev6 .NET -> F5 -> res://scenes/world/key_west/key_west_reality.tscn.
└────────────────────────────────────────────────────────────────────────┘

┌─ RUNTIME OWNERSHIP ────────────────────────────────────────────────────┐
│ GAMEPLAY   scripts/ + core/ + production scenes.
│ ROOT       world/world.gd is the runtime composition root.
│ INTERACT   InteractComponent owns player-side interaction intent/targeting.
│ SAVE       SaveManager coordinates persistence; subsystem state stays owned locally.
└────────────────────────────────────────────────────────────────────────┘

┌─ CHANGE SAFELY ────────────────────────────────────────────────────────┐
│ EXPERIMENT scripts/experimental/ is the explicit lab area.
│            tests/, tools/ and archive/ are support/history unless production references them.
│ DELETE     Delete only after proving no production, reference or retention dependency.
│            Archived or experimental does not mean disposable.
│ VERIFY     Import/compile -> focused test/runtime proof -> visual/play check if player-facing.
│ NEW SYSTEM Find owner -> one authoritative state -> small contracts -> no duplicate manager/state.
└────────────────────────────────────────────────────────────────────────┘

┌─ AUTHORITY ────────────────────────────────────────────────────────────┐
│ ARCH       docs/technical/ARCHITECTURE.md is the canonical technical contract.
│ AUTHOR     Product/design canon, scope, architecture-direction changes and main integration
│            require the author's decision.
└────────────────────────────────────────────────────────────────────────┘
```

Copyright © 2025–2026 Nolavel. All rights reserved. See [`LICENSE`](LICENSE).