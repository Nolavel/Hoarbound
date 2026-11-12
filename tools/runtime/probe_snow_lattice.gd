extends SceneTree
## Real 727 start: is the near snow's chunk lattice (SnowShell far grid) built on streamed ground? Logs, every
## half second, lattice points whose ground was not streamed when it was sampled and that now differ.
## Needs a real renderer (headless ImageTexture readback is stale): xvfb + --rendering-driver vulkan --fixed-fps 4 -- [seconds]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	var ctx: Variant = null
	while ctx == null:
		await process_frame
		ctx = world.call(&"get_context")
	var player := ctx.player as CharacterBody3D
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seconds: float = float(args[0]) if args.size() > 0 else 60.0
	var t: float = 0.0
	var next_log: float = 0.0
	var walking: bool = false
	var worst: float = 0.0
	while t < seconds:
		await process_frame
		t += player.get_process_delta_time()
		var shell := SnowShell.active
		if shell == null or shell._far_grid_tex == null:
			continue
		if not walking and t > seconds * 0.3:
			walking = true
			player.rotation.y += PI
			Input.action_press(&"move_forward", 1.0)
		if t < next_log:
			continue
		next_log = t + 0.5
		var img: Image = shell._far_grid_tex.get_image()
		var n: int = img.get_width()
		var origin: Vector2 = shell._far_grid_origin
		var step: float = SnowChunkCover.STEP_M
		var stale: int = 0
		var drift: float = 0.0
		for z: int in range(0, n):
			for x: int in range(0, n):
				var at: Vector2 = origin + Vector2(x, z) * step
				var drawn: float = img.get_pixel(x, z).r
				var now: float = shell._terrain.get_height(at.x, at.y)
				if absf(drawn - now) > 0.01:
					stale += 1
					drift = maxf(drift, absf(drawn - now))
		worst = maxf(worst, drift)
		print("LATTICE t=%.1f retries=%d far_ready=%s stale_points=%d/%d max_diff_m=%.3f" % [t, shell._far_retries, shell._far_ready, stale, n * n, drift])
	print("LATTICE_DONE worst_m=%.3f" % worst)
	quit(0)
