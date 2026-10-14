# Key West Reality: editor view, partial rebuild, Blender roundtrip

Status: stage 1 done, 2026-10-14 (section 10). Owner asked for an editor workflow over the Reality world:
see the city in the editor without loading all of it, find a building by address,
replace its massing with an authored model from Blender, move trees and props, and
rebuild only what changed without breaking neighbouring chunks.

## 1. Measured state

| Fact | Evidence |
|---|---|
| `key_west_reality.tscn` in the editor is the `World` skeleton; the city streams at runtime | scene file: `StreamContainer` is empty |
| `generated/KeyWest_generated.tscn` instances all 459 chunks | generator `_write_root_scene` |
| Every chunk already has a cheap far mesh (`generated/far/Far_x_z.res`) | 459 files, used by `KeyWestRealityFar` |
| Godot build of one chunk: 3.3 s (CPU container); one CLI run 110 s wall, mostly engine start | `generate_key_west_chunks_cli.gd -- -7:3` |
| Python export of 3 chunks: 47 s (library load and island-wide rules dominate) | `export-editor --chunk=-7:3 --chunk=-8:3 --chunk=-7:2` |
| Partial export dropped pieces of features owned by a neighbour (22 roads in `-7:3`) and cut `manifest.json` down to the requested chunks | fixed 2026-10-14; the 3 chunks now equal the full export feature for feature |
| A chunk's node digest depends on which chunks were built before it in the same run | `-7:3` alone vs after `-8:3`: two digests; cause below |

Cause of the order dependence: two `CollisionShape3D` nodes in `key_west_chunk_builder.gd`
(terrain height map, per-mesh trimesh) have no name, so Godot names them
`@CollisionShape3D@N` from a process-wide counter. Geometry is identical; the node path is
not. Fixing it renames a node in every chunk, so it lands with the next snapshot commit.

## 2. Rules

1. **Data, then generator, then snapshot.** The editor never edits generated scenes; they
   are rewritten on every rebuild. An edit is a record keyed by `feature_id` in the edit
   layer (`overrides/`, `authoring/asset_manifest.json`); the generator applies it.
2. **A chunk is a pure function** of (library, edit layer, generator version, chunk id).
   Island-wide rules (tree clearance, ways through buildings) are computed over the whole
   island on every export; only the output is filtered to the requested chunks.
3. **Dirty set.** An edit rebuilds the chunks whose box touches the feature's old or new
   bounds. Lines and areas crossing a border are cut per chunk the same way in a full and a
   partial run, so a neighbour is either rebuilt identically or not touched.
4. **Proof, not trust.** A test rebuilds chunks alone and compares them with the full build
   (export features and Godot node digest).

## 3. Editor view

An `@tool` node in a review scene (not the runtime scene):
- the whole island as far meshes (already generated, cheap);
- detailed chunks (`KeyWestChunkGenerator.instantiate_assembled`) around the editor camera,
  limited to a budget (default 3x3) so the editor stays usable on the 4 GB machine;
- detail nodes are previews: not owned by the edited scene, never saved into it;
- a click resolves to the `feature_id` the generator already writes into node metadata.

## 4. Search dock

The export writes `editor_index.json`: feature id, class, name, address (street, number),
chunk, centre, height, levels, footprint bounds. The library has 13,376 buildings and
9,149 address points; addresses are joined to footprints by point in polygon. The dock
searches by street, number, name or id, flies the camera there and shows the record.

## 5. Blender roundtrip

- **Out:** Blender cannot read Godot meshes or scenes, so nothing is exported from Godot.
  The Python pipeline writes the actor's shell alone as glTF (the writer `landmarks.py`
  already uses): the footprint outline extruded to the measured eave height plus the roof
  height, origin at the footprint centre on the ground, metres, +Y up. No neighbours, no
  terrain. A sidecar JSON (and the glTF extras) carry `feature_id`, `asset_id`,
  `source_geometry_hash`, the world placement (`origin_local`, yaw) and the measured sizes,
  so the model is built to the real dimensions and placed back by data, not by hand.
- **Back:** the artist exports glTF to `assets/world/key_west/buildings/<asset_id>.glb`.
  The file name is the binding; the glTF extras carry `feature_id` as a cross-check
  (confirm how 4.8 maps extras to node metadata before relying on it). An import hook
  registers the asset as `artist_modified` (existing `asset` command), marks its chunk
  dirty and rebuilds it. The existing regen guard keeps authored assets from being
  overwritten and flags them `needs_rebase` when the source footprint changes.
- **Ready tools reviewed:** Import Replacer (MIT; replaces name-tagged empties with scenes)
  fits placeholders inside an authored building (doors, lamps), not the world binding.
  GLTF Level Importer and the Blender To Godot 4 Pipeline addon are paid; the latter
  dropped `.blend` import for glTF plus custom properties, the route chosen here. None
  binds a model to a GIS feature id, so that thin layer is ours; the identity system it
  needs (`feature_id`, asset manifest, regen guard) exists.

## 6. Placement edits

Records: move (x, z, yaw), remove, add (catalog asset) for trees, shrubs, signs, banners,
street furniture. The dock writes them through `EditorUndoRedoManager`; a rebuild of the
dirty chunks follows, then the traversal check for those chunks (an edit must not close a
walkable way).

## 7. Snapshot cost

Git stores whole changed files. A partial rebuild that touches 3 chunks adds those chunks'
files (a few MB), not a new 370 MB snapshot, provided unchanged chunks are not rewritten
and a rebuilt chunk is byte-stable when nothing changed. Stage 0 secures that.

## 8. Stages

0. **Determinism:** name the two shapes; the contract check rejects auto-named nodes; the
   partial-equals-full test; generator `.11`; one snapshot commit.
1. **Editor view and search** (read-only): index export, far overview, detail budget,
   search, fly-to, record panel.
2. **Rebuild button:** dirty chunks, partial export, partial generate, preview reload. Later,
   a resident export process to cut the library load.
3. **Building replacement** through Blender.
4. **Placement edits** with undo and validation.

Open for the author: which edits come first (buildings or vegetation and props); the
Blender version in use.

## 9. Compared with UE5 World Partition

Godot has no built-in World Partition. Reality already has most of the runtime half;
the editor half is what this plan adds. The source of truth differs: in UE the designer
edits one persistent level and the engine cuts it into cells; here the Reality Library
plus the edit layer is the world, and the generator cuts it into chunks.

| UE5 World Partition | Reality today | Gap |
|---|---|---|
| Spatial grid, runtime cells | 512 m chunks `kw_gen_x_z`, 459 on the island | none |
| Cell streaming | `StreamingSystem`: `load_threaded_request`, load band = radius + margin, unload hysteresis 120 m, 1 instantiation per frame | none |
| Streaming sources | the player only | the editor camera (view), later vehicles |
| Runtime grids at several ranges | near chunks plus far meshes in a 2,500 m band (`KeyWestRealityFar`) | a middle range only if a profile asks for it |
| HLOD | one far mesh per chunk (16 m terrain, building prisms) | none for now |
| Data Layers | per-chunk part scenes by family (Buildings, Roads, Vegetation...) attached in stages | gameplay layers stay in the content scene |
| One File Per Actor | one record per `feature_id`; generated chunks are outputs | edit records per chunk file, so two people rarely touch one file |
| Editor: place actors in one world | none | this plan, stages 1 to 4 |
| World origin management | not needed: the island spans about ±5 km, where 32-bit float precision is about 0.5 mm | none |
| Persistent world state | `SaveManager`, `ShelterState`, `PickupLedger` | a generic per-`feature_id` state when world objects become breakable |

A C++ streaming manager is not on the list: activation is staged and measured, and the
architecture contract moves code to native only after a profile shows the bottleneck.

## 10. Decisions and progress (2026-10-14)

Owner answers: Blender 5.x; Blender work comes later, so its bridge stays shallow for now.
Data layers named so far: loot sets per playthrough; winter dressing, including snow caps on
roofs (layered, overhanging the eaves) and a wind map that sets windward and lee sides.

**Stage 1 (done):** read-only editor view and search.
- `python3 tools/world/key_west_reality.py editor-index` writes
  `data/world/key_west/reality/editor/editor_index.json` (13,376 buildings; address from the
  building attribute for 9,727, from an address point inside the outline for 4 and within
  6 m for 138, labelled `addr_src`; the 160 buildings not generated are flagged).
- `scenes/world/key_west/key_west_reality_editor.tscn`: `KeyWestRealityEditorView` shows all
  459 far meshes and assembles up to 9 detail chunks around the 3D editor camera, one per
  half second. Preview nodes are internal children: nothing is saved into the scene.
- Dock "Reality" (`addons/reality_editor`): search by house number, street, name or id;
  "Go to" moves `FocusMarker` there and selects it (press F to frame); "At marker" and
  "At camera" identify the building under the marker or the camera's look point; the record
  shows address source, use, height, levels, chunk and the bound asset.
- Test: `tests/systems/test_reality_editor.gd`. Captures: `docs/runtime_previews/reality_editor/`.

**Edit layer (done):** `tools/world/reality/edits.py` and `RealityEditStore` read and
write `data/world/key_west/reality/overrides/edits/edits_<x>_<z>.json`
(schema `kw_reality.edits.v1`). A record: `edit_id`, `op` (`remove`, `move`; `add` is
recorded, not generated yet), `layer` (`base`, `winter`, `loot:<set>`, `story:<state>`),
`feature_id`, `chunk`, `source_geometry_hash`, `params` (`x`, `z` local metres, `yaw_deg`
as Godot's rotation about +Y). Only `base` changes the generated world; a move carries the
source geometry before meshing, so ground height, clearance and the owning chunk are
recomputed. Other layers ride in the chunk export as `layer_edits` for the runtime.
`export-editor` refuses malformed records and warns when the source changed since the
edit. With no edits the export is unchanged. The dock records "Remove in layer" and
"Drop edit" through the editor's undo history and copies the chunk rebuild commands.

**Blender bridge (shallow, done):** `key_west_reality.py blender-shell --feature-id <id>`
writes `authoring/blender/<stem>/shell.glb` (the exact library outline, courtyards
included, extruded to the measured height; origin at the footprint centroid on the
ground) and `shell.json` (sizes, roof figures, placement, return path, register command).
Godot 4.8 imports glTF node extras as node metadata `extras` (checked on a shell). The
model comes back as `assets/world/key_west/buildings/<stem>.glb`; `asset ... --state
artist_modified` registers it and takes `origin_local` from the shell sidecar.

**Next:** the winter pass, one snapshot: stage 0 (naming, partial-equals-full test), a wind
exposure field from the profile wind and building shelter, and static snow (below).

**Static snow is not the dynamic snow.** Henry deforms the dynamic system (deep-snow shell,
chunk cover, footprints); it stays as it is. Snow caps on roofs, wires, poles, fences and
tree branches are static winter dressing: geometry generated offline into the `winter`
layer, visual only, never deformed by Henry and never read by the dynamic system. Cap
thickness, layering and the overhang that droops past the eaves come from the roof shape
and the wind exposure field (thin on windward slopes, cornices on lee edges), fixed at
generation time.
