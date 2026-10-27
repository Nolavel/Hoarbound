@tool
class_name HeldPropFactory
extends RefCounted

const FLARE_SCENE: PackedScene = preload("res://scenes/actors/player/held/HeldFlare.tscn")


## One authoring/runtime factory for every one-hand prop. The Item Fitter and
## gameplay call this same method, so a fitted preview cannot drift from the
## object Henry actually holds.
static func make(item_id: StringName, item_override: ItemResource = null) -> Node3D:
	if item_id == &"hammer":
		return _make_hammer()
	if item_id == &"road_flare":
		var flare := FLARE_SCENE.instantiate() as HeldFlare
		if flare != null:
			flare.auto_ignite = false
		return flare
	var prop: Node3D = SurvivalItemVisual.make(item_id, item_override)
	if item_id == &"lighter":
		var flame := LighterFlame.new()
		flame.name = "Flame"
		flame.position = SurvivalItemVisual.LIGHTER_NOZZLE
		flame.wheel = prop.find_child("Lighter_v2_Wheel", true, false) as Node3D
		prop.add_child(flame)
	return prop


static func _make_hammer() -> Node3D:
	var root := Node3D.new()
	root.name = "HeldHammer"

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.26, 0.16, 0.08)
	wood.roughness = 0.9
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.24, 0.25)
	metal.metallic = 0.75
	metal.roughness = 0.38

	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.035, 0.30, 0.035)
	handle_mesh.material = wood
	handle.mesh = handle_mesh
	handle.position.y = 0.12
	root.add_child(handle)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.18, 0.065, 0.065)
	head_mesh.material = metal
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.29, 0.0)
	root.add_child(head)
	return root
