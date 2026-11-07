class_name Window727RealLightProbeAB
extends Window727RealLightProbe

## Issue #281, MCode/MiniMax: the real-light probe with the world streaming off.
##
## The machine this was captured on has 3 GB of RAM. The streamed 727 cells do
## not fit next to the Forward+ renderer on the software Vulkan device: the
## world grew past 2.8 GB while the cells were still loading and was killed.
##
## Everything the A/B is about stays exactly as the original probe has it:
## the real Shelter727 house, the real window GLB, the production sun and
## WorldEnvironment, the real stove and its light and the authored shelter
## colour grade. Only the cells around the shelter are not streamed in, so the
## street beyond the window is not there. The capture says so in its log.

func _ready() -> void:
	_world = WORLD_SCENE.instantiate() as World
	if _world == null:
		push_error("WINDOW_727_AB_FAIL: could not instantiate real key_west_reality world")
		return
	_world.spawn_at_shelter = true
	_world.print_runtime_debug_stats = false
	_world.enable_runtime_dev_map = false
	add_child(_world)
	# Before the first frame: this machine has 3 GB of RAM and the software
	# Vulkan device keeps every render target in system memory.
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	var environment_system: WorldEnvironmentController = _world.get_node_or_null(^"WorldEnvironmentSystem") as WorldEnvironmentController
	if environment_system != null and environment_system.world_environment != null:
		var environment_node: WorldEnvironment = environment_system.world_environment
		if environment_node.environment != null:
			environment_node.environment.volumetric_fog_enabled = false
	disable_nonessential_preview_viewports()
	# The world starts in a blizzard; this capture uses the calm profile, and
	# this machine cannot hold the blizzard's particles either. Pin it now,
	# before the warmup, instead of after it.
	for _i: int in range(4):
		await get_tree().process_frame
	for node: Node in get_tree().get_nodes_in_group(&"weather_controller"):
		if _world.is_ancestor_of(node):
			var weather: WeatherController = node as WeatherController
			weather.scheduler_enabled = false
			weather.set_weather(&"calm", true)
			break
	disable_nonessential_preview_viewports()
