class_name SeeThroughWarmup
extends Node

## Under the startup card, draws once a see-through copy of every thin mesh near the camera (#173): the first
## occluder fade in a session then finds its transparent pipelines compiled instead of stalling the frame.
## Only meshes present at boot are covered; chunks streamed in later compile on their first fade.

## The player's camera; its fade rule (see-through amount, thin-mesh limit) is the one warmed.
@export var camera: TpsCamera
## Meshes within this of the camera at boot are warmed, metres.
@export var radius_m: float = 40.0
## Copies stand this far ahead of the camera, scaled down to a speck, metres.
@export var ahead_m: float = 0.6
## Frames the copies stay drawn before they are freed.
@export_range(1, 10, 1) var frames_drawn: int = 3

var _pending: bool = true
var _warmed: int = 0


func _ready() -> void:
	BootLoadCapability.publish(self, self, &"is_pending")
	_run.call_deferred()


## True until the warm-up has drawn and freed its copies (BootLoadCapability).
func is_pending() -> bool:
	return _pending


## How many see-through copies the warm-up drew.
func get_warmed_count() -> int:
	return _warmed


func _run() -> void:
	## The rest of the boot work first, so the meshes around the spawn are there.
	while _others_pending():
		await get_tree().process_frame
	var started: int = Time.get_ticks_msec()
	var copies: Array[GeometryInstance3D] = []
	if camera != null and camera.is_inside_tree():
		for mesh: MeshInstance3D in _representatives():
			copies.append(_copy(mesh))
		## Process frames, not frame_post_draw: that never fires headless, and a frame draws after its process.
		for _i: int in frames_drawn + 1:
			await get_tree().process_frame
		for copy: GeometryInstance3D in copies:
			copy.queue_free()
	_warmed = copies.size()
	print("[Boot] see-through warm-up: %d meshes drawn transparent in %d ms" % [_warmed, Time.get_ticks_msec() - started])
	_pending = false


func _others_pending() -> bool:
	for provider_name: String in BootLoadCapability.pending_names(get_tree()):
		if provider_name != String(name):
			return true
	return false


## One mesh per distinct (material, vertex format) the fader could turn see-through, outside Henry.
func _representatives() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var seen: Dictionary = {}
	var eye: Vector3 = camera.global_position
	var player: Node = camera.player
	for node: Node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.skin != null or not mesh.is_visible_in_tree() or is_ancestor_of(mesh):
			continue
		if player != null and player.is_ancestor_of(mesh):
			continue
		if mesh.global_position.distance_to(eye) > radius_m or TpsCameraFader._middle_extent(mesh) > camera.occluder_max_extent():
			continue
		var fresh: bool = false
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			var array_mesh := mesh.mesh as ArrayMesh
			var format: Variant = array_mesh.surface_get_format(surface) if array_mesh != null else mesh.mesh.get_class()
			var key: Array = [material.get_rid() if material != null else RID(), format]
			if not seen.has(key):
				seen[key] = true
				fresh = true
		if fresh:
			out.append(mesh)
	return out


## A speck of `mesh` just ahead of the camera, see-through as the fader makes it, with no scripts or children.
func _copy(mesh: MeshInstance3D) -> GeometryInstance3D:
	var copy := mesh.duplicate(0) as MeshInstance3D
	for child: Node in copy.get_children():
		copy.remove_child(child)
		child.free()
	copy.visibility_range_begin = 0.0
	copy.visibility_range_end = 0.0
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.transparency = camera.occluder_transparency
	add_child(copy)
	copy.global_transform = camera.global_transform * Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0.0, 0.0, -ahead_m))
	return copy
