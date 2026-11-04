extends SceneTree

## Bakes the 3D inventory's body panel: Henry's coat and trousers as he stands, seen square from the front by an
## orthographic camera, drawn as a flat mask (the coat white, the trousers grey) on a clear background (tinted grey and see-through in game).
## Beside it, where each body pocket sits on the mask (0..1 of the image), found from his bones.
## Run: xvfb-run godot --path . --rendering-driver vulkan --resolution 1024x1024 --script res://tools/runtime/bake_body_silhouette.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const OUT_PNG: String = "res://assets/ui/inventory/body_front.png"
const OUT_JSON: String = "res://assets/ui/inventory/body_front.json"
const GARMENTS: Array[StringName] = [&"Outfit_Jacket", &"Outfit_Pants"]
## Each garment's shade on the mask, so the coat and the trousers read apart.
const SHADES: Array[float] = [1.0, 0.72]
## A coat pocket sits this far above the hip joint and out to the side of it; a thigh pocket this far out on
## the side of the thigh's middle, metres.
const COAT_POCKET_UP_M: float = 0.1
const COAT_POCKET_OUT_M: float = 0.05
const THIGH_POCKET_OUT_M: float = 0.07


func _initialize() -> void:
	_run()


func _run() -> void:
	var player := (load(PLAYER) as PackedScene).instantiate() as Node3D
	root.add_child(player)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	root.add_child(floor)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var visual := player.get_node(^"HenryUALVisual") as HenryUALAnimation
	for _i: int in 60:
		await process_frame
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if GARMENTS.has(geometry.name):
			var mask := StandardMaterial3D.new()
			mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mask.albedo_color = Color(1.0, 1.0, 1.0) * SHADES[GARMENTS.find(geometry.name)]
			geometry.material_override = mask
		else:
			geometry.visible = false
	## Only the garments: no 2D overlay from the player's scene either.
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node: Node in root.find_children("*", "CanvasItem", true, false):
		if node.get_parent() == root or node.get_parent() is CanvasLayer:
			(node as CanvasItem).visible = false
	var rig: Skeleton3D = visual.skeleton
	var bone := func(bone_name: String) -> Vector3:
		return rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone_name)).origin)
	var left_side: Vector3 = (bone.call("thigh_l") - bone.call("thigh_r")).normalized()
	var forward: Vector3 = Vector3.UP.cross(-left_side).normalized()
	var middle: Vector3 = (bone.call("spine_01") + bone.call("thigh_l") + bone.call("thigh_r")) / 3.0
	var top: float = (bone.call("neck_01") as Vector3).y + 0.1
	var bottom: float = (bone.call("foot_l") as Vector3).y - 0.12
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = top - bottom
	root.add_child(camera)
	var aim := Vector3(middle.x, (top + bottom) * 0.5, middle.z)
	camera.look_at_from_position(aim + forward * 3.0, aim, Vector3.UP)
	camera.make_current()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	root.add_child(env)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	## Shades on black, read back opaque: whatever is lit is the mask, its brightness the garment's shade.
	var shot: Image = root.get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	var image := Image.create(shot.get_width(), shot.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in shot.get_height():
		for x: int in shot.get_width():
			var shade: float = shot.get_pixel(x, y).v
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0) if shade > 0.03 else Color(0.0, 0.0, 0.0, 0.0))
	var used: Rect2i = image.get_used_rect()
	var cropped: Image = image.get_region(used)
	var right_side: Vector3 = -left_side
	var pockets: Dictionary = {
		"coat_left": (bone.call("thigh_l") as Vector3) + Vector3.UP * COAT_POCKET_UP_M + left_side * COAT_POCKET_OUT_M,
		"coat_right": (bone.call("thigh_r") as Vector3) + Vector3.UP * COAT_POCKET_UP_M + right_side * COAT_POCKET_OUT_M,
		"thigh_left": ((bone.call("thigh_l") as Vector3) + (bone.call("calf_l") as Vector3)) * 0.5 + left_side * THIGH_POCKET_OUT_M,
		"thigh_right": ((bone.call("thigh_r") as Vector3) + (bone.call("calf_r") as Vector3)) * 0.5 + right_side * THIGH_POCKET_OUT_M,
	}
	var anchors: Dictionary = {}
	for pocket: String in pockets:
		var at: Vector2 = camera.unproject_position(pockets[pocket]) - Vector2(used.position)
		anchors[pocket] = [snappedf(at.x / used.size.x, 0.001), snappedf(at.y / used.size.y, 0.001)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PNG.get_base_dir()))
	cropped.save_png(ProjectSettings.globalize_path(OUT_PNG))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_JSON), FileAccess.WRITE)
	file.store_string(JSON.stringify({"size": [used.size.x, used.size.y], "pockets": anchors}, "\t"))
	file.close()
	print("[body silhouette] ", used.size, " ", anchors)
	quit()
