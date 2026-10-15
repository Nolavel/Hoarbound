# East Key West audit (airport, Stock Island, towards Boca Chica)

Owner report, 2026-10-15: "the closer to Boca Chica, the worse the terrain and the fewer houses, especially the
airport". Measured from the Reality Library, the editor export and the raw NOAA data, before changing anything.

## Boca Chica has no houses by design

`config/extent_rules.json`, author rule: *"Boca Chica is not a playable district. Only its outline on the bridge
side, terrain and coastline are kept; its buildings, roads, vegetation and infrastructure are not ingested."*
- The library excludes 96 Boca Chica buildings and 129 taxilanes as `boca_chica_out_of_scope`.
- Boca Chica Key itself lies at local x ≈ 8,300 m, outside the 2 m runtime crop (x ≤ 6,601 m).
- **Bringing its houses in is the owner's call:** change the rule, then re-ingest.

## The airport is in the data; most of it is open pavement

- Taxiways, runway 09/27 and the aprons export as ribbons and drapes.
- Buildings around the terminal and the general-aviation ramp are in the library: Signature Aviation, Island City
  Flying Service, FedEx, Avis, Dollar, and the buildings by the gates.
- The runway chunks 2:1 and 1:2 have no buildings, as on the ground.
- A lidar roof search (DSM − ground > 3 m, smooth) could not tell flat mangrove canopy from roofs. Without a
  building classification it is not evidence of missing houses.

## Terrain voids are water, not land

- The NOAA DEM 6366 has voids: 24–41 % of chunks 6:−1…6:1, 61–76 % of 13:−2/13:−1, and 45 % of the Old Town harbour
  chunk −8:1.
- In 97–100 % of the void cells the 2019 NOAA lidar has no ground return either, so these are water or closed
  mangrove.
- The export fills them with the nearest valid depth, clamped to MLLW, which puts them at the frozen sea level. That
  is correct for water.

## Open

The reported "worse terrain" is not explained by the source data: the same DEM and the same 2 m sampling cover the
whole island. A screenshot or position of the place that looked wrong is needed to measure it.
