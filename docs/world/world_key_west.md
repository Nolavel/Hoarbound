# world_key_west — Key West world attributes

> **Living world document.** This is the single registry of *what Key West is in
> Hoarbound*: the attributes the author wants to see in the game, built up over the
> course of development. It sits beside `KEY_WEST_FIRST_EXIT.md` (the route) and
> `WORLD_PROFILES.md` (the runtime wiring).
>
> Two kinds of line:
> - **[geo]** — geographic source-of-truth from NOAA/OSM. Do not casually change it
>   (see #138). Authored gameplay sits *on top* of it.
> - **[game]** — authored attribute: the game-world decision. `← author` marks a slot
>   waiting on Nolavel.
>
> Owner: Nolavel · Started 2026-10-08 · Policy: English per `CLAUDE.md` (give inputs
> in any language; they are folded in here in English).

---

## 1. Identity

- **[game]** Hoarbound's world is a **frozen Key West after a climate catastrophe** —
  the southernmost city in the continental US, now locked in ice and blizzard.
- **[game]** One-line feel: `← author` (the single sentence a player should leave with).
- **[game]** What makes it *this* place and not a generic snow map: the real street
  grid, the airport, the marinas and the causeways still read through the snow.

## 2. Geographic truth  *(source of truth — [geo])*

| Attribute | Value |
|---|---|
| Source dataset | NOAA / NGS 2016 Topobathy Lidar DEM, Key West FL (dataset 6366) |
| Source resolution | 1 m (runtime preview resampled to 2 m) |
| CRS | EPSG:32617 — WGS 84 / UTM zone 17N |
| Geographic extent | lon −81.835…−81.705 W, lat 24.535…24.595 N |
| Playable crop | 6602 × 3286 px @ 2 m = **13.2 × 6.6 km** |
| World origin (x,z) | (−6601, −3285) m, 2 m/px, +X east, +Z south (Godot) |
| Elevation (real) | −8.18 … 28.46 m; **sea level = 0** (28 m includes structures/vegetation) |
| Land above sea | ≈ **18 km²** |
| Building footprints | **12,354** OSM-derived |
| Roads / attributes | OSM road geometry + Overture visual attributes |
| Runtime streaming | **148** city chunks, runtime-only mode |
| Base rule | NOAA base heights are **un-authored**; height edits only via Blender |

## 3. Winter transformation  *(how tropical Key West becomes Hoarbound)*

- **[game]** Snow cover model: `← author` (uniform depth? drift by wind exposure? bare
  where sheltered?)
- **[game]** What freezes over: marinas, canals, swimming pools, salt ponds → `← author`
  (which are walkable ice, which are thin/dangerous — thin ice is a later slice).
- **[game]** Vegetation under winter: palms/mangroves dead or snow-laden → `← author`.
- **[game]** Signature frost/ice look (the identity shot): `← author`
  (ties to snow/frost presentation, issue #16/#156).
- **[geo→game]** City-scale wind field + streamed snow already exist; exposure should
  derive from real building massing and shoreline, not decoration.

## 4. Districts / zones

Seeded from the real geography and the map; roles are author-owned.

| Zone | [geo] what it is | [game] role `← author` |
|---|---|---|
| **Old Town** | Dense OSM street grid, SW of the island | Primary traversal + shelter hunting ground |
| **Whitehead Spit** | SW tip; the First Exit bunker/spawn | Start point / tutorial pressure |
| **Fort Street area** | Residential lot NE of the spit (~710 m) | First Exit shelter district |
| **Airport** | Long runway + terminal, south-central | Landmark; dedicated data layer; later gameplay? |
| **Marinas / harbor** | Piers and basins, N and E shore | Frozen-water crossings, boat wrecks, loot |
| **Salt ponds** | Flats, central-east | Open exposure, wind, possible ice |
| **Causeways → Stock Island** | Bridges leaving E edge | Route out / later-islands hook (scoped separately) |
| **Shoreline / beaches** | Perimeter, S and W | Thin-ice coast (later slice), shore-route grammar |

## 5. Landmarks / readability anchors

Recognizable points a player navigates by without a map.

- **[game]** Chosen landmarks: `← author` (candidates from real Key West: Fort Zachary
  Taylor, the lighthouse, Mallory Square, Southernmost Point, the airport terminal).
- **[game]** For each landmark — in-game name, winter state, survival function
  (shelter / fuel / water / danger / pure wayfinding): `← author`.

## 6. Routes & traversal

- **[geo]** First Exit route: **Whitehead Spit bunker → Fort Street shelter**, ~710 m,
  wind pinned 8° (Whitehead → Fort Street), start in the `blizzard` profile.
- **[game]** Land-route grammar: road / shore / ruins — at least two options readable
  without a map (plan step 6, #138).
- **[game]** Other authored routes beyond First Exit: `← author`.

## 7. Survival-relevant attributes

- **[game]** Wind-exposure zones (where the blizzard bites vs. where massing shelters):
  `← author`, derived from real geometry.
- **[game]** Shelter candidates beyond Fort Street: `← author` (criteria: enclosable,
  fuel nearby, off the wind).
- **[game]** Resource geography — fuel, food, water, boards: `← author`.
- **[game]** Hazards: thin ice (coast, later), exposure, open crossings: `← author`.

## 8. Atmosphere / mood / lore

- **[game]** Catastrophe backstory (why Key West froze): `← author`.
- **[game]** Environmental storytelling beats the world should carry: `← author`.
- **[game]** Tone references (The Long Dark is the *system* reference; what is the
  *place/mood* reference?): `← author`.

## 9. Scope & non-goals

- **[geo]** In now: NOAA terrain, OSM buildings/roads, airport layer, ocean
  connectivity, 148 chunks, winter vegetation, city wind + streamed snow, First Exit
  shelter.
- **[game]** First Exit A uses only the Whitehead→Fort Street corridor; the rest of the
  island is backdrop until a scoped task needs it.
- **Later (not now):** coastal thin ice, nearby islands (Stock Island +), combat.

## 10. Open attributes awaiting the author

Running checklist — each gets filled as you decide it, in this conversation and after.

- [ ] One-line world feel (§1)
- [ ] Snow/ice model + what freezes (§3)
- [ ] Signature frost look (§3)
- [ ] District roles (§4)
- [ ] Landmark picks + their in-game function (§5)
- [ ] Wind-exposure / shelter / resource geography (§7)
- [ ] Catastrophe backstory + mood references (§8)
