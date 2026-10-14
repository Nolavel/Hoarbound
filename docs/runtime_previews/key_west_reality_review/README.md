# Key West Reality review captures

Shot from the real `scenes/world/key_west/key_west_reality.tscn` (World, Henry, TPS camera,
blizzard weather, deep snow, streaming) with
`tools/runtime/capture_key_west_reality_set.gd`, generator `kw_chunk_builder.9`, CPU Vulkan
(lavapipe), 2026-10-13. Downscaled to 960×540. `street_petronia`, `residential_block`,
`approach_727` and `exterior_727` were reshot on `kw_chunk_builder.10` (paving under snow,
buildings across mapped ways removed).

| Shot | What to look at |
|---|---|
| `battery_start` | Henry's first view: Fort Zachary Taylor parade ground, deep snow |
| `battery_door` | the First Exit bunker block set into the fort's courtyard face (game-authored) |
| `street_petronia` | Petronia Street, Old Town; streets and sidewalks lie under the snow cover |
| `residential_block` | houses and a draped parking lot, snowed over like the ground |
| `vegetation_deep_snow` | lidar trees as bare trees, frozen shrub stems standing out of the snow |
| `coast_frozen_sea` | the west shore: frozen-sea surface to the horizon, beach loot at Henry's feet |
| `approach_727` | the open lot west of 727 in the blizzard |
| `exterior_727` | 727 Fort Street, yard supplies by the front |
| `interior_727` | the heated waiting room; no snowfall indoors |
| `far_city_from_727`, `far_island_from_fort` | far meshes beyond the load band, no hole at the horizon |

Winter pass, generator `kw_chunk_builder.11` (2026-10-14):

| Shot | What to look at |
|---|---|
| `winter_roofs_727`, `winter_lee_eaves` | static snow caps on roofs, wires and poles in the real scene, in the blizzard |
| `caps_oblique`, `caps_close`, `caps_lee_eaves` | the same caps without weather (scratch render of chunk `-7:3`): thin on windward slopes, lips drooping past lee eaves |
| `wind_field_727` | shelter channel of the city wind field around 727; top: legacy bake (fake Truman Annex block, red), bottom: the Reality bake from the generated buildings (green outlines) |
