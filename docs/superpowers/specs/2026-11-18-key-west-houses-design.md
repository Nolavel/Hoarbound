# Key West houses: a data-driven house kit, first slice around 727

Date: 2026-11-18. Owner: Nolavel. Stage 1 (geography: the city as built on the world date, 2025-12-31).

## Intent

The generator draws every ordinary building as the same beige box with a 1.0 x 1.4 m window every
3.2 m and a lidar roof. The city reads as a blockout, not as Key West (owner's main complaint). This
work makes ordinary houses recognisable as Key West houses, and as *the* house at that address where
evidence exists. The first slice is the 400 x 400 m square around 727 Fort Street (Bahama Village),
the same square as the geographic audit.

## Goals

- Every building in the square carries a **house record**: attributes (type, storeys, cladding,
  colours, roof material, porch, foundation, openings), each with its source, confidence and date.
- A **kit** in the chunk builder assembles each house from that record: clad walls, porch (deck, posts,
  railing, roof), piers with lattice, windows with shutters, doors, metal roof, trim.
- Documented houses (HARC applications in Legistar) get their real facades through the same kit, as
  data, not as separate models.
- The owner gets a **screenshot list**: the houses whose fronts no source covers, with address, side
  and view, ordered by how visible they are from the streets around 727.
- Verified by comparison shots (street level and top down) and render statistics against today.

## Non-goals

- Interiors, enterable houses, damage, boarding, human traces: stage 2 (house state).
- Per-house Blender models. Blender stays for buildings the kit cannot express (727, churches, large
  public buildings).
- The rest of the island. The kit must scale to it, but only the square is regenerated now.
- Fences, gardens, hedges, cars.

## Anti-goals (failure even if it technically works)

- An attribute shown as fact that no source supports. Inferred attributes are marked as inferred.
- A grey or uniform city: every house the same colour, the same porch, the same window rhythm.
- A frame rate regression on the low-end target (Intel HD 620): the kit must not add draw calls per
  detail.
- Breaking what works: frosted facade windows and window breakage (they read the `windows` surface),
  static roof snow caps, HLOD clusters, collision.

## Constraints

- Owner rules (`.claude/rules/key-west-reconstruction.md`): real Key West; never invent architecture
  silently; ask for screenshots naming address, side and view; screenshots are visual only; positions
  and sizes come from sources that allow extraction; a missing screenshot never blocks the work.
- Licences: Legistar documents are facts only (no sheets stored); Google Street View and the Esri
  orthophoto are visual only; City of Key West GIS layers are public records (receipts kept).
- Provenance: extend the existing Reality Library model (attribute store, reconstruction classes,
  receipts); no new classification system (owner decision).
- Data and presentation stay separate: the record is authoritative, the mesh is derived from it.
- Charter: GDScript static typing, English code and docs, no new visual `.new()` construction in
  `scripts/` or `world/` (the ratchet), tests that fail on the old code, CHANGELOG entry.

## Evidence ladder (owner-approved 2026-11-18)

Per attribute, the strongest available source wins:

1. **Documents.** HARC Certificate of Appropriateness packages in Legistar: survey, street photos,
   existing elevations of all four sides, the Property Appraiser card (building sketch with porch
   areas, wall and roof material). In the square, 56 of about 140 parcel addresses have Legistar
   matters, at least 20 of them building works. Planning records (as for 727 and Lofts) also count.
2. **Lidar 2019/2016 (measured).** Porch roofs sit about 3 m above ground against 5-7 m for the main
   roof, along one wall; wings, lean-tos and roof form are found the same way. Applies to every house.
3. **Owner screenshots (visual).** Windows, doors, shutters, colour, cladding where 1-2 are silent.
4. **Type rules (inferred, flagged).** From the HARC style of the City survey
   (`HARC_CONT_STRUCT1292025`: style and year built per contributing structure; 57 of 79 in the square
   are Frame Vernacular), the parcel data (`MCPAO_PARCELS_KW_ALL_INFO`: year built, use code, floor
   area) and the City's *Historic Architectural Guidelines* (HARC, 2002, pp. 34-35 colours, 59-70
   styles). Example: a 1930s Frame Vernacular cottage gets lap siding, a metal roof, piers with
   lattice, double-hung windows with shutters, a front porch on the street side.

## Approaches

- **A. Data-driven kit for all houses (chosen by the owner).** One record per house, one kit; documented
  houses are the same kit with exact numbers. Scales to the island; detail cost is controlled by
  merging per building.
- B. Per-house Blender models for documented houses, boxes for the rest. Highest fidelity for about 25
  houses, the other ~180 stay boxes; manual work per house.
- C. A small library of Blender house types fitted to footprints. Quick and pretty, but it deforms on
  real outlines and shows invented architecture.

## Design

### House record (Python, Reality Library)

A new build stage `houses` writes one record per building feature into the attribute store
(existing `attribute_store` / provenance), each attribute as `{value, source, recon, confidence,
observed}`:

- `type`: HARC style (survey) or inferred from year, use and form (`frame_vernacular`,
  `cigar_makers_cottage`, `eyebrow`, `classical_revival`, `masonry_vernacular`, `cbs_modern`, ...);
- `storeys`, `half_storey`;
- `cladding`: `lap_siding`, `drop_siding`, `board_and_batten`, `stucco`, `block`;
- `body_colour`, `trim_colour` (sRGB, with the date it was seen);
- `roof_material`: `metal_5v`, `asphalt_shingle`, `membrane`; `roof_colour`;
- `foundation`: `piers_lattice` with height, or `slab`;
- `porches`: list of `{edge, depth_m, length_m, offset_m, storeys, roof}`;
- `facades`: per footprint edge, the openings `{kind: window|door, along_m, width_m, sill_m, head_m,
  sash, shutters}`, or a rule reference (`bays: 3`) when only the type is known.

Inputs, each its own module with tests:

- `config/house_types.json`: type rules with page citations of the HARC Guidelines;
- `config/documented_houses.json`: facts read from HARC packages (address, matter, date, per-edge
  openings, porch, materials), the same pattern as `documented_buildings.json`;
- `config/house_observations.json`: owner screenshot observations (address, side, date seen,
  attributes), visual class;
- City GIS: HARC survey and parcels fetched with receipts (new source entries in `sources.json`);
- lidar porch detection: per footprint edge, a DSM band outside or inside the edge at porch height.

### Kit (Godot chunk builder)

The export carries the record; `key_west_chunk_builder.gd` assembles it:

- walls: body colour as vertex colour on the existing walls surface (one material for all houses);
  cladding drawn by the stylized shader from a world-space line pitch, not by geometry;
- trim surface (new, one per building, vertex-coloured): corner boards, porch posts, railings, fascia,
  shutters, door panels, lattice;
- porch: deck, posts and railing in the trim surface, porch roof in the roof surface;
- windows stay the `windows` surface (frost and breakage keep working), placed from the record;
- roof: metal roofs get the existing roof surface with a seam pattern by material, colour per record.

Draw calls per house go from 3 to at most 4 surfaces; the porch and shutter detail lives in vertex
data. HLOD proxies keep body and roof colour only.

### Screenshot list

A report `reports/house_screenshot_requests.md`: houses whose street facades no document or lidar
settles, ranked by visibility from Fort, Petronia, Emma, Olivia and Angela streets, each line naming
the address, the side and the view to take.

## Calls made by Claude (owner may overrule)

- Measured absence beats the type: where the lidar finds no porch roof along a wall, no porch is added
  there even if the type usually has one.
- Non-residential and post-war buildings (use codes, year after 1945, CBS) get the masonry or modern
  types, not porches by default.
- Porch roofs go into the roof mesh, so the static snow caps cover them like any roof.
- The render budget (+15 % draw calls) is a working number until an HD 620 run gives a real one.

## Order of work

1. Sources: HARC survey and parcels with receipts; the guideline rules file with citations.
2. House record stage with type rules only; export; tests.
3. Lidar porch and wing detection; tests on houses with documented porches.
4. Kit in the chunk builder: colours, cladding, trim, porches, piers, windows by record, doors.
5. Documented houses from HARC packages (about 20-25 in the square).
6. Screenshot list to the owner; observations as they arrive.
7. Regenerate the square; comparison shots; render statistics; CHANGELOG; library documentation.

## Verification

- Python tests per module (rules, detection against documented porches, record provenance).
- Godot suites: chunk builder output (surfaces, vertex colours, windows still named `windows`),
  window frost and breakage, snow caps, world composition.
- Comparison shots at fixed viewpoints in the square, before and after, and against owner screenshots
  where they exist.
- Render statistics in the same views: draw calls within +15 % of today, primitives reported.

## Left to the builder

Mesh details of posts and railings, the shader pattern for cladding and roof seams, the detection
thresholds (tuned on documented houses), and the visibility ranking for the screenshot list.

## Open for the owner

- Colour where no source shows the house: see the question in the conversation of 2026-11-18.
