# Vertical Slice — First Exit A: One Land Night

**Status:** current production target; core implementation exists, human end-to-end acceptance is still open.

This document is the scope contract for the first playable Hoarbound slice. Product intent lives in `PRD.md`; code-grounded implementation status lives in `docs/GDD.md`; world coordinates and authored placement live in the Key West world data / docs.

Reference for decision pressure: *The Long Dark*. Tone reference: *The Road*.

## 1. Scope split

### First Exit A — land night

One uninterrupted survival run in the current **Key West** production world:

`Battery Osceola bunker exit -> choose road / exposed shore / ruins -> collect useful supplies -> weather worsens -> reach 727 Fort Street -> repair openings -> light/feed stove -> recover/dry -> sleep/save -> reload`

Battery Osceola and 727 Fort Street are the canonical route endpoints. The former custom Fort Street hut remains present but no longer owns the primary First Exit shelter role. Issue #211 owns the remaining generator/runtime migration.

There is **no required thin-ice route in First Exit A**.

### Coast / Thin Ice — later slice

Coastal ice is a later gameplay problem built on the maritime geography around Key West. Ice simulation code may exist in the repository, but it is not part of the First Exit A completion contract.

## 2. Player fantasy

Henry has been forced out of a protected bunker into a frozen version of a place that was never built for permanent cold.

The opening problem is environmental rather than combat-driven: can he read the landscape, carry enough useful material, react to worsening weather and make one bad building survivable before he loses the safe window?

Kenny is carried on Henry's backpack during this phase. He is not an active ability companion in First Exit A; his physical presence and weight matter before his future functionality does.

## 3. Current production foundation

The slice already has substantial system support:

- Key West terrain and city generated from real geographic data;
- data-driven First Exit route / content placement;
- road / shore / ruins route grammar;
- Henry third-person locomotion, camera and interaction path;
- thermal model with ambient cold, wind, shelter, wetness, clothing and heat;
- weather profiles and authored WeatherBeat;
- hunger, hydration, fatigue and carried-load pressure;
- Player Hub, Quick Access, held items and physical carry rules;
- shelter with repairable openings and an operable door;
- boards, nails, hammer work and breach state;
- stove, fuel, cooking / water / warming workflows;
- contextual rest / sleep and sleep-driven save;
- persistence for inventory, equipment, shelter, weather, bedroll and consumed authored pickups;
- snow / snowfall / footprint presentation integrated with the world.

Implementation existence is not the final gate: the loop still needs to work coherently for a person who does not know the project.

## 4. Current supply candidate

The live candidate intentionally keeps the currently authored increased supply pool, including bonus stacks. Current production docs record **33 boards, 66 nails and 12 logs**.

This run validates the complete interaction loop and decision readability. It does **not** prove the older reduced-stock scarcity balance.

Do not silently remove supplies while rebuilding / regenerating the scene unless the owner explicitly reopens balance.

## 5. Remaining blockers

### Weather turn — implementation complete, decision effect unproven

`WeatherBeat` already uses the existing weather authority and persists its state. The remaining question is whether its timing materially changes a new player's return decision.

Tracked in #78.

### Systemic pressure — implementation largely complete, player read unproven

Weight, wetness, fatigue and exposure already affect simulation. The remaining question is whether they interrupt the fixed “collect everything, then do the checklist” behaviour.

Tracked in #134.

### Continuous stranger run — P0 closing gate

Tracked in #80.

Required run:

1. start at Battery Osceola;
2. recognise at least two route options without a map;
3. find, carry and use supplies;
4. experience the authored weather turn;
5. reach 727 Fort Street;
6. make meaningful repair / fuel decisions;
7. light and maintain the stove;
8. warm / dry / recover enough to sleep;
9. sleep and save;
10. reload into a coherent world state.

If a required step needs a debug teleport, console call, TestScene shortcut or manual state repair, it remains a blocker.

## 6. Readability / P1 quality

After the P0 loop closes, improve the slice without creating new subsystems:

- verify major route landmarks at normal TPS distance;
- verify Kenny reads clearly as carried physical mass;
- improve route-specific environmental audio using existing exposure / weather ownership;
- capture a small publisher-proof image / video set from the accepted run.

Prefer better placement, scale, pose, timing and feedback over broad new technology.

## 7. First Exit A is done when

- [ ] A new player completes Battery Osceola -> 727 Fort Street -> sleep/save in roughly 10–15 minutes.
- [ ] At least two land routes are readable without a map.
- [ ] The player can make a poor decision around time, greed, weather or carried load and understand the consequence.
- [ ] Shelter preparation requires choices rather than functioning as an automatic safe room.
- [ ] Sleep/reload restores coherent shelter, fuel, weather, bedroll, inventory and consumed-loot state.
- [ ] The run requires no debug workaround.
- [ ] `README.md`, `PRD.md`, this document and #42 describe the same slice.
- [ ] Thin ice neither blocks nor masquerades as a promised A-route.

## 8. Explicitly out of First Exit A

- coastal thin-ice route / fracture presentation as a required feature;
- combat and enemies;
- radiation gameplay;
- active Kenny abilities;
- large crafting trees;
- additional survival meters added for completeness;
- island expansion unrelated to the route;
- technology work that does not improve the playable loop.

Later milestones may add these systems. They are not reasons to keep the land-night slice open.
