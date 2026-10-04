# =============================================================================
# world.gd — the composition root.
#
# Everything alive at runtime is created and wired here, in one place, and
# THIS FILE DOES NOT GROW AS SYSTEMS ARE ADDED. Three declarative lists say
# what exists; the loops below are fixed.
#
# Adding a system, a 3D entity or a UI scene is ONE LINE in the relevant
# array, plus an optional on_world_ready(context) in the thing itself.
#
# The three lists are separate because the three categories are built
# differently and parented differently:
#   1) WORLD_SYSTEM_SCRIPTS — Node classes via .new(), parented to World.
#   2) WORLD_3D_ENTITY_SCENES — .tscn via instantiate(), under StreamContainer.
#   3) WORLD_UI_SCENES — Control scenes, under a dedicated CanvasLayer.
#
# What this file is NOT about: world CONTENT. Chunks and their contents belong
# to the streaming pipeline, which is independent of this lifecycle.
#
# Borrowed wholesale from the ADT project's world.gd. See
# docs/technical/WORLD_ARCHITECTURE.md for what was taken and why.
# =============================================================================
class_name World
extends Node3D

## Optional lifecycle hook. Anything in the three lists below, plus the
## player, may implement it; nodes that do not are skipped silently.
const WORLD_READY_METHOD: StringName = &"on_world_ready"
const APPLY_WORLD_PROFILE_METHOD: StringName = &"apply_world_profile"

## Node systems — .new(), parented to World.
const WORLD_SYSTEM_SCRIPTS: Array[GDScript] = [
	preload("res://scripts/systems/time/simulation_clock.gd"),
	preload("res://scripts/systems/actions/time_costed_action_system.gd"),
	preload("res://scripts/systems/world/WeatherController.gd"),
	preload("res://scripts/systems/world/weather/snowfall_vfx.gd"),
	preload("res://scripts/systems/world/snow/snow_presentation_system.gd"),
	preload("res://scripts/systems/world/snow/footprint_system.gd"),
	preload("res://scripts/systems/world/snow/snow_shell.gd"),
	preload("res://scripts/systems/save/save_manager.gd"),
	preload("res://core/world/streaming_system.gd"),
	preload("res://scripts/systems/survival/thermal_manager.gd"),
	preload("res://scripts/systems/survival/shelter_state.gd"),
	preload("res://scripts/systems/world/shelter_grade_binder.gd"),
	preload("res://scripts/systems/audio/world_audio_binder.gd"),
	preload("res://scripts/systems/save/sleep_controller.gd"),
	preload("res://scripts/systems/save/session_state.gd"),
]

## Standalone 3D scenes — instantiate(), parented to StreamContainer.
const WORLD_3D_ENTITY_SCENES: Array[PackedScene] = []

## Screen-space UI scenes — instantiate(), parented to a shared CanvasLayer.
const WORLD_UI_SCENES: Array[PackedScene] = [
	preload("res://tools/StatsDisplay/StatsDisplay.tscn"),
	preload("res://scenes/ui/debug/dev_diorama_map.tscn"),
	preload("res://scenes/ui/hud/input_hints/key_hints_panel.tscn"),
	preload("res://scenes/ui/hud/sleep_prompt.tscn"),
	preload("res://scenes/ui/menu/pause_menu.tscn"),
]

const UI_CANVAS_LAYER_INDEX: int = 40
## Lift above the spawn marker, so the capsule does not start inside the floor.
const SPAWN_CLEARANCE: float = 1.0

@export_group("Scene wiring")
## A playable scene may pin its dataset independently of developer test defaults.
@export var world_profile: WorldProfile
## Container the streaming pipeline fills. Created if absent.
@export var stream_container: Node3D
## Player already present in the scene; one is not spawned when this is set.
@export var player: Node3D
## Camera already present in the scene.
@export var camera: Camera3D
## Where the player starts. Freed after use, as the old GameRouter did.
@export var first_spawner_marker: Marker3D
## Start at the shelter entrance instead of the authored scenario spawn.
@export var spawn_at_shelter: bool = false
## Off for a scene with its own floor, such as TestScene, so the island's
## chunks are not streamed on top of it.
@export var streaming_enabled: bool = true
@export_group("Developer tools")
## Shows the runtime performance panel. Enabled by default for development builds/scenes.
@export var enable_runtime_debug_panel: bool = true
## Writes an opt-in performance snapshot to the console once per second.
@export var print_runtime_debug_stats: bool = false
## Allows M to show/hide the debug diorama map in runtime debug builds.
@export var enable_runtime_dev_map: bool = false

var _systems: Array[Node] = []
var _context: WorldContext
var _profile: WorldProfile
var _profile_content: Node3D


func _ready() -> void:
	_profile = world_profile if world_profile != null else WorldProfileCatalog.load_selected()
	if _profile != null and _profile.prewarm_before_first_frame:
		initialize()
		return
	await get_tree().process_frame
	initialize()


## Builds the world. Public and idempotent so tests can drive it directly
## instead of waiting for a frame.
func initialize() -> void:
	if _context != null:
		return
	_resolve_scene_nodes()
	if _profile == null:
		_profile = world_profile if world_profile != null else WorldProfileCatalog.load_selected()
	_apply_profile_terrain()
	_apply_profile_content()
	_build_systems()
	_place_player()
	_context = _build_context()
	_notify(player)
	for system: Node in _systems:
		_notify(system)
	for child: Node in get_children():
		if child != player and child != stream_container and not _systems.has(child):
			_notify(child)
	_build_3d_entities()
	_build_ui()
	print("[World] initialized with %d systems" % _systems.size())


## The context handed to every system; null before initialize() has run.
func get_context() -> WorldContext:
	return _context


## Finds the container and the player/camera the scene already carries.
func _resolve_scene_nodes() -> void:
	if stream_container == null:
		stream_container = get_node_or_null("StreamContainer") as Node3D
	if stream_container == null:
		stream_container = Node3D.new()
		stream_container.name = "StreamContainer"
		add_child(stream_container)
	if player == null:
		player = get_node_or_null("Player") as Node3D
	if camera == null:
		camera = get_node_or_null("PlayerCamera") as Camera3D


func _apply_profile_terrain() -> void:
	if _profile == null or not _profile.terrain_is_configured():
		return
	var terrain := get_node_or_null("IslandTerrain") as IslandTerrain
	if terrain == null:
		push_warning("World: selected profile has terrain data but the scene has no IslandTerrain")
		return
	if not FileAccess.file_exists(_profile.terrain_image_path) or not FileAccess.file_exists(_profile.terrain_meta_path):
		push_error("World: terrain for '%s' is not built; run its documented offline bake first" % _profile.id)
		return
	if terrain.heightmap != null and terrain.heightmap_image_path == _profile.terrain_image_path \
		and terrain.heightmap_meta_path == _profile.terrain_meta_path:
		return
	if not terrain.reload_heightmap(_profile.terrain_image_path, _profile.terrain_meta_path):
		push_error("World: failed to load terrain for '%s'" % _profile.id)


func _apply_profile_content() -> void:
	if _profile == null or _profile.content_scene_path == "":
		return
	if not ResourceLoader.exists(_profile.content_scene_path):
		push_error("World: content scene for '%s' is missing: %s" % [_profile.id, _profile.content_scene_path])
		return
	var legacy := get_node_or_null("FirstExitBlockout")
	if legacy != null:
		first_spawner_marker = null
		remove_child(legacy)
		legacy.queue_free()
	var packed := load(_profile.content_scene_path) as PackedScene
	if packed == null:
		push_error("World: cannot load content scene %s" % _profile.content_scene_path)
		return
	_profile_content = packed.instantiate() as Node3D
	if _profile_content == null:
		push_error("World: content scene root must be Node3D")
		return
	_profile_content.name = "ProfileContent"
	add_child(_profile_content)
	if _profile_content.has_method(&"prepare_world_content"):
		_profile_content.call(&"prepare_world_content", self)
	var marker := _profile_content.find_child(String(_profile.spawn_marker_name), true, false) as Marker3D
	if marker != null:
		first_spawner_marker = marker
	else:
		push_error("World: profile '%s' has no spawn marker '%s'" % [_profile.id, _profile.spawn_marker_name])


func _build_systems() -> void:
	for system_script: GDScript in WORLD_SYSTEM_SCRIPTS:
		var instance: Node = system_script.new()
		if _profile != null and instance.has_method(APPLY_WORLD_PROFILE_METHOD):
			instance.call(APPLY_WORLD_PROFILE_METHOD, _profile)
		add_child(instance)
		_systems.append(instance)


## Moves the player onto the spawn marker, then drops the marker.
func _place_player() -> void:
	if spawn_at_shelter:
		var shelter_spawn := find_child("ShelterSpawnPoint", true, false) as Marker3D
		if shelter_spawn != null:
			if first_spawner_marker != null and first_spawner_marker != shelter_spawn:
				first_spawner_marker.queue_free()
			first_spawner_marker = shelter_spawn
		else:
			push_warning("World: ShelterSpawnPoint is missing; using the scenario spawn")
	if player == null or first_spawner_marker == null:
		return
	player.global_position = (
		first_spawner_marker.global_position + Vector3(0.0, SPAWN_CLEARANCE, 0.0)
	)
	player.global_rotation.y = first_spawner_marker.global_rotation.y
	player.reset_physics_interpolation()
	var follow_camera := camera as TpsCamera
	if follow_camera != null:
		follow_camera.set_look(player.global_rotation.y, follow_camera.start_pitch_deg)
		follow_camera.snap_to_target()
	first_spawner_marker.queue_free()
	first_spawner_marker = null


func _build_context() -> WorldContext:
	var context := WorldContext.new()
	context.player = player
	context.camera = camera
	context.stream_container = stream_container
	context.world = self
	context.streaming_enabled = streaming_enabled
	context.systems = _systems
	return context


func _build_3d_entities() -> void:
	for scene: PackedScene in WORLD_3D_ENTITY_SCENES:
		var instance: Node = scene.instantiate()
		stream_container.add_child(instance)
		_notify(instance)


func _build_ui() -> void:
	if WORLD_UI_SCENES.is_empty():
		return
	var canvas := CanvasLayer.new()
	canvas.name = "WorldUI"
	canvas.layer = UI_CANVAS_LAYER_INDEX
	add_child(canvas)
	for scene: PackedScene in WORLD_UI_SCENES:
		var instance: Node = scene.instantiate()
		canvas.add_child(instance)
		_notify(instance)


## Offers the optional lifecycle hook to a node and everything under it, so a
## HUD indicator deep in the player scene can ask for what it needs too.
func _notify(node: Node) -> void:
	if node == null:
		return
	if node.has_method(WORLD_READY_METHOD):
		node.call(WORLD_READY_METHOD, _context)
	for child: Node in node.get_children():
		_notify(child)
