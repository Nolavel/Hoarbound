@tool
class_name SurvivalItemVisual
extends RefCounted

## Authored Key West mug: real scale, base at y = 0, handle towards +X (13 x 8.7 x 10 cm).
const MUG_SCENE: PackedScene = preload("res://assets/items/mug/Mug_game_ready.glb")
const MUG_FILL_RADIUS := 0.043
const SNOW_COLOUR := Color(0.92, 0.94, 0.97)
## Authored worn lighter: real scale, base at y = 0, burner nozzle above LIGHTER_NOZZLE.
const LIGHTER_SCENE: PackedScene = preload("res://assets/items/lighter/Lighter_game_ready.glb")
const LIGHTER_NOZZLE := Vector3(-0.0066, 0.0778, 0.0)
## Authored SPoV canned meat (tools/blender/build_spov_can.py): 10.4 x 6.1 x 7.1 cm, base at
## y = 0, length along X, label front towards +Z, pull ring on the lid at the +X end.
const SPOV_CAN_SCENE: PackedScene = preload("res://assets/items/spov_can/SPoV_Can.glb")
## Recessed lid of the SPoV can: height above the base and inner size, metres.
const SPOV_LID_Y := 0.068
const SPOV_LID_SIZE := Vector2(0.092, 0.053)
## Authored steel thermos (tools/blender/build_thermos.py): 7.5 cm across, 24 cm tall, base at
## y = 0; the flip-top lid is Thermos_Lid, turning on its hinge about local +Z (latch towards +X).
const THERMOS_SCENE: PackedScene = preload("res://assets/items/thermos/Thermos.glb")
## Thermos body radius (build_thermos.py RADIUS): a pocket wraps it as a cylinder (meta round_radius).
const THERMOS_RADIUS := 0.0375
## Worn olive-drab paint over steel (carabiner shader): GLB slot -> sRGB paint colour, paint left.
const WORN_PAINT_SHADER: Shader = preload("res://shaders/items/carabiner.gdshader")
const THERMOS_PAINT := {"Thermos_Paint": [Color(0.33, 0.33, 0.20), 0.78], "Thermos_LidPaint": [Color(0.26, 0.26, 0.16), 0.7], "Thermos_Steel": [Color(0.2, 0.2, 0.2), 0.0]}

## Authored Build-Rite hatchet and claw hammer (tools/blender/build_hand_tools.py): handle along +Y
## from the butt at y = 0, head on top, blade/face towards +X, label wrapped round the handle.
const AXE_SCENE: PackedScene = preload("res://assets/items/axe/Axe.glb")
const HAMMER_SCENE: PackedScene = preload("res://assets/items/hammer/Hammer.glb")
## Codex's worn 24 cm frying pan (assets/items/frying_pan/README.md): forged handle with an oval hanging eye.
const FRYING_PAN_SCENE: PackedScene = preload("res://assets/items/frying_pan/frying_pan.glb")
const AXE_TAG: Texture2D = preload("res://assets/items/axe/axe_tag.png")
const HAMMER_TAG: Texture2D = preload("res://assets/items/hammer/hammer_tag.png")
const WORN_TOOL_SHADER: Shader = preload("res://shaders/items/worn_tool.gdshader")
## Handle half-section where a pocket sleeve holds it (X, Z), and the head's underside at the eye.
const AXE_HANDLE_HALF := Vector2(0.015, 0.0105)
const AXE_HEAD_BOTTOM := 0.30
const HAMMER_HANDLE_HALF := Vector2(0.0138, 0.0098)
const HAMMER_HEAD_BOTTOM := 0.291
## The handle's bow (toward -X) where a sleeve holds it, from the build script's curve.
const AXE_HANDLE_BOW := -0.011
const HAMMER_HANDLE_BOW := -0.004
## Worn-tool shader settings per GLB slot: base, wear A, wear B, amounts, rub colour and share,
## metallic base/wear. Handle colours differ per tool.
const TOOL_METAL := [Color(0.36, 0.36, 0.38), Color(0.42, 0.25, 0.15), Color(0.21, 0.15, 0.12), 0.5, 0.35, Color(0.74, 0.72, 0.68), 0.5, 0.7, 0.1]
const TOOL_EDGE := [Color(0.82, 0.8, 0.76), Color(0.55, 0.3, 0.15), Color(0.3, 0.2, 0.12), 0.15, 0.05, Color(0.92, 0.9, 0.86), 0.2, 0.9, 0.2]
const TOOL_GRIP := [Color(0.1, 0.1, 0.1), Color(0.24, 0.2, 0.17), Color(0.16, 0.12, 0.09), 0.25, 0.15, Color(0.32, 0.3, 0.28), 0.4, 0.0, 0.0]
const AXE_HANDLE := [Color(0.93, 0.66, 0.14), Color(0.27, 0.23, 0.18), Color(0.45, 0.33, 0.18), 0.28, 0.14, Color(1.0, 0.86, 0.5), 0.4, 0.0, 0.0]
const HAMMER_HANDLE := [Color(0.78, 0.16, 0.1), Color(0.24, 0.16, 0.13), Color(0.4, 0.2, 0.14), 0.28, 0.14, Color(0.95, 0.5, 0.4), 0.4, 0.0, 0.0]

## Shared readable props for world pickups and the meal table; no inventory state.
static func make(item_id: StringName, _item_override: ItemResource = null) -> Node3D:
	var holder := Node3D.new()
	if String(item_id).begins_with("water_flask"):
		holder.add_child(_thermos())
		holder.set_meta(&"round_radius", THERMOS_RADIUS)
	elif item_id == &"tinder":
		for i: int in range(7):
			var shaving := BoxMesh.new()
			shaving.size = Vector3(0.018,0.008,0.065)
			_part(holder,shaving,Vector3(sin(float(i)*2.7)*0.012,float(i%3)*0.005,cos(float(i))*0.013),
				Color(0.65+0.035*float(i%2),0.49,0.28))
			(holder.get_child(holder.get_child_count()-1) as Node3D).rotation = Vector3(0.1*float(i%2),float(i)*0.91,0.15*sin(float(i)))
	elif item_id == &"knife":
		var handle := BoxMesh.new()
		handle.size = Vector3(0.04, 0.03, 0.10)
		_part(holder, handle, Vector3(0, 0.025, 0.06), Color(0.28, 0.18, 0.11))
		var blade := PrismMesh.new()
		blade.size = Vector3(0.028, 0.012, 0.14)
		_part(holder, blade, Vector3(0, 0.025, -0.06), Color(0.72, 0.76, 0.78))
	elif item_id == &"work_gloves":
		## A pair laid flat, cuffs out: palm, four fingers, thumb and a darker cuff each.
		for side: float in [-1.0, 1.0]:
			var glove := Node3D.new()
			glove.position = Vector3(side * 0.055, 0.0, side * 0.01)
			glove.rotation.y = side * 0.25
			holder.add_child(glove)
			var palm := BoxMesh.new()
			palm.size = Vector3(0.085, 0.022, 0.095)
			_part(glove, palm, Vector3(0, 0.011, 0), Color(0.16, 0.13, 0.10))
			for f: int in range(4):
				var finger := BoxMesh.new()
				finger.size = Vector3(0.018, 0.018, 0.07 - absf(float(f) - 1.5) * 0.012)
				_part(glove, finger, Vector3(-0.03 + float(f) * 0.02, 0.009, -0.08), Color(0.17, 0.14, 0.11))
			var thumb := BoxMesh.new()
			thumb.size = Vector3(0.02, 0.018, 0.05)
			_part(glove, thumb, Vector3(side * 0.055, 0.009, -0.02), Color(0.17, 0.14, 0.11))
			(glove.get_child(glove.get_child_count() - 1) as Node3D).rotation.y = side * 0.6
			var cuff := BoxMesh.new()
			cuff.size = Vector3(0.09, 0.026, 0.04)
			_part(glove, cuff, Vector3(0, 0.013, 0.065), Color(0.11, 0.09, 0.07))
	elif item_id == &"axe":
		holder.add_child(_hand_tool(AXE_SCENE, AXE_HANDLE, AXE_TAG))
		holder.set_meta(&"handle_half", AXE_HANDLE_HALF)
		holder.set_meta(&"head_bottom", AXE_HEAD_BOTTOM)
		holder.set_meta(&"handle_bow", AXE_HANDLE_BOW)
	elif item_id == &"hammer":
		holder.add_child(_hand_tool(HAMMER_SCENE, HAMMER_HANDLE, HAMMER_TAG))
		holder.set_meta(&"handle_half", HAMMER_HANDLE_HALF)
		holder.set_meta(&"head_bottom", HAMMER_HEAD_BOTTOM)
		holder.set_meta(&"handle_bow", HAMMER_HANDLE_BOW)
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
	elif item_id == &"frying_pan":
		var pan: Node3D = FRYING_PAN_SCENE.instantiate()
		StylizedEnvironmentMaterial.apply_to_tree(pan)
		holder.add_child(pan)
	elif item_id in [&"egg_raw", &"egg_fried", &"egg_fried_well", &"egg_fried_burnt"]:
		if item_id == &"egg_raw":
			var shell := SphereMesh.new()
			shell.radius = 0.026
			shell.height = 0.060
			shell.radial_segments = 16
			shell.rings = 8
			_part(holder, shell, Vector3(0.0, 0.031, 0.0), Color(0.72, 0.58, 0.43))
		else:
			var white := CylinderMesh.new()
			white.top_radius = 0.064
			white.bottom_radius = 0.060
			white.height = 0.005
			_part(holder, white, Vector3(0.0, 0.005, 0.0), Color(0.23, 0.17, 0.12) if item_id == &"egg_fried_burnt" else (Color(0.66, 0.55, 0.38) if item_id == &"egg_fried_well" else Color(0.83, 0.81, 0.72)))
			var yolk := SphereMesh.new()
			yolk.radius = 0.017
			yolk.height = 0.013
			_part(holder, yolk, Vector3(0.0, 0.014, 0.0), Color(0.25, 0.15, 0.09) if item_id == &"egg_fried_burnt" else Color(0.84, 0.39, 0.10))
	elif String(item_id).contains("mug") or item_id == &"warm_water":
		holder.add_child(MUG_SCENE.instantiate())
		if item_id != &"mug":
			var fill := CylinderMesh.new()
			fill.top_radius = MUG_FILL_RADIUS
			fill.bottom_radius = MUG_FILL_RADIUS
			fill.height = 0.004
			var snow: bool = item_id == &"mug_snow"
			_part(holder, fill, Vector3(0, 0.078 if snow else 0.066, 0), Color(0.92, 0.94, 0.96) if snow else Color(0.42, 0.50, 0.52))
			if snow:
				## Scooped snow heaps above the rim.
				var heap := SphereMesh.new()
				heap.radius = MUG_FILL_RADIUS
				heap.height = 0.05
				_part(holder, heap, Vector3(0, 0.08, 0), SNOW_COLOUR)
	elif item_id == &"snow_handful":
		## A packed handful: a few overlapping lumps, not a perfect ball.
		for lump: Vector4 in [Vector4(0, 0.035, 0, 0.034), Vector4(0.014, 0.044, 0.008, 0.024), Vector4(-0.012, 0.03, -0.01, 0.026)]:
			var ball := SphereMesh.new()
			ball.radius = lump.w
			ball.height = lump.w * 1.8
			_part(holder, ball, Vector3(lump.x, lump.y, lump.z), SNOW_COLOUR)
	elif item_id == &"stone":
		## A fist-sized field stone: a flattened low-poly body with a smaller knob, weathered grey.
		var body := SphereMesh.new()
		body.radius = 0.042
		body.height = 0.058
		body.radial_segments = 7
		body.rings = 4
		_part(holder, body, Vector3(0, 0.029, 0), Color(0.42, 0.41, 0.39))
		var knob := SphereMesh.new()
		knob.radius = 0.024
		knob.height = 0.036
		knob.radial_segments = 6
		knob.rings = 3
		_part(holder, knob, Vector3(0.022, 0.034, -0.012), Color(0.38, 0.37, 0.35))
	elif item_id == &"lighter":
		holder.add_child(LIGHTER_SCENE.instantiate())
	elif item_id in [&"spov_can", &"spov_can_open", &"spov_can_empty"]:
		var can: Node3D = SPOV_CAN_SCENE.instantiate()
		holder.add_child(can)
		if item_id != &"spov_can":
			## Lid and ring peeled off: the meat block shows at the rim, or the dark empty inside.
			var ring := can.find_child("SPoV_Can_Ring", true, false) as Node3D
			if ring != null:
				ring.visible = false
			var inside := BoxMesh.new()
			inside.size = Vector3(SPOV_LID_SIZE.x, 0.004, SPOV_LID_SIZE.y)
			var colour: Color = Color(0.90, 0.46, 0.46) if item_id == &"spov_can_open" else Color(0.07, 0.06, 0.05)
			_part(holder, inside, Vector3(0, SPOV_LID_Y + 0.002, 0), colour)
	else:
		var parcel := BoxMesh.new()
		parcel.size = Vector3(0.12, 0.065, 0.085)
		_part(holder, parcel, Vector3(0, 0.04, 0), Color(0.58, 0.44, 0.25))
	return holder


## A Build-Rite tool with its GLB slots swapped for the worn-tool shader and the label texture.
static func _hand_tool(scene: PackedScene, handle: Array, tag: Texture2D) -> Node3D:
	var tool: Node3D = scene.instantiate()
	var looks := {"Tool_Metal": TOOL_METAL, "Tool_Edge": TOOL_EDGE, "Tool_Handle": handle, "Tool_Grip": TOOL_GRIP}
	for mesh_node: Node in tool.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mesh_node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var source := mesh.surface_get_material(surface)
			var slot: String = source.resource_name if source != null else ""
			var material: Material
			if slot == "Tool_Tag":
				var label := StandardMaterial3D.new()
				label.albedo_texture = tag
				label.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				label.alpha_scissor_threshold = 0.5
				label.roughness = 0.9
				label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				material = label
			elif looks.has(slot):
				var look: Array = looks[slot]
				var worn := ShaderMaterial.new()
				worn.shader = WORN_TOOL_SHADER
				worn.set_shader_parameter(&"base_colour", look[0])
				worn.set_shader_parameter(&"wear_a", look[1])
				worn.set_shader_parameter(&"wear_b", look[2])
				worn.set_shader_parameter(&"amount_a", look[3])
				worn.set_shader_parameter(&"amount_b", look[4])
				worn.set_shader_parameter(&"rub_colour", look[5])
				worn.set_shader_parameter(&"rub", look[6])
				worn.set_shader_parameter(&"metallic_base", look[7])
				worn.set_shader_parameter(&"metallic_wear", look[8])
				material = worn
			if material != null:
				(mesh_node as MeshInstance3D).set_surface_override_material(surface, material)
	return tool


## Hinged lid of a thermos prop; rotate it about local +Z to flip it open (it never comes off).
static func thermos_lid(holder: Node3D) -> Node3D:
	return holder.find_child("Thermos_Lid", true, false) as Node3D


## The thermos with its GLB slots swapped for the worn-paint shader; the lid starts shut.
static func _thermos() -> Node3D:
	var thermos: Node3D = THERMOS_SCENE.instantiate()
	for mesh_node: Node in thermos.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mesh_node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var source := mesh.surface_get_material(surface)
			var slot: String = source.resource_name if source != null else ""
			if not THERMOS_PAINT.has(slot):
				continue
			var worn := ShaderMaterial.new()
			worn.shader = WORN_PAINT_SHADER
			worn.set_shader_parameter(&"paint_colour", THERMOS_PAINT[slot][0])
			worn.set_shader_parameter(&"paint_left", THERMOS_PAINT[slot][1])
			worn.set_shader_parameter(&"chip_m", 0.008)
			(mesh_node as MeshInstance3D).set_surface_override_material(surface, worn)
	return thermos


static func _part(holder: Node3D, mesh: PrimitiveMesh, at: Vector3, colour: Color) -> void:
	var part := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.65
	mesh.material = material
	part.mesh = mesh
	part.position = at
	holder.add_child(part)
