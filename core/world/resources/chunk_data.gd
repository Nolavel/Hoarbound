class_name ChunkData
extends Resource

## One streamed chunk of the island. Authored by the generator from the scene,
## never hand-written — the scene's Area3D nodes stay the source of truth.

## Stable id used as the streaming key and in save files.
@export var id: StringName = &""
## Human-readable name; a localisation key once chunks are named in game.
@export var display_name: String = ""
## Location this chunk belongs to, for debug readouts and grouping.
@export var location: String = ""

@export_group("Placement")
## Chunk centre in world space, taken from the authored Area3D.
@export var position: Vector3 = Vector3.ZERO
## Radius covering the authored polygon. Drives the one distance metric.
@export var radius: float = 100.0

@export_group("Streaming scenes")
## Ring 1 — the full content, streamed in and out around the player.
@export_file("*.tscn") var content_scene_path: String = ""
## Optional parts of ring 1, loaded with the content scene on loader threads and attached
## under it a few per frame (StreamingSystem.assembly_budget_usec), nearest chunk first.
@export var part_scene_paths: PackedStringArray = PackedStringArray()
## Ring 0 — a light stand-in that loads once and never unloads. Optional for
## now; a chunk without one simply has no silhouette.
@export_file("*.tscn") var silhouette_scene_path: String = ""


## True when this chunk has enough to be streamed at all.
func is_streamable() -> bool:
	return id != &"" and content_scene_path != "" and radius > 0.0
