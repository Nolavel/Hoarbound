# Key West Reality Library — accuracy report

Spatial coverage, attribute completeness and source confidence are reported separately. A processed feature is not an accurate feature; see reconstruction classes.

Extent (WGS84): {'west': -81.836047, 'south': 24.532311, 'east': -81.699056, 'north': 24.61161}  ·  library size: 133.2 MB

## Buildings

- 13,376 total; footprint geometry from OpenStreetMap 12,358, Microsoft ML Buildings 320, Struct_Poly_FEMA 698
- 100.0% real footprints (no box proxies); reconstruction: {'cross_verified': 8327, 'derived': 5049}
- height: 99.3% measured by lidar (9,458 cross-verified 2016+2019, 3,819 2019 only), 29 tag/ML-derived, 0.0% inferred, 0.5% unknown
- 1,492 buildings changed height by > max(2.5 m, 25 %) between 2016 and 2019 (flagged, not resolved)
- roof shape tagged: 88; lidar flat/pitched form: 13,136; exact roof shape unknown for 99.3%
- levels tagged 300 / inferred 12,837 / unknown 239
- address known 9,727 (72.7%); use (OSM) 2,874; occupancy (USA Structures) 10,669
- facade material/colour known: 0 / 0 (no imagery source reachable)

## Roads

- 5,900 segments; geometry cross-verified with Census TIGER: 2,125; TIGER-only (unverified): 8
- width: {'inferred': 5888, 'derived': 1} (inferred = class table); lanes known 689; surface known 1,599
- sidewalks 1,529, crosswalks 307
- length km by class: {'cycleway': 21.6, 'ferry_route': 503.93, 'footway': 162.65, 'living_street': 0.14, 'path': 195.01, 'pedestrian': 1.28, 'primary': 8.86, 'rail_unknown': 4.76, 'residential': 128.82, 'secondary': 13.11, 'service': 136.34, 'steps': 0.15, 'tertiary': 33.42, 'tiger_s1400': 0.46, 'track': 5.64, 'trunk': 9.04, 'unclassified': 6.08, 'unknown': 2.96}

## Power / utilities

- 589 poles/towers mapped; 564 connected into known line topology; 25 position-only
- 709 topology edges, 532 pole-to-pole (rest have an unmapped support at one end)

## Trees and vegetation

- 295 source-mapped trees (OSM), 104 confirmed by a 2019 lidar crown
- 37,023 lidar crown candidates (derived detections)
- coverage completeness: unknown: lidar detects crowns >= 2.5 m wide and >= 3 m tall in 2019; small, young and post-2019 trees are missing; dense canopy is stored as areas
- vegetation areas km²: {'forest': 0.106, 'heath': 0.008, 'lidar_canopy_dense': 1.259, 'mangrove': 2.533, 'scrub': 0.52, 'wc_herbaceous_wetland': 0.129, 'wc_tree_cover': 1.233, 'wetland': 0.627, 'wood': 1.005}

## Other classes

- **barriers**: barrier 3, bollard 23 (0.00 km), entrance 2, fence 35 (9.29 km), gate 73 (0.02 km), hedge 15 (0.34 km), jersey_barrier 1 (0.02 km), kerb 65, lift_gate 8, swing_gate 1, wall 42 (3.27 km)
- **coastal_structures**: breakwater 16 (0.11 km), pier 493 (12.05 km)
- **bridges**: boardwalk 1 (0.06 km), bridge 45 (4.08 km)
- **street_furniture**: artwork 9, atm 7, bench 81, charging_station 1, crossing 718, drinking_water 1, fire_hydrant 7, fountain 3, information 41, milestone 4, post_box 3, recycling 28, stop 87, street_lamp 75, toilets 21, traffic_signals 80, vending_machine 33, viewpoint 4, waste_basket 94
- **utilities**: communication_tower 6, lighting_tower 31, mobile_phone_tower 4, pipeline 21 (12.19 km), storage_tank 27, water_tower 3
- **power**: cable 2 (0.04 km), generator 15, minor_line 38 (7.07 km), plant 1, portal 21, power_line 26 (44.41 km), power_pole 518, power_tower 30, substation 9, switch 6, transformer 2

## Features by family

| family | count | reconstruction classes |
|---|---:|---|
| addresses | 9,149 | {'derived': 9149} |
| admin_areas | 15 | {'derived': 4, 'authoritative': 11} |
| airport | 85 | {'authoritative': 4, 'derived': 81} |
| barriers | 268 | {'derived': 268} |
| bridges | 46 | {'derived': 46} |
| building_parts | 24 | {'derived': 24} |
| buildings | 13,376 | {'cross_verified': 8327, 'derived': 5049} |
| coastal_structures | 509 | {'derived': 509} |
| coastline | 96 | {'derived': 96} |
| land | 333 | {'measured': 227, 'derived': 106} |
| land_use | 557 | {'derived': 557} |
| places | 4,978 | {'derived': 4943, 'authoritative': 35} |
| power | 668 | {'derived': 668} |
| roads | 5,900 | {'derived': 3775, 'cross_verified': 2125} |
| street_furniture | 1,297 | {'derived': 1297} |
| terrain_coverage | 1 | {'measured': 1} |
| transit | 1,106 | {'derived': 1106} |
| transport_nodes | 9,988 | {'derived': 9988} |
| trees | 37,318 | {'derived': 37214, 'cross_verified': 104} |
| utilities | 92 | {'derived': 92} |
| vegetation_areas | 736 | {'derived': 736} |
| water | 1,864 | {'derived': 1810, 'cross_verified': 54} |

## Excluded

- outside_extent: 1,101
- boca_chica_out_of_scope: 473
- duplicate_of_source:esa_worldcover_2021_v200 (Overture land_cover is derived from ESA WorldCover): 250
- duplicate_of: 107
- merged_into: 35

Boca Chica out-of-scope by class: {'taxilane': 129, 'building': 96, 'connector': 63, 'wetland': 33, 'service': 22, 'residential': 18, 'wood': 15, 'power_pole': 15, 'meadow': 15, 'taxiway': 12, 'unclassified': 11, 'trunk': 6, 'scrub': 6, 'place': 6, 'gate': 6, 'pier': 5, 'runway': 2, 'parking': 2, 'fence': 2, 'apron': 2, 'tree_row': 1, 'track': 1, 'storage_tank': 1, 'stopway': 1, 'rail_unknown': 1, 'power_tower': 1, 'breakwater': 1}

## Attribution required

- overture_2026_09_23_1 — © OpenStreetMap contributors (ODbL), © Overture Maps Foundation; Microsoft ML Buildings (ODbL)
- esa_worldcover_2021_v200 — © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium
- hoarbound_legacy_osm_2026_09_29 — © OpenStreetMap contributors

