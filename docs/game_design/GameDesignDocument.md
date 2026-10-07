# Hoarbound — Legacy Vision Notes

> **Status: historical / non-authoritative design context.**  
> This file is preserved because it contains early ideas that may still be useful as reference. It is **not** the current production requirements document.
>
> For current work use:
> - `PRD.md` — product direction and milestone scope;
> - `docs/game_design/VERTICAL_SLICE.md` — First Exit A contract;
> - `docs/GDD.md` — code-grounded runtime/design snapshot.

## Why this file is legacy

This document originated before the current Key West / First Exit production direction stabilised. It contains concepts that are no longer part of the current vertical slice and, in some cases, are not implemented at all.

Historical ideas include:

- a 2159 nuclear-winter framing;
- underground cities such as Fernvale and Lorong;
- Gizmo as an active miniature robot companion;
- tactical combat and enemy encounters;
- radiation avoidance;
- large crafting / resource systems;
- non-linear narrative and moral-choice structures;
- cursor-following / snap-turn control concepts from earlier prototypes.

None of those concepts should be treated as permission to expand First Exit A.

## Ideas that still overlap with current Hoarbound

Some early pillars survived in a different form:

- **Henry is forced out of protected shelter** and must learn to survive on the surface.
- **Third-person survival** remains the core format.
- **Physical inventory / item handling** remains an important presentation goal.
- **Sleep is tied to saving** and reaching a viable shelter state.
- **Cold, food, water and environmental pressure** remain central survival concerns.
- **Atmosphere and deliberate pacing** matter more than constant combat.

The current implementation expresses these ideas through frozen Key West, First Exit, shelter repair, systemic weather / thermal pressure, diegetic equipment and the Kenny companion concept.

## Historical high concept

The earlier pitch described young Henry Moss being cast out of an underground bunker into a world dominated by prolonged nuclear winter. He would search for refuge while travelling with an active robot companion and eventually encounter combat, radiation and narrative choices.

That pitch is useful as provenance, but it is **not** the current opening game contract.

## Historical design themes

### Atmosphere

The early direction combined post-apocalyptic winter, cinematic third-person presentation, meditative exploration and occasional high-pressure encounters.

### Survival

The old concept already emphasized body warmth, food, water, resource gathering and safe sleep. Current Hoarbound keeps those systemic concerns but tests them through a smaller, more grounded route-and-shelter loop.

### Physical interaction

The legacy design called for a physical 3D inventory and close interaction with carried objects. This remains relevant and is now pursued through the existing inventory / equipment ownership model and the embodied interaction workstream.

### Save structure

Safe sleep as a save rule remains one of the clearest ideas carried forward into production.

## Explicit non-authority

Do not use this file to justify adding, during First Exit A:

- combat or enemies;
- radiation gameplay;
- active Gizmo abilities;
- large crafting trees;
- new story-choice systems;
- old control schemes that conflict with the current TPS camera / input grammar.

If a legacy idea returns, it should be reintroduced through a current product decision and a new scoped issue rather than by citing this document.

## Current references

- [`../../PRD.md`](../../PRD.md)
- [`VERTICAL_SLICE.md`](VERTICAL_SLICE.md)
- [`../GDD.md`](../GDD.md)
- GitHub issue #42 — First Exit A
- GitHub issue #198 — Embodied Interaction Stack