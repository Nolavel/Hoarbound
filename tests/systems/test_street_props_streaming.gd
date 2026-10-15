extends SceneTree

## Every street prop kind, tall silhouettes included, is filed per city chunk and streams in with it.
## Run: godot --headless --script tests/systems/test_street_props_streaming.gd

const CITY_JSON: String = "res://data/world/key_west/city_preview.json"
const ENRICHMENT_JSON: String = "res://data/world/key_west/visual_enrichment.json"
const STREAMED: Array[String] = ["Benches", "FireHydrants", "AbandonedCars", "Scrub", "Palms", "BareTrees", "PowerPoles"]

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CITY_JSON))
	var enrichment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ENRICHMENT_JSON))
	var terrain := IslandTerrain.new()
	var roads: Array = city.get("roads", [])
	KeyWestStreetProps.visuals.clear()
	var first: Node3D = KeyWestStreetProps.build(terrain, enrichment, roads)
	var snapshot: Dictionary = _snapshot()
	for kind: String in STREAMED:
		_check(first.get_node_or_null(kind) == null, "%s is still drawn island-wide" % kind)
		_check(snapshot.has(kind), "%s was filed under no chunk" % kind)
	_check_chunks_hold_their_own()
	KeyWestStreetProps.visuals.clear()
	var second: Node3D = KeyWestStreetProps.build(terrain, enrichment, roads)
	_check(_snapshot() == snapshot, "a second build placed props differently")
	first.free()
	second.free()
	terrain.free()
	if _failures > 0:
		push_error("street props streaming: %d check(s) failed" % _failures)
		quit(1)
		return
	print("street props streaming: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("street props streaming: %s" % message)


## Kind -> every filed transform, in chunk order.
func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = KeyWestStreetProps.visuals.keys()
	keys.sort()
	for key: String in keys:
		var kinds: Dictionary = KeyWestStreetProps.visuals[key]
		for kind: String in kinds:
			if not out.has(kind):
				out[kind] = []
			(out[kind] as Array).append_array(kinds[kind][1])
	return out


## Filed transforms lie in their chunk, and the chunk node carries all of them.
func _check_chunks_hold_their_own() -> void:
	for key: String in KeyWestStreetProps.visuals:
		var kinds: Dictionary = KeyWestStreetProps.visuals[key]
		for kind: String in kinds:
			for xf: Transform3D in kinds[kind][1]:
				_check(KeyWestStreetProps.chunk_key(Vector2(xf.origin.x, xf.origin.z)) == key,
					"%s in chunk %s lies outside it at %s" % [kind, key, xf.origin])
		var node: Node3D = KeyWestStreetProps.build_chunk_visuals(key)
		for child: Node in node.get_children():
			if not child is MultiMeshInstance3D:
				continue  # the crossings mesh is one merged surface, not instances
			var count: int = (child as MultiMeshInstance3D).multimesh.instance_count
			_check(count == (kinds[String(child.name)][1] as Array).size(), "%s in chunk %s lost instances" % [child.name, key])
		node.free()
