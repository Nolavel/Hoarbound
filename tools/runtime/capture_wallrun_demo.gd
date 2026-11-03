extends SceneTree

## Real Godot runtime capture: CharacterBody3D + RayCast3D + ShortWallRun,
## FIRST-PERSON camera roll and CanvasLayer progress. No animated fake positions.
## xvfb-run godot --path . --resolution 960x540 --fixed-fps 30 \
##   --rendering-driver vulkan --script res://tools/runtime/capture_wallrun_demo.gd \
##   -- res://docs/runtime_previews/wallrun_demo

const ACTOR = preload("res://tests/demos/wallrun/demo_actor.gd")
const FPS: int = 30
const FRAME_COUNT: int = 240

var _out: String = "res://docs/runtime_previews/wallrun_demo"
var _actor
var _camera: Camera3D
var _title: Label
var _caption: Label
var _telemetry: Label
var _progress: ProgressBar
var _progress_text: Label
var _starts: int = 0
var _max_speed: float = 0.0
var _max_camera_roll: float = 0.0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        _out = args[0]
    var frames_path := ProjectSettings.globalize_path(_out.path_join("frames"))
    DirAccess.make_dir_recursive_absolute(frames_path)
    Engine.physics_ticks_per_second = FPS
    _build_stage()
    _build_hud()
    _update_camera(true)

    for i: int in range(FRAME_COUNT):
        await process_frame
        _update_camera(false)
        _update_hud()
        _max_speed = maxf(_max_speed, _actor.horizontal_speed())
        _max_camera_roll = maxf(_max_camera_roll, absf(_actor.camera_roll))
        await RenderingServer.frame_post_draw
        var img := root.get_texture().get_image()
        var rc := img.save_png(frames_path.path_join("f_%03d.png" % i))
        if rc != OK:
            push_error("wallrun capture failed to save frame %d (err %d)" % [i, rc])
            quit(2)
            return

    var report := {
        "frames": FRAME_COUNT,
        "fps": FPS,
        "duration_s": float(FRAME_COUNT) / FPS,
        "wall_runs_started": _starts,
        "max_speed_mps": _max_speed,
        "max_camera_roll_deg": _max_camera_roll,
        "capture": "actual Godot CharacterBody3D + RayCast3D + ShortWallRun with camera/UI",
        "visual": "FIRST-PERSON camera at eye height, HUD over 3D scene; isolated physics demo (not Henry)",
    }
    var path := ProjectSettings.globalize_path(_out.path_join("report.json"))
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(report, "  "))
        f.close()
    print("WALLRUN_DEMO ", JSON.stringify(report))
    if _starts != 2 or _max_camera_roll < 8.0 or _max_speed < 13.0:
        push_error("Wall-run evidence incomplete: expected 2 starts, camera roll and real speed-up")
        quit(3)
        return
    quit(0)


func _build_stage() -> void:
    var stage := Node3D.new()
    stage.name = "WallRun_DemoStage"
    root.add_child(stage)

    var env := WorldEnvironment.new()
    env.environment = Environment.new()
    env.environment.background_mode = Environment.BG_COLOR
    env.environment.background_color = Color(0.085, 0.13, 0.17)
    env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color = Color(0.61, 0.72, 0.82)
    env.environment.ambient_light_energy = 0.75
    env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    stage.add_child(env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50.0, -25.0, -15.0)
    sun.light_energy = 1.2
    sun.shadow_enabled = true
    stage.add_child(sun)

    _solid_box(stage, "WalkingSurface", Vector3(12.0, 0.4, 60.0), Vector3(0.0, -0.20, -7.0), Color(0.28, 0.39, 0.46))
    for side: int in [-1, 1]:
        var x := float(side) * 1.65
        var body := _solid_box(stage, "Wall_%d" % side, Vector3(0.6, 3.8, 38.0), Vector3(x, 1.9, -9.0), Color(0.31, 0.45, 0.52))
        body.collision_layer = 1
        for idx: int in range(18):
            var mark := MeshInstance3D.new()
            var mark_mesh := BoxMesh.new()
            mark_mesh.size = Vector3(0.035, 1.28 + 0.25 * float(idx % 3), 0.16)
            mark.mesh = mark_mesh
            mark.position = Vector3(x - float(side) * 0.316, 1.45, 7.5 - float(idx) * 2.0)
            var stripe_mat := StandardMaterial3D.new()
            stripe_mat.albedo_color = Color(0.58, 0.76, 0.76) if idx % 3 == 0 else Color(0.38, 0.59, 0.63)
            stripe_mat.roughness = 1.0
            mark.material_override = stripe_mat
            stage.add_child(mark)

    for i: int in range(23):
        var stripe := MeshInstance3D.new()
        var stripe_mesh := BoxMesh.new()
        stripe_mesh.size = Vector3(0.09, 0.02, 0.62)
        stripe.mesh = stripe_mesh
        stripe.position = Vector3(0.0, 0.012, 9.0 - 2.0 * float(i))
        var stripe_mat := StandardMaterial3D.new()
        stripe_mat.albedo_color = Color(0.79, 0.81, 0.71)
        stripe.material_override = stripe_mat
        stage.add_child(stripe)

    _actor = ACTOR.new()
    _actor.name = "RuntimeInputDriver"
    stage.add_child(_actor)
    # First-person view: keep physical capsule and raycasts, but do not render the
    # debug mannequin from inside its own body.
    for child: Node in _actor.get_children():
        if child is MeshInstance3D:
            child.visible = false
    _actor.wall_run.wall_run_started.connect(_on_wall_run_started)

    _camera = Camera3D.new()
    _camera.name = "FirstPersonCamera"
    _camera.fov = 83.0
    _camera.current = true
    stage.add_child(_camera)


func _solid_box(stage: Node3D, label: String, dimensions: Vector3, origin: Vector3, tint: Color) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = label
    body.collision_layer = 1
    body.collision_mask = 0
    body.position = origin
    var shape_node := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = dimensions
    shape_node.shape = box_shape
    body.add_child(shape_node)
    var mesh_node := MeshInstance3D.new()
    var box_mesh := BoxMesh.new()
    box_mesh.size = dimensions
    mesh_node.mesh = box_mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    material.roughness = 1.0
    mesh_node.material_override = material
    body.add_child(mesh_node)
    stage.add_child(body)
    return body


func _build_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "IndependentWallRunUI"
    root.add_child(layer)

    var hud := Control.new()
    hud.size = Vector2(960, 540)
    hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(hud)

    var header := ColorRect.new()
    header.position = Vector2(0, 0)
    header.size = Vector2(960, 84)
    header.color = Color(0.035, 0.07, 0.1, 0.83)
    hud.add_child(header)

    _title = _label(hud, Vector2(28, 14), 26, Color(0.95, 0.9, 0.72), "SHORT WALL RUN")
    _caption = _label(hud, Vector2(29, 50), 17, Color(0.75, 0.87, 0.94), "FIRST-PERSON / REAL WALL CONTACT / CAMERA ROLL / LIVE HUD")
    _telemetry = _label(hud, Vector2(28, 432), 21, Color(1.0, 0.94, 0.81), "")
    _progress_text = _label(hud, Vector2(28, 466), 17, Color(0.72, 0.84, 0.91), "WALL RUN / TIME LEFT")
    _progress = ProgressBar.new()
    _progress.position = Vector2(28, 493)
    _progress.size = Vector2(475, 19)
    _progress.min_value = 0.0
    _progress.max_value = 100.0
    _progress.show_percentage = false
    var back := StyleBoxFlat.new()
    back.bg_color = Color(0.10, 0.14, 0.18, 0.95)
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color(0.91, 0.70, 0.39)
    _progress.add_theme_stylebox_override("background", back)
    _progress.add_theme_stylebox_override("fill", fill)
    hud.add_child(_progress)


func _label(parent: Control, pos: Vector2, font_size: int, tint: Color, value: String) -> Label:
    var label := Label.new()
    label.position = pos
    label.text = value
    label.add_theme_color_override("font_color", tint)
    label.add_theme_font_size_override("font_size", font_size)
    parent.add_child(label)
    return label


func _update_camera(_first: bool) -> void:
    # A real first-person view from inside the CharacterBody3D capsule.
    # Rotation follows the component's wall-run side and smoothly returns
    # upright when contact ends. No external TPS follow-cam.
    _camera.global_position = _actor.global_position + Vector3(0.0, 0.66, -0.08)
    _camera.rotation = Vector3.ZERO
    _camera.rotate_object_local(Vector3.BACK, deg_to_rad(_actor.camera_roll))


func _update_hud() -> void:
    var side_name := "LEFT" if _actor.wall_side == -1 else "RIGHT"
    _title.text = "%s WALL  /  SHORT WALL RUN" % side_name
    _telemetry.text = "%s    |    SPEED %04.1f m/s    |    CAMERA ROLL %+04.1f deg" % [
        _actor.phase_caption, _actor.horizontal_speed(), _actor.camera_roll
    ]
    _progress.value = _actor.remaining_ratio * 100.0
    _progress.visible = _actor.wall_run.is_running
    _progress_text.visible = _actor.wall_run.is_running


func _on_wall_run_started(side: int) -> void:
    _starts += 1
    print("WALLRUN_START side=%d t=%.2f" % [side, _actor.segment_time])
