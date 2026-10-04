extends SceneTree

## Bake immutable chunk snow geometry without launching the gameplay scene.
## Run with Godot 4.8 dev6: --headless --path . --script res://tools/world/bake_key_west_chunk_snow.gd

const OUTPUT_DIR: String = "res://data/world/key_west/snow_chunk"
const CITY_JSON: String = "res://data/world/key_west/city_preview.json"
const ENRICHMENT_JSON: String = "res://data/world/key_west/visual_enrichment.json"
const HEIGHT_PNG: String = "res://world/terrain/key_west_preview_2m_la8.png"
const HEIGHT_META: String = "res://world/terrain/key_west_preview_2m_la8.json"


func _initialize() -> void:
	call_deferred(&"_bake")


func _bake() -> void:
	var terrain := IslandTerrain.new()
	terrain.heightmap = IslandHeightmap.load_from(HEIGHT_PNG, HEIGHT_META)
	if terrain.heightmap == null:
		push_error("Snow bake: terrain heightmap could not be loaded")
		quit(1)
		return
	var city := ChunkedCityMassing.new()
	if not city.configure(terrain, CITY_JSON, ENRICHMENT_JSON):
		push_error("Snow bake: city source could not be loaded")
		quit(1)
		return
	var outline: PackedVector2Array = KeyWestFirstExit.shelter_snow_outline()
	city.exclude_buildings_overlapping(outline)
	city.register_snow_obstacle(&"first_exit_shelter", outline)
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if error != OK:
		push_error("Snow bake: cannot create output directory (%d)" % error)
		quit(1)
		return
	var chunks: Dictionary = city.data.get("chunks", {})
	var ids: Array = chunks.keys()
	ids.sort()
	var entries: Dictionary = {}
	for id_variant: Variant in ids:
		var cid: String = String(id_variant)
		var chunk: Dictionary = chunks[cid] as Dictionary
		var o: Array = chunk.get("origin", [0, 0])
		var origin := Vector2(float(o[0]), float(o[1]))
		var cover: MeshInstance3D = SnowChunkCover.build(terrain, origin, city.chunk_size_m, city)
		if cover == null:
			entries[cid] = ""
			continue
		var mesh: ArrayMesh = cover.mesh as ArrayMesh
		mesh.surface_set_material(0, null)
		var filename: String = "%s.res" % cid.replace(":", "_")
		error = ResourceSaver.save(mesh, OUTPUT_DIR.path_join(filename), ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("Snow bake: failed %s (%d)" % [cid, error])
			quit(1)
			return
		entries[cid] = filename
		cover.free()
		print("Snow bake: %d/%d %s" % [entries.size(), ids.size(), cid])
	var manifest: Dictionary = {
		"version": SnowChunkCover.BAKE_VERSION,
		"chunk_size_m": city.chunk_size_m,
		"chunks": entries,
	}
	var file: FileAccess = FileAccess.open(OUTPUT_DIR.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Snow bake: cannot write manifest")
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	city.free()
	terrain.free()
	print("Snow bake: finished %d chunks" % entries.size())
	quit()
