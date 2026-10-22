@tool
class_name SurvivalItemVisual
extends RefCounted

## Authored Key West mug: real scale, base at y = 0, handle towards +X (13 x 8.7 x 10 cm).
const MUG_SCENE: PackedScene = preload("res://assets/items/mug/Mug_game_ready.glb")
const MUG_FILL_RADIUS := 0.043

## Shared readable props for world pickups and the meal table; no inventory state.
static func make(item_id: StringName, item_override: ItemResource = null) -> Node3D:
	var holder := Node3D.new()
	if String(item_id).begins_with("water_flask"):
		var body := BoxMesh.new()
		body.size = Vector3(0.12, 0.19, 0.07)
		_part(holder, body, Vector3(0, 0.105, 0), Color(0.20, 0.42, 0.43))
		var neck := CylinderMesh.new()
		neck.top_radius = 0.025
		neck.bottom_radius = 0.025
		neck.height = 0.04
		_part(holder, neck, Vector3(0, 0.215, 0), Color(0.18, 0.19, 0.20))
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.065, 0.035, 0.074)
		_part(holder, stripe, Vector3(0, 0.14, 0), Color(0.84, 0.87, 0.78))
		var item: ItemResource = item_override if item_override != null else ItemCatalog.get_item(item_id)
		var mark := Label3D.new()
		mark.name = "VolumeMark"
		mark.text = TranslationServer.translate(&"FLASK_HELD_MARK") % item.water_remaining_ml
		mark.font_size = 34
		mark.pixel_size = 0.0006
		mark.modulate = Color(0.06, 0.08, 0.08)
		mark.outline_size = 0
		mark.position = Vector3(0, 0.14, 0.045)
		holder.add_child(mark)
		var back_mark := mark.duplicate() as Label3D
		back_mark.name = "VolumeMarkBack"
		back_mark.position.z = -mark.position.z
		back_mark.rotation.y = PI
		holder.add_child(back_mark)
	elif item_id == &"knife":
		var handle := BoxMesh.new()
		handle.size = Vector3(0.04, 0.03, 0.10)
		_part(holder, handle, Vector3(0, 0.025, 0.06), Color(0.28, 0.18, 0.11))
		var blade := PrismMesh.new()
		blade.size = Vector3(0.028, 0.012, 0.14)
		_part(holder, blade, Vector3(0, 0.025, -0.06), Color(0.72, 0.76, 0.78))
	elif item_id == &"axe":
		var handle := BoxMesh.new()
		handle.size = Vector3(0.035, 0.36, 0.035)
		_part(holder, handle, Vector3(0, 0.16, 0), Color(0.30, 0.18, 0.09))
		var head := PrismMesh.new()
		head.size = Vector3(0.20, 0.11, 0.035)
		_part(holder, head, Vector3(0.055, 0.32, 0), Color(0.40, 0.43, 0.46))
	elif item_id in [&"tinned_pineapple", &"tinned_pineapple_open", &"tinned_stew", &"tinned_stew_hot", &"empty_tin"]:
		var tin := CylinderMesh.new()
		tin.top_radius = 0.055
		tin.bottom_radius = 0.055
		tin.height = 0.10
		_part(holder, tin, Vector3(0, 0.055, 0), Color(0.64, 0.67, 0.66))
		var label := CylinderMesh.new()
		label.top_radius = 0.056
		label.bottom_radius = 0.056
		label.height = 0.062
		_part(holder, label, Vector3(0, 0.055, 0), Color(0.88, 0.67, 0.12) if String(item_id).begins_with("tinned_pineapple") else Color(0.62, 0.18, 0.12))
		if item_id in [&"tinned_pineapple_open", &"empty_tin"]:
			var opening := CylinderMesh.new()
			opening.top_radius = 0.048
			opening.bottom_radius = 0.048
			opening.height = 0.003
			_part(holder, opening, Vector3(0, 0.106, 0), Color(0.07, 0.06, 0.03))
			if item_id == &"tinned_pineapple_open":
				for x: float in [-0.024, 0.0, 0.024]:
					var fruit := BoxMesh.new()
					fruit.size = Vector3(0.019, 0.01, 0.019)
					_part(holder, fruit, Vector3(x, 0.112, 0), Color(0.98, 0.78, 0.22))
	elif String(item_id).contains("mug") or item_id == &"warm_water":
		holder.add_child(MUG_SCENE.instantiate())
		if item_id != &"mug":
			var fill := CylinderMesh.new()
			fill.top_radius = MUG_FILL_RADIUS
			fill.bottom_radius = MUG_FILL_RADIUS
			fill.height = 0.004
			var snow: bool = item_id == &"mug_snow"
			_part(holder, fill, Vector3(0, 0.078 if snow else 0.066, 0), Color(0.92, 0.94, 0.96) if snow else Color(0.42, 0.50, 0.52))
	else:
		var parcel := BoxMesh.new()
		parcel.size = Vector3(0.12, 0.065, 0.085) if item_id != &"lighter" else Vector3(0.03, 0.08, 0.02)
		_part(holder, parcel, Vector3(0, 0.04, 0), Color(0.80, 0.44, 0.08) if item_id == &"lighter" else Color(0.58, 0.44, 0.25))
	return holder


static func _part(holder: Node3D, mesh: PrimitiveMesh, at: Vector3, colour: Color) -> void:
	var part := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.65
	mesh.material = material
	part.mesh = mesh
	part.position = at
	holder.add_child(part)
