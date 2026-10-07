# Hoarbound — Code-Grounded Game Design Document

> **Document type:** living runtime/design snapshot, not a wish list.  
> **Audit basis:** `codex`, runtime snapshot `804887cb248cd5d9d68f7723bb0ad94419b1ea8a` (2026-10-04).  
> Re-audit volatile implementation details before treating this document as proof of current code state.

This GDD separates **what the game intends to be** from **what the runtime actually supports**. A resource name, input action, archived scene or legacy script is not evidence that a mechanic is production-ready.

## Status vocabulary

- **IMPLEMENTED** — present in the production runtime path with a clear owner / integration point.
- **PARTIAL** — substantial implementation exists, but the end-to-end player flow or production integration is incomplete.
- **MENTIONED** — present in design notes, data, enums or legacy code but not confirmed as a production mechanic.
- **ABSENT** — no current production implementation found.

## Sources of truth

For implementation status, prefer this order:

1. `project.godot` — startup, input, renderer and global configuration.
2. Production `.tscn` composition and resources actually instantiated by it.
3. `world/world.gd`, `core/**/*.gd`, `scripts/**/*.gd` — runtime ownership and system wiring.
4. `data/**/*.tres` / `data/**/*.json` — authored gameplay and world data.
5. `PRD.md`, `README.md`, `docs/game_design/VERTICAL_SLICE.md` — product intent and scope, not automatic proof of implementation.
6. `archive/`, tests, CI tools and addon demos — history / support infrastructure unless explicitly referenced by production.

# 1. High concept

**IMPLEMENTED + documented intent**

Hoarbound is a third-person systemic survival game set in a frozen Key West. Henry manages cold, wind, wet clothing, hunger, hydration, fatigue, carried weight, fuel and time while trying to turn unsafe structures into temporary shelter.

The current product target is **First Exit A: One Land Night**, a short bunker-to-shelter survival run whose final acceptance is human playability rather than feature count.

Primary current documents:

- `PRD.md`
- `docs/game_design/VERTICAL_SLICE.md`
- issue #42

# 2. Design pillars

## 2.1 Survival decisions, not meter maintenance

**IMPLEMENTED / PARTIAL**

Systems should change route, timing and inventory decisions rather than exist as isolated bars.

Current runtime evidence includes:

- carried load affects inventory capacity, movement and fatigue;
- clothing insulation is reduced by wetness and can recover through drying / heat;
- weather, simulation time, thermal state and snow presentation share production ownership rather than independent clocks;
- hunger, hydration and fatigue have dedicated state owners.

Representative owners:

- `InventoryComponent`
- `EquipmentComponent`
- `MovementController`
- `BioMonitorManager`
- `ThermalManager`
- `SimulationClock`
- `WeatherController`

Human acceptance is still required to prove that these systems actually alter decisions during First Exit.

## 2.2 Shelter as an action

**IMPLEMENTED / PARTIAL**

A shelter is not simply a safe trigger volume. The current stack supports:

- repairable breaches / windows;
- carried boards and hammer work;
- door / exposure state;
- stove / heat-source fuel;
- warming and drying;
- rest / sleep;
- persistence of relevant shelter state.

Important runtime areas include `breach_board_up.gd`, `shelter_breach.gd`, `shelter_state.gd`, heat-source / stove scripts and the First Exit shelter content.

The remaining question is player pressure and readability, not whether those classes exist.

## 2.3 Physical handling of gear

**IMPLEMENTED / PARTIAL**

Items use data-driven `ItemResource` definitions with inventory, equipment, Quick Access, held-item, carry and per-item fit paths.

The production direction is diegetic handling without duplicating ownership. Current work under #198 / #203 explores controlled 3D backpack placement on top of the existing inventory backend.

## 2.4 Weather and world as survival pressure

**IMPLEMENTED / PARTIAL**

Weather, day/night, snow, world exposure and thermal simulation are systemic sources of pressure. The current Key West world combines real geographic data with authored First Exit content and streamed city / winter presentation.

# 3. Current First Exit loop

**Documented target:**

`bunker -> choose land route -> gather/carry useful supplies -> weather turn -> shelter -> repair -> stove -> recover/dry -> sleep -> save/reload`

Current runtime support includes:

1. **Movement / exploration — IMPLEMENTED**  
   CharacterBody3D Henry, TPS camera, walk / crouch / sprint / jump, slope response, stamina and systemic modifiers.

2. **Interaction / pickup — IMPLEMENTED**  
   Central interaction path with reusable world interactables and pickups.

3. **Inventory / carry — IMPLEMENTED**  
   Weight-based loose inventory plus special physical carry rules.

4. **Survival simulation — IMPLEMENTED**  
   Hunger, hydration, fatigue and thermal simulation advance through production time ownership.

5. **Shelter work — IMPLEMENTED / PARTIAL**  
   Repair, doors, stove, heat, rest and related world state exist; human readability remains under playtest.

6. **Time-costed actions — IMPLEMENTED**  
   Long actions can advance canonical simulation time through the shared action system.

7. **Sleep / save — IMPLEMENTED / PARTIAL**  
   Sleeping is the in-play save trigger. Individual persistence contracts are substantial; the First Exit human reload proof remains a closing gate.

# 4. Player abilities and interaction surface

| Area | Status | Notes |
|---|---|---|
| Walk / directional locomotion | IMPLEMENTED | Production movement controller |
| Sprint + stamina | IMPLEMENTED | Stamina-gated movement |
| Crouch | IMPLEMENTED | Movement / body-state support |
| Jump | IMPLEMENTED | CharacterBody3D movement path |
| Lean / shoulder camera controls | IMPLEMENTED / PARTIAL | Present in current input / camera stack |
| Interact press / hold / release | IMPLEMENTED | Shared interaction path |
| Pickup / store / use items | IMPLEMENTED / PARTIAL | Backend is real; presentation continues to evolve |
| Bulky hand carry | IMPLEMENTED | Separate from loose backpack storage |
| Quick Access | IMPLEMENTED / PARTIAL | Physical pocket / access concept |
| Clothing / insulation | IMPLEMENTED | Equipment feeds thermal model |
| Breach / hammer work | IMPLEMENTED | Shelter repair path |
| Bedroll | IMPLEMENTED / PARTIAL | Placement / persistence exists; human-flow acceptance still matters |
| Snow handling | IMPLEMENTED / PARTIAL | Item / world interaction exists |
| Held flare / light | IMPLEMENTED / PARTIAL | Hand presentation and VFX path exist |
| Narrow-passage traversal | IMPLEMENTED / PARTIAL | Bounded authored traversal support |

The presence of the legacy `fire` input action does **not** mean a production combat system exists.

# 5. Progression model

**PARTIAL / systemic rather than meta-progression**

No confirmed XP, level, perk or skill-tree system is part of the current production loop.

Progress currently comes from persistent changes to:

- inventory and consumed resources;
- worn equipment / accessible storage;
- shelter repair and fuel state;
- world pickups;
- time / weather / thermal consequences;
- sleep/save checkpoint state.

Formal quest or character-progression frameworks should not be inferred from old docs.

# 6. Combat, enemies and tools

## Combat / enemies

**ABSENT from First Exit production scope**

Combat and enemies are explicitly out of First Exit A. No current production enemy / weapon stack should be assumed from old concepts or leftover inputs.

## Tools

**IMPLEMENTED / PARTIAL**

Axe, knife, hammer, lighter and similar resources exist as survival tools / item data. Their presence does not imply a combat weapon framework.

# 7. Survival systems

## Thermal / cold — IMPLEMENTED

`ThermalManager` owns body-temperature pressure, felt temperature, wind chill, insulation, wetness penalties, drying, exertion heat and shelter / heat-zone effects.

## Clothing / wetness — IMPLEMENTED

Runtime garment state and equipment feed effective insulation / wetness into the thermal model.

## Hunger / hydration / fatigue — IMPLEMENTED with partial depth

Dedicated components own the needs. Some modifier seams remain simple / unused, so the system should not be described as deeper than current data supports.

## Health / afflictions — IMPLEMENTED / PARTIAL

Health and persistent affliction foundations exist. Do not infer a full disease / injury catalogue beyond authored data.

## Carry pressure — IMPLEMENTED

Load affects inventory limits and feeds movement / fatigue pressure.

## Fire / shelter / drying — IMPLEMENTED / PARTIAL

Runtime wiring exists; First Exit still needs end-to-end player acceptance.

## Weather — IMPLEMENTED

`WeatherController` is the weather authority. Authored WeatherBeat and persistence exist.

## Snow — IMPLEMENTED / PARTIAL

Snowfall, streamed cover, local SnowShell deformation, footprints and track persistence are production systems. Heavy deformation is not a reason to expand First Exit scope indefinitely.

## Thin ice — CODE EXISTS, NOT FIRST EXIT A

Ice / cold-water systems exist in the repository, but Coast / Thin Ice is a later slice and should not be presented as a required First Exit mechanic.

# 8. Inventory and equipment ownership

The important production rule is **one logical owner per item**.

Current player-side structure includes:

```text
EquipmentComponent  -> worn gear / physical equipment locations
InventoryComponent  -> loose carried inventory
PlayerHubComponent  -> presentation / management
QuickAccessComponent -> fast physical access layer
HeldItemComponent   -> item currently in hand
CarryComponent      -> bulky physical carry
ConsumptionController -> item consumption / body effects
```

The 3D backpack work must extend this model, not create another inventory database.

# 9. Saving and persistence

**IMPLEMENTED / PARTIAL end-to-end acceptance**

`SaveManager` provides versioned save data and a participant contract:

```text
get_save_key()
get_save_data()
load_save_data(data)
```

Known persistence ownership covers major player, weather, thermal, shelter, snow / track and world-pickup state.

**Sleep = autosave** is a current design rule. The remaining product proof is a coherent human First Exit run through sleep and reload.

# 10. World structure

## Production world

`project.godot` launches `res://scenes/world/key_west/key_west.tscn`.

`world/world.gd` is the composition root for world systems, shared context and UI / runtime services.

## Key West

The world uses baked real-world terrain / city data and deterministic authored First Exit content. City geometry / enrichment participates in the shared streaming path rather than defining a second world owner.

## Archived / legacy world content

Graciosa and older chunk assets may remain for history, tests or reusable content. Their presence does not make them part of the current Key West production route.

# 11. Streaming

**IMPLEMENTED / PARTIAL tuning**

`StreamingSystem` owns bounded chunk lifecycle and runtime source registration. Key West city content uses runtime chunk sources / HLOD-style representation.

Performance tuning is tracked separately; do not create a parallel streaming manager for local content problems.

# 12. UI / UX

Current player-facing / development UI includes:

- dynamic interaction cursor / prompts;
- vital HUD;
- Player Hub / inventory presentation;
- pause / sleep UI;
- developer stats / map tools where enabled.

The project still needs deliberate release gating for developer-only UI.

# 13. Audio

**IMPLEMENTED / PARTIAL**

`SoundSystem` and world audio binding exist, with weather / shelter / surface context available to runtime audio. Route-specific ambience remains polish rather than proof of a complete adaptive audio system.

# 14. Camera and locomotion

Third-person camera and locomotion are production systems. Camera responsiveness / collision quality is tracked under #170.

The desired architecture is centralized input ownership, but direct input reads have historically existed in player / movement code; treat that rule as something to verify rather than assume fully enforced.

# 15. Technical architecture

- Engine target: Godot 4.8-dev6 .NET / Forward+
- Gameplay runtime: predominantly GDScript
- Composition root: `world/world.gd`
- Dependency context: `WorldContext`
- Canonical simulation time: `SimulationClock`
- Major authoring: Resources / JSON for items, equipment, world profiles, terrain and city data
- Rendering / snow / world systems are expected to remain bounded for the project's low-end target

# 16. Current product limitations / risks

These are more important to collaborators than dormant feature ideas:

1. **First Exit still needs human end-to-end proof.** Working systems are not the same as a readable game loop.
2. **Combat / enemies are intentionally absent from A.** Do not interpret old inputs or legacy docs as permission to build them.
3. **Thin ice is later scope.** Existing code does not change the milestone contract.
4. **No formal quest / meta-progression framework is currently required.** World state and survival pressure carry the opening loop.
5. **Key West / city technology still requires performance and traversal acceptance on low-end hardware.**
6. **Developer tooling must remain clearly separated from release-facing UI.**
7. **Legacy HFN / Graciosa / Gizmo naming may survive in technical history.** Current product identity and First Exit direction take precedence.
8. **The project has more systemic capability than the vertical slice has proven in human play.** Feature expansion should not hide usability, pacing or balance problems.

# 17. Current design authority

When documents disagree, use this order for current work:

1. direct owner decision;
2. current production code / scene composition for implementation facts;
3. `PRD.md` for product scope;
4. `docs/game_design/VERTICAL_SLICE.md` for First Exit A;
5. current owning GitHub issue;
6. this code-grounded GDD snapshot;
7. legacy / historical design documents.

The older `docs/game_design/GameDesignDocument.md` is retained as legacy vision context and is **not** a production requirements document.