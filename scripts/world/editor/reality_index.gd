class_name RealityIndex
extends RefCounted
## Searchable view of the Reality buildings (tools/world/reality/editor_index.py output).
## Editor tooling only; coordinates are the local frame (x east, z south).

const INDEX_PATH: String = "res://data/world/key_west/reality/editor/editor_index.json"
const ASSET_MANIFEST_PATH: String = "res://data/world/key_west/reality/authoring/asset_manifest.json"
const DEFAULT_LIMIT: int = 50
## Side of the grid cells that bucket footprints for picking.
const CELL_M: float = 64.0

var buildings: Array = []
var counts: Dictionary = {}

var _haystack: PackedStringArray = PackedStringArray()
var _assets: Dictionary = {}  # feature_id -> asset record
var _cells: Dictionary = {}  # Vector2i cell -> Array[int] building indices


## Reads the index and the asset manifest; false when the index file is missing or malformed.
func load_index(path: String = INDEX_PATH) -> bool:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (doc is Dictionary) or not (doc as Dictionary).has("buildings"):
		return false
	buildings = doc["buildings"]
	counts = doc.get("counts", {})
	_haystack.resize(buildings.size())
	_cells.clear()
	for i: int in range(buildings.size()):
		var b: Dictionary = buildings[i]
		_haystack[i] = ("%s %s|%s|%s" % [b["number"], b["street"], String(b["name"]).to_upper(), String(b["id"]).to_upper()])
		var ring: Array = b["ring"]
		var lo: Vector2i = Vector2i(1 << 30, 1 << 30)
		var hi: Vector2i = -lo
		for k: int in range(0, ring.size(), 2):
			var cell: Vector2i = Vector2i(floori(float(ring[k]) / CELL_M), floori(float(ring[k + 1]) / CELL_M))
			lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
			hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
		for cx: int in range(lo.x, hi.x + 1):
			for cz: int in range(lo.y, hi.y + 1):
				(_cells.get_or_add(Vector2i(cx, cz), []) as Array).append(i)
	_assets.clear()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSET_MANIFEST_PATH))
	if manifest is Dictionary:
		for asset: Dictionary in (manifest as Dictionary).get("assets", []):
			_assets[asset["feature_id"]] = asset
	return true


## Buildings whose address, name or id contain every word of the query; exact house numbers first.
func search(query: String, limit: int = DEFAULT_LIMIT) -> Array:
	var words: PackedStringArray = query.strip_edges().to_upper().split(" ", false)
	if words.is_empty():
		return []
	var exact: Array = []
	var other: Array = []
	for i: int in range(buildings.size()):
		var hay: String = _haystack[i]
		var ok: bool = true
		for w: String in words:
			if not hay.contains(w):
				ok = false
				break
		if not ok:
			continue
		(exact if words.has(String(buildings[i]["number"])) else other).append(buildings[i])
		if exact.size() >= limit:
			break
	return (exact + other).slice(0, limit)


## The building whose footprint contains the local point, or an empty dictionary.
func pick(x: float, z: float) -> Dictionary:
	var p: Vector2 = Vector2(x, z)
	for i: int in _cells.get(Vector2i(floori(x / CELL_M), floori(z / CELL_M)), []):
		var ring: Array = buildings[i]["ring"]
		var poly: PackedVector2Array = PackedVector2Array()
		for k: int in range(0, ring.size(), 2):
			poly.append(Vector2(float(ring[k]), float(ring[k + 1])))
		if Geometry2D.is_point_in_polygon(p, poly):
			return buildings[i]
	return {}


## The authored asset bound to a feature, or an empty dictionary.
func asset_of(feature_id: String) -> Dictionary:
	return _assets.get(feature_id, {})


## One-line address for display: "727 FORT ST" or the name or the id.
static func label_of(b: Dictionary) -> String:
	var addr: String = ("%s %s" % [b["number"], b["street"]]).strip_edges()
	if String(b["name"]) != "":
		return "%s — %s" % [b["name"], addr] if addr != "" else String(b["name"])
	return addr if addr != "" else String(b["id"])
