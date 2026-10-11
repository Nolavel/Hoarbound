# Key West First Exit — Battery Osceola → 727 Fort Street

> Reality Library binding (`docs/world/KEY_WEST_REALITY_LIBRARY.md` §9): 727 Fort Street =
> `kw:building:osm:w339414849`; Battery Osceola anchor lies in Fort Zachary Taylor
> `kw:building:osm:w524088621` (no separate source footprint). Roles live in
> `data/world/key_west/reality/overrides/first_exit_landmarks.geojson`.

The main scene `scenes/world/key_west/key_west.tscn` pins the `key_west_test`
profile and owns the default F5 gameplay start.

## Canonical route anchors

Owner decision, 2026-10-10:

- **Bunker / First Exit start:** **Battery Osceola** at Fort Zachary Taylor,
  projected into the current NOAA local frame at approximately
  **(-4052.73, 1924.69)**.
- **Primary First Exit shelter:** **727 Fort Street**, the real historic
  one-story masonry building at Fort Street / Petronia Street, projected at
  approximately **(-3531.78, 1590.28)**.
- **Former custom Fort Street shelter/hut:** **(-3579.85, 1574.51)**. Keep it in
  the project and world for now, but it no longer owns the primary First Exit
  shelter role. Its later use is undecided.
- The Battery Osceola → 727 Fort Street separation is roughly **619 m** in the
  current local frame.
- No waypoint is added.

These anchors are production decisions and must survive any future Key West
crop rebuild, city-data regeneration, OSM/Overture refresh, Blender world pass,
or authored map rebuild. Do not silently restore the old Whitehead generic
bunker anchor or the vacant-lot hut as the primary route endpoints.

## Real-building-first rule

For Key West, first look for an existing real structure that can perform the
gameplay role. Create a custom building only when the real city provides no
suitable structure.

Selected real landmarks may receive authored, reference-backed form overrides
while preserving real footprint, parcel/street relationship and source
provenance. Generic OSM massing that occupies the same landmark footprint must
be suppressed when the authored landmark form is active.

Battery Osceola should use documented historic-preservation form rather than a
generic bunker silhouette. 727 Fort Street should preserve the documented
historic masonry-building identity and health-center adaptation. If a public
floor plan is recovered, use it for major room/corridor structure; otherwise
keep the exterior/footprint truthful and author a conservative clinic-derived
interior without presenting it as archival fact.

## Shelter gameplay contract

The shelter remains a place Henry must make usable rather than an automatic safe
room. Existing survival interactions should be preserved where practical:
repairable openings, door interaction, stove/heat, sleep/rest, supplies and the
basic shelter-preparation loop.

The intended shelter fiction is that 727 Fort Street was adapted during the
cold years as a communal/medical warm point and later survival shelter. The
building should show that people compressed life into a smaller heated core
rather than successfully heating the whole structure.

## Current implementation status

Issue **#211** owns the migration from the legacy anchors to the real landmark
route. The current production runtime may still contain legacy constants for the
old Whitehead start / vacant Fort Street hut until the selected-landmark
generator/runtime override is finished. Treat those old constants as
implementation debt, not as the route source of truth.

The existing Key West capture harness already contains architectural review
anchors for Battery Osceola and 727 Fort Street and must be reused for visual
acceptance. Do not create a second render pipeline.

Key West starts directly in the existing `blizzard` profile. World
initialization happens before the first visible frame for this profile.
SnowfallVFX already preprocesses its GPU layers; the local HeightField and
WorldAudioBinder reuse the same authoritative weather values.

Key West uses the existing StreamingSystem in runtime-only mode. Its generated
city chunks register into that same lifecycle. Production city/mask data are
committed under `data/world/key_west/`; the frozen snapshot and its hashes are
recorded in `source_receipt.json`. NOAA terrain is committed under
`world/terrain/`, with its derived source and provenance in `source/key_west/`.

Launch with F5 or:

```bash
godot --path .
```

The scene contains the player, TPS camera, IslandTerrain, environment and title
card, and reuses the shared First Exit content through its profile. It does not
instantiate the archived Graciosa scene. Graciosa is retained with its authored
terrain and streaming data under `archive/graciosa/` and has its own pinned
profile for direct F6 launches. Test scenes keep their existing isolated defaults.

Validation/capture extends the existing checks workflow; no second CI pipeline
is introduced.

## Shelter start toggle

The `spawn_at_shelter` debug/start option should resolve to the canonical primary
shelter at 727 Fort Street once #211 integration is complete. Until that code
migration lands, any legacy vacant-lot target is transitional only.
