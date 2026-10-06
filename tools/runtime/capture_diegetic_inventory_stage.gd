extends SceneTree

## Issue #203 preparation capture. No backpack UI and no packing mechanic yet:
## only the production Player, production TPS camera, production MealTable and
## production item pickup visuals staged for visual approval.

const SCENE: PackedScene = preload("res://tests/diegetic_inventory/diegetic_inventory_stage.tscn")
const OUT_DIR: String = "res://docs/runtime_previews/diegetic_inventory_stage"
const SHOTS: Array[String] = [
	"01_gameplay_read",
	"02_items_close_read",
	"03_gameplay_alternate_angle",
]

var _stage: DiegeticInventoryStage


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_stage = SCENE.instantiate() as DiegeticInventoryStage
	root.add_child(_stage)
	_run.call_deferred()


func _run() -> void:
	await _frames(120)
	if _stage.table == null or _stage.items.size() < 3:
		push_error("diegetic inventory stage capture: production table/items were not prepared")
		quit(1)
		return

	for index: int in range(SHOTS.size()):
		_stage.prepare_capture_pose(index)
		await _frames(45)
		var path: String = "%s/%s.png" % [OUT_DIR, SHOTS[index]]
		root.get_texture().get_image().save_png(path)
		print("[diegetic-inventory-stage] shot=", SHOTS[index],
			" player=", _stage.player.global_position,
			" camera=", _stage.camera.global_position,
			" items=", _stage.items.size())

	quit(0)


func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame
