# World profiles

The default playable scene is `scenes/world/key_west/key_west_reality.tscn`. It assigns
`key_west_reality.tres` to World's exported `world_profile`; the Reality chunks carry their own
terrain, so the profile has no heightmap. (`key_west_test.tres` and the legacy `key_west.tscn`
were removed on 2026-10-15.) Graciosa still uses `IslandTerrain` with its heightmap paths.

`WorldProfile` stores dataset paths, streaming/content selection, initial weather
and provenance. World forwards the chosen resource to existing systems through
`apply_world_profile`; content and city chunks retain their existing ownership.

The archived Graciosa scene in `archive/graciosa/scenes/` pins `graciosa.tres`.
Its authored source, packed heightmap and WorldData live in the same archive.
Shared gameplay assets remain under their normal paths. For scenes with no
explicit resource, WorldProfileCatalog retains the `HFN_WORLD` developer selector
and its Graciosa test fallback. A scene's pinned profile takes precedence.

The main Key West snapshot includes real NOAA-derived terrain, ocean connectivity,
12,354 OSM building footprints, road geometry, Overture visual attributes and
148 runtime chunks. The data, source attribution and import receipts are committed,
so startup has no network dependency. Existing offline builders remain the source
of truth for rebuilding these datasets; no runtime downloader or height editor is
introduced. Graciosa's zero-argument bake now writes into its archive.
