extends SceneTree

## The carry-load badge (#42 record 02, item 4): small and flat on the pack's outer panel, as Splinter Cell's light
## meter on Sam's back; it no longer hangs in the air beside the pack turned to the camera.
## Run: godot --headless --script tests/systems/test_load_badge.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const BANNER: String = "res://scenes/ui/hud/backpack_load_banner.tscn"
const MAX_WIDTH_M: float = 0.2
## The badge is placed before the pose of the frame is final: it may trail its spot by this much, metres.
const FRAME_LAG_M: float = 0.02

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var banner := (load(BANNER) as PackedScene).instantiate() as BackpackLoadBanner
	root.add_child(banner)
	banner.bind_player(player, null)
	for _i: int in 90:
		await process_frame
	var visual := player.get_node(^"HenryUALVisual") as HenryUALAnimation
	var canvas: BackpackModel = visual.get_pack_rig().get_canvas()
	var back: Vector3 = canvas.get_badge_transform().basis.z.normalized()
	camera.look_at_from_position(banner.global_position + back * 2.0 + Vector3.UP * 0.4, banner.global_position, Vector3.UP)
	for _i: int in 20:
		banner._visible_left = 4.0
		await process_frame
	var sprite := banner.get_node(^"Billboard") as Sprite3D
	_check(sprite.is_visible_in_tree(), "the badge is not shown seen from behind")
	_check(sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED, "the badge still turns to the camera")
	var width: float = sprite.texture.get_size().x * sprite.pixel_size
	_check(width <= MAX_WIDTH_M, "the badge is %.2f m wide (at most %.2f m)" % [width, MAX_WIDTH_M])
	var spot: Transform3D = canvas.get_badge_transform()
	var local: Vector3 = canvas.global_transform.affine_inverse() * spot.origin
	var out: float = signf(canvas._hinge_at.z - BackpackModel.BODY.z * 0.5)
	var face_z: float = BackpackModel.BODY.z * 0.5 * (1.0 + out)
	var off_face: float = (local.z - face_z) * out
	var most: float = BackpackModel.CANVAS_STRETCH_M + BackpackModel.BADGE_STANDOFF_M + 0.005
	_check(absf(local.x) <= BackpackModel.BODY.x * 0.5 and local.y > 0.0 and local.y < BackpackModel.BODY.y,
		"the badge's spot %s (pack space) is off the panel" % local)
	## An emptyish pack's wall sags in a little; a full one bulges out.
	_check(off_face >= -BackpackModel.SLUMP_WALL_M and off_face <= most,
		"the badge's spot stands %.3f m off the panel face (cloth: %.3f..%.3f)" % [off_face, -BackpackModel.SLUMP_WALL_M, most])
	_check(banner.global_position.distance_to(spot.origin) <= FRAME_LAG_M, "the badge is %.3f m from its spot on the panel"
		% banner.global_position.distance_to(spot.origin))
	_check(sprite.global_basis.z.normalized().dot(back) > 0.97, "the badge does not lie flat on the panel")
	print("load badge: on the panel at %s (pack space), %.2f m wide" % [local, width])
	if _failures > 0:
		push_error("load badge: %d check(s) failed" % _failures)
		quit(1)
		return
	print("load badge: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("load badge: " + message)
