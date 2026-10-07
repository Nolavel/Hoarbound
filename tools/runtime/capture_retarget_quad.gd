extends SceneTree

## Quad review (front/side/rear/feet or hand) of <dataset>:<clip> retarget-only, UAL:<clip>
## or TRACE:<path>; env MM_OUT_DIR, MM_START, MM_SECONDS, MM_DIAG_VARIANT, MM_CLOSEUP.

const Dump := preload("res://tools/runtime/dump_retarget_layers.gd")
const HENRY_MODEL := "res://assets/characters/henry/henry_outfit.glb"
const PANEL := Vector2i(960, 540)
const FPS := 30.0
## Panel name -> [eye, target]; Henry faces +Z, his left is +X.
const VIEWS := {
	"front": [Vector3(0.0, 1.05, 3.4), Vector3(0.0, 0.92, 0.0)],
	"side (his left)": [Vector3(3.4, 1.05, 0.0), Vector3(0.0, 0.92, 0.0)],
	"rear": [Vector3(0.0, 1.05, -3.4), Vector3(0.0, 0.92, 0.0)],
	"feet": [Vector3(1.05, 0.42, 1.15), Vector3(0.0, 0.2, 0.0)],
}
## MM_CLOSEUP=hand swaps the feet panel for his left hand and forearm.
const HAND_VIEW := [Vector3(1.25, 1.0, 0.75), Vector3(0.3, 0.9, 0.0)]
const SOURCE_COLOR := Color(1.0, 0.55, 0.15)
const BONE_HALF_WIDTH := 0.006

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _model := UALSkeletonModel.new()
var _backend: ModifierRetargetBackend
var _overlay: MeshInstance3D
var _material: StandardMaterial3D
var _views: Array[SubViewport] = []
var _labels: Array[Label] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := OS.get_environment("MM_OUT_DIR")
	var args: Array = Array(OS.get_cmdline_user_args())
	if out_dir.is_empty() or args.is_empty():
		push_error("RetargetQuad: set MM_OUT_DIR and pass CMU:<clip> or UAL:<clip>.")
		quit(2)
		return
	var parts := String(args[0]).split(":")
	var world := _build_world()
	var henry := (load(HENRY_MODEL) as PackedScene).instantiate() as Node3D
	world.add_child(henry)
	_skeleton = henry.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var players := henry.find_children("*", "AnimationPlayer", true, false)
	_player = players[0] as AnimationPlayer if not players.is_empty() else null
	_model.load_from_skeleton(_skeleton)
	_build_views(world)
	await process_frame
	var start := OS.get_environment("MM_START").to_float()
	var seconds := OS.get_environment("MM_SECONDS").to_float() if not OS.get_environment("MM_SECONDS").is_empty() else 4.0
	var layer := OS.get_environment("MM_DIAG_VARIANT") if not OS.get_environment("MM_DIAG_VARIANT").is_empty() else "L4_full"
	var retargeter: MotionRetargeter = null
	var trace: Array = []
	if parts[0] == "TRACE":
		trace = JSON.parse_string(FileAccess.get_file_as_string(String(args[0]).substr(6)))["frames"]
		if _player != null:
			_player.stop()
	elif parts[0] == "UAL":
		_player.play(parts[1])
		_player.pause()
	else:
		var profile := SourceRetargetProfile.for_dataset(parts[0])
		var clip := BVHClip.new()
		clip.load_file(profile.source_dir + parts[1] + ".bvh", profile.units_to_meters)
		var variant: Variant = Dump.VARIANTS[layer]
		retargeter = MotionRetargeter.new()
		retargeter.stages = int(variant) if variant is int else MotionRetargeter.STAGE_ALL
		retargeter.target_neutral_local = _model.mean_pose(_player.get_animation(Dump.HENRY_IDLE) if _player != null else null)
		if not profile.neutral_clip.is_empty():
			retargeter.source_neutral_clip = BVHClip.new()
			retargeter.source_neutral_clip.load_file(profile.source_dir + profile.neutral_clip + ".bvh", profile.units_to_meters)
		if not retargeter.setup(clip, profile, _model):
			push_error("RetargetQuad: %s" % retargeter.error_message)
			quit(2)
			return
		if variant is String:
			_backend = ModifierRetargetBackend.new()
			if not _backend.setup(clip, profile, _skeleton, variant == "global", root):
				push_error("RetargetQuad: %s" % _backend.error_message)
				quit(2)
				return
		if _player != null:
			_player.stop()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var title := "%s  %s" % [String(args[0]).get_file(), "in-game pose trace" if not trace.is_empty() \
		else ("Henry's own clip" if retargeter == null else "retarget-only " + layer)]
	if not OS.get_environment("MM_TITLE").is_empty():
		title = OS.get_environment("MM_TITLE")
	for frame in range(int(seconds * FPS)):
		var t := start + float(frame) / FPS
		if not trace.is_empty():
			_show_trace(trace[clampi(int(round(t * FPS)), 0, trace.size() - 1)])
		elif retargeter != null:
			await _show_retarget(retargeter, t)
		else:
			_player.seek(fmod(t, _player.current_animation_length), true)
			_draw_lines(PackedVector3Array())
		for index in range(_labels.size()):
			_labels[index].text = "%s  |  %s  |  t %.2f s" % [title, VIEWS.keys()[index], t]
		await process_frame
		await RenderingServer.frame_post_draw
		_compose().save_png("%s/%04d.png" % [out_dir, frame])
	print("[RETARGET_QUAD] %s frames %d -> %s" % [title, int(seconds * FPS), out_dir])
	quit(0)


func _show_retarget(retargeter: MotionRetargeter, t: float) -> void:
	var pose := retargeter.retarget_at(t)
	var rotations: Array[Quaternion] = pose["rotations"]
	if _backend != null:
		rotations = await _backend.pose_at(retargeter.clip.frame_at_time(t, retargeter.profile.first_motion_frame), self, retargeter.root_space_basis(t))
	for bone in range(rotations.size()):
		_skeleton.set_bone_pose_rotation(bone, rotations[bone])
		_skeleton.set_bone_pose_position(bone, _model.rest_local[bone].origin)
	_skeleton.set_bone_pose_position(_model.pelvis_index, pose["pelvis_position"])
	var positions := retargeter.normalized_source_positions(t)
	var segments := PackedVector3Array()
	for joint in range(positions.size()):
		var parent := retargeter.clip.parents[joint]
		if parent >= 0:
			segments.append(positions[parent])
			segments.append(positions[joint])
	_draw_lines(segments)


## Local rotations from the trace; the pelvis offset is recovered from its drawn
## position under the root bone, every other bone keeps its rest offset.
func _show_trace(entry: Dictionary) -> void:
	var rotations: Array = entry["rotations"]
	var positions: Array = entry["positions"]
	for bone in range(_model.get_bone_count()):
		var q := Quaternion(rotations[bone * 4], rotations[bone * 4 + 1], rotations[bone * 4 + 2], rotations[bone * 4 + 3])
		_skeleton.set_bone_pose_rotation(bone, q)
		_skeleton.set_bone_pose_position(bone, _model.rest_local[bone].origin)
	var pelvis := _model.pelvis_index
	var parent := _model.parents[pelvis]
	var parent_q := Quaternion(rotations[parent * 4], rotations[parent * 4 + 1], rotations[parent * 4 + 2], rotations[parent * 4 + 3])
	var parent_global := Transform3D(Basis(parent_q), _model.rest_local[parent].origin)
	var drawn := Vector3(positions[pelvis * 3], positions[pelvis * 3 + 1], positions[pelvis * 3 + 2])
	_skeleton.set_bone_pose_position(pelvis, parent_global.affine_inverse() * drawn)
	_draw_lines(PackedVector3Array())


func _draw_lines(segments: PackedVector3Array) -> void:
	var mesh := _overlay.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if segments.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for index in range(0, segments.size(), 2):
		var a := segments[index]
		var b := segments[index + 1]
		for side in [Vector3(BONE_HALF_WIDTH, 0, 0), Vector3(0, 0, BONE_HALF_WIDTH)]:
			for vertex in [a - side, a + side, b + side, a - side, b + side, b - side]:
				mesh.surface_set_color(SOURCE_COLOR)
				mesh.surface_add_vertex(vertex)
	mesh.surface_end()


func _build_world() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.35, 0.39)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.64, 0.7)
	environment.ambient_light_energy = 0.8
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	light.shadow_enabled = true
	world.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.2, 0.22, 0.24)
	plane.material = floor_material
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	for line in range(-8, 9):
		_add_grid_line(world, Vector3(line * 0.25, 0.001, -2.0), Vector3(line * 0.25, 0.001, 2.0))
		_add_grid_line(world, Vector3(-2.0, 0.001, line * 0.25), Vector3(2.0, 0.001, line * 0.25))
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_overlay = MeshInstance3D.new()
	_overlay.mesh = ImmediateMesh.new()
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_overlay)
	return world


func _add_grid_line(world: Node3D, a: Vector3, b: Vector3) -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(absf(b.x - a.x), 0.004), 0.002, maxf(absf(b.z - a.z), 0.004))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.41, 0.44)
	box.material = material
	line.mesh = box
	line.position = (a + b) * 0.5
	world.add_child(line)


func _build_views(world: Node3D) -> void:
	for view_name in VIEWS.keys():
		var view := SubViewport.new()
		view.size = PANEL
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.world_3d = world.get_viewport().world_3d
		root.add_child(view)
		var camera := Camera3D.new()
		camera.fov = 40.0 if view_name == "feet" else 46.0
		view.add_child(camera)
		var pose: Array = VIEWS[view_name]
		if view_name == "feet" and OS.get_environment("MM_CLOSEUP") == "hand":
			pose = HAND_VIEW
		camera.look_at_from_position(pose[0], pose[1])
		camera.make_current()
		var hud := CanvasLayer.new()
		var label := Label.new()
		label.position = Vector2(10.0, 8.0)
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 5)
		hud.add_child(label)
		view.add_child(hud)
		_views.append(view)
		_labels.append(label)


func _compose() -> Image:
	var image := Image.create(PANEL.x * 2, PANEL.y * 2, false, Image.FORMAT_RGB8)
	for index in range(_views.size()):
		var panel := _views[index].get_texture().get_image()
		panel.convert(Image.FORMAT_RGB8)
		image.blit_rect(panel, Rect2i(Vector2i.ZERO, PANEL), Vector2i((index % 2) * PANEL.x, (index / 2) * PANEL.y))
	return image
