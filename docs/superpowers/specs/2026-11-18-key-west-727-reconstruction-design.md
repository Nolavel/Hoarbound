# Key West 727 district: geographic reconstruction, stage 1

Owner-approved through the grilling rounds of 2026-11-17/18. Evidence: the audit page
(claude.ai artifact "Аудит квартала 727", version 2).

## Intent

Hoarbound rebuilds a recognisable, real Key West, not an approximate American town. The street
around the First Exit shelter (727 Fort Street) reads as a blockout today because real buildings
are missing, some are wrongly reconstructed, and the generator draws roofs and facades it cannot
resolve as flat boxes.

## Decisions

- Two separate tracks. Stage 1 is geography: positions, outlines, proportions, roofs, street
  silhouette. Post-catastrophe state (damage, snow, insulation, interactivity) is stage 2.
- Geography date: the city as it stands no earlier than late 2025. The exact world date is a
  lore decision.
- Audit square: 400 × 400 m centred on 727; buildings crossing its edge are never cut.
- Discrepancy classes: (1) missing from source geodata, (2) built after the survey dates,
  (3) in the library but reconstructed wrongly, (4) right in the library, drawn wrongly.
- Measured geometry comes from sources that allow extraction (official GIS, lidar, NAIP,
  public planning records). Google Street View and owner screenshots are visual checks only.
- Where official data, drawings and permitted imagery are not enough, ask the owner for
  screenshots, naming the address, the side of the building and the view. Never fill a gap with
  invented architecture; mark it uncertain and keep working on confirmed buildings.
- Approved plans are an accepted temporary geometry source. Each such building carries its
  record number, date, source, accuracy and the flag "as designed, not surveyed".
- Provenance extends the existing Reality Library model (source registry, receipts,
  reconstruction class, confidence, accuracy, flags); no new classification.
- Performance is checked, not assumed: draw calls and triangles are measured before and after.
- 727 exterior: the CHI clinic facade is the main candidate, not yet approved. 727 interior stays
  as the game plan.

## Approaches considered for adding post-survey buildings

1. Rebuild the whole library from fresh OSM/Overture. Rejected: the sources still lack the
   buildings, and a full rebuild needs the multi-gigabyte raw cache and moves thousands of
   unrelated features.
2. Game edit layer (`overrides/edits`, op `add`). Rejected: it is for game-authored changes and
   would label real buildings as invented; `add` is not generated either.
3. **Chosen:** a documented-buildings source. Hand-checked records in
   `config/documented_buildings.json`, read by a build stage that creates normal library
   features, and the same stage applied to the committed library without the raw cache. Roofs
   come from the documents through the existing roof-model path.

## Scope of the first slice

Lofts at Bahama Village (918 Fort Street; Legistar 22-3575, 22-3623, 25-4377): buildings A (two
wings), B and C. Then, in order: the new Frederick Douglass Community Center (111 Olivia St), the
20 outbuildings of class 1, splitting the 14 merged outlines, the 727 exterior.

## Done when

Library, chunk export, chunk scenes and HLOD clusters for the affected chunks are regenerated;
untouched chunks stay byte-identical; tests pass; street-level and top-down comparison shots
from the audit positions show the buildings; the draw-call and triangle delta is reported;
`CHANGELOG.md` has an entry.
