# Key West Reality: editor view, partial rebuild, Blender roundtrip

Status: plan, 2026-10-14. Owner asked for an editor workflow over the Reality world:
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

- **Out:** "Open in Blender" runs Blender with a project script that builds a blank: the
  footprint extruded to the measured height and roof height, ground at the origin,
  neighbours and terrain as a non-exported reference, custom properties `feature_id`,
  `asset_id`, `source_geometry_hash`.
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
